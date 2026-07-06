# Pull request

## What changed

<!-- Describe the concrete change in 2-4 bullets. -->

## Why

<!-- Link the issue or explain the bug, request, or cleanup this addresses. -->

## Safety checklist

- [ ] `cd CleanerEngine && swift test` passes, or this PR only changes docs/metadata.
- [ ] Any new deletable path is an explicit `CleanupTargetRegistry` entry.
- [ ] Deletion still goes through `SafetyValidator`.
- [ ] User-facing cleanup behavior previews paths and sizes before removal.
- [ ] README, site copy, or docs are updated when behavior changes.

## Notes for reviewers

<!-- Call out anything unusual, risky, or intentionally left out. -->
