# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and run

This is an Xcode project — there is no SwiftPM manifest, no test target, and no lint config. Build via Xcode or:

```bash
# Build (Debug)
xcodebuild -project DisplayManager.xcodeproj -scheme DisplayManager -configuration Debug build

# Build and run the app from Xcode (⌘R) — the app must be launched from a signed location.
# Running the binary out of DerivedData directly may fail because the menu-bar UI relies on
# Accessibility/Screen Recording permissions tied to the bundle path.
```

Runtime dependency: `displayplacer` must be installed (`brew install displayplacer`). The app probes `/opt/homebrew/bin`, `/usr/local/bin`, then `/usr/bin` — there is no PATH lookup, so non-standard install locations are not supported.

Deployment target is **macOS 26.1** (Tahoe), Swift 5.0, default-actor-isolation = `MainActor`. The README still says "macOS 12.0+" but that is out of date — do not lower the deployment target unless you also remove the Swift 6 concurrency settings.

## Architecture

Three Swift files do the entire job (all under `DisplayManager/`):

- **`DisplayManagerApp.swift`** — `@main` SwiftUI entry. Body is a `Settings { EmptyView() }` because this is a menu-bar-only app (`LSUIElement = true` in `Info.plist`); the real lifecycle is in `AppDelegate` via `@NSApplicationDelegateAdaptor`.
- **`AppDelegate.swift`** — owns the `NSStatusItem` and a borderless `NSPanel` that hosts the SwiftUI menu. The panel is **not** an `NSPopover`; it is positioned manually under the status item, set to `.screenSaver` window level so it floats above full-screen apps, and dismissed by a global mouse-down monitor plus a local key-down monitor that closes the menu when the user presses ⌘⇧3/4/5 (screenshot shortcuts).
- **`DisplayManager.swift`** — `ObservableObject` that shells out to `displayplacer` via `Process` and parses its `list` output with regex.

The displayplacer interaction is the only non-trivial logic. Two things to be aware of before editing it:

1. **Extended-mode restoration is stateful.** The first time the app sees an "extended" configuration, it stashes the raw `displayplacer` argument strings in `savedExtendedConfig`. Subsequent extended-mode requests replay those exact arguments rather than reconstructing them. If the user mirrors before the app ever saw an extended config (e.g. they launched the app while already mirrored), `parseExtendedCommand` falls back to a hand-built config with **hardcoded `res:2560x1440` and `origin:(0,-1440)`** for the external display. This was tuned for a Dell S2725QC stacked above a MacBook built-in display. Other monitors will land in the wrong place or wrong resolution on first un-mirror.
2. **Mode detection is heuristic.** A single config with a `+` in the `id:` field means mirrored; two separate configs means extended. Built-in vs external is identified by `origin:(0,0)`. Anything beyond two displays is not handled.

Errors surface as `NSAlert` modals from `showAlert(_:)`. Verbose `print(...)` debug output goes to Console.app — useful when display parsing misbehaves.

## Project file gotchas

- **Sources build phase is intentionally empty.** The Xcode project uses `PBXFileSystemSynchronizedRootGroup` (`fileSystemSynchronizedGroups = (DisplayManager)`). Every `.swift` file under `DisplayManager/` is auto-included in the target — do not add `PBXBuildFile` entries by hand, just drop the file in the folder.
- **The repo root contains stale duplicate Swift files.** `AppDelegate.swift`, `DisplayManager.swift`, `DisplayManagerApp.swift`, and `MenuView.swift` exist at the top level *and* under `DisplayManager/`. Only the ones under `DisplayManager/` are compiled. The root copies are an older draft (popover-based menu, `which`-based displayplacer lookup) and should not be edited — edit the `DisplayManager/` versions, or delete the root duplicates if you want to clean up.
- **App sandbox is disabled** (`com.apple.security.app-sandbox = false` in `DisplayManager.entitlements`) and must stay disabled — `Process()` cannot launch `displayplacer` from inside the sandbox. Hardened runtime is on.
