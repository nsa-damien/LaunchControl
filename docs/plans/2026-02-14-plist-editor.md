# Plist Editor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a structured plist viewer/editor opened by double-clicking a launch item row, with a raw XML tab.

**Architecture:** New `PlistDocument` model for round-trip plist parsing. `PlistEditorView` sheet with tabbed Form/Raw display. Reusable sub-components (ListEditorView, KeyValueEditorView, CalendarIntervalEditorView). Editing restricted to user agents; system items read-only.

**Tech Stack:** SwiftUI, Foundation (PropertyListSerialization), no new dependencies.

---

### Task 1: PlistDocument Data Model

**Files:**
- Create: `LaunchControl/PlistDocument.swift`
- Test: `LaunchControlTests/LaunchControlTests.swift` (append)

**Step 1: Write failing tests for PlistDocument parsing**

Add to `LaunchControlTests/LaunchControlTests.swift`:

```swift
@Test
func plistDocument_parsesStructuredFields() throws {
    let dict: [String: Any] = [
        "Label": "com.example.test",
        "Program": "/usr/bin/env",
        "ProgramArguments": ["/bin/bash", "-c", "echo hello"],
        "RunAtLoad": true,
        "KeepAlive": false,
        "StartInterval": 300,
        "EnvironmentVariables": ["HOME": "/Users/test"],
        "WorkingDirectory": "/tmp",
        "StandardOutPath": "/tmp/out.log",
        "StandardErrorPath": "/tmp/err.log",
        "ThrottleInterval": 60,
        "Nice": 5,
        "ProcessType": "Background"
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    let doc = try PlistDocument(data: data)

    #expect(doc.label == "com.example.test")
    #expect(doc.program == "/usr/bin/env")
    #expect(doc.programArguments == ["/bin/bash", "-c", "echo hello"])
    #expect(doc.runAtLoad == true)
    #expect(doc.keepAlive == false)
    #expect(doc.startInterval == 300)
    #expect(doc.environmentVariables == ["HOME": "/Users/test"])
    #expect(doc.workingDirectory == "/tmp")
    #expect(doc.standardOutPath == "/tmp/out.log")
    #expect(doc.standardErrorPath == "/tmp/err.log")
    #expect(doc.throttleInterval == 60)
    #expect(doc.nice == 5)
    #expect(doc.processType == "Background")
}

@Test
func plistDocument_preservesOtherKeys() throws {
    let dict: [String: Any] = [
        "Label": "com.example.test",
        "ProgramArguments": ["/bin/true"],
        "SomeCustomKey": "custom-value",
        "AnotherKey": 42
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    let doc = try PlistDocument(data: data)

    #expect(doc.otherKeys["SomeCustomKey"] as? String == "custom-value")
    #expect(doc.otherKeys["AnotherKey"] as? Int == 42)
    #expect(doc.otherKeys["Label"] == nil) // structured keys excluded
    #expect(doc.otherKeys["ProgramArguments"] == nil)
}

@Test
func plistDocument_roundTrips() throws {
    let dict: [String: Any] = [
        "Label": "com.example.test",
        "ProgramArguments": ["/bin/bash", "-c", "echo hello"],
        "RunAtLoad": true,
        "EnvironmentVariables": ["PATH": "/usr/bin"],
        "SomeCustomKey": "preserved"
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    var doc = try PlistDocument(data: data)
    doc.runAtLoad = false
    doc.programArguments = ["/bin/zsh"]

    let outputDict = doc.toDictionary()
    #expect(outputDict["RunAtLoad"] as? Bool == false)
    #expect(outputDict["ProgramArguments"] as? [String] == ["/bin/zsh"])
    #expect(outputDict["Label"] as? String == "com.example.test")
    #expect(outputDict["SomeCustomKey"] as? String == "preserved")
}

@Test
func plistDocument_parsesCalendarInterval() throws {
    let dict: [String: Any] = [
        "Label": "com.example.test",
        "ProgramArguments": ["/bin/true"],
        "StartCalendarInterval": [
            ["Hour": 7, "Minute": 0, "Weekday": 1],
            ["Hour": 15, "Minute": 30]
        ]
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    let doc = try PlistDocument(data: data)

    #expect(doc.startCalendarInterval.count == 2)
    #expect(doc.startCalendarInterval[0].hour == 7)
    #expect(doc.startCalendarInterval[0].minute == 0)
    #expect(doc.startCalendarInterval[0].weekday == 1)
    #expect(doc.startCalendarInterval[1].hour == 15)
    #expect(doc.startCalendarInterval[1].minute == 30)
    #expect(doc.startCalendarInterval[1].weekday == nil)
}

@Test
func plistDocument_throwsForMissingLabel() throws {
    let dict: [String: Any] = ["ProgramArguments": ["/bin/true"]]
    let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)

    #expect(throws: (any Error).self) {
        try PlistDocument(data: data)
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `xcodebuild -project LaunchControl.xcodeproj -scheme LaunchControl build-for-testing -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: Build error — `PlistDocument` not found.

