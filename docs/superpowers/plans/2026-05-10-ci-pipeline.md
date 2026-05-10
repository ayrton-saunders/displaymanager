# CI Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up GitHub Actions CI (lint + build + test) gated by branch protection on `main`, with a new XCTest target covering the `displayplacer` output parser.

**Architecture:** Three sequential PRs — (1) testability refactor of `DisplayManager.swift`, (2) test target + parser tests, (3) CI workflow + repo housekeeping — followed by a one-time branch-protection setup in the GitHub web UI. Workflow is one file with three parallel jobs on `macos-26`; each job becomes a required status check.

**Tech Stack:** Swift 5 / SwiftUI / Xcode 26 (macOS 26.1 SDK), XCTest, GitHub Actions, SwiftLint (Homebrew), xcbeautify (Homebrew).

**Spec:** `docs/superpowers/specs/2026-05-10-ci-pipeline-design.md`

---

## File Structure

**PR 1 (testability refactor):**
- Create: `DisplayManager/DisplayParser.swift` — pure `DisplayInfo`/`DisplayMode` types, `parseDisplays`, `detectMode`.
- Modify: `DisplayManager/DisplayManager.swift` — remove inline `DisplayMode` enum, replace three inline parsing blocks with `DisplayParser` calls.

**PR 2 (test target + tests):**
- Modify: `DisplayManager.xcodeproj/project.pbxproj` — added by Xcode UI when creating the test target; do **not** hand-edit.
- Create: `DisplayManagerTests/DisplayParserTests.swift`
- Create: `DisplayManagerTests/Fixtures/single-display.txt`
- Create: `DisplayManagerTests/Fixtures/extended-builtin-plus-dell.txt`
- Create: `DisplayManagerTests/Fixtures/mirrored-two-displays.txt`

**PR 3 (CI workflow):**
- Create: `.github/workflows/ci.yml`
- Create: `.swiftlint.yml`
- Create: `.github/pull_request_template.md`
- Modify: `README.md` — add CI badge near top; add branch-naming note; fix the stale "macOS 12.0+" requirement line.

---

## Pre-flight (do once before any PR)

- [ ] **P.1: Verify clean working tree**

Run:
```bash
git status
```
Expected: working tree clean on `main`, or only the `docs/ci-pipeline-spec` branch from the brainstorming step. No uncommitted source changes.

- [ ] **P.2: Confirm GitHub runner availability for `macos-26`**

Open https://github.com/actions/runner-images in a browser and confirm `macos-26` (or `macos-26-arm64`) is listed under "Available Images." Note the exact label and the Xcode 26 install path under `/Applications/`. Record these for PR 3.

If `macos-26` is not yet available, stop and reassess: either wait for it, drop the deployment target to macOS 15, or use a self-hosted runner. Do not proceed.

---

## PR 1: Testability Refactor

Branch: `refactor/extract-display-parser`. Verification is manual (build + launch + exercise mirror/extend) because the test target doesn't exist yet. PR 2 will add automated coverage.

### Task 1.1: Create the new branch

- [ ] **Step 1: Branch from main**

```bash
git checkout main
git pull
git checkout -b refactor/extract-display-parser
```

### Task 1.2: Create `DisplayParser.swift`

**Files:**
- Create: `DisplayManager/DisplayParser.swift`

- [ ] **Step 1: Write the file**

```swift
import Foundation

enum DisplayMode {
    case mirrored
    case extended
    case unknown
}

struct DisplayInfo: Equatable {
    let id: String
    let config: String
}

enum DisplayParser {
    /// Parses a full `displayplacer list` output into the per-display configs
    /// found on the `displayplacer "..." "..."` command line.
    static func parseDisplays(_ output: String) -> [DisplayInfo] {
        guard let cmdLine = output
            .components(separatedBy: .newlines)
            .first(where: { $0.hasPrefix("displayplacer \"") }) else {
            return []
        }
        guard let regex = try? NSRegularExpression(pattern: "\"([^\"]+)\"") else {
            return []
        }
        let nsString = cmdLine as NSString
        let matches = regex.matches(
            in: cmdLine,
            range: NSRange(location: 0, length: nsString.length)
        )
        return matches.compactMap { match -> DisplayInfo? in
            guard match.numberOfRanges > 1 else { return nil }
            let config = nsString.substring(with: match.range(at: 1))
            guard let idRange = config.range(
                of: "id:([A-F0-9+-]+)",
                options: .regularExpression
            ) else { return nil }
            let id = config[idRange].replacingOccurrences(of: "id:", with: "")
            return DisplayInfo(id: id, config: config)
        }
    }

    /// Mirrored = one config whose id contains "+".
    /// Extended = two configs, neither containing "+".
    /// Anything else = unknown.
    static func detectMode(_ displays: [DisplayInfo]) -> DisplayMode {
        if displays.count == 1, displays[0].id.contains("+") {
            return .mirrored
        }
        if displays.count == 2,
           !displays[0].id.contains("+"),
           !displays[1].id.contains("+") {
            return .extended
        }
        return .unknown
    }
}
```

