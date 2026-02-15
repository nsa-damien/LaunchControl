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
            Section("Identity") {
                LabeledContent("Label", value: document.wrappedValue.label)
            }

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
            originalData = data
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
