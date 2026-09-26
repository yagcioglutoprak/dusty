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

## Memory

The memory feature sits beside the cleaning pipeline and never touches a file,
so it has no path through `SafetyValidator`. It is split the same way:

```text
CleanerEngine                                  Dusty app
  MemoryMonitor         kernel VM counters,      MemoryModel     samples, tracks which app
                        swap, pressure level                     was used when, quits and
  ProcessMemoryScanner  per-process footprint,                   reopens apps (after the
                        responsible process                      user confirms)
  AppMemoryGrouping     processes -> apps (pure) MemoryView      card, screen, sheet, receipt
  MemoryAdvisor         idle suggestions,
                        growth, alert policy (pure)
```

Everything that decides (grouping, suggestions, growth, when to alert) is pure
and unit tested. The only action, quitting an app, lives in the app layer and
uses `NSRunningApplication.terminate()`, the same request ⌘Q sends: apps can
save, ask, or refuse. Nothing is force quit, no signal is sent to any process,
and nothing runs as root. `dusty memory` and the Shortcuts action only read.
