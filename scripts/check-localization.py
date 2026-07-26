#!/usr/bin/env python3
"""Check that every localized string in the app is present in every language.

The engine has its own coverage tests (CleanerEngineTests/LocalizationTests), but
the app target has no test bundle, and `L10n` deliberately falls back to English
when a key is missing. That fallback is right at runtime and useless as a signal:
a forgotten translation just quietly reads English. This script is the signal.

It fails on:
  * a key used in Swift that is missing from any locale's table
  * a key in a translation that no longer exists in English (dead weight)
  * a translation whose %-placeholders differ from English, which crashes
    String(format:) at runtime rather than merely looking wrong

Run from the repo root:  python3 scripts/check-localization.py
"""

import os
import plistlib
import re
import sys

LOCALES = ["en", "fr", "es", "ru"]
APP_RESOURCES = "Dusty/Dusty/Resources"
APP_SOURCES = "Dusty/Dusty"
ENGINE_RESOURCES = "CleanerEngine/Sources/CleanerEngine/Resources"

# Keys chosen at the call site by a condition, so the literal never appears
# next to an L10n call.
DYNAMIC_KEYS = {
    "target.a11y.showItems",
    "target.a11y.hideItems",
    "result.skipped.show",
    "result.skipped.hide",
}

PLACEHOLDER = re.compile(r"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:@|d|f|ld|lld|s)")


def placeholders(fmt):
    """Sorted conversions in a format string, so word order may move but the
    argument list may not. `%%` is a literal percent, not a conversion, and has
    to go first or its trailing text gets read as one."""
    return sorted(PLACEHOLDER.findall(fmt.replace("%%", "")))


def strings_keys(path):
    with open(path, encoding="utf-8") as handle:
        return dict(re.findall(r'^"([^"]+)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', handle.read(), re.M))


def table(resources, locale):
    """All keys for one locale, from Localizable.strings plus .stringsdict."""
    entries = strings_keys(os.path.join(resources, locale + ".lproj", "Localizable.strings"))
    plural_path = os.path.join(resources, locale + ".lproj", "Localizable.stringsdict")
    if os.path.exists(plural_path):
        with open(plural_path, "rb") as handle:
            for key, value in plistlib.load(handle).items():
                entries[key] = value["NSStringLocalizedFormatKey"]
    return entries


def keys_used_in_swift(root):
    used = set()
    for base, _, files in os.walk(root):
        for name in files:
            if not name.endswith(".swift"):
                continue
            with open(os.path.join(base, name), encoding="utf-8") as handle:
                source = handle.read()
            used |= set(re.findall(r'L10n\.[tf]\(\s*"([^"]+)"', source))
            used |= set(re.findall(r'LocalizedStringResource\(\s*"([^"]+)"', source))
    return used | DYNAMIC_KEYS


def check(name, resources, used=None):
    problems = []
    tables = {locale: table(resources, locale) for locale in LOCALES}
    english = tables["en"]

    if used is not None:
        for key in sorted(used - set(english)):
            problems.append("%s: key used in code but missing from en: %s" % (name, key))

    for locale in LOCALES[1:]:
        translated = tables[locale]
        for key in sorted(set(english) - set(translated)):
            problems.append("%s: %s is missing %s" % (name, locale, key))
        for key in sorted(set(translated) - set(english)):
            problems.append("%s: %s has %s, which no longer exists in en" % (name, locale, key))
        for key in sorted(set(english) & set(translated)):
            want = placeholders(english[key])
            got = placeholders(translated[key])
            if want != got:
                problems.append(
                    "%s: %s placeholders differ for %s: en %s vs %s %s"
                    % (name, locale, key, want, locale, got)
                )
    return problems, len(english)


def main():
    problems = []

    app_problems, app_count = check("app", APP_RESOURCES, keys_used_in_swift(APP_SOURCES))
    problems += app_problems
    engine_problems, engine_count = check("engine", ENGINE_RESOURCES)
    problems += engine_problems

    # Every cleanup target needs a name, and the registry is the list that grows.
    with open("CleanerEngine/Sources/CleanerEngine/CleanupTargetRegistry.swift", encoding="utf-8") as handle:
        target_ids = set(re.findall(r'^\s*id:\s*"([^"]+)"', handle.read(), re.M))
    for locale in LOCALES:
        names = table(ENGINE_RESOURCES, locale)
        for target in sorted(target_ids):
            if "target." + target not in names:
                problems.append("engine: %s has no name for target %s" % (locale, target))

    if problems:
        for problem in problems:
            print("FAIL " + problem)
        print("\n%d problem(s)." % len(problems))
        return 1

    print("app: %d keys x %d locales" % (app_count, len(LOCALES)))
    print("engine: %d keys x %d locales, %d targets named" % (engine_count, len(LOCALES), len(target_ids)))
    print("localization OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
