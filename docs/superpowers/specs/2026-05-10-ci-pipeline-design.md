# CI pipeline design

**Status:** approved
**Date:** 2026-05-10
**Author:** ayrton-saunders (drafted with Claude Code)

## Goal

Stand up a CI pipeline for the DisplayManager macOS app so that merges to `main` are gated on automated checks. Once in place, the repo can be made public without risk of breaking-code merges. Deployment is intentionally out of scope — the app is not distributed via the App Store and there is no signed-release pipeline.

## Constraints and context

- Single Xcode project (`DisplayManager.xcodeproj`), no SwiftPM manifest.
- Deployment target macOS 26.1 (Tahoe), Swift 5, SwiftUI menu-bar app (`LSUIElement = true`).
- App sandbox is disabled and must stay disabled (`Process` launches `displayplacer`). Hardened runtime is on.
- The Xcode project uses `PBXFileSystemSynchronizedRootGroup` for the main target — new files under `DisplayManager/` are auto-included without manual `PBXBuildFile` entries.
- No test target exists today.
- Single contributor (ayrton-saunders). Repo will be made public after CI lands.
- The only non-trivial logic is the `displayplacer list` output parser and the mirrored/extended mode-detection heuristic in `DisplayManager.swift`.

## Decisions

| Topic | Decision |
|---|---|
| PR checks | Build, SwiftLint, unit tests |
| Test scope | Parser tests for `displayplacer` output (requires extracting the parser into a pure function) |
| Lint strictness | Warnings-only initially; tighten later |
| Branch protection | Strict, no admin bypass |
| Workflow shape | Single `ci.yml`, three parallel jobs |
| Branch naming | Documented in README, not enforced |
| Deployment | Out of scope |

## Architecture

### Workflow file

Single workflow at `.github/workflows/ci.yml`.

**Triggers:**
- `pull_request` targeting `main` — gates merges.
- `push` to `main` — populates README status badge and provides a post-merge sanity check.

**Concurrency:** group by `${{ github.workflow }}-${{ github.ref }}` with `cancel-in-progress: true`. New commits on a PR branch cancel the in-flight run for that branch.

**Runner:** `macos-26`. Required for Xcode 26's macOS 26.1 SDK. `macos-15` and earlier do not have it.

### Three parallel jobs

| Job ID | Status check name | Purpose |
|---|---|---|
| `lint` | `CI / lint` | SwiftLint over `DisplayManager/**/*.swift` |
| `build` | `CI / build` | `xcodebuild build` on the Debug scheme |
| `test` | `CI / test` | `xcodebuild test` against the new test target |

Each job is independent: its own `actions/checkout@v4`, its own Xcode-select step where needed, its own cache key. All three status-check names are listed as required in branch protection.

## Job details

### Lint job

**Install:** `brew install swiftlint`. Cached via `actions/cache@v4` keyed on the Homebrew formula version to avoid repeated installs.

**Config file:** `.swiftlint.yml` at repo root:

```yaml
included:
  - DisplayManager
excluded:
  - DisplayManager/Assets.xcassets
disabled_rules:
  - trailing_whitespace   # Xcode handles this
  - todo                  # noisy
```

The `included:` directive intentionally excludes the stale duplicate `.swift` files at the repo root (flagged in CLAUDE.md as not compiled).

**Invocation:**

```
swiftlint lint --reporter github-actions-logging
```

No `--strict`. Violations surface as PR annotations on changed lines but do not fail the job. The job fails only if SwiftLint itself errors (invalid config, missing files).

**Future tightening:** flip to `swiftlint lint --strict` when the codebase is clean. Single-line change. Tracked as a follow-up.

### Build job

**Steps:**

1. `sudo xcode-select -s /Applications/Xcode_26.app` — exact path verified against the `macos-26` runner image manifest at implementation time. Pinning prevents silent SDK changes on runner image bumps.
2. `actions/cache@v4` for DerivedData, keyed on a hash of `DisplayManager.xcodeproj/project.pbxproj` plus the Swift source tree.
3. Install `xcbeautify` via Homebrew (cached) for readable logs. Fall back to raw `xcodebuild` output if `xcbeautify` is unavailable, so the job never fails on its formatter.
4. Build:

```
xcodebuild \
  -project DisplayManager.xcodeproj \
  -scheme DisplayManager \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build \
  | xcbeautify
```

**Flag notes:**
- `CODE_SIGNING_ALLOWED=NO` — runner has no Developer ID cert. Signing is only relevant at runtime (Accessibility / Screen Recording permissions tied to the bundle path); CI only proves the build compiles.
- `-destination 'platform=macOS'` — pure macOS build, no simulator.
- `displayplacer` is intentionally **not** installed on the runner — it is a runtime dependency, not a build dependency.

### Test job

#### Refactor for testability

Today the regex parsing for `displayplacer list` is embedded inside `DisplayManager: ObservableObject`, which cannot be unit-tested without spinning up a `Process`.

Changes:

- Create `DisplayManager/DisplayParser.swift` with two pure, side-effect-free static functions:
  - `static func parseDisplays(_ output: String) -> [DisplayInfo]` — parses the per-display blocks from `displayplacer list`.
  - `static func detectMode(_ displays: [DisplayInfo]) -> DisplayMode` — applies the mirrored/extended heuristic.
- Hoist `DisplayInfo` and `DisplayMode` to file-scope types so the test target can reach them.
- `DisplayManager.swift` keeps its `Process` plumbing and delegates parsing to the new statics. Observable runtime behavior is unchanged.

