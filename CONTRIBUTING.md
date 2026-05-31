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

No other code changes are required. The scanner, the UI section, and the safety
checks all pick it up from the registry.

## The one rule that is not negotiable

Every deletable path has to be reachable from the allowlist in the registry.
`SafetyValidator` is the only thing that authorizes a deletion, and it is the
reason people can trust Dusty. Do not add a code path that deletes something the
validator has not approved. If you touch `SafetyValidator`, add a test for it.

## Before you open a PR

- `swift test` passes
- the app builds
- no new path can be deleted without going through `SafetyValidator`
- no em dashes in code, comments, or docs (project style)

Small, focused pull requests get reviewed fastest.
