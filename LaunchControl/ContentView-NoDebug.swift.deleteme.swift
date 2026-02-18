//
//  ContentView-NoDebug.swift
//  LaunchControl
//
//  Temporary version without DebugView dependency
//

import SwiftUI

struct ContentView_NoDebug: View {
    @State private var viewModel = LaunchControlViewModel()
    @State private var selectedItem: LaunchItem?
    
    var body: some View {
        NavigationSplitView {
            // Sidebar with filters
            List(selection: $viewModel.selectedType) {
                Section("Filters") {
                    NavigationLink(value: nil as LaunchItemType?) {
                        Label("All Items", systemImage: "list.bullet")
                    }
                    
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
                                // No plist editor in this temporary view.
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
