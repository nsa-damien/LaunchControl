# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-02-17

### Added
- "Run Now" context menu option to trigger on-demand execution via `launchctl kickstart`

## [0.3.0] - 2026-02-15

### Added
- Plist editor/viewer: double-click any launch item to view or edit its configuration
- Structured form editor with sections for Program, Schedule, Environment, I/O, and Advanced settings
- Raw XML tab for inspecting full plist source
- Read-only mode for system agents and daemons
- Save with reload prompt for running agents
- Edit context menu item on launch items
- Reusable editor components: ListEditorView, KeyValueEditorView, CalendarIntervalEditorView
- PlistDocument model with round-trip plist parsing
- Makefile with build, test, archive, and package targets
- Reveal in Finder context menu action for launch items
- GitHub Actions CI workflow for pull request checks (build and test)
- GitHub Actions Release workflow for automated builds on version tags
- Unit test suite for ViewModel filtering, plist validation, and agent installation

### Changed
- Double-click edit moved into LaunchItemRow via onEdit callback for better encapsulation
- ViewModel supports dependency injection for FileManager, command runner, and agent directory (testability)

### Fixed
- CalendarIntervalEditorView picker labels display correctly on macOS
- launchctl enable/bootstrap failures now surface to user via error message
- Plist parse errors preserve original error details instead of generic message
- deleteItemWithoutAuth uses injected FileManager consistently

## [0.1.0] - 2026-02-14

### Added
- View, load/unload, enable/disable LaunchAgents and LaunchDaemons
- Three-category browsing: User Agents, System Agents, System Daemons
- Touch ID / password authentication for system-level operations
- Real-time status monitoring (running, stopped, loaded state)
- Search and filter across all launch items
- Drag-and-drop .plist files onto window to install as user agents
- Post-install prompt to enable and start newly installed agents
- Overwrite confirmation when installing an agent that already exists
- Filter validation: drop only accepted when User Agents filter is active
- Delete action on launch item rows via context menu
- Debug diagnostics sheet