- [ ] **Step 2: Build to confirm the new file compiles**

```bash
xcodebuild -project DisplayManager.xcodeproj -scheme DisplayManager \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```
Expected: BUILD SUCCEEDED. The file is auto-included via the `PBXFileSystemSynchronizedRootGroup`; no project changes needed.

### Task 1.3: Remove duplicate `DisplayMode` from `DisplayManager.swift`

**Files:**
- Modify: `DisplayManager/DisplayManager.swift:9-13`

- [ ] **Step 1: Delete the nested enum**

Delete these lines:
```swift
    enum DisplayMode {
        case mirrored
        case extended
        case unknown
    }
```

The file-scope `DisplayMode` from `DisplayParser.swift` will now be used. `currentMode: DisplayMode = .unknown` on the line above continues to resolve correctly.

- [ ] **Step 2: Build to confirm**

```bash
xcodebuild -project DisplayManager.xcodeproj -scheme DisplayManager \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```
Expected: BUILD SUCCEEDED.

### Task 1.4: Replace `refreshMode()` parsing with `DisplayParser`

**Files:**
- Modify: `DisplayManager/DisplayManager.swift` (the `refreshMode()` method, currently lines 24-70)

- [ ] **Step 1: Replace the parsing block**

Replace the body of `refreshMode()` from the line `let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()` through the end of the method with:

```swift
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: outputData, encoding: .utf8) else {
            return
        }
        let displays = DisplayParser.parseDisplays(output)
        currentMode = DisplayParser.detectMode(displays)
        print("DEBUG: Initial mode detected: \(currentMode)")
    }
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project DisplayManager.xcodeproj -scheme DisplayManager \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```
Expected: BUILD SUCCEEDED.

### Task 1.5: Replace `parseMirrorCommand` config extraction with `DisplayParser`

**Files:**
- Modify: `DisplayManager/DisplayManager.swift` (the `parseMirrorCommand(from:displayplacerPath:)` method)

- [ ] **Step 1: Replace the parsing prelude**

In `parseMirrorCommand`, replace everything from `let lines = output.components(...)` down through the construction of `displayConfigs` (the `for result in results { ... }` loop that builds `displayConfigs`) with a single call to `DisplayParser.parseDisplays`. The downstream code uses the same `(id, config)` shape, so:

```swift
    private func parseMirrorCommand(from output: String, displayplacerPath: String) {
        print("DEBUG: Full output from displayplacer list:")
        print(output)
        print("DEBUG: End of output")

        let displays = DisplayParser.parseDisplays(output)
        guard !displays.isEmpty else {
            showAlert(message: "Could not parse display configuration. Check Console.app for debug output.")
            return
        }
        let displayConfigs: [(id: String, config: String)] = displays.map { ($0.id, $0.config) }

        print("DEBUG: Total displays found: \(displayConfigs.count)")

        // ... rest of method unchanged from here:
        // "If already in extended mode (2 separate configs), save them" onward
```

Keep all code from `// If already in extended mode (2 separate configs), save them` to the end of the method exactly as it is. Only the parsing prelude changes.

- [ ] **Step 2: Build**

```bash
xcodebuild -project DisplayManager.xcodeproj -scheme DisplayManager \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```
Expected: BUILD SUCCEEDED.

### Task 1.6: Replace `parseExtendedCommand` config extraction with `DisplayParser`

**Files:**
- Modify: `DisplayManager/DisplayManager.swift` (the `parseExtendedCommand(from:displayplacerPath:)` method)

- [ ] **Step 1: Replace the parsing prelude**

In `parseExtendedCommand`, leave the "saved config replay" early-return block untouched. Then replace the second parsing block (starting at `// Otherwise parse the current config and separate the displays`, currently `let lines = output.components(...)` through the regex matching) with:

