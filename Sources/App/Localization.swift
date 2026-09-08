// In-app language handling. The app follows the system language by default and can be switched to any supported
// language from the menu in the app header; the choice is stored in UserDefaults and applied immediately.
// String tables live in Resources/App/Localizations/<code>.json and are copied into the bundle by build.sh.
// Note: extension names shown inside Safari's own settings come from InfoPlist.strings / _locales in the bundles
// and always follow the system language, not this setting.
import Foundation
import SwiftUI

@MainActor
final class Lang: ObservableObject {
    static let supported: [(code: String, name: String)] = [
        ("ko", "한국어"), ("en", "English"), ("ja", "日本語"), ("zh-Hans", "中文（简体）"),
    ]
    static let systemCode = "system"
    private static let defaultsKey = "language"

    @Published var selection: String {
        didSet { UserDefaults.standard.set(selection, forKey: Lang.defaultsKey) }
    }
    private var tables: [String: [String: String]] = [:]

    init() {
        selection = UserDefaults.standard.string(forKey: Lang.defaultsKey) ?? Lang.systemCode
        for (code, _) in Lang.supported {
            if let url = Bundle.main.url(forResource: code, withExtension: "json", subdirectory: "Localizations"),
               let data = try? Data(contentsOf: url),
               let table = try? JSONDecoder().decode([String: String].self, from: data) {
                tables[code] = table
            }
        }
    }

    /// The language actually in use: the chosen one, or the system language mapped onto a supported one.
    var resolved: String {
        selection == Lang.systemCode ? Lang.match(Locale.preferredLanguages) : selection
    }

    static func match(_ preferred: [String]) -> String {
        for language in preferred {
            let lower = language.lowercased()
            if lower.hasPrefix("ko") { return "ko" }
            if lower.hasPrefix("ja") { return "ja" }
            if lower.hasPrefix("zh") { return "zh-Hans" }
            if lower.hasPrefix("en") { return "en" }
        }
        return "en"
    }

    /// Looks up a string; `{name}` placeholders are replaced from `args`. Falls back to English, then to the key itself.
    func t(_ key: String, _ args: [String: String] = [:]) -> String {
        var text = tables[resolved]?[key] ?? tables["en"]?[key] ?? key
        for (name, value) in args { text = text.replacingOccurrences(of: "{\(name)}", with: value) }
        return text
    }
}
