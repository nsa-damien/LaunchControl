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
- Modern macOS interface with split-view layout

## Setup

### 1. Add Entitlements

Make sure `LaunchControl.entitlements` is added to your target:
1. In Xcode, select your project
2. Select the LaunchControl target
3. Go to "Signing & Capabilities"
4. Ensure the entitlements file is referenced

### 2. Info.plist Privacy Keys

Add the following to your `Info.plist`:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>LaunchControl needs to execute system commands to manage launch items.</string>
```

### 3. Hardened Runtime (Optional)

For distribution, you may need to disable certain hardened runtime protections:
- Disable Library Validation (if needed)
- Allow Execution of JIT-compiled Code (if needed)

## Usage

### User Agents
User-level agents don't require authentication. You can:
- Load/Unload immediately
- Enable/Disable for automatic startup

### System Agents & Daemons
System-level items require administrator privileges:
1. Click Load, Unload, Enable, or Disable on any system item
2. Touch ID prompt will appear
3. Authenticate with your fingerprint or password
4. Operation will be executed with elevated privileges

## Controls

Each launch item row has the following controls:

- **🟢 Green Dot**: Service is running
- **🔴 Red Dot**: Service is stopped
- **🔒 Lock Icon**: Requires administrator privileges
- **Enable/Disable Button**: Controls automatic startup
- **Load/Unload Button**: Starts or stops the service immediately

## Important Notes

### AuthorizationExecuteWithPrivileges Deprecation

The app currently uses `AuthorizationExecuteWithPrivileges`, which is deprecated. For production apps, consider:

1. **SMJobBless** for helper tools
2. **XPC Services** with elevated privileges
3. **Shell scripts with osascript** for admin prompts

### Permissions

The app needs read access to:
- `/Library/LaunchAgents/`
- `/Library/LaunchDaemons/`
- `~/Library/LaunchAgents/`

These are configured in the entitlements file.

### Launch Item States

Launch items can be in various states:
- **Enabled + Loaded + Running**: Working normally
- **Enabled + Loaded + Stopped**: Crashed or stopped
- **Disabled**: Won't start automatically
- **Not Loaded**: Not currently active

## Troubleshooting

### User Agents not loading?

Make sure the app has read permissions for `~/Library/LaunchAgents/`. The domain for user agents is `gui/<uid>`.

### Authentication failures?

1. Check that Touch ID is enabled in System Settings
2. Ensure your user account has admin privileges
3. Check Console.app for authorization errors

### Commands not working?

The app uses these `launchctl` commands:
- `bootstrap <domain> <path>` - Load a launch item
- `bootout <domain>/<label>` - Unload a launch item
- `enable <domain>/<label>` - Enable automatic startup
- `disable <domain>/<label>` - Disable automatic startup
- `print <domain>/<label>` - Check status
- `print-disabled <domain>` - List disabled items

## Architecture

- **ContentView.swift**: Main UI with split-view layout
- **LaunchItem.swift**: Data models for launch items and types
- **LaunchControlViewModel.swift**: Business logic and state management
- **LaunchItemRow.swift**: Individual row UI component
- **AuthenticationHelper.swift**: Touch ID and privileged execution

## Requirements

- macOS 14.0+
- Xcode 15.0+
- Swift 5.9+

## License

MIT License - feel free to use and modify as needed.
