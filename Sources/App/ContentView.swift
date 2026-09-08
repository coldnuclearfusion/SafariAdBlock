import SwiftUI

struct ContentView: View {
    @StateObject private var model = BlockerModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Safari Ad Blocker").font(.title2.bold())
                    Text("Three Safari content blockers plus a video ad skipper. Each one can be turned on or off in Safari settings.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(model.blockers.enumerated()), id: \.element.id) { index, blocker in
                    BlockerRow(blocker: blocker,
                               state: model.states[blocker.id] ?? .unknown,
                               meta: model.metas[blocker.id]) {
                        model.openSafariSettings(for: blocker)
                    }
                    if index < model.blockers.count - 1 { Divider() }
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))

            HelpBox(signed: model.isSigned)

            HStack {
                Button("Open Safari Extension Settings") { model.openSafariSettings() }
                Button("Check It Works (Test Site)") { model.openCheckPage() }
                Button("Reload Rules") { model.reloadAll() }
                    .disabled(model.busy)
                Spacer()
                Button("Refresh Status") { model.refresh() }
            }

            if !model.message.isEmpty {
                Text(model.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 620)
        .onAppear {
            // When install.sh launches the app with `--reload`, push the new rules to Safari right away.
            if CommandLine.arguments.contains("--reload") { model.reloadAll() } else { model.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }
}

struct BlockerRow: View {
    let blocker: BlockerInfo
    let state: BlockerState
    let meta: RuleMeta?
    let open: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(blocker.title).font(.headline)
                    Text(stateText).font(.caption).foregroundStyle(color)
                }
                Text(blocker.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let meta = meta {
                    Text("\(meta.rules.formatted()) rules · lists updated \(meta.generated)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button("Set Up in Safari", action: open)
        }
        .padding(12)
    }

    private var stateText: String {
        switch state {
        case .unknown: return "Checking…"
        case .enabled: return "On"
        case .disabled: return "Off — turn it on in Safari"
        case .missing(let why): return "Not recognized by Safari (\(why))"
        }
    }

    private var color: Color {
        switch state {
        case .unknown: return .gray
        case .enabled: return .green
        case .disabled: return .orange
        case .missing: return .red
        }
    }
}

struct HelpBox: View {
    let signed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How to use").font(.headline)
            step("1.circle", "Turn on the four items in Safari › Settings › Extensions. The button below opens that screen.")
            step("person.2.circle", "If you use Safari profiles (a profile icon at the left of the tab bar), each profile must be turned on separately: Safari › Settings › Profiles › the profile › Extensions tab. The ‘On’ shown here refers to the default profile.")
            step("2.circle", "To turn blocking off for one site only, open that site and choose Safari menu › ‘Settings for <site>…’ › uncheck ‘Enable content blockers’.")
            step("3.circle", "The ‘Check It Works’ button opens a test site so you can confirm blocking is active. Pages that were already open must be reloaded after enabling.")
            step("4.circle", "To update the block lists, run ./update-rules.sh in the project folder and then ./install.sh.")
            step("info.circle", "Video ads cannot be blocked by content blockers, so ‘Video Ad Skipper’ ends them inside the page instead. It may stop working for a while when the site changes its structure.")
            if !signed {
                step("exclamationmark.triangle.fill",
                     "This build is signed ad hoc (no certificate). Turn on Safari › Settings › Advanced › ‘Show features for web developers’, then Develop › Developer Settings… › ‘Allow unsigned extensions’ for the extensions to appear. Safari resets that setting when it quits, so sign with an Apple Development certificate for regular use (see README).")
                    .foregroundStyle(.orange)
            }
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func step(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon)
        }
    }
}
