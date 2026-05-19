# Taskbar-mac

A Windows-style taskbar for macOS. Forked from `hamet/taskbar-mac` (last touched 2019) to revive and modernize.

## Architecture

- `source/ax/` — Accessibility API wrappers. `AXWorkspace` is the central observer; it watches running apps via `NSWorkspace` and per-app windows via `AXObserver`. Window lifecycle events (created/destroyed/renamed/focused/moved/resized) flow out as Objective-C delegate callbacks on a protocol implemented by `AppDelegate`'s `Workspace`.
- `source/ui/` — Cocoa UI. `TaskBarWindow` is the borderless always-on-top strip; `AppleButton` is the Start-menu anchor; `StartMenu`/`ShortcutsWindow` populate launcher entries from `~/Applications` and disk shortcuts; `HoverButton` is the per-window task button.
- `source/main/` — `main.mm` + `AppDelegate.mm`. `AppDelegate.applicationDidFinishLaunching` calls `[AXWorkspace assertAccessibilityEnabled]` which terminates the process if the user hasn't granted Accessibility in System Settings.

## Build

```sh
xcodebuild -project source/Taskbar.xcodeproj -scheme Taskbar -configuration Release
```

Output: `bin/Taskbar.app` (universal: arm64 + x86_64). Deployment target is macOS 11.0.

## Install (required for TCC to persist)

Linker-emitted ad-hoc signatures don't give TCC a stable identity, so the OS will re-prompt for Accessibility on every launch. After building:

```sh
codesign --force --deep --sign - bin/Taskbar.app
cp -R bin/Taskbar.app /Applications/
tccutil reset Accessibility com.showdownsoftware.taskbar  # if a stale grant exists
open /Applications/Taskbar.app
```

Then grant Accessibility in System Settings → Privacy & Security → Accessibility.

## Code conventions

- Objective-C++ with **manual reference counting** (pre-ARC). Expect `retain`/`release`/`autorelease`/`dealloc` everywhere. Do not introduce ARC-style patterns in MRC files without converting the file.
- Headers use `#pragma once`. Mixed `#import` (Cocoa/Foundation) and `#include` (C++ STL via `<ax/*.h>`).
- C++ STL is used freely inside `.mm` files (e.g. `std::string`, `std::vector`, `std::runtime_error`).
- The codebase predates many AppKit enum renames (e.g. `NSLeftMouseDown` → `NSEventTypeLeftMouseDown`); deprecation warnings are present but non-blocking.

## Known modernization status

- ✅ Builds on Xcode 26 / macOS 26 (Tahoe) as a universal binary.
- ✅ AX-based window tracking works on Tahoe.
- ⚠️  ~30 AppKit deprecation warnings remain (mechanical to clean).
- ⚠️  Still MRC, not ARC.
- ⚠️  No Stage Manager / Spaces-aware behavior validation yet.
