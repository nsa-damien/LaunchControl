# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

LaunchControl is a macOS SwiftUI app for managing LaunchAgents and LaunchDaemons. It provides a GUI over `launchctl` with Touch ID authentication for privileged system operations.

**Requirements:** macOS 14.0+, Xcode 15.0+, Swift 5.9+

## Build & Run

```bash
# Build from command line
xcodebuild -project LaunchControl.xcodeproj -scheme LaunchControl -configuration Debug build

# Run tests
xcodebuild -project LaunchControl.xcodeproj -scheme LaunchControl -configuration Debug test

# Clean build
xcodebuild -project LaunchControl.xcodeproj -scheme LaunchControl clean
```

The app is normally built and run from Xcode. Open `LaunchControl.xcodeproj` directly.

## Architecture

**MVVM pattern** with modern Swift concurrency:

- **Model** — `LaunchItem.swift`: `LaunchItemType` enum (userAgent/systemAgent/systemDaemon), `LaunchItemStatus` enum, `LaunchItem` struct. Each type maps to a directory (`~/Library/LaunchAgents`, `/Library/LaunchAgents`, `/Library/LaunchDaemons`).
- **ViewModel** — `LaunchControlViewModel.swift`: `@Observable @MainActor` class. Loads plist files from launch directories, queries status via `launchctl print`, and executes load/unload/enable/disable commands. User-level ops run directly; system-level ops delegate to `AuthenticationHelper`.
- **Views** — `ContentView.swift` (NavigationSplitView with sidebar filters + list), `LaunchItemRow.swift` (per-item controls), `DebugView.swift` (diagnostics sheet).
- **Auth** — `AuthenticationHelper.swift`: Swift `actor` that chains Touch ID/password auth (LocalAuthentication framework) then runs privileged commands via `/usr/bin/osascript` with `do shell script ... with administrator privileges`.

**Key domain concepts:**
- User agents use `gui/<uid>` domain, system agents/daemons use `system` domain
- `launchctl bootstrap/bootout` for load/unload; `launchctl enable/disable` for startup control
- `launchctl print` determines loaded/running state; `print-disabled` determines enabled state
- Home directory resolution avoids sandbox redirection using `$HOME` env var with `getpwuid` fallback

## Entitlements

The app runs sandboxed with temporary read-only exceptions for `/Library/LaunchAgents/`, `/Library/LaunchDaemons/`, and `~/Library/LaunchAgents/`. Defined in `LaunchControl/LaunchControl.entitlements`.

## No Third-Party Dependencies

Pure Swift/SwiftUI using only system frameworks: Foundation, SwiftUI, LocalAuthentication, Security.