```swift
        // Otherwise parse the current config and separate the displays
        let displays = DisplayParser.parseDisplays(output)
        guard !displays.isEmpty else {
            showAlert(message: "Could not parse display configuration")
            return
        }

        if displays.count == 1 {
            let config = displays[0].config
            let combinedId = displays[0].id
            // Currently mirrored - need to split into separate displays
            // ... existing downstream logic continues here, using `config` and `combinedId`
```

Then the existing downstream logic from `// Split the IDs` (currently `let ids = combinedId.split(separator: "+")...`) continues unchanged. The `if let idRange = ...` wrapper that used to extract `combinedId` is gone — we already have it from `DisplayInfo.id`. The `results.count == 1` check and inner `if results[0].numberOfRanges > 1` are also gone — `displays.count == 1` replaces them.

The variable `config` (the per-display config string) and `combinedId` (the `id:...` value) are the two bindings the downstream code expects. No other changes inside the method.

- [ ] **Step 2: Build**

```bash
xcodebuild -project DisplayManager.xcodeproj -scheme DisplayManager \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```
Expected: BUILD SUCCEEDED. If you see "unresolved identifier `combinedId`" or similar, the variable was deeper inside the original `if let idRange = ...` block — hoist its `let` binding up to immediately after `if displays.count == 1 {`.

### Task 1.7: Manual smoke test on hardware

This PR has no automated tests. Verification is manual.

- [ ] **Step 1: Launch the app from Xcode**

In Xcode, press ⌘R to run. The menu-bar icon should appear. There should be no crash, and Console.app should show `DEBUG: Initial mode detected:` followed by the current mode.

- [ ] **Step 2: Exercise mode switching**

With the MacBook + Dell S2725QC connected:
1. From the menu-bar icon, click "Mirrored Mode". Confirm the displays mirror.
2. Click "Extended Mode". Confirm the Dell returns to extended above the built-in display.
3. Repeat once more.

If anything breaks, fix the implementation and re-run from Task 1.4.

### Task 1.8: Commit and open PR

- [ ] **Step 1: Commit**

```bash
git add DisplayManager/DisplayParser.swift DisplayManager/DisplayManager.swift
git commit -m "$(cat <<'EOF'
Extract DisplayParser for testability

Moves the regex-based displayplacer output parsing out of
DisplayManager into a pure DisplayParser enum. Hoists DisplayMode
to file scope so a future test target can reach it. No runtime
behavior change; verified manually by exercising mirror/extend
switching on hardware.
EOF
)"
```

- [ ] **Step 2: Push and open PR**

```bash
git push -u origin refactor/extract-display-parser
gh pr create --title "Extract DisplayParser for testability" --body "$(cat <<'EOF'
## Summary
- Move displayplacer output parsing into a pure `DisplayParser` enum
- Hoist `DisplayMode` to file scope so the upcoming test target can reach it
- No runtime behavior change

## Test plan
- [x] App builds with no warnings
- [x] Menu opens, mirror toggle works
- [x] Extend toggle works (returns Dell to its expected position)
- [x] No regressions in the "Default State" detection at launch

Part 1 of 3 toward the CI pipeline. See `docs/superpowers/specs/2026-05-10-ci-pipeline-design.md`.
EOF
)"
```

- [ ] **Step 3: Merge once green**

CI doesn't exist yet, so this is a clean self-merge:

```bash
gh pr merge --squash --delete-branch
git checkout main
git pull
```

---

## PR 2: Test Target + Parser Tests

Branch: `feat/add-test-target`. TDD throughout — fixtures first, then failing tests, then verify they pass against the already-refactored parser.

### Task 2.1: Create the new branch

- [ ] **Step 1: Branch from main**

```bash
git checkout main
git pull
git checkout -b feat/add-test-target
```

### Task 2.2: Capture fixtures from real hardware

**Files:**
- Create: `DisplayManagerTests/Fixtures/extended-builtin-plus-dell.txt`
- Create: `DisplayManagerTests/Fixtures/mirrored-two-displays.txt`
- Create: `DisplayManagerTests/Fixtures/single-display.txt`

The folder `DisplayManagerTests/` does not exist yet. Create it first:

```bash
mkdir -p DisplayManagerTests/Fixtures
```

- [ ] **Step 1: Capture the extended fixture**

Set displays to extended mode (use the app or the Display preferences). Then:

