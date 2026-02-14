# Design: Drag-and-Drop User Agent Installation

## Summary

Add drag-and-drop support for installing new user agents. Users drop `.plist` files onto the LaunchControl window, which copies them to `~/Library/LaunchAgents/` and prompts to enable and start.

## Drop Target

The entire `NavigationSplitView` gets `.onDrop(of: [.fileURL])`. On drop:
- If `selectedType != .userAgent` → alert: "Switch to User Agents to install."
- Extract file URLs, filter to `.plist` only. Reject non-plist with alert.

## Validation

For each dropped `.plist`:
- Parse with `PropertyListSerialization` to confirm valid plist with a `Label` key.
- If invalid → alert with filename and reason.

## Copy

- Copy file to `~/Library/LaunchAgents/<filename>`.
- If file already exists → confirmation alert ("Replace existing agent?"). On confirm, overwrite.

## Post-Install Prompt

After successful copy, standard macOS alert with:
- **Enable & Start** — `launchctl enable` then `launchctl bootstrap`
- **Just Copy** — leaves file in place, no launchctl action

## ViewModel Changes

New method `installUserAgent(from url: URL, enableAndStart: Bool)`:
- Copies file to target directory (overwrite if confirmed)
- If `enableAndStart`: enable + bootstrap via existing patterns
- Calls `loadLaunchItems()` to refresh the list

## ContentView State

New `@State` properties:
- `dropAlertType`: enum driving which alert is shown (error, overwrite confirmation, post-install)
- `pendingDropURL`: URL being processed through multi-step alert flow

## Dependencies

None. Uses `UniformTypeIdentifiers` (system framework) for `.fileURL` type identifier.