**Step 3: Implement PlistDocument**

Create `LaunchControl/PlistDocument.swift`:

```swift
import Foundation

struct CalendarInterval: Equatable {
    var month: Int?
    var day: Int?
    var weekday: Int?
    var hour: Int?
    var minute: Int?

    init(from dict: [String: Any]) {
        month = dict["Month"] as? Int
        day = dict["Day"] as? Int
        weekday = dict["Weekday"] as? Int
        hour = dict["Hour"] as? Int
        minute = dict["Minute"] as? Int
    }

    init(month: Int? = nil, day: Int? = nil, weekday: Int? = nil, hour: Int? = nil, minute: Int? = nil) {
        self.month = month
        self.day = day
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
    }

    func toDictionary() -> [String: Int] {
        var dict: [String: Int] = [:]
        if let month { dict["Month"] = month }
        if let day { dict["Day"] = day }
        if let weekday { dict["Weekday"] = weekday }
        if let hour { dict["Hour"] = hour }
        if let minute { dict["Minute"] = minute }
        return dict
    }
}

struct PlistDocument {
    enum ParseError: LocalizedError {
        case invalidData
        case missingLabel

        var errorDescription: String? {
            switch self {
            case .invalidData: return "File is not a valid property list"
            case .missingLabel: return "Property list has no Label key"
            }
        }
    }

    // Structured fields
    let label: String
    var program: String?
    var programArguments: [String]
    var runAtLoad: Bool
    var keepAlive: Bool
    var startInterval: Int?
    var startCalendarInterval: [CalendarInterval]
    var watchPaths: [String]
    var environmentVariables: [String: String]
    var workingDirectory: String?
    var standardOutPath: String?
    var standardErrorPath: String?
    var throttleInterval: Int?
    var nice: Int?
    var processType: String?

    // Unmodeled keys for round-trip preservation
    var otherKeys: [String: Any]

    // Raw XML for display
    let rawXML: String

    private static let structuredKeys: Set<String> = [
        "Label", "Program", "ProgramArguments", "RunAtLoad", "KeepAlive",
        "StartInterval", "StartCalendarInterval", "WatchPaths",
        "EnvironmentVariables", "WorkingDirectory", "StandardOutPath",
        "StandardErrorPath", "ThrottleInterval", "Nice", "ProcessType"
    ]

    init(data: Data) throws {
        guard let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw ParseError.invalidData
        }
        guard let label = dict["Label"] as? String else {
            throw ParseError.missingLabel
        }

        self.label = label
        self.program = dict["Program"] as? String
        self.programArguments = dict["ProgramArguments"] as? [String] ?? []
        self.runAtLoad = dict["RunAtLoad"] as? Bool ?? false
        self.keepAlive = dict["KeepAlive"] as? Bool ?? false
        self.startInterval = dict["StartInterval"] as? Int
        self.watchPaths = dict["WatchPaths"] as? [String] ?? []
        self.environmentVariables = dict["EnvironmentVariables"] as? [String: String] ?? [:]
        self.workingDirectory = dict["WorkingDirectory"] as? String
        self.standardOutPath = dict["StandardOutPath"] as? String
        self.standardErrorPath = dict["StandardErrorPath"] as? String
        self.throttleInterval = dict["ThrottleInterval"] as? Int
        self.nice = dict["Nice"] as? Int
        self.processType = dict["ProcessType"] as? String

        // Parse StartCalendarInterval (single dict or array of dicts)
        if let intervals = dict["StartCalendarInterval"] as? [[String: Any]] {
            self.startCalendarInterval = intervals.map { CalendarInterval(from: $0) }
        } else if let single = dict["StartCalendarInterval"] as? [String: Any] {
            self.startCalendarInterval = [CalendarInterval(from: single)]
        } else {
            self.startCalendarInterval = []
        }

        // Preserve unmodeled keys
        self.otherKeys = dict.filter { !Self.structuredKeys.contains($0.key) }

        // Generate raw XML
        if let xmlData = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0),
           let xml = String(data: xmlData, encoding: .utf8) {
            self.rawXML = xml
        } else {
            self.rawXML = ""
        }
    }

    func toDictionary() -> [String: Any] {
        var dict = otherKeys
        dict["Label"] = label
        if let program { dict["Program"] = program }
        if !programArguments.isEmpty { dict["ProgramArguments"] = programArguments }
        if runAtLoad { dict["RunAtLoad"] = true }
        if keepAlive { dict["KeepAlive"] = true }
        if let startInterval { dict["StartInterval"] = startInterval }
        if !startCalendarInterval.isEmpty {
            dict["StartCalendarInterval"] = startCalendarInterval.map { $0.toDictionary() }
        }
        if !watchPaths.isEmpty { dict["WatchPaths"] = watchPaths }
        if !environmentVariables.isEmpty { dict["EnvironmentVariables"] = environmentVariables }
        if let workingDirectory { dict["WorkingDirectory"] = workingDirectory }
        if let standardOutPath { dict["StandardOutPath"] = standardOutPath }
        if let standardErrorPath { dict["StandardErrorPath"] = standardErrorPath }
        if let throttleInterval { dict["ThrottleInterval"] = throttleInterval }
        if let nice { dict["Nice"] = nice }
        if let processType { dict["ProcessType"] = processType }
        return dict
    }
}
```