```bash
/opt/homebrew/bin/displayplacer list > DisplayManagerTests/Fixtures/extended-builtin-plus-dell.txt
```

Open the file and confirm it contains a line starting with `displayplacer "...` followed by two quoted configs. Both `id:` values should be plain UUIDs (no `+`).

- [ ] **Step 2: Capture the mirrored fixture**

Set displays to mirrored mode. Then:

```bash
/opt/homebrew/bin/displayplacer list > DisplayManagerTests/Fixtures/mirrored-two-displays.txt
```

Open the file. The `displayplacer "..."` line should contain **one** quoted config, and the `id:` value should contain a `+`.

- [ ] **Step 3: Capture the single-display fixture**

Unplug the Dell. Then:

```bash
/opt/homebrew/bin/displayplacer list > DisplayManagerTests/Fixtures/single-display.txt
```

Open the file. The `displayplacer "..."` line should contain exactly **one** quoted config and the `id:` should be a plain UUID (no `+`).

- [ ] **Step 4: Re-plug the Dell** so subsequent manual testing works.

### Task 2.3: Add the test target via Xcode UI

Hand-editing `project.pbxproj` is error-prone. Use Xcode.

- [ ] **Step 1: Open the project in Xcode**

```bash
open DisplayManager.xcodeproj
```

- [ ] **Step 2: File → New → Target…**

In the template chooser:
- Platform: **macOS**
- Template: **Unit Testing Bundle**
- Click **Next**

- [ ] **Step 3: Configure the target**

- Product Name: `DisplayManagerTests`
- Team: (your team, same as the app)
- Organization Identifier: same as the app (`com.ayrton`)
- Bundle Identifier: should auto-fill to `com.ayrton.DisplayManagerTests`
- Language: Swift
- Project: `DisplayManager`
- **Target to be Tested: `None`** ← logic-only test bundle, no host app.

Click **Finish**.

