# LaunchControl

A macOS app for managing LaunchAgents and LaunchDaemons with Touch ID authentication.

## Features

- **View all launch items** across three categories:
  - User Agents (`~/Library/LaunchAgents`)
  - System Agents (`/Library/LaunchAgents`)
  - System Daemons (`/Library/LaunchDaemons`)
- **Load/Unload** launch items with a single click
- **Enable/Disable** launch items to control whether they start automatically
- **Touch ID authentication** for system-level operations
- **Real-time status monitoring** showing whether items are running, stopped, or loaded
- **Search and filter** capabilities
- **Drag-and-drop installation** of new user agents from Finder
- **Plist Editor** — Double-click any item to view/edit its configuration with a structured form and raw XML view
- Modern macOS interface with split-view layout

## Requirements

- macOS 14.0+
- Xcode 15.0+
- Swift 5.9+

## Setup

1. Open `LaunchControl.xcodeproj` in Xcode
2. Ensure `LaunchControl.entitlements` is referenced under Signing & Capabilities
3. Add the following to `Info.plist`:
   ```xml
   <key>NSLocalNetworkUsageDescription</key>
   <string>LaunchControl needs to execute system commands to manage launch items.</string>
   ```
4. Build and run (Cmd+R)

## Usage

### User Agents
User-level agents don't require authentication. You can load/unload and enable/disable them immediately.

### System Agents & Daemons
System-level items require administrator privileges:
1. Click Load, Unload, Enable, or Disable on any system item
2. Authenticate with Touch ID or your password
3. The operation executes with elevated privileges

### Status Indicators

| Indicator | Meaning |
|-----------|---------|
| Green dot | Service is running |
| Red dot | Service is stopped |
| Lock icon | Requires admin privileges |

### Launch Item States

- **Enabled + Loaded + Running** — Working normally
- **Enabled + Loaded + Stopped** — Crashed or stopped
- **Disabled** — Won't start automatically
- **Not Loaded** — Not currently active

## Architecture

MVVM pattern with Swift concurrency:

- `ContentView.swift` — Main UI with NavigationSplitView
- `LaunchItem.swift` — Data models (`LaunchItemType`, `LaunchItemStatus`, `LaunchItem`)
- `LaunchControlViewModel.swift` — Business logic, `launchctl` command execution, state management
- `LaunchItemRow.swift` — Per-item row with controls
- `AuthenticationHelper.swift` — Touch ID auth + privileged execution via `osascript`
- `DebugView.swift` — Diagnostics sheet

## Troubleshooting

### User Agents not loading?
Ensure the app has read permissions for `~/Library/LaunchAgents/`. The domain for user agents is `gui/<uid>`.

### Authentication failures?
1. Check that Touch ID is enabled in System Settings
2. Ensure your user account has admin privileges
3. Check Console.app for authorization errors

### launchctl commands reference
| Command | Purpose |
|---------|---------|
| `bootstrap <domain> <path>` | Load a launch item |
| `bootout <domain>/<label>` | Unload a launch item |
| `enable <domain>/<label>` | Enable automatic startup |
| `disable <domain>/<label>` | Disable automatic startup |
| `print <domain>/<label>` | Check status |
| `print-disabled <domain>` | List disabled items |

## License

MIT License
