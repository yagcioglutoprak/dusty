import Foundation
import AppKit

/// Every string the panel puts in front of a person goes through here.
///
/// Keys are semantic (`panel.scan.rescan`), not the English sentence, so rewording
/// the English copy never orphans three translations. The English text is passed at
/// the call site as the fallback value: it documents what the key says, and a key
/// that is missing from a table degrades to real English rather than showing
/// `panel.scan.rescan` in the UI.
enum L10n {
    static func t(_ key: String, _ english: String) -> String {
        Bundle.main.localizedString(forKey: key, value: english, table: nil)
    }

    /// A localized format string filled in with `args`. Plural keys live in
    /// `Localizable.stringsdict` and resolve through this same call: the lookup
    /// returns their `%#@…@` format and `String(format:)` expands it.
    static func f(_ key: String, _ english: String, _ args: CVarArg...) -> String {
        let format = Bundle.main.localizedString(forKey: key, value: english, table: nil)
        return String(format: format, locale: .current, arguments: args)
    }
}

/// The language the panel is drawn in.
///
/// macOS can already do this from System Settings, but only for apps it has seen
/// declare localizations, and a menu bar app is easy to miss in that list. Picking
/// the language in Dusty writes the same `AppleLanguages` preference the system
/// would, scoped to Dusty's own defaults domain, so nothing else on the Mac changes.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case french = "fr"
    case spanish = "es"
    case russian = "ru"

    var id: String { rawValue }

    /// Written in the language itself: a Russian speaker looking for their language
    /// should not have to read "Russian" in English to find it.
    var label: String {
        switch self {
        case .system: return L10n.t("settings.language.system", "Match system")
        case .english: return "English"
        case .french: return "Français"
        case .spanish: return "Español"
        case .russian: return "Русский"
        }
    }

    private static let defaultsKey = "AppleLanguages"

    /// The override the picker has written, or `.system` when there is none.
    ///
    /// Read out of Dusty's own defaults domain rather than through
    /// `UserDefaults.standard`: the standard search list falls through to
    /// `NSGlobalDomain`, where `AppleLanguages` always exists, so a plain lookup
    /// answers with the Mac's system language and never reports "no override".
    static var current: AppLanguage {
        guard let domain = Bundle.main.bundleIdentifier,
              let stored = UserDefaults.standard.persistentDomain(forName: domain)?[defaultsKey] as? [String],
              let first = stored.first
        else { return .system }
        // Stored values can carry a region ("fr-FR"), so match on the language code.
        let code = first.split(separator: "-").first.map(String.init) ?? first
        return AppLanguage.allCases.first { $0.rawValue == code } ?? .system
    }

    /// The language the app was launched with. Bundles resolve their localization
    /// once at launch, so this is what the panel is actually drawn in no matter what
    /// the picker has been set to since. Captured in `AppSettings.init`, before
    /// anything can write the preference.
    static let launchLanguage = current

    static func apply(_ language: AppLanguage) {
        if language == .system {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: defaultsKey)
        }
    }

    /// Start a fresh copy, then quit this one. There is no way to re-resolve a
    /// bundle's localization in place, and a menu bar app restarts cheaply.
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            // Give the new instance a moment to claim its menu bar slot, so the icon
            // never blinks out entirely during the handover.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                NSApp.terminate(nil)
            }
        }
    }
}
