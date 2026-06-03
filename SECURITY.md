# Security Policy

Dusty deletes files, so its safety is the thing we care about most. The deletion
logic lives in the `CleanerEngine` Swift package with no UI, and a single
`SafetyValidator` is the only thing that can authorize a delete: a path is
removable only if it descends from an explicit entry in a fixed allowlist. Those
rules are unit tested in isolation.

## Supported versions

Only the latest release gets security fixes. Please update before reporting.

| Version | Supported |
| --- | --- |
| 1.2.x   | Yes       |
| < 1.2   | No        |

## Reporting a vulnerability

Please report privately, not in a public issue.

- Preferred: use GitHub's **"Report a vulnerability"** button under this
  repository's **Security** tab (private vulnerability reporting is enabled).
- Include the affected version, steps to reproduce, and the impact.

We aim to acknowledge within 72 hours and to ship a fix or mitigation for a
confirmed issue in the next release. We are glad to credit you once a fix is out,
unless you would rather stay anonymous.

## What we most want to hear about

The high-value reports are anything that breaks the safety model:

- a path that escapes the allowlist,
- a symlink (including an ancestor directory) that lets a delete walk out of an
  allowed location,
- a way to touch a protected folder (Documents, Desktop, Photos, Music, Movies,
  Mail, iCloud Drive, Keychains) or anything outside the boot volume,
- a path-traversal or normalization trick that defeats the checks.

The validator and its tests are the place to look:
`CleanerEngine/Sources/CleanerEngine/SafetyValidator.swift` and
`CleanerEngine/Tests/CleanerEngineTests/`.
