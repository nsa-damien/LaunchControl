//
//  ContentView.swift
//  LaunchControl
//
//  Created by Damien Corbell on 2/13/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var viewModel = LaunchControlViewModel()
    @State private var selectedItem: LaunchItem?
    @State private var showingDebug = false
    @State private var showDropError = false
    @State private var dropErrorMessage = ""
    @State private var showOverwriteConfirm = false
    @State private var showPostInstallPrompt = false
    @State private var pendingDropURL: URL?
    @State private var editingItem: LaunchItem?

    var body: some View {
        NavigationSplitView {
            // Sidebar with filters
            List(selection: $viewModel.selectedType) {
                Section("Filters") {
                    ForEach(LaunchItemType.allCases, id: \.self) { type in
                        NavigationLink(value: type) {
                            Label(type.rawValue, systemImage: iconForType(type))
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 250)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        Button(action: {
                            showingDebug = true
                        }) {
                            Label("Debug", systemImage: "ladybug")
                        }
                        
                        Button(action: {
                            Task {
                                await viewModel.refreshAll()
                            }
                        }) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .disabled(viewModel.isLoading)
                    }
                }
            }
        } detail: {
            // Main content area
            VStack(spacing: 0) {
                if viewModel.isLoading {
                    ProgressView("Loading launch items...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.filteredItems.isEmpty {
                    ContentUnavailableView(
                        "No Launch Items",
                        systemImage: "tray",
                        description: Text(viewModel.searchText.isEmpty ? "No launch items found" : "No results for '\(viewModel.searchText)'")
                    )
                } else {
                    List(viewModel.filteredItems, selection: $selectedItem) { item in
                        LaunchItemRow(
                            item: item,
                            onLoad: {
                                await viewModel.loadItem(item)
                            },
                            onUnload: {
                                await viewModel.unloadItem(item)
                            },
                            onEnable: {
                                await viewModel.enableItem(item)
                            },
                            onDisable: {
                                await viewModel.disableItem(item)
                            },
                            onDelete: {
                                await viewModel.deleteItem(item)
                            },
                            onKickstart: {
                                await viewModel.kickstartItem(item)
                            },
                            onEdit: {
                                editingItem = item
                            }
                        )
                        .tag(item)
                    }
                    .searchable(text: $viewModel.searchText, prompt: "Search launch items")
                }
            }
            .navigationTitle("Launch Control")
            .toolbar {
                ToolbarItem(placement: .status) {
                    HStack {
                        if let errorMessage = viewModel.errorMessage {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(errorMessage)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                                .lineLimit(1)
                        } else {
                            Text("\(viewModel.filteredItems.count) items")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .task {
            await viewModel.loadLaunchItems()
        }
        .sheet(isPresented: $showingDebug) {
            SimpleDebugView()
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
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
            Button("Enable & Start") { performInstall(enableAndStart: true) }
            Button("Just Copy", role: .cancel) { performInstall(enableAndStart: false) }
        } message: {
            if let url = pendingDropURL {
                Text("\(url.lastPathComponent) will be copied to ~/Library/LaunchAgents. Enable and start it now?")
            }
        }
        .sheet(item: $editingItem) { item in
            PlistEditorView(item: item, onReload: {
                if item.isLoaded {
                    await viewModel.unloadItem(item)
                    await viewModel.loadItem(item)
                }
                await viewModel.refreshAll()
            })
        }
    }
    
    private func performInstall(enableAndStart: Bool) {
        guard let url = pendingDropURL else { return }
        Task {
            do {
                try await viewModel.installUserAgent(from: url, enableAndStart: enableAndStart)
            } catch {
                dropErrorMessage = error.localizedDescription
                showDropError = true
            }
            pendingDropURL = nil
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard viewModel.selectedType == .userAgent else {
            dropErrorMessage = "Switch to User Agents filter to install agents."
            showDropError = true
            return false
        }

        guard let provider = providers.first else { return false }

        Task {
            guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier),
                  let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                dropErrorMessage = "Could not read dropped file."
                showDropError = true
                return
            }

            guard url.pathExtension.lowercased() == "plist" else {
                dropErrorMessage = "Only .plist files can be installed as launch agents."
                showDropError = true
                return
            }

            do {
                _ = try viewModel.validatePlist(at: url)
            } catch {
                dropErrorMessage = error.localizedDescription
                showDropError = true
                return
            }

            pendingDropURL = url
            if viewModel.userAgentExists(fileName: url.lastPathComponent) {
                showOverwriteConfirm = true
            } else {
                showPostInstallPrompt = true
            }
        }

        return true
    }

    private func proceedWithInstall(url: URL) {
        pendingDropURL = url
        showPostInstallPrompt = true
    }

    private func iconForType(_ type: LaunchItemType) -> String {
        switch type {
        case .userAgent:
            return "person.circle"
        case .systemAgent:
            return "gearshape.2"
        case .systemDaemon:
            return "gearshape.2.fill"
        }
    }
}

// Inline debug view to avoid file issues
private struct SimpleDebugView: View {
    @State private var debugInfo: String = "Checking..."
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Debug Information")
                    .font(.title)
                
                Text(debugInfo)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                
                Button("Refresh") {
                    checkDirectories()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            checkDirectories()
        }
    }
    
    private func checkDirectories() {
        var output = ""
        let fm = FileManager.default
        
        for type in LaunchItemType.allCases {
            let path = type.expandedDirectory
            output += "\n\(type.rawValue)\n"
            output += "Path: \(path)\n"
            
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue {
                do {
                    let files = try fm.contentsOfDirectory(atPath: path)
                    let plists = files.filter { $0.hasSuffix(".plist") }
                    output += "✅ Directory exists\n"
                    output += "📁 Total files: \(files.count)\n"
                    output += "📄 Plist files: \(plists.count)\n"
                    if plists.count > 0 {
                        output += "Files:\n"
                        for plist in plists.prefix(10) {
                            output += "  - \(plist)\n"
                        }
                        if plists.count > 10 {
                            output += "  ... and \(plists.count - 10) more\n"
                        }
                    }
                } catch {
                    output += "❌ Error reading: \(error.localizedDescription)\n"
                }
            } else {
                output += "❌ Directory does not exist or is not accessible\n"
            }
            output += "\n"
        }
        
        debugInfo = output
    }
}

#Preview {
    ContentView()
}