#### Test target

Edits to `DisplayManager.xcodeproj/project.pbxproj`:

- Add a unit-test bundle target `DisplayManagerTests` (productType `com.apple.product-type.bundle.unit-test`).
- Use a `PBXFileSystemSynchronizedRootGroup` rooted at `DisplayManagerTests/` so test files auto-include, matching the existing main-target pattern.
- **Host application: none.** A logic-only test bundle. Avoids the Accessibility / Screen Recording permission issue CLAUDE.md flags around bundle-path-dependent runtime behavior, and runs cleanly on a headless CI runner.
- Add `DisplayManagerTests` to the existing `DisplayManager` scheme's Test action so `xcodebuild test -scheme DisplayManager` picks it up.

Folder layout:

```
DisplayManagerTests/
  DisplayParserTests.swift
  Fixtures/
    mirrored-two-displays.txt
    extended-builtin-plus-dell.txt
    single-display.txt
```

Fixtures are verbatim `displayplacer list` outputs captured locally from real hardware. Tests load them via `Bundle(for: DisplayParserTests.self).url(forResource:withExtension:)`. The fixture-capture step must be performed during PR 2 implementation against the MacBook + Dell S2725QC setup; cannot be done from CI.

#### CI step

```
xcodebuild \
  -project DisplayManager.xcodeproj \
  -scheme DisplayManager \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test \
  | xcbeautify
```

Same Xcode selection and caching as the build job. Job fails on any XCTest failure.

#### Initial test cases

For `parseDisplays`:
- Single-display output → one `DisplayInfo` with the expected resolution, origin, and id.
- Two-display extended output → two `DisplayInfo`s with distinct origins.
- Mirrored output → one `DisplayInfo` whose id contains a `+`.
- Garbage / empty input → empty array, no crash.

For `detectMode`:
- Single display (e.g. MacBook with no external connected) → whatever the current code returns (verified against implementation, not guessed).
- Empty input → no crash; returns a sensible default.
- Two displays, one at `origin:(0,0)` → `.extended`.
- One config with `+` in id → `.mirrored`.

The `parseExtendedCommand` fallback with the hardcoded `2560x1440` / `(0,-1440)` values is testable but **out of scope** for the initial set — the hardcoding is a known issue but fixing it is unrelated to setting up CI.

## Branch protection on `main`

Configured in the GitHub web UI under Settings → Branches → Branch protection rules (or as a GitHub Ruleset, equivalent surface).

1. **Require a pull request before merging.** Blocks direct pushes to `main` from anyone, including the repo owner. Only path in is a PR from another branch.
2. **Require status checks to pass before merging.** Required checks: `CI / lint`, `CI / build`, `CI / test`.
3. **Require branches to be up to date before merging.** PR branch must include the latest `main` before checks are accepted.
4. **Require linear history.** Squash-merge or rebase-merge only, no merge commits.
5. **Require conversation resolution before merging.**
6. **Block force pushes.**
7. **Block deletions.**
8. **Do not allow bypassing the above settings.** Rules apply to admins.

**Intentionally not enabled:**
- *Require approvals.* Solo contributor. With "no bypass" enabled, requiring 1 approval would make merging impossible without inviting a collaborator. Revisit if collaborators are added.
- *Require signed commits.* Nice-to-have for a public repo; deferred to keep initial setup friction low. One-line rule change when ready.
- *CODEOWNERS file.* No second reviewer, no purpose.

## Repo housekeeping

Three small additions:

- `.github/pull_request_template.md` with "Summary" and "Test plan" sections.
- README CI status badge near the top, linking to the latest `ci.yml` run on `main`.
- One-sentence note in README documenting the branch-naming convention: PRs from `feat/*`, `fix/*`, `chore/*`, `docs/*`, or `refactor/*` branches. **Not enforced** by CI or ruleset — convention only.

**Out of scope** (flagged here so they don't sneak into implementation):

- Deleting the stale duplicate `.swift` files at the repo root. `.swiftlint.yml`'s `included: [DisplayManager]` already keeps them out of lint. Cleanup is a separate concern.
- Correcting the README's outdated "macOS 12.0+" line.
- Code signing, notarization, DMG release, App Store distribution.

## Rollout sequence

Each step is an independent PR. Order matters because branch protection requires its status checks to exist before they can be marked required.

1. **PR 1 — testability refactor.** Extract `DisplayParser.swift`, hoist `DisplayInfo` and `DisplayMode`. No CI files, no test target. Verified by launching the app locally and exercising mirrored/extended switching. This is the only PR that carries runtime-behavior risk; it ships alone.
2. **PR 2 — test target and tests.** New `DisplayManagerTests/` folder, `project.pbxproj` edits, fixtures captured from real hardware, XCTest cases. Verified locally with `xcodebuild test`.
3. **PR 3 — CI workflow.** `.github/workflows/ci.yml`, `.swiftlint.yml`, `.github/pull_request_template.md`, README badge and branch-naming note. After merge, the workflow exists on `main` and runs on subsequent PRs.
4. **Repo settings (no PR).** Enable branch protection on `main` with the three required checks from PR 3. Done in the GitHub web UI.

## Open follow-ups (deferred, not blocking)

- Flip SwiftLint to `--strict` once the codebase is clean.
- Enable "Require signed commits" branch-protection rule.
- Fix the hardcoded `2560x1440` / `(0,-1440)` values in `parseExtendedCommand` (separate concern from CI).
- Correct the README's macOS-version requirement line.
- Delete the stale duplicate `.swift` files at the repo root.
