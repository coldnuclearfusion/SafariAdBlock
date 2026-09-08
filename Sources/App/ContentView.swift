import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var lang: Lang
    @StateObject private var model = BlockerModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(lang.t("app.title")).font(.title2.bold())
                    Text(lang.t("app.subtitle"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                LanguagePicker()
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
                Button(lang.t("button.openSettings")) { model.openSafariSettings() }
                Button(lang.t("button.check")) { model.openCheckPage() }
                Button(lang.t("button.reload")) { model.reloadAll() }
                    .disabled(model.busy)
                Spacer()
                Button(lang.t("button.refresh")) { model.refresh() }
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
        .frame(width: 640)
        .onAppear {
            model.lang = lang
            // When install.sh launches the app with `--reload`, push the new rules to Safari right away.
            if CommandLine.arguments.contains("--reload") { model.reloadAll() } else { model.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }
}

struct LanguagePicker: View {
    @EnvironmentObject private var lang: Lang

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Picker(lang.t("language.label"), selection: $lang.selection) {
                Text(lang.t("language.system")).tag(Lang.systemCode)
                ForEach(Lang.supported, id: \.code) { item in
                    Text(item.name).tag(item.code)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            Text(lang.t("language.note"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 220, alignment: .trailing)
        }
    }
}

struct BlockerRow: View {
    @EnvironmentObject private var lang: Lang
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
                    Text(lang.t("ext.\(blocker.folder).name")).font(.headline)
                    Text(stateText).font(.caption).foregroundStyle(color)
                }
                Text(lang.t("ext.\(blocker.folder).detail"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let meta = meta {
                    Text(lang.t("meta.rules", ["count": meta.rules.formatted(), "date": meta.generated]))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button(lang.t("button.setup"), action: open)
        }
        .padding(12)
    }

    private var stateText: String {
        switch state {
        case .unknown: return lang.t("state.checking")
        case .enabled: return lang.t("state.on")
        case .disabled: return lang.t("state.off")
        case .missing(let why): return lang.t("state.missing", ["error": why])
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
    @EnvironmentObject private var lang: Lang
    let signed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lang.t("help.title")).font(.headline)
            step("1.circle", lang.t("help.step1"))
            step("person.2.circle", lang.t("help.profiles"))
            step("2.circle", lang.t("help.step2"))
            step("3.circle", lang.t("help.step3"))
            step("4.circle", lang.t("help.step4"))
            step("info.circle", lang.t("help.video"))
            if !signed {
                step("exclamationmark.triangle.fill", lang.t("help.unsigned"))
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
