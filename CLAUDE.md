# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and run

This is an Xcode project — there is no SwiftPM manifest. Build, test, and lint via Xcode or:

```bash
# Build (Debug)
xcodebuild -project DisplayManager.xcodeproj -scheme DisplayManager -configuration Debug build

# Run the unit tests (DisplayManagerTests — pure DisplayParser logic, no UI)
xcodebuild test -project DisplayManager.xcodeproj -scheme DisplayManager -destination 'platform=macOS'

# Lint (config in .swiftlint.yml; install with `brew install swiftlint`)
swiftlint

# Build and run the app from Xcode (⌘R) — the app must be launched from a signed location.
# Running the binary out of DerivedData directly may fail because the menu-bar UI relies on
# Accessibility/Screen Recording permissions tied to the bundle path.
```

There is a `DisplayManagerTests` target (`DisplayManager.xctestplan`) covering the pure parsing/mode-detection helpers in `DisplayParser.swift`; the UI layer is not unit-tested. CI runs build, test, and lint.

Runtime dependency: `displayplacer` must be installed (`brew install displayplacer`). The app probes `/opt/homebrew/bin`, `/usr/local/bin`, then `/usr/bin` — there is no PATH lookup, so non-standard install locations are not supported.

Deployment target is **macOS 26.1** (Tahoe), Swift 5.0, default-actor-isolation = `MainActor`. The README still says "macOS 12.0+" but that is out of date — do not lower the deployment target unless you also remove the Swift 6 concurrency settings.

## Architecture

A handful of small Swift files do the entire job (all under `DisplayManager/`):

- **`DisplayManagerApp.swift`** — `@main` SwiftUI entry. Body is a `Settings { EmptyView() }` because this is a menu-bar-only app (`LSUIElement = true` in `Info.plist`); the real lifecycle is in `AppDelegate` via `@NSApplicationDelegateAdaptor`.
- **`AppDelegate.swift`** — owns the `NSStatusItem` and builds a real `NSMenu` (`statusItem.menu`). Because the menu is system-tracked, it pins the menu bar in full screen, dismisses on Mission Control / Space changes / outside clicks, and renders with native Liquid Glass — all for free, with **no** manual event monitors or window-level juggling (an earlier version used a borderless `NSPanel` and hand-rolled all of that). Each row is an `NSMenuItem` whose `.view` hosts custom SwiftUI from `MenuRow.swift`; `menuNeedsUpdate` syncs the active-mode marker and enabled state on each open (mode rows disable when no two-display arrangement is recognized).
- **`MenuRow.swift`** — `DisplayMenuRow`, the stateless SwiftUI rendering of one Control-Center-style row (icon tile + title + hover highlight), and `MenuRowItemView`, the `NSView` that hosts it. The `NSView` owns hover-tracking and click handling because `NSMenu` does **not** highlight custom-view items or forward clicks to embedded SwiftUI controls during its tracking loop; `mouseUp` activates the row and dismisses via `cancelTracking()`.
- **`DisplayManager.swift`** — `ObservableObject` that shells out to `displayplacer` via `Process` and parses its `list` output with regex.
- **`DisplayParser.swift`** — pure (stateless) parsing and mode-detection helpers, extracted so they can be unit-tested without launching `displayplacer`.

The displayplacer interaction is the only non-trivial logic. Two things to be aware of before editing it:

1. **Extended-mode restoration replays a persisted snapshot.** Whenever the app observes an extended configuration — on launch in `refreshMode`, when mirroring from extended, or when the display arrangement changes while running (an `NSApplication.didChangeScreenParametersNotification` observer re-runs `refreshMode`) — `captureExtendedConfigIfPresent` stashes the raw `displayplacer` argument strings, via the pure `DisplayParser.extendedConfigArguments`, into `UserDefaults` under `savedExtendedConfig`. Un-mirroring replays those exact arguments, so the real arrangement (e.g. the Dell's `origin:(-423,-1440)`) is reproduced precisely, and only when `terminationStatus == 0` is the mode considered changed. There is **no hardcoded fallback**. Before replaying, `DisplayParser.savedConfigIsRestorable` checks that every display the saved config references is still connected (reusing the `displayplacer list` output already fetched) — guarding against replaying stale IDs after a monitor swap. If nothing has been captured yet, or the saved displays are no longer attached, `parseExtendedCommand` shows an alert asking the user to establish the layout once rather than guessing. The persisted snapshot survives app restarts.
2. **Mode detection is heuristic.** A single config with a `+` in the `id:` field means mirrored; two separate configs means extended. Built-in vs external is identified by `origin:(0,0)`. Anything beyond two displays is not handled.

Errors surface as `NSAlert` modals from `showAlert(_:)`. Verbose `print(...)` debug output goes to Console.app — useful when display parsing misbehaves.

## Project file gotchas

- **Sources build phase is intentionally empty.** The Xcode project uses `PBXFileSystemSynchronizedRootGroup` (`fileSystemSynchronizedGroups = (DisplayManager)`). Every `.swift` file under `DisplayManager/` is auto-included in the target — do not add `PBXBuildFile` entries by hand, just drop the file in the folder.
- **App sandbox is disabled** (`com.apple.security.app-sandbox = false` in `DisplayManager.entitlements`) and must stay disabled — `Process()` cannot launch `displayplacer` from inside the sandbox. Hardened runtime is on.
