<div align="center">

<img src="Dusty/Dusty/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="96" height="96" alt="">

# Dusty

**Free up disk space on your Mac, and see every file before it goes.**

A free, open-source alternative to CleanMyMac that lives in your menu bar.

[![Release](https://img.shields.io/github/v/release/yagcioglutoprak/dusty?color=3b82f6&label=Release)](https://github.com/yagcioglutoprak/dusty/releases/latest)
[![CI](https://github.com/yagcioglutoprak/dusty/actions/workflows/ci.yml/badge.svg)](https://github.com/yagcioglutoprak/dusty/actions/workflows/ci.yml)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/github/license/yagcioglutoprak/dusty?color=6366f1)](LICENSE)
[![Stars](https://img.shields.io/github/stars/yagcioglutoprak/dusty?label=Stars&color=38bdf8)](https://github.com/yagcioglutoprak/dusty/stargazers)

**English** · [简体中文](docs/i18n/README.zh-CN.md) · [日本語](docs/i18n/README.ja.md) · [Español](docs/i18n/README.es.md) · [Français](docs/i18n/README.fr.md) · [Русский](docs/i18n/README.ru.md)

[**Download**](https://github.com/yagcioglutoprak/dusty/releases/latest) ·
[Install](#install) ·
[What it cleans](#what-it-cleans) ·
[Why it is safe](#why-you-can-trust-it) ·
[Command line](#command-line-and-shortcuts) ·
[FAQ](#faq)

<br>

<img src="docs/screenshots/demo.gif?v=4" width="480" alt="Dusty's first-run welcome, a scan filling up, the reclaimable space by level, a Safe clean with its undo countdown, then the Developer level item by item">

<sub>If Dusty saves you space, a GitHub star helps more Mac users find a safer cleaner.</sub>

</div>

## At a glance

- **It shows its work.** Every path and its size are on screen before anything
  is deleted. Scanning never deletes.
- **It can only touch junk.** Deletes come from a fixed, readable allowlist of
  caches and leftovers. Your documents, photos, and mail are out of reach by
  design.
- **Every clean can be undone.** Items pass through the Trash with an Undo
  button for a few seconds, and every deletion is written to a log.
- **It knows developer junk.** Xcode DerivedData, simulators, npm, Cargo, and
  pip caches, and the `node_modules` of projects you forgot about.
- **It is fast.** A full scan of a working dev machine (M3, about 18 GB across
  866 paths) takes about 5 seconds.
- **It stays out of the way.** Free space sits in your menu bar, a background
  scan keeps the "to clean" figure current, and the app updates itself.
- **It costs nothing.** Free, MIT licensed, no account, no telemetry. The panel
  speaks English, French, Spanish, and Russian.

## Install

```bash
brew install --cask yagcioglutoprak/tap/dusty
```

Or download `Dusty.dmg` from the
[latest release](https://github.com/yagcioglutoprak/dusty/releases/latest),
drag it to Applications, and open it. Both are signed and notarized by Apple.

Dusty shows up in your menu bar as a disk icon with your free space next to it.
It needs macOS 13 Ventura or later, and it keeps itself up to date (you can turn
that off in Settings).

## How it works

1. **Scan.** Click the disk icon and run a scan. Dusty measures every cleanup
   target and sorts what it finds into three levels, largest first.
2. **Review.** One tap cleans the Safe level. Or open any level and untick
   whatever you want to keep, item by item. The bar at the bottom always shows
   what a clean would take.
3. **Clean, with a way back.** A confirmation lists every path and your free
   space before and after. After the clean you get a few seconds to change your
   mind: press Undo (or ⌘Z) and the cleaned items go back where they were.

<p align="center">
<img src="docs/screenshots/overview.png" alt="Dusty's panel: the home screen with a storage bar and a one-tap Safe clean, the Developer level item by item, the confirmation sheet, and Settings">
</p>

## What it cleans

Three levels, from "do this anytime" to "look before you leap."

| Level | What it clears | Why it is safe |
| --- | --- | --- |
| 🟢 **Safe** | User caches, app logs, Trash, browser caches (Safari, Chrome, Firefox, Edge, Brave, Arc), and app caches (Slack, Discord, Notion, Spotify, VS Code, Cursor, Signal, Obsidian, Microsoft Teams, Zoom update installers, Telegram media cache) | Regenerates on its own, zero functional impact |
| 🟣 **Developer** | Xcode DerivedData, old DeviceSupport, unavailable simulators, package manager caches (npm, yarn, pnpm, pip, uv, Bun, Deno, Cargo, Go, Homebrew, Composer, Gradle, CocoaPods, SwiftPM, Dart/Flutter pub), Cypress binary cache, dev tool caches in `~/.cache` (never the AI model stores in it), JetBrains and Unity caches, opt-in Maven local repository, optional `docker system prune` | Rebuilds or re-downloads next time you need it |
| 🟠 **Deep** | Old `.dmg` / `.pkg` installers in Downloads, Xcode archives, unused simulators, local Time Machine snapshots, aged diagnostic logs, opt-in Ollama models, opt-in AI model caches (Hugging Face, PyTorch, Whisper, LM Studio), stale project artifacts | Nothing is selected until you tick it |

**Forgotten projects.** The Deep level also looks where cleaners never do:
inside your projects. It finds the `node_modules`, Cargo `target` folder, or
virtualenv of a project you have not touched in a month. The rules are strict
on purpose. The tool's manifest has to sit right next to the artifact (a folder
you happened to name `target` is never offered), activity is judged by your own
files and git history, and if you touch a project between the scan and the
clean, its artifacts are refused.

**Insights.** After a scan, Dusty points out what a person would spot: 12 GB of
DerivedData with no Xcode installed anymore, a cache nothing has written to
since spring, a disk on course to fill up in three weeks. Click one and the
panel opens that item. Insights only point; they never select or delete
anything.

## Hands-off mode

- **Background scan** (on by default, every 4 hours) keeps the "N GB to clean"
  figure in the menu bar current. It never deletes anything.
- **Auto clean** (off by default) runs on a schedule (daily, weekly, or every
  two weeks), or the moment free space drops below a threshold you pick. You
  choose the scope: Safe caches only, or Developer caches too.

Unattended cleans follow the same rules as the panel. Apps that are open are
skipped, a notification reports what was freed, and every path lands in the
deletion log. They also stand down on Low Power Mode and never run while dry
run is your default.

## Why you can trust it

"Mac cleaner" usually means "app that deletes things you cannot see." Dusty is
built the other way around. The deletion logic is a separate, fully tested
Swift package (`CleanerEngine`) with no UI, and a single component,
`SafetyValidator`, is the only thing that can authorize a delete. It enforces:

- **Allowlist only.** A path is deletable only if it descends from an explicit
  target in [`CleanupTargetRegistry`](CleanerEngine/Sources/CleanerEngine/CleanupTargetRegistry.swift).
  There is no "delete everything except" logic anywhere in the codebase.
- **Protected folders are off limits.** Documents, Desktop, Pictures, the Photos
  library, Music, Movies, Mail, iCloud Drive, Keychains, and Application Support
  are rejected even as prefixes. The only Application Support exceptions are the
  specific cache subfolders named by registered targets, never an app's whole
  folder.
- **No symlink escapes.** Symlinks are never followed, including a symlinked
  parent folder. The path is resolved and checked again against the allowlist.
- **Boot volume only, no root.** Dusty never runs as root or uses `sudo`, and
  nothing SIP-protected is touched. The only paths outside your home folder are
  the Deep level's system diagnostic logs under `/Library/Logs`.
- **Undo at every level.** Cleans park items in the Trash first. Restores are
  checked the same way deletes are, so an item can only go back to a place its
  target is allowed to touch.
- **Dry run.** One switch makes every clean report what it would delete, and
  delete nothing.
- **A written record.** Every action (time, path, bytes) is appended to
  `~/Library/Application Support/Dusty/deletion-log.jsonl`.

If a permission error hits one file, that file is skipped and the rest carries
on. The longer design writeup, with code, is
[How Dusty is built to avoid deleting the wrong thing](https://toprak.sh/dusty/safety/).

Found a way to make it delete something outside the allowlist? Please report it
privately: see [SECURITY.md](.github/SECURITY.md).

## How it compares

The honest version, set against the paid cleaners (CleanMyMac and the like):

| | Dusty | CleanMyMac and similar |
| --- | --- | --- |
| Price | Free, MIT licensed | Paid license or subscription |
| Source code | Open, every deletion rule is readable | Closed |
| What it can delete | A fixed allowlist, nothing outside it | Broad categories, not all of them visible |
| Sizes shown before deleting | Always, per path | Varies |
| Undo and a written deletion log | Yes | Varies |
| CLI and Shortcuts automation | Yes | Rare |
| Account or telemetry | None | Often |

## Command line and Shortcuts

The same engine, allowlist, and safety rules, scriptable. The `dusty` CLI ships
inside the app, and the Homebrew cask puts it on your `PATH`:

```bash
dusty scan                                    # measure all three levels, deletes nothing
dusty scan --json                             # the same, machine-readable
dusty clean                                   # print the deletion plan for the Safe level
dusty clean --yes                             # actually delete it
dusty clean --level developer --trash --yes   # park dev caches in the Trash
dusty targets                                 # print the entire allowlist
```

`clean` touches nothing without `--yes`. It only deletes the items the app would
select on its own (installers, Xcode archives, simulators, Docker, and AI models
stay manual-pick only), and it skips any target whose app is open. Installed
from the DMG instead of Homebrew? Link it once:

```bash
ln -s /Applications/Dusty.app/Contents/Helpers/dusty /usr/local/bin/dusty
```

Two Shortcuts actions, **Clean Safe Items** and **Get Reclaimable Space**, put
Dusty in any macOS automation.

## Keyboard shortcuts

| Keys | In the panel |
| --- | --- |
| ⌘R | Rescan |
| ⌘, | Settings |
| Esc | Back |
| ⌘Z | Undo the last clean |
| ⌘Q | Quit |

## Settings

<details>
<summary>Everything you can change</summary>

- **General:** launch at login, and the panel language (English, French,
  Spanish, Russian, or match the system)
- **Menu bar:** show free space, a percentage, or just the icon; show or hide
  the "N GB to clean" suffix; how often free space refreshes (default 30 s)
- **Automation:** background scan and how often (default every 4 hours);
  scheduled auto clean; auto clean when free space runs low, and the threshold;
  whether unattended cleans include Developer caches
- **Cleanup defaults:** dry run by default; keep Developer and Deep items in
  the Trash instead of purging them after Undo; the age for system logs to be
  offered (default 30 days)
- **Statistics:** space reclaimed all-time, number of cleans, recent cleans
- **Updates:** automatic checks, automatic install, and Check for Updates Now

</details>

## Full Disk Access

Dusty is not sandboxed, because a sandboxed app cannot reach the caches it is
meant to clean. Everything under `~/Library` works out of the box. Only a
couple of system diagnostic paths in the Deep level need Full Disk Access:

1. Open **System Settings > Privacy & Security > Full Disk Access**
2. Add **Dusty**
3. Reopen the app

Without it, those few paths are skipped and everything else works.

## FAQ

<details>
<summary><b>Is it actually free?</b></summary>

Yes. MIT licensed, no trial, no upsell, no account.
</details>

<details>
<summary><b>Can it delete my projects or documents?</b></summary>

No. Those folders are rejected by the validator before anything is touched, and
only allowlisted cache and artifact paths are ever in scope. Even a forgotten
project only ever offers its build artifacts, never your code.
</details>

<details>
<summary><b>What if I clean something I needed?</b></summary>

Press Undo (or ⌘Z) in the few seconds after a clean and the items go back where
they were. The one exception is emptying the Trash, which is final, just like in
Finder. The caches Dusty picks on its own regenerate or re-download when
something needs them, and the deletion log records every path.
</details>

<details>
<summary><b>How does it update?</b></summary>

With [Sparkle](https://sparkle-project.org): it checks once a day and installs
signed updates on its own. You can turn either off in **Settings > Updates**.
Homebrew installs update the same way.
</details>

<details>
<summary><b>Why not the Mac App Store?</b></summary>

The App Store requires sandboxing, and a sandboxed app cannot reach the caches
Dusty cleans. The trade off would defeat the point.
</details>

<details>
<summary><b>How is this different from <code>rm -rf ~/Library/Caches</code>?</b></summary>

It sizes everything first, skips what is in use, gives every clean an undo
window, logs what it did, and refuses anything outside the allowlist.
</details>

## Contributing

Pull requests are welcome, especially new cleanup targets and
[translations](https://github.com/yagcioglutoprak/dusty/issues/33). See
[CONTRIBUTING.md](CONTRIBUTING.md), pick up a
[good first issue](https://github.com/yagcioglutoprak/dusty/labels/good%20first%20issue),
and share scan results or a missing cache in
[Discussions](https://github.com/yagcioglutoprak/dusty/discussions/5).

**Add a cleanup target.** Targets are data, not code. One entry in
`CleanupTargetRegistry.swift` and the scanner, the panel, and the safety checks
all pick it up:

```swift
CleanupTarget(
    id: "dart-pub-cache",
    displayName: "Dart and Flutter pub cache",
    level: .developer,
    pathTemplates: ["~/.pub-cache"],
    category: "Package Manager",
    deletesContentsNotDirectory: true,
    regenerates: true
)
```

**How it is put together.**

```
CleanerEngine/    Swift package: scan, size, delete, safety. No SwiftUI. Unit tested.
Dusty/            SwiftUI menu bar app (MenuBarExtra) on top of the engine.
```

Keeping the engine free of UI means the rules that matter are tested on their
own. It compiles in Swift 6 language mode with strict concurrency, and CI treats
warnings as errors. See [docs/architecture.md](docs/architecture.md) for the
one-screen map.

```bash
cd CleanerEngine && swift test
```

<details>
<summary><b>Build from source</b></summary>

This one line clones the repo, builds it on your Mac, and installs it to
`/Applications`. Because the build happens locally, macOS opens it with no
Gatekeeper prompt:

```bash
curl -fsSL https://raw.githubusercontent.com/yagcioglutoprak/dusty/main/scripts/install.sh | bash
```

It needs Xcode 16 or later (not just the Command Line Tools). By hand:

```bash
git clone https://github.com/yagcioglutoprak/dusty.git
cd dusty/Dusty
open Dusty.xcodeproj   # then run the Dusty scheme, or:
xcodebuild -scheme Dusty -configuration Release build
```

Maintainers: cutting a notarized release is in [docs/SIGNING.md](docs/SIGNING.md)
and auto-updates in [docs/UPDATES.md](docs/UPDATES.md).
</details>

## License

MIT. See [LICENSE](LICENSE).

---

<div align="center">
made by <a href="https://toprak.sh">toprak.sh</a>
</div>
