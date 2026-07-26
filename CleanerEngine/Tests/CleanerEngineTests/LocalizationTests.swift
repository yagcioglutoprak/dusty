import XCTest
@testable import CleanerEngine

/// The engine falls back to English whenever a lookup misses, which is the right
/// behaviour at runtime but hides a broken resource bundle completely: every string
/// would silently read English and nothing would fail. These tests read the tables
/// directly so a missing bundle, a dropped locale, or a target added without a
/// translation shows up as a red test instead of a quietly untranslated panel.
final class LocalizationTests: XCTestCase {
    private static let locales = ["en", "fr", "es", "ru"]

    private func table(for locale: String) throws -> Bundle {
        let path = try XCTUnwrap(
            L10n.resourceBundle.path(forResource: locale, ofType: "lproj"),
            "\(locale).lproj is missing from the engine resource bundle"
        )
        return try XCTUnwrap(Bundle(path: path))
    }

    /// The resource bundle resolved to something real, not the fallback.
    func testResourceBundleIsFound() throws {
        XCTAssertNotNil(L10n.resourceBundle.path(forResource: "en", ofType: "lproj"))
    }

    /// Every registry target has a name in every language.
    func testEveryTargetIsTranslatedInEveryLocale() throws {
        for locale in Self.locales {
            let bundle = try table(for: locale)
            for target in CleanupTargetRegistry.all {
                let key = "target.\(target.id)"
                let value = bundle.localizedString(forKey: key, value: "MISSING", table: nil)
                XCTAssertNotEqual(value, "MISSING", "\(locale) is missing \(key)")
            }
        }
    }

    /// Level titles and subtitles too: they head every section of the panel.
    func testEveryLevelIsTranslatedInEveryLocale() throws {
        let keys = CleanupLevel.allCases.flatMap { level -> [String] in
            let slug: String
            switch level {
            case .safe: slug = "safe"
            case .developer: slug = "developer"
            case .deep: slug = "deep"
            }
            return ["level.\(slug).title", "level.\(slug).subtitle"]
        }
        for locale in Self.locales {
            let bundle = try table(for: locale)
            for key in keys {
                let value = bundle.localizedString(forKey: key, value: "MISSING", table: nil)
                XCTAssertNotEqual(value, "MISSING", "\(locale) is missing \(key)")
            }
        }
    }

    /// Translations must not drift away from English: a format string with the wrong
    /// number of placeholders crashes `String(format:)` at runtime.
    func testFormatPlaceholdersMatchEnglish() throws {
        let formatKeys = [
            "advisory.orphan.detail",
            "advisory.stale.detail",
            "format.gbFree",
            "format.mbFree"
        ]
        let english = try table(for: "en")
        for key in formatKeys {
            let reference = placeholders(in: english.localizedString(forKey: key, value: "", table: nil))
            for locale in Self.locales.dropFirst() {
                let bundle = try table(for: locale)
                let translated = placeholders(in: bundle.localizedString(forKey: key, value: "", table: nil))
                XCTAssertEqual(translated, reference, "\(locale) placeholders drifted for \(key)")
            }
        }
    }

    /// Translations actually differ from English, so a copied-over file cannot pass.
    func testTranslationsAreNotJustEnglish() throws {
        for locale in Self.locales.dropFirst() {
            let bundle = try table(for: locale)
            XCTAssertNotEqual(
                bundle.localizedString(forKey: "level.safe.title", value: "", table: nil),
                "Level 1: Safe",
                "\(locale) still has the English level title"
            )
        }
    }

    /// Sorted multiset of `%…` conversions, so word order can move but the argument
    /// list cannot change. `%%` is a literal percent rather than a conversion, and
    /// has to be dropped first or the text after it gets read as one.
    private func placeholders(in format: String) -> [String] {
        let stripped = format.replacingOccurrences(of: "%%", with: "")
        let pattern = "%(?:\\d+\\$)?[-+ #0]*\\d*(?:\\.\\d+)?(?:@|d|f|ld|lld|s)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(stripped.startIndex..., in: stripped)
        return regex.matches(in: stripped, range: range)
            .compactMap { Range($0.range, in: stripped).map { String(stripped[$0]) } }
            .sorted()
    }
}
