# Architecture Overview

Dusty is split into two layers: a thin menu bar app and a UI-free cleaning
engine. The boundary keeps deletion rules testable without SwiftUI.

```text
                 +-----------------------------+
                 | Dusty menu bar app          |
                 | SwiftUI, MenuBarExtra,      |
                 | settings, panels, alerts    |
                 +--------------+--------------+
                                |
                                | asks for scans and cleans
                                v
                 +-----------------------------+
                 | CleanerEngine               |
                 | scan, size, target registry,|
                 | deletion plan, undo/logging |
                 +--------------+--------------+
                                |
                                | every delete must pass through
                                v
                 +-----------------------------+
                 | SafetyValidator             |
                 | allowlist, protected paths, |
                 | symlink and volume checks   |
                 +-----------------------------+
```

## Layer Responsibilities

`Dusty/` contains the macOS app. It owns the menu bar surface, settings,
notifications, confirmation sheets, and view models. It should stay a thin
presentation layer over the engine.

`CleanerEngine/` contains the Swift package used by both the app and CLI. It
owns cleanup targets, scanning, size calculation, deletion plans, undo support,
and deletion logs. It has no SwiftUI dependency and is covered by unit tests.

`SafetyValidator` is the authorization point for deletion. It rejects paths
outside registered targets, protected user folders, symlink escapes, and
non-boot-volume paths before an item can be removed or restored.

The intended dependency direction is:

```text
Dusty app -> CleanerEngine -> SafetyValidator
```

No UI code should bypass the engine, and no delete path should bypass
`SafetyValidator`.