(Note: this deviates from the textbook Xcode setup. With "None" the test bundle doesn't link against the app's compiled module, so `@testable import DisplayManager` would not work. Instead, the next step adds `DisplayParser.swift` to the test target's source compile directly — it gets compiled into both the app and the test bundle. The test code sees the parser types as same-module symbols, no import needed. Two upsides: (1) tests don't depend on the app's NSApplication setup at test time, (2) works identically on the CI runner without any TEST_HOST plumbing.)

- [ ] **Step 4: Move the auto-generated test file out of the way**

Xcode created `DisplayManagerTests/DisplayManagerTests.swift` with a placeholder test. Delete it from disk (right-click in the project navigator → Delete → Move to Trash). The fixtures from Task 2.2 should already be visible in the navigator under `DisplayManagerTests/Fixtures/` because the new target uses a file-system synchronized group.

- [ ] **Step 5: Add `DisplayParser.swift` to the test target's membership**

In the project navigator, click `DisplayManager/DisplayParser.swift`. In the right-hand File Inspector panel, find the "Target Membership" section. Check the box next to `DisplayManagerTests`. The `DisplayManager` box should already be checked — leave it.

The parser is now compiled into both bundles. Source of truth stays in `DisplayManager/`.

- [ ] **Step 6: Verify the scheme includes the test target**

Product → Scheme → Edit Scheme… → Test (left sidebar) → Info tab. `DisplayManagerTests` should appear under "Tests" with its checkbox enabled. If not, click `+` and add it.

- [ ] **Step 7: Verify an empty `xcodebuild test` succeeds**

```bash
xcodebuild -project DisplayManager.xcodeproj -scheme DisplayManager \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```
Expected: BUILD SUCCEEDED, then `Test Suite 'All tests' passed` (zero tests run). If you see "Scheme 'DisplayManager' is not currently configured for the test action," redo Step 6.

- [ ] **Step 8: Commit the test-target scaffolding**

```bash
git add DisplayManager.xcodeproj/project.pbxproj DisplayManagerTests
git status
```
Confirm only `DisplayManager.xcodeproj/project.pbxproj` and the `DisplayManagerTests/` folder are staged.

```bash
git commit -m "Add empty DisplayManagerTests target with fixtures"
```

### Task 2.4: Write a failing parseDisplays test for the single-display fixture

**Files:**
- Create: `DisplayManagerTests/DisplayParserTests.swift`

- [ ] **Step 1: Write the test file with one failing test**

```swift
import XCTest

final class DisplayParserTests: XCTestCase {
    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: DisplayParserTests.self)
        let url = bundle.url(
            forResource: name,
            withExtension: "txt",
            subdirectory: "Fixtures"
        ) ?? bundle.url(forResource: name, withExtension: "txt")
        guard let foundURL = url else {
            XCTFail("Missing fixture: \(name).txt — check Copy Bundle Resources")
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: foundURL, encoding: .utf8)
    }

    func testParseDisplays_singleDisplay_returnsOneDisplayWithoutPlus() throws {
        let output = try fixture("single-display")
        let displays = DisplayParser.parseDisplays(output)
        XCTAssertEqual(displays.count, 1)
        XCTAssertFalse(displays[0].id.contains("+"))
        XCTAssertTrue(displays[0].config.contains("id:\(displays[0].id)"))
    }
}
```

- [ ] **Step 2: Run only this test, expect it to PASS**

```bash
xcodebuild -project DisplayManager.xcodeproj -scheme DisplayManager \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:DisplayManagerTests/DisplayParserTests/testParseDisplays_singleDisplay_returnsOneDisplayWithoutPlus \
  test
```

This is the "verify it fails first" step from TDD — except the implementation already exists from PR 1, so the test should **pass on first run**. That's expected; the TDD signal here is that the test could have failed if `parseDisplays` were broken.

Expected: `** TEST SUCCEEDED **`. If it fails, debug the parser before moving on.

### Task 2.5: Add the extended-mode test

- [ ] **Step 1: Append to `DisplayParserTests.swift`**

Add this method inside the class:

```swift
    func testParseDisplays_extendedMode_returnsTwoDisplaysNoPlus() throws {
        let output = try fixture("extended-builtin-plus-dell")
        let displays = DisplayParser.parseDisplays(output)
        XCTAssertEqual(displays.count, 2)
        XCTAssertFalse(displays[0].id.contains("+"))
        XCTAssertFalse(displays[1].id.contains("+"))
        XCTAssertTrue(
            displays.contains(where: { $0.config.contains("origin:(0,0)") }),
            "Expected one display anchored at origin:(0,0) (the built-in)"
        )
    }
```

- [ ] **Step 2: Run only this test**

```bash
xcodebuild -project DisplayManager.xcodeproj -scheme DisplayManager \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:DisplayManagerTests/DisplayParserTests/testParseDisplays_extendedMode_returnsTwoDisplaysNoPlus \
  test
```
Expected: `** TEST SUCCEEDED **`.

### Task 2.6: Add the mirrored-mode test

- [ ] **Step 1: Append to `DisplayParserTests.swift`**

```swift
    func testParseDisplays_mirroredMode_returnsOneDisplayWithPlus() throws {
        let output = try fixture("mirrored-two-displays")
        let displays = DisplayParser.parseDisplays(output)
        XCTAssertEqual(displays.count, 1)
        XCTAssertTrue(displays[0].id.contains("+"))
    }
```

- [ ] **Step 2: Run only this test**

```bash
xcodebuild -project DisplayManager.xcodeproj -scheme DisplayManager \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:DisplayManagerTests/DisplayParserTests/testParseDisplays_mirroredMode_returnsOneDisplayWithPlus \
  test
```
Expected: `** TEST SUCCEEDED **`.

### Task 2.7: Add the garbage-input test

- [ ] **Step 1: Append**

```swift
    func testParseDisplays_garbageInput_returnsEmptyArrayWithoutCrash() {
        XCTAssertEqual(DisplayParser.parseDisplays(""), [])
        XCTAssertEqual(DisplayParser.parseDisplays("nonsense"), [])
        XCTAssertEqual(DisplayParser.parseDisplays("displayplacer"), [])
        XCTAssertEqual(
            DisplayParser.parseDisplays("displayplacer \"missing close quote"),
            []
        )
    }
```

- [ ] **Step 2: Run**

```bash
xcodebuild -project DisplayManager.xcodeproj -scheme DisplayManager \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:DisplayManagerTests/DisplayParserTests/testParseDisplays_garbageInput_returnsEmptyArrayWithoutCrash \
  test
```
Expected: `** TEST SUCCEEDED **`.

### Task 2.8: Add detectMode tests

- [ ] **Step 1: Append all four**

```swift
    func testDetectMode_emptyInput_isUnknown() {
        XCTAssertEqual(DisplayParser.detectMode([]), .unknown)
    }

    func testDetectMode_singleDisplay_isUnknown() throws {
        let displays = DisplayParser.parseDisplays(try fixture("single-display"))
        XCTAssertEqual(DisplayParser.detectMode(displays), .unknown)
    }

    func testDetectMode_extendedFixture_isExtended() throws {
        let displays = DisplayParser.parseDisplays(try fixture("extended-builtin-plus-dell"))
        XCTAssertEqual(DisplayParser.detectMode(displays), .extended)
    }

    func testDetectMode_mirroredFixture_isMirrored() throws {
        let displays = DisplayParser.parseDisplays(try fixture("mirrored-two-displays"))
        XCTAssertEqual(DisplayParser.detectMode(displays), .mirrored)
    }
```

Note on the `testDetectMode_singleDisplay_isUnknown` assertion: the spec says "verified against implementation, not guessed." Per `DisplayParser.detectMode`, a single display without `+` falls through to `.unknown`. If on your hardware the single-display fixture parses to something different (e.g. the regex captures the id differently), update the assertion to match observed behavior before declaring the test passing.

- [ ] **Step 2: Run all detectMode tests**

```bash
xcodebuild -project DisplayManager.xcodeproj -scheme DisplayManager \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:DisplayManagerTests/DisplayParserTests \
  test
```
Expected: `** TEST SUCCEEDED **`, all eight tests passing.

### Task 2.9: Run the full test action

- [ ] **Step 1: Run everything**

```bash
xcodebuild -project DisplayManager.xcodeproj -scheme DisplayManager \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```
Expected: BUILD SUCCEEDED followed by `Test Suite 'All tests' passed` with 8 tests, 0 failures.

### Task 2.10: Commit and open PR

- [ ] **Step 1: Commit**

```bash
git add DisplayManagerTests DisplayManager.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
Add DisplayManagerTests target with parser coverage

Adds a logic-only XCTest bundle (no host app) covering
DisplayParser.parseDisplays and DisplayParser.detectMode against
three fixtures captured from real hardware (single, extended,
mirrored). Runs via `xcodebuild test` on the existing scheme.
EOF
)"
```

- [ ] **Step 2: Push and open PR**

```bash
git push -u origin feat/add-test-target
gh pr create --title "Add DisplayManagerTests target with parser coverage" --body "$(cat <<'EOF'
## Summary
- New `DisplayManagerTests` logic-only XCTest bundle
- Eight tests covering `DisplayParser.parseDisplays` and `detectMode`
- Three fixtures captured from MacBook + Dell S2725QC

## Test plan
- [x] `xcodebuild test` passes locally
- [x] Test target builds clean

Part 2 of 3 toward the CI pipeline.
EOF
)"
```

- [ ] **Step 3: Merge once you've reviewed**

```bash
gh pr merge --squash --delete-branch
git checkout main
git pull
```

---

## PR 3: CI Workflow + Repo Housekeeping

Branch: `feat/ci-pipeline`. After this PR merges, the three status checks (`CI / lint`, `CI / build`, `CI / test`) exist on `main` and can be marked required in branch protection.

### Task 3.1: Create the new branch

- [ ] **Step 1: Branch**

```bash
git checkout main
git pull
git checkout -b feat/ci-pipeline
```

### Task 3.2: Create `.swiftlint.yml`

**Files:**
- Create: `.swiftlint.yml`

- [ ] **Step 1: Write the config**

```yaml
included:
  - DisplayManager
excluded:
  - DisplayManager/Assets.xcassets
disabled_rules:
  - trailing_whitespace
  - todo
```

- [ ] **Step 2: Verify SwiftLint runs locally (optional but recommended)**

If you have SwiftLint installed:
```bash
swiftlint lint
```
Expected: a list of warnings (probably some) but no SwiftLint crashes or "Could not read config" errors. The CI invocation will use the same config.

### Task 3.3: Create `.github/workflows/ci.yml`

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Confirm Xcode 26 path from the runner image manifest**

From Pre-flight P.2, you should have noted the exact Xcode app path on `macos-26`. If you didn't, look at the image manifest at https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md — it lists installed Xcode versions and their paths (typically `/Applications/Xcode_26.X.app`). Pick the latest Xcode 26 path.

Substitute your confirmed path into `XCODE_PATH` below.

- [ ] **Step 2: Write the workflow**

```yaml
name: CI

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

env:
  XCODE_PATH: /Applications/Xcode_26.1.app  # adjust to the actual path on macos-26
  SCHEME: DisplayManager
  PROJECT: DisplayManager.xcodeproj

jobs:
  lint:
    name: lint
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4

      - name: Cache Homebrew
        uses: actions/cache@v4
        with:
          path: |
            ~/Library/Caches/Homebrew
            /opt/homebrew/Cellar/swiftlint
          key: brew-swiftlint-${{ runner.os }}-v1

      - name: Install SwiftLint
        run: brew install swiftlint

      - name: Run SwiftLint
        run: swiftlint lint --reporter github-actions-logging

  build:
    name: build
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s "$XCODE_PATH"

      - name: Show Xcode version
        run: xcodebuild -version

      - name: Cache DerivedData
        uses: actions/cache@v4
        with:
          path: ~/Library/Developer/Xcode/DerivedData
          key: dd-${{ runner.os }}-${{ hashFiles('DisplayManager.xcodeproj/project.pbxproj', 'DisplayManager/**/*.swift') }}
          restore-keys: |
            dd-${{ runner.os }}-

      - name: Install xcbeautify
        run: brew install xcbeautify

      - name: Build
        run: |
          set -o pipefail
          xcodebuild \
            -project "$PROJECT" \
            -scheme "$SCHEME" \
            -configuration Debug \
            -destination 'platform=macOS' \
            CODE_SIGNING_ALLOWED=NO \
            build | xcbeautify

  test:
    name: test
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s "$XCODE_PATH"

      - name: Cache DerivedData
        uses: actions/cache@v4
        with:
          path: ~/Library/Developer/Xcode/DerivedData
          key: dd-test-${{ runner.os }}-${{ hashFiles('DisplayManager.xcodeproj/project.pbxproj', 'DisplayManager/**/*.swift', 'DisplayManagerTests/**/*.swift') }}
          restore-keys: |
            dd-test-${{ runner.os }}-

      - name: Install xcbeautify
        run: brew install xcbeautify

      - name: Test
        run: |
          set -o pipefail
          xcodebuild \
            -project "$PROJECT" \
            -scheme "$SCHEME" \
            -destination 'platform=macOS' \
            CODE_SIGNING_ALLOWED=NO \
            test | xcbeautify
```

### Task 3.4: Create `.github/pull_request_template.md`

**Files:**
- Create: `.github/pull_request_template.md`

- [ ] **Step 1: Write the template**

```markdown
## Summary

<!-- 1-3 bullet points describing what changed and why -->

## Test plan

<!-- Checklist of what you tested. CI handles build/lint/test automatically. -->

- [ ] Manually launched the app and exercised affected flows
- [ ] Added or updated unit tests where applicable
- [ ] Updated README / docs if user-facing behavior changed
```

### Task 3.5: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add CI badge at the top**

Insert directly below the `# Display Manager` line (line 1):

```markdown
[![CI](https://github.com/ayrton-saunders/displaymanager/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/ayrton-saunders/displaymanager/actions/workflows/ci.yml)
```

- [ ] **Step 2: Fix the outdated macOS requirement**

In the "## Requirements" section, replace:
```
- macOS 12.0 or later
```
with:
```
- macOS 26.1 (Tahoe) or later
```

- [ ] **Step 3: Add a "Contributing" section near the bottom**

Append before any existing "## Notes" section, or at the end of the file:

```markdown
## Contributing

PRs are welcome. Branch from `main` using one of these prefixes:

- `feat/...` — new features
- `fix/...` — bug fixes
- `chore/...` — tooling, deps, repo housekeeping
- `docs/...` — documentation only
- `refactor/...` — internal restructuring with no behavior change

All PRs must pass the CI checks (lint, build, test) before merging. Direct pushes to `main` are blocked.
```

### Task 3.6: Commit and open PR

- [ ] **Step 1: Stage everything**

```bash
git add .github .swiftlint.yml README.md
git status
```
Confirm exactly: `.github/workflows/ci.yml`, `.github/pull_request_template.md`, `.swiftlint.yml`, `README.md`.

- [ ] **Step 2: Commit**

```bash
git commit -m "$(cat <<'EOF'
Add GitHub Actions CI pipeline

Adds lint/build/test jobs running in parallel on macos-26.
SwiftLint runs in warnings-only mode (annotations on PR, no
hard fail). Build and test use xcodebuild with code signing
disabled. README gets a CI badge, an updated macOS requirement,
and a Contributing section documenting branch-naming conventions.
EOF
)"
```

- [ ] **Step 3: Push and open PR**

```bash
git push -u origin feat/ci-pipeline
gh pr create --title "Add GitHub Actions CI pipeline" --body "$(cat <<'EOF'
## Summary
- Three parallel jobs (lint, build, test) on macos-26
- SwiftLint warnings-only initially
- README: CI badge, fixed macOS version, branch conventions

## Test plan
- [ ] CI workflow runs on this PR and all three jobs pass
- [ ] Badge URL resolves to the workflow run history once merged

Part 3 of 3. After merge, enable branch protection on `main` per the spec.
EOF
)"
```

- [ ] **Step 4: Wait for CI on this PR**

The workflow runs on the PR itself. Watch the checks. If any job fails:
- `lint` failing: SwiftLint has a config error (not a rule violation — those don't fail). Read the log, fix `.swiftlint.yml`, push another commit.
- `build` failing: most likely `XCODE_PATH` is wrong. Update to match the runner image's actual Xcode path.
- `test` failing: fixture loading is the usual suspect — confirm `Fixtures/` is in the test target's Copy Bundle Resources (Task 2.3 Step 5).

- [ ] **Step 5: Merge once green**

```bash
gh pr merge --squash --delete-branch
git checkout main
git pull
```

---

## Step 4: Enable Branch Protection (GitHub Web UI)

Not a code change. Must be done after PR 3 merges so the status-check names exist in the repo's check history.

- [ ] **Step 1: Open Branch Protection settings**

Go to https://github.com/ayrton-saunders/displaymanager/settings/branches and click "Add branch protection rule" (or use the Rulesets page — equivalent).

- [ ] **Step 2: Configure the rule**

- **Branch name pattern:** `main`
- ☑ Require a pull request before merging
  - Required approvals: **0** (solo dev)
  - ☐ Dismiss stale pull request approvals when new commits are pushed (irrelevant at 0 approvals)
  - ☐ Require review from Code Owners
- ☑ Require status checks to pass before merging
  - ☑ Require branches to be up to date before merging
  - Required status checks (search and add each — GitHub's UI may show them as bare job names or as `CI / lint`-style, depending on which view you're in; add whichever form appears):
    - `CI / lint` (or `lint`)
    - `CI / build` (or `build`)
    - `CI / test` (or `test`)

    These get registered after the workflow has run at least once on `main` (which happens automatically when PR 3 merges). If the search box returns no matches, the workflow hasn't run on `main` yet — push a tiny no-op commit through a PR first.

- ☑ Require conversation resolution before merging
- ☑ Require linear history
- ☐ Require signed commits (deferred per spec)
- ☐ Require deployments to succeed before merging
- ☑ Do not allow bypassing the above settings
- ☑ Restrict who can push to matching branches → leave empty (nobody can push directly)

Bottom of page:
- ☑ Block force pushes
- ☑ Block deletions

Click **Create** / **Save changes**.

- [ ] **Step 3: Smoke-test the protection**

```bash
git checkout main
echo "# test" >> /tmp/dm-protection-test.txt
git checkout -b chore/test-branch-protection
mv /tmp/dm-protection-test.txt PROTECTION_TEST.md
git add PROTECTION_TEST.md
git commit -m "chore: smoke-test branch protection"
git push -u origin chore/test-branch-protection
```

Then try:
```bash
git checkout main
git merge chore/test-branch-protection
git push
```
Expected: `! [remote rejected] main -> main (protected branch hook declined)`. If the push *succeeds*, branch protection is misconfigured — re-check "Do not allow bypassing" and the required status checks.

Clean up:
```bash
git checkout main
git reset --hard origin/main
git branch -D chore/test-branch-protection
git push origin --delete chore/test-branch-protection
```

---

## Post-completion checklist

- [ ] Three PRs merged to `main`
- [ ] CI badge on README shows green
- [ ] Direct push to `main` is rejected
- [ ] PR with failing CI cannot be merged (test by intentionally breaking lint config in a throwaway PR if you want full confidence)
- [ ] Spec's "Open follow-ups" list reviewed; create tracking issues for any you want to act on (SwiftLint --strict, signed commits, hardcoded resolution fix, stale duplicate files cleanup)
- [ ] Decide whether to flip the repo to public (see spec section + earlier conversation)
