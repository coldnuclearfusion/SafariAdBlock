// Entry point of a Safari content blocker extension. When Safari asks for rules, hand it the bundled blockerList.json.
// The three extensions (Ads / Privacy / Korea) share this file and differ only in their rule file.
// Diagnostics: /usr/bin/log show --info --predicate 'subsystem == "com.jhunos.SafariAdBlock" AND category == "extension"'
// AppKit must be linked: without it the extension process starts but the request never reaches this handler.
import AppKit
import Foundation
import os

private let logger = Logger(subsystem: "com.jhunos.SafariAdBlock", category: "extension")

@objc(ContentBlockerRequestHandler)
final class ContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {
    override init() {
        super.init()
        logger.notice("handler created: \(Bundle.main.bundleIdentifier ?? "?", privacy: .public)")
    }

    func beginRequest(with context: NSExtensionContext) {
        logger.notice("beginRequest")
        guard let url = Bundle.main.url(forResource: "blockerList", withExtension: "json") else {
            logger.error("blockerList.json not found in bundle: \(Bundle.main.bundlePath, privacy: .public)")
            context.cancelRequest(withError: NSError(
                domain: "SafariAdBlock", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "blockerList.json not found"]))
            return
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
        guard let attachment = NSItemProvider(contentsOf: url) else {
            logger.error("could not create NSItemProvider: \(url.path, privacy: .public)")
            context.cancelRequest(withError: NSError(
                domain: "SafariAdBlock", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "could not open the rule file"]))
            return
        }
        logger.notice("rule file ready: \(url.lastPathComponent, privacy: .public) \(size) bytes, types \(attachment.registeredTypeIdentifiers.joined(separator: ","), privacy: .public)")
        let item = NSExtensionItem()
        item.attachments = [attachment]
        context.completeRequest(returningItems: [item]) { expired in
            logger.notice("completeRequest finished (expired=\(expired))")
        }
        logger.notice("completeRequest called")
    }
}
