// Queries Safari for the state of each extension, reloads content blocker rules, and opens Safari settings.
import AppKit
import Foundation
import SafariServices
import os

private let logger = Logger(subsystem: "com.jhunos.SafariAdBlock", category: "blocker")

struct BlockerInfo: Identifiable {
    enum Kind { case contentBlocker, webExtension }
    let id: String        // extension bundle identifier
    let folder: String    // Contents/PlugIns/<folder>.appex
    let title: String
    let detail: String
    var kind: Kind = .contentBlocker
}

enum BlockerState: Equatable {
    case unknown
    case enabled
    case disabled
    case missing(String)
}

struct RuleMeta: Decodable {
    struct Source: Decodable {
        let title: String?
        let version: String?
        let modified: String?
    }
    let rules: Int
    let generated: String
    let sources: [Source]
}

/// Error messages collected from several callbacks (thread-safe)
final class MessageBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func append(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}

@MainActor
final class BlockerModel: ObservableObject {
    static let appID = Bundle.main.bundleIdentifier ?? "com.jhunos.SafariAdBlock"

    let blockers: [BlockerInfo] = [
        BlockerInfo(id: appID + ".Ads", folder: "Ads", title: "Ad Blocking",
                    detail: "EasyList plus your own rules (filters/custom.txt). Blocks banners, pop-ups and ad scripts, and hides ad placeholders."),
        BlockerInfo(id: appID + ".Privacy", folder: "Privacy", title: "Tracker Blocking",
                    detail: "EasyPrivacy. Blocks analytics and tracking scripts and beacons."),
        BlockerInfo(id: appID + ".Korea", folder: "Korea", title: "Korean Sites Ad Blocking",
                    detail: "List-KR and YousList. Rules specific to Korean sites such as Naver and Daum."),
        BlockerInfo(id: appID + ".VideoAdSkip", folder: "VideoAdSkip", title: "Video Ad Skipper",
                    detail: "Skips pre-roll and mid-roll video ads automatically and dismisses ad-blocker warnings. After enabling it, Safari asks for site access the first time you open the video site; choose ‘Always Allow’.",
                    kind: .webExtension),
    ]

    @Published private(set) var states: [String: BlockerState] = [:]
    @Published private(set) var metas: [String: RuleMeta] = [:]
    @Published private(set) var message = ""
    @Published private(set) var busy = false
    let signing: String

    init() {
        let signingFile = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/signing.txt")
        signing = (try? String(contentsOf: signingFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "adhoc"
        if let plugins = Bundle.main.builtInPlugInsURL {
            for b in blockers {
                let url = plugins.appendingPathComponent("\(b.folder).appex/Contents/Resources/meta.json")
                if let data = try? Data(contentsOf: url),
                   let meta = try? JSONDecoder().decode(RuleMeta.self, from: data) {
                    metas[b.id] = meta
                }
            }
        }
    }

    /// Whether the build is signed with an Apple-issued certificate. Otherwise Safari needs "Allow unsigned extensions".
    var isSigned: Bool {
        ["Apple Development", "Developer ID Application", "Apple Distribution", "3rd Party Mac Developer"]
            .contains { signing.hasPrefix($0) }
    }

    func refresh() {
        for b in blockers {
            let handle: (Bool?, Error?) -> Void = { enabled, error in
                Task { @MainActor in
                    if let enabled = enabled {
                        self.states[b.id] = enabled ? .enabled : .disabled
                        logger.notice("\(b.id, privacy: .public): \(enabled ? "enabled" : "disabled", privacy: .public)")
                    } else {
                        let why = error?.localizedDescription ?? "unknown error"
                        self.states[b.id] = .missing(why)
                        logger.error("\(b.id, privacy: .public): state lookup failed — \(why, privacy: .public)")
                    }
                }
            }
            switch b.kind {
            case .contentBlocker:
                SFContentBlockerManager.getStateOfContentBlocker(withIdentifier: b.id) { handle($0?.isEnabled, $1) }
            case .webExtension:
                SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: b.id) { handle($0?.isEnabled, $1) }
            }
        }
    }

    private var reloadGeneration = 0

    func reloadAll() {
        busy = true
        message = "Reloading rules in Safari…"
        reloadGeneration += 1
        let generation = reloadGeneration
        let errors = MessageBox()
        let group = DispatchGroup()
        // Safari sometimes never calls the completion handler, so cap the wait (the rules may already have been reloaded).
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            Task { @MainActor in
                guard self.busy, self.reloadGeneration == generation else { return }
                self.busy = false
                self.message = "Safari did not respond within 20 seconds. The rules may have been reloaded anyway; reload a page in Safari to check."
                logger.error("Rule reload: no response from Safari (20 s)")
                self.refresh()
            }
        }
        for b in blockers where b.kind == .contentBlocker {
            group.enter()
            SFContentBlockerManager.reloadContentBlocker(withIdentifier: b.id) { error in
                if let error = error {
                    errors.append("\(b.title): \(error.localizedDescription)")
                    logger.error("\(b.id, privacy: .public): rule reload failed — \(error.localizedDescription, privacy: .public)")
                } else {
                    logger.notice("\(b.id, privacy: .public): rules reloaded")
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            Task { @MainActor in
                guard self.reloadGeneration == generation else { return }
                self.busy = false
                let failed = errors.all
                self.message = failed.isEmpty ? "Rules reloaded." : failed.joined(separator: "\n")
                self.refresh()
            }
        }
    }

    func openSafariSettings(for blocker: BlockerInfo? = nil) {
        let id = (blocker ?? blockers[0]).id
        SFSafariApplication.showPreferencesForExtension(withIdentifier: id) { error in
            Task { @MainActor in
                if let error = error {
                    self.message = "Could not open Safari settings automatically (\(error.localizedDescription)). Enable the extensions in Safari › Settings › Extensions."
                    self.openSafari()
                }
            }
        }
    }

    /// Opens a public ad-block test site in Safari. (A local file page cannot be used: Safari does not apply per-site content blocker settings to it.)
    func openCheckPage() {
        guard let url = URL(string: "https://adblock-tester.com/"),
              let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") else {
            message = "Safari was not found."
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: safari, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            Task { @MainActor in
                if let error = error {
                    self.message = "Could not open the test site: \(error.localizedDescription)"
                } else {
                    self.message = "Opened the test site in Safari. A high score (80 or more) means the rules are active. Both Ad Blocking and Tracker Blocking must be on for a high score."
                }
            }
        }
    }

    func openSafari() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