**Step 4: Add PlistDocument.swift to Xcode project**

Add the new file to the LaunchControl target in the Xcode project. Verify build compiles.

Run: `xcodebuild -project LaunchControl.xcodeproj -scheme LaunchControl build-for-testing -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'BUILD|error:'`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add LaunchControl/PlistDocument.swift LaunchControlTests/LaunchControlTests.swift LaunchControl.xcodeproj
git commit -m "feat: add PlistDocument model with round-trip parsing"
```

---

### Task 2: Reusable Sub-components

**Files:**
- Create: `LaunchControl/Editor/ListEditorView.swift`
- Create: `LaunchControl/Editor/KeyValueEditorView.swift`
- Create: `LaunchControl/Editor/CalendarIntervalEditorView.swift`

**Step 1: Create ListEditorView**

Create `LaunchControl/Editor/ListEditorView.swift`:

```swift
import SwiftUI

struct ListEditorView: View {
    let title: String
    @Binding var items: [String]
    let isEditable: Bool

    var body: some View {
        Section(title) {
            ForEach(items.indices, id: \.self) { index in
                HStack {
                    if isEditable {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.secondary)
                    }
                    TextField("Value", text: $items[index])
                        .textFieldStyle(.roundedBorder)
                        .disabled(!isEditable)
                    if isEditable {
                        Button(action: { items.remove(at: index) }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .onMove { from, to in
                guard isEditable else { return }
                items.move(fromOffsets: from, toOffset: to)
            }
            if isEditable {
                Button(action: { items.append("") }) {
                    Label("Add", systemImage: "plus.circle")
                }
            }
            if items.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

**Step 2: Create KeyValueEditorView**

Create `LaunchControl/Editor/KeyValueEditorView.swift`:

```swift
import SwiftUI

struct KeyValueEditorView: View {
    let title: String
    @Binding var pairs: [String: String]
    let isEditable: Bool

    @State private var sortedKeys: [String] = []

    var body: some View {
        Section(title) {
            ForEach(sortedKeys, id: \.self) { key in
                HStack {
                    TextField("Key", text: Binding(
                        get: { key },
                        set: { newKey in
                            guard newKey != key, let value = pairs[key] else { return }
                            pairs.removeValue(forKey: key)
                            pairs[newKey] = value
                            refreshKeys()
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    .disabled(!isEditable)

                    TextField("Value", text: Binding(
                        get: { pairs[key] ?? "" },
                        set: { pairs[key] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .disabled(!isEditable)

                    if isEditable {
                        Button(action: {
                            pairs.removeValue(forKey: key)
                            refreshKeys()
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if isEditable {
                Button(action: {
                    let newKey = uniqueKey()
                    pairs[newKey] = ""
                    refreshKeys()
                }) {
                    Label("Add", systemImage: "plus.circle")
                }
            }
            if pairs.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { refreshKeys() }
        .onChange(of: pairs) { _, _ in refreshKeys() }
    }

    private func refreshKeys() {
        sortedKeys = pairs.keys.sorted()
    }

    private func uniqueKey() -> String {
        var key = "NEW_KEY"
        var i = 1
        while pairs[key] != nil {
            key = "NEW_KEY_\(i)"
            i += 1
        }
        return key
    }
}
```

**Step 3: Create CalendarIntervalEditorView**

Create `LaunchControl/Editor/CalendarIntervalEditorView.swift`:

```swift
import SwiftUI

struct CalendarIntervalEditorView: View {
    @Binding var intervals: [CalendarInterval]
    let isEditable: Bool

    private static let weekdayNames = [
        1: "Monday", 2: "Tuesday", 3: "Wednesday", 4: "Thursday",
        5: "Friday", 6: "Saturday", 7: "Sunday"
    ]

    var body: some View {
        Section("Calendar Schedule") {
            ForEach(intervals.indices, id: \.self) { index in
                HStack(spacing: 12) {
                    // Weekday picker
                    Picker("Day", selection: Binding(
                        get: { intervals[index].weekday ?? 0 },
                        set: { intervals[index].weekday = $0 == 0 ? nil : $0 }
                    )) {
                        Text("Any").tag(0)
                        ForEach(1...7, id: \.self) { day in
                            Text(Self.weekdayNames[day] ?? "").tag(day)
                        }
                    }
                    .frame(maxWidth: 140)
                    .disabled(!isEditable)

                    // Hour
                    Picker("Hour", selection: Binding(
                        get: { intervals[index].hour ?? 0 },
                        set: { intervals[index].hour = $0 }
                    )) {
                        ForEach(0..<24, id: \.self) { h in
                            Text(String(format: "%02d", h)).tag(h)
                        }
                    }
                    .frame(maxWidth: 70)
                    .disabled(!isEditable)

                    Text(":")

                    // Minute
                    Picker("Min", selection: Binding(
                        get: { intervals[index].minute ?? 0 },
                        set: { intervals[index].minute = $0 }
                    )) {
                        ForEach(0..<60, id: \.self) { m in
                            Text(String(format: "%02d", m)).tag(m)
                        }
                    }
                    .frame(maxWidth: 70)
                    .disabled(!isEditable)

                    if isEditable {
                        Button(action: { intervals.remove(at: index) }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if isEditable {
                Button(action: {
                    intervals.append(CalendarInterval(hour: 0, minute: 0))
                }) {
                    Label("Add Schedule", systemImage: "plus.circle")
                }
            }
            if intervals.isEmpty {
                Text("No schedule")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

**Step 4: Add files to Xcode project and verify build**

Add all three files to the LaunchControl target. Verify build compiles.

Run: `xcodebuild -project LaunchControl.xcodeproj -scheme LaunchControl build -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'BUILD|error:'`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add LaunchControl/Editor/ LaunchControl.xcodeproj
git commit -m "feat: add reusable editor sub-components"
```

---

### Task 3: PlistEditorView Main View

**Files:**
- Create: `LaunchControl/Editor/PlistEditorView.swift`

**Step 1: Create PlistEditorView**

Create `LaunchControl/Editor/PlistEditorView.swift`:

```swift
import SwiftUI

struct PlistEditorView: View {
    let item: LaunchItem
    let onReload: () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var document: PlistDocument?
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var selectedTab = 0
    @State private var showDiscardAlert = false
    @State private var showReloadPrompt = false

    // Snapshot for dirty tracking
    @State private var originalData: Data?

    private var isEditable: Bool { item.type == .userAgent }

    private var isDirty: Bool {
        guard let document, let originalData else { return false }
        let currentDict = document.toDictionary()
        guard let currentData = try? PropertyListSerialization.data(
            fromPropertyList: currentDict, format: .xml, options: 0
        ) else { return false }
        return currentData != originalData
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(item.displayName)
                    .font(.title2.bold())
                Spacer()
                if !isEditable {
                    Text("Read Only")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            .padding()

            if let loadError {
                ContentUnavailableView("Cannot Read File", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else if let document = Binding($document) {
                // Tab picker
                Picker("View", selection: $selectedTab) {
                    Text("Editor").tag(0)
                    Text("Raw").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if selectedTab == 0 {
                    editorTab(document: document)
                } else {
                    rawTab
                }

                // Bottom bar
                HStack {
                    if let saveError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(saveError)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    Spacer()
                    Button("Cancel") { handleCancel() }
                        .keyboardShortcut(.cancelAction)
                    if isEditable {
                        Button("Save") { save() }
                            .keyboardShortcut("s", modifiers: .command)
                            .disabled(!isDirty)
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            } else {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 600, idealWidth: 700, minHeight: 500, idealHeight: 600)
        .task { loadDocument() }
        .alert("Unsaved Changes", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have unsaved changes. Discard them?")
        }
        .alert("Reload Agent?", isPresented: $showReloadPrompt) {
            Button("Reload") {
                Task {
                    await onReload()
                    dismiss()
                }
            }
            Button("Later", role: .cancel) { dismiss() }
        } message: {
            Text("This agent is running. Reload it now for changes to take effect?")
        }
    }

    @ViewBuilder
    private func editorTab(document: Binding<PlistDocument>) -> some View {
        Form {
            // Identity
            Section("Identity") {
                LabeledContent("Label", value: document.wrappedValue.label)
            }

            // Program
            Section("Program") {
                TextField("Executable", text: Binding(
                    get: { document.wrappedValue.program ?? "" },
                    set: { document.wrappedValue.program = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .disabled(!isEditable)
            }

            ListEditorView(
                title: "Program Arguments",
                items: document.programArguments,
                isEditable: isEditable
            )

            // Schedule
            Section("Schedule") {
                Toggle("Run at Load", isOn: document.runAtLoad)
                    .disabled(!isEditable)

                Toggle("Keep Alive", isOn: document.keepAlive)
                    .disabled(!isEditable)

                HStack {
                    Text("Start Interval")
                    Spacer()
                    TextField("seconds", value: Binding(
                        get: { document.wrappedValue.startInterval },
                        set: { document.wrappedValue.startInterval = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 100)
                    .disabled(!isEditable)
                }
            }

            CalendarIntervalEditorView(
                intervals: document.startCalendarInterval,
                isEditable: isEditable
            )

            ListEditorView(
                title: "Watch Paths",
                items: document.watchPaths,
                isEditable: isEditable
            )

            // Environment
            KeyValueEditorView(
                title: "Environment Variables",
                pairs: document.environmentVariables,
                isEditable: isEditable
            )

            Section("Working Directory") {
                TextField("Path", text: Binding(
                    get: { document.wrappedValue.workingDirectory ?? "" },
                    set: { document.wrappedValue.workingDirectory = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .disabled(!isEditable)
            }

            // I/O Paths
            Section("I/O Paths") {
                LabeledContent("Stdout") {
                    TextField("Path", text: Binding(
                        get: { document.wrappedValue.standardOutPath ?? "" },
                        set: { document.wrappedValue.standardOutPath = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .disabled(!isEditable)
                }
                LabeledContent("Stderr") {
                    TextField("Path", text: Binding(
                        get: { document.wrappedValue.standardErrorPath ?? "" },
                        set: { document.wrappedValue.standardErrorPath = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .disabled(!isEditable)
                }
            }

            // Advanced
            Section("Advanced") {
                HStack {
                    Text("Throttle Interval")
                    Spacer()
                    TextField("seconds", value: Binding(
                        get: { document.wrappedValue.throttleInterval },
                        set: { document.wrappedValue.throttleInterval = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 100)
                    .disabled(!isEditable)
                }
                HStack {
                    Text("Nice")
                    Spacer()
                    TextField("priority", value: Binding(
                        get: { document.wrappedValue.nice },
                        set: { document.wrappedValue.nice = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 100)
                    .disabled(!isEditable)
                }
                HStack {
                    Text("Process Type")
                    Spacer()
                    TextField("type", text: Binding(
                        get: { document.wrappedValue.processType ?? "" },
                        set: { document.wrappedValue.processType = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    .disabled(!isEditable)
                }
            }

            // Other Keys
            if !document.wrappedValue.otherKeys.isEmpty {
                DisclosureGroup("Other Keys (\(document.wrappedValue.otherKeys.count))") {
                    ForEach(document.wrappedValue.otherKeys.keys.sorted(), id: \.self) { key in
                        LabeledContent(key) {
                            Text(String(describing: document.wrappedValue.otherKeys[key] ?? ""))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var rawTab: some View {
        ScrollView {
            Text(document?.rawXML ?? "")
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }

    private func loadDocument() {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: item.path))
            document = try PlistDocument(data: data)
            // Snapshot for dirty tracking
            let dict = document!.toDictionary()
            originalData = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save() {
        guard let document else { return }
        saveError = nil
        do {
            let dict = document.toDictionary()
            let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
            try data.write(to: URL(fileURLWithPath: item.path))
            // Update snapshot
            originalData = data
            // Prompt reload if running
            if item.isLoaded {
                showReloadPrompt = true
            } else {
                dismiss()
            }
        } catch {
            saveError = "Save failed: \(error.localizedDescription)"
        }
    }

    private func handleCancel() {
        if isDirty {
            showDiscardAlert = true
        } else {
            dismiss()
        }
    }
}
```

**Step 2: Add to Xcode project and verify build**

Run: `xcodebuild -project LaunchControl.xcodeproj -scheme LaunchControl build -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'BUILD|error:'`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add LaunchControl/Editor/PlistEditorView.swift LaunchControl.xcodeproj
git commit -m "feat: add PlistEditorView with form and raw XML tabs"
```

---

### Task 4: Wire Up Double-Click in ContentView

**Files:**
- Modify: `LaunchControl/ContentView.swift`

**Step 1: Add sheet state and double-click gesture**

In `ContentView.swift`, add state for the editor sheet and wire it to double-click:

1. Add state variable: `@State private var editingItem: LaunchItem?`
2. Add `.sheet(item: $editingItem)` presenting `PlistEditorView`
3. Add `.onTapGesture(count: 2)` to each row in the List, or use `onDoubleClick` gesture on the row

Changes to `ContentView.swift`:

Add state:
```swift
@State private var editingItem: LaunchItem?
```

Replace the `List(viewModel.filteredItems ...)` block — add a double-click gesture to each row:
```swift
List(viewModel.filteredItems, selection: $selectedItem) { item in
    LaunchItemRow(
        item: item,
        onLoad: { await viewModel.loadItem(item) },
        onUnload: { await viewModel.unloadItem(item) },
        onEnable: { await viewModel.enableItem(item) },
        onDisable: { await viewModel.disableItem(item) },
        onDelete: { await viewModel.deleteItem(item) }
    )
    .tag(item)
    .onTapGesture(count: 2) { editingItem = item }
}
```

Add sheet modifier after the existing `.alert` modifiers:
```swift
.sheet(item: $editingItem) { item in
    PlistEditorView(item: item, onReload: {
        if item.isLoaded {
            await viewModel.unloadItem(item)
            await viewModel.loadItem(item)
        }
        await viewModel.refreshAll()
    })
}
```

**Step 2: Verify build**

Run: `xcodebuild -project LaunchControl.xcodeproj -scheme LaunchControl build -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'BUILD|error:'`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add LaunchControl/ContentView.swift
git commit -m "feat: wire plist editor to double-click on launch items"
```

---

### Task 5: Update CHANGELOG and Documentation

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `README.md`

**Step 1: Update CHANGELOG.md**

Add under `[Unreleased]` > `Added`:
```
- Plist editor/viewer: double-click any launch item to view or edit its configuration
- Structured form with sections for Program, Schedule, Environment, I/O, and Advanced settings
- Raw XML tab for inspecting the full plist source
- Reusable editor components: ListEditorView, KeyValueEditorView, CalendarIntervalEditorView
- Save with reload prompt for running agents
- Read-only mode for system agents and daemons
```

**Step 2: Update README.md Features section**

Add to Features list:
```
- **Plist Editor** — Double-click any item to view/edit its configuration with a structured form and raw XML view
```

**Step 3: Commit**

```bash
git add CHANGELOG.md README.md
git commit -m "docs: add plist editor to changelog and readme"
```

---

### Task 6: Manual Smoke Test

**No files modified — verification only.**

**Step 1: Build and run the app from Xcode**

1. Open `LaunchControl.xcodeproj` in Xcode
2. Build and run (Cmd+R)
3. Verify the app launches and items load

**Step 2: Test double-click opens editor**

1. Double-click a user agent in the list
2. Verify: Sheet opens with the structured form
3. Verify: Label field shows correct value and is not editable
4. Verify: ProgramArguments, Schedule, Environment sections populated correctly
5. Switch to "Raw" tab — verify XML is displayed

**Step 3: Test editing (user agent)**

1. Double-click a user agent
2. Toggle "Run at Load"
3. Verify Save button becomes enabled
4. Click Save
5. If agent was running: verify reload prompt appears
6. Re-open — verify the change persisted

**Step 4: Test read-only (system agent/daemon)**

1. Switch to System Agents or System Daemons filter
2. Double-click one
3. Verify: "Read Only" badge shown, all fields disabled, no Save button

**Step 5: Test cancel with unsaved changes**

1. Double-click a user agent
2. Make a change
3. Click Cancel
4. Verify: "Unsaved Changes" confirmation appears
5. Click "Discard" — verify sheet closes without saving
