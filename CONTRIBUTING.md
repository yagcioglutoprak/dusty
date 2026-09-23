# Contributing to Dusty

Thanks for taking the time. Dusty stays small and careful on purpose, so a few
things are worth knowing before you open a pull request.

## The shape of the project

```
CleanerEngine/    Swift package: scanning, sizing, deletion, safety. No UI. Fully tested.
Dusty/            SwiftUI menu bar app that talks to the engine.
```

The engine has zero SwiftUI dependencies and carries the safety guarantees, so
that is where most logic and all tests live. The app is a thin presentation
layer on top of it.

## Building

You need Xcode 16 or later (the full app, not just the Command Line Tools).

```bash
# Run the engine tests
cd CleanerEngine && swift test

# Open the app
cd Dusty && open Dusty.xcodeproj   # then run the Dusty scheme
```

The Xcode project is generated from `Dusty/project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen). It is committed so you can
build without XcodeGen installed. If you change `project.yml`, regenerate it:

```bash
cd Dusty && xcodegen generate
```

## Changing the panel

Every screen of the panel can be rendered from fixture data, without scanning
or touching your disk. A Debug build takes a flag:

```bash
cd Dusty
xcodebuild -scheme Dusty -configuration Debug -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
build/Build/Products/Debug/Dusty.app/Contents/MacOS/Dusty --render-snapshots /tmp/dusty-snapshots
```

That writes each state (welcome, home, scanning, a level, the confirmation,
the undo receipt, settings) in light and dark. CI does the same on every
branch that touches `Dusty/` and attaches the PNGs to the run as
`panel-snapshots`, so reviewers can see a UI change without building it.

## Adding a cleanup target

This is the most common contribution and it is meant to be a one-liner. Add an
entry to `CleanerEngine/Sources/CleanerEngine/CleanupTargetRegistry.swift`:

```swift
CleanupTarget(
    id: "rust-cargo-cache",
    displayName: "Cargo Registry Cache",
    level: .developer,
    pathTemplates: ["~/.cargo/registry/cache"],
    category: "Package Manager",
    deletesContentsNotDirectory: true,
    regenerates: true
)
```

The scanner, the UI section, and the safety checks all pick it up from the
registry. The one other thing a target needs is a name in every language the
panel speaks: add a `"target.<id>" = "...";` line to `Localizable.strings` in
each folder under `CleanerEngine/Sources/CleanerEngine/Resources/`. If you do
not speak one of those languages, copy the English name and say so in the pull
request. `python3 scripts/check-localization.py` checks this, and CI runs it.

## Translating the panel

Dusty speaks English, French, Spanish, and Russian, and every other language is
open. A translation needs no Swift: it is two string tables plus a few lines to
register the language. The steps, and one issue per wanted language, are in
[Help translate Dusty into your language](https://github.com/yagcioglutoprak/dusty/issues/33).

## The one rule that is not negotiable

Every deletable path has to be reachable from the allowlist in the registry.
`SafetyValidator` is the only thing that authorizes a deletion, and it is the
reason people can trust Dusty. Do not add a code path that deletes something the
validator has not approved. If you touch `SafetyValidator`, add a test for it.

## Before you open a PR

- `swift test` passes
- `python3 scripts/check-localization.py` passes
- the app builds
- no new path can be deleted without going through `SafetyValidator`
- no em dashes in code, comments, or docs (project style)

Small, focused pull requests get reviewed fastest.
