import Foundation

/// Localized copy the engine owns: level names, target names, advisory wording.
/// The app reads these straight off `CleanupLevel` and `CleanupTarget`, so the
/// translations have to live beside the registry rather than in the UI layer.
///
/// Every call carries its English text as the fallback value. That way a missing
/// key, a stripped resource bundle, or a half-finished translation degrades to
/// readable English instead of leaking a raw key like `target.npm-cache` into the
/// panel.
enum L10n {
    /// A plain localized string.
    static func t(_ key: String, _ english: String) -> String {
        resourceBundle.localizedString(forKey: key, value: english, table: nil)
    }

    /// A localized format string filled in with `args`. Also the entry point for
    /// plural keys: `.stringsdict` entries resolve through the same lookup, and
    /// `String(format:)` expands their `%#@…@` tokens.
    static func f(_ key: String, _ english: String, _ args: CVarArg...) -> String {
        let format = resourceBundle.localizedString(forKey: key, value: english, table: nil)
        return String(format: format, locale: .current, arguments: args)
    }

    /// The resource bundle SwiftPM builds for this target.
    ///
    /// Deliberately not `Bundle.module`: that accessor calls `fatalError()` when the
    /// bundle is missing, which would turn a packaging slip into a crash in a disk
    /// cleaner. The search order matches `Bundle.module`'s own, and the fallback is
    /// simply a bundle with no tables, so lookups return the English defaults.
    static let resourceBundle: Bundle = {
        let name = "CleanerEngine_CleanerEngine.bundle"
        let token = Bundle(for: BundleToken.self)
        let roots: [URL?] = [
            Bundle.main.resourceURL,
            token.resourceURL,
            Bundle.main.bundleURL,
            token.bundleURL.deletingLastPathComponent()
        ]
        for root in roots.compactMap({ $0 }) {
            if let found = Bundle(url: root.appendingPathComponent(name)) { return found }
        }
        return token
    }()

}

private final class BundleToken {}
