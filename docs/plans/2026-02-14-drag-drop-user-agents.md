# Drag-and-Drop User Agent Installation — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow users to drag `.plist` files onto the LaunchControl window to install them as user agents, with a prompt to enable and start.

**Architecture:** Add `.onDrop` modifier to the NavigationSplitView in ContentView. A new `installUserAgent` method on LaunchControlViewModel handles file validation, copy to `~/Library/LaunchAgents/`, and optional enable+bootstrap. Alert state in ContentView drives the multi-step dialog flow (wrong filter, validation error, overwrite confirmation, post-install prompt).

**Tech Stack:** SwiftUI `.onDrop`, `UniformTypeIdentifiers` framework, `NSItemProvider`, `PropertyListSerialization`, `FileManager`

---

### Task 1: Add `installUserAgent` to ViewModel

**Files:**
- Modify: `LaunchControl/LaunchControlViewModel.swift:381` (after `refreshAll`)

**Step 1: Add the validation + copy + enable method**

After the `refreshAll()` method (line 384), add:

```swift
// MARK: - Install user agent

enum InstallError: LocalizedError {
    case invalidPlist(String)
    case missingLabel(String)
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPlist(let name): return "\(name) is not a valid property list"
        case .missingLabel(let name): return "\(name) has no Label key"
        case .copyFailed(let reason): return "Copy failed: \(reason)"
        }
    }
}

/// Validate that a URL points to a .plist with a Label key. Returns the label.
func validatePlist(at url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
        throw InstallError.invalidPlist(url.lastPathComponent)
    }
    guard let label = plist["Label"] as? String else {
        throw InstallError.missingLabel(url.lastPathComponent)
    }
    return label
}

/// Check if a file with this name already exists in ~/Library/LaunchAgents.
func userAgentExists(fileName: String) -> Bool {
    let dest = LaunchItemType.userAgent.expandedDirectory + "/" + fileName
    return FileManager.default.fileExists(atPath: dest)
}

/// Copy plist to ~/Library/LaunchAgents, optionally enable and start it.
func installUserAgent(from url: URL, enableAndStart: Bool) async throws {
    let fileName = url.lastPathComponent
    let destDir = LaunchItemType.userAgent.expandedDirectory
    let destPath = destDir + "/" + fileName

    // Ensure target directory exists
    try FileManager.default.createDirectory(atPath: destDir, withIntermediateDirectories: true)

    // Copy (overwrite if exists)
    if FileManager.default.fileExists(atPath: destPath) {
        try FileManager.default.removeItem(atPath: destPath)
    }
    try FileManager.default.copyItem(atPath: url.path, toPath: destPath)

    print("📦 Installed \(fileName) to \(destPath)")

    if enableAndStart {
        let label = try validatePlist(at: URL(fileURLWithPath: destPath))
        let domain = "gui/\(getuid())"
        _ = await runCommand("/bin/launchctl", arguments: ["enable", "\(domain)/\(label)"])
        _ = await runCommand("/bin/launchctl", arguments: ["bootstrap", domain, destPath])
        print("✅ Enabled and started \(label)")
    }

    await loadLaunchItems()
}
```

**Step 2: Build to verify compilation**

Run: `xcodebuild -project LaunchControl.xcodeproj -scheme LaunchControl -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add LaunchControl/LaunchControlViewModel.swift
git commit -m "feat: add installUserAgent method to ViewModel"
```

---

### Task 2: Add drop handling and alert state to ContentView

**Files:**
- Modify: `LaunchControl/ContentView.swift:8` (imports)
- Modify: `LaunchControl/ContentView.swift:10-108` (ContentView struct)

**Step 1: Add import and state properties**

Add `import UniformTypeIdentifiers` after `import SwiftUI` (line 8).

Add these `@State` properties after `showingDebug` (line 13):

```swift
@State private var showDropError = false
@State private var dropErrorMessage = ""
@State private var showOverwriteConfirm = false
@State private var showPostInstallPrompt = false
@State private var pendingDropURL: URL?
```

**Step 2: Add the `.onDrop` modifier and alerts**

After the `.sheet(isPresented: $showingDebug)` block (line 105-107), add the `.onDrop` modifier and three `.alert` modifiers:

```swift
.onDrop(of: [.fileURL], isTargeted: nil) { providers in
    handleDrop(providers)
    return true
}
.alert("Cannot Install", isPresented: $showDropError) {
    Button("OK", role: .cancel) {}
} message: {
    Text(dropErrorMessage)
}
.alert("File Already Exists", isPresented: $showOverwriteConfirm) {
    Button("Replace", role: .destructive) {
        guard let url = pendingDropURL else { return }
        proceedWithInstall(url: url)
    }
    Button("Cancel", role: .cancel) {
        pendingDropURL = nil
    }
} message: {
    if let url = pendingDropURL {
        Text("\(url.lastPathComponent) already exists in ~/Library/LaunchAgents. Replace it?")
    }
}
.alert("Agent Installed", isPresented: $showPostInstallPrompt) {
    Button("Enable & Start") {
        guard let url = pendingDropURL else { return }
        Task {
            do {
                try await viewModel.installUserAgent(from: url, enableAndStart: true)
            } catch {
                dropErrorMessage = error.localizedDescription
                showDropError = true
            }
            pendingDropURL = nil
        }
    }
    Button("Just Copy", role: .cancel) {
        guard let url = pendingDropURL else { return }
        Task {
            do {
                try await viewModel.installUserAgent(from: url, enableAndStart: false)
            } catch {
                dropErrorMessage = error.localizedDescription
                showDropError = true
            }
            pendingDropURL = nil
        }
    }
} message: {
    if let url = pendingDropURL {
        Text("\(url.lastPathComponent) will be copied to ~/Library/LaunchAgents. Enable and start it now?")
    }
}
```

**Step 3: Add the helper methods**

Before `iconForType` (line 110), add:

```swift
private func handleDrop(_ providers: [NSItemProvider]) {
    // Only accept when User Agents filter is selected
    guard viewModel.selectedType == .userAgent else {
        dropErrorMessage = "Switch to User Agents filter to install agents."
        showDropError = true
        return
    }

    guard let provider = providers.first else { return }

    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, error in
        guard let data = data as? Data,
              let url = URL(dataRepresentation: data, relativeTo: nil) else {
            DispatchQueue.main.async {
                dropErrorMessage = "Could not read dropped file."
                showDropError = true
            }
            return
        }

        guard url.pathExtension.lowercased() == "plist" else {
            DispatchQueue.main.async {
                dropErrorMessage = "Only .plist files can be installed as launch agents."
                showDropError = true
            }
            return
        }

        // Validate plist content
        do {
            _ = try viewModel.validatePlist(at: url)
        } catch {
            DispatchQueue.main.async {
                dropErrorMessage = error.localizedDescription
                showDropError = true
            }
            return
        }

        DispatchQueue.main.async {
            pendingDropURL = url

            if viewModel.userAgentExists(fileName: url.lastPathComponent) {
                showOverwriteConfirm = true
            } else {
                showPostInstallPrompt = true
            }
        }
    }
}

private func proceedWithInstall(url: URL) {
    pendingDropURL = url
    showPostInstallPrompt = true
}
```

**Step 4: Build to verify compilation**

Run: `xcodebuild -project LaunchControl.xcodeproj -scheme LaunchControl -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 5: Commit**

```bash
git add LaunchControl/ContentView.swift
git commit -m "feat: add drag-and-drop install with alerts for user agents"
```

---

### Task 3: Manual smoke test

**Step 1: Create a test plist**

```bash
cat > tmp/com.test.launchcontrol.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.test.launchcontrol</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/true</string>
    </array>
</dict>
</plist>
EOF
```

**Step 2: Test plan**

1. Build and run in Xcode (Cmd+R)
2. Select "User Agents" in sidebar
3. Drag `tmp/com.test.launchcontrol.plist` onto window → expect "Agent Installed" alert
4. Click "Enable & Start" → expect agent appears in list
5. Switch to "System Agents" → drag file → expect "Switch to User Agents" error
6. Switch back to "User Agents" → drag file again → expect "File Already Exists" overwrite alert
7. Clean up: unload and delete the test agent from the app

**Step 3: Clean up test file**

```bash
rm -f tmp/com.test.launchcontrol.plist
# Also unload from launchctl if loaded:
launchctl bootout gui/$(id -u)/com.test.launchcontrol 2>/dev/null || true
rm -f ~/Library/LaunchAgents/com.test.launchcontrol.plist
```

---

### Task 4: Update docs and changelog

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`
- Create: `CHANGELOG.md`

**Step 1: Add drag-and-drop to README features section**

In `README.md`, add to the features list after "Search and filter":

```markdown
- **Drag-and-drop installation** of new user agents from Finder
```

**Step 2: Create CHANGELOG.md**

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Drag-and-drop .plist files onto window to install as user agents
- Post-install prompt to enable and start newly installed agents
- Overwrite confirmation when installing an agent that already exists
- Filter validation: drop only accepted when User Agents filter is active
```

**Step 3: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: add drag-and-drop feature to README and create CHANGELOG"
```
