//
//  LaunchItemRow.swift
//  LaunchControl
//
//  Created by Damien Corbell on 2/13/26.
//

import SwiftUI
import AppKit

struct LaunchItemRow: View {
    let item: LaunchItem
    let onLoad: () async -> Void
    let onUnload: () async -> Void
    let onEnable: () async -> Void
    let onDisable: () async -> Void
    let onDelete: () async -> Void
    let onKickstart: () async -> Void
    let onEdit: () -> Void
    
    @State private var isWorking = false
    @State private var showingDeleteAlert = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Enabled checkbox on the left
            Button(action: {
                Task {
                    isWorking = true
                    if item.isEnabled {
                        await onDisable()
                    } else {
                        await onEnable()
                    }
                    isWorking = false
                }
            }) {
                Image(systemName: item.isEnabled ? "checkmark.square.fill" : "square")
                    .foregroundStyle(item.isEnabled ? .blue : .secondary)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .help(item.isEnabled ? "Enabled - Click to disable" : "Disabled - Click to enable")
            
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.headline)
                
                Text(item.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 8) {
                    Label(item.type.rawValue, systemImage: typeIcon)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Text(item.status.displayName)
                        .font(.caption2)
                        .foregroundStyle(statusTextColor)
                    
                    if item.requiresAuth {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            
            Spacer()
            
            if isWorking {
                ProgressView()
                    .controlSize(.small)
            } else {
                // Start/Stop button based on running status
                Button(action: {
                    Task {
                        isWorking = true
                        if item.status == .running {
                            await onUnload()
                        } else {
                            await onLoad()
                        }
                        isWorking = false
                    }
                }) {
                    Image(systemName: item.status == .running ? "stop.circle.fill" : "play.circle.fill")
                        .foregroundStyle(item.status == .running ? .red : .green)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
                .help(item.status == .running ? "Stop" : "Start")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                onEdit()
            }
        )
        .contextMenu {
            // Edit section
            Section {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
            }

            // Start/Stop section
            Section {
                if item.status == .running {
                    Button(action: {
                        Task {
                            await onUnload()
                        }
                    }) {
                        Label("Stop", systemImage: "stop.circle")
                    }
                } else {
                    Button(action: {
                        Task {
                            await onLoad()
                        }
                    }) {
                        Label("Start", systemImage: "play.circle")
                    }
                }
            }
            
            // Run Now (kickstart)
            Section {
                Button(action: {
                    Task {
                        await onKickstart()
                    }
                }) {
                    Label("Run Now", systemImage: "bolt.circle")
                }
            }

            // Enable/Disable section
            Section {
                if item.isEnabled {
                    Button(action: {
                        Task {
                            await onDisable()
                        }
                    }) {
                        Label("Disable", systemImage: "xmark.square")
                    }
                } else {
                    Button(action: {
                        Task {
                            await onEnable()
                        }
                    }) {
                        Label("Enable", systemImage: "checkmark.square")
                    }
                }
            }
            
            // Reveal in Finder section
            Section {
                Button(action: {
                    if !NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "") {
                        print("⚠️ Could not reveal \(item.path) in Finder")
                    }
                }) {
                    Label("Reveal in Finder", systemImage: "folder")
                }
            }

            Divider()

            // Delete section
            Button(role: .destructive, action: {
                showingDeleteAlert = true
            }) {
                Label("Delete…", systemImage: "trash")
            }
        }
        .alert("Delete \(item.displayName)?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await onDelete()
                }
            }
        } message: {
            Text("This will permanently delete the file '\(item.name)' from disk. This action cannot be undone.")
        }
    }
    
    private var statusColor: Color {
        switch item.status {
        case .running:
            return .green
        case .stopped:
            return .red
        case .unknown:
            return .gray
        }
    }
    
    private var statusTextColor: Color {
        switch item.status {
        case .running:
            return .green
        case .stopped:
            return .orange
        case .unknown:
            return .secondary
        }
    }
    
    private var typeIcon: String {
        switch item.type {
        case .userAgent:
            return "person.circle"
        case .systemAgent:
            return "gearshape.2"
        case .systemDaemon:
            return "gearshape.2.fill"
        }
    }
}
