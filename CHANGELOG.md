# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Reveal in Finder context menu action for launch items
- GitHub Actions CI workflow for pull request checks (build and test)
- GitHub Actions Release workflow for automated builds on version tags

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
