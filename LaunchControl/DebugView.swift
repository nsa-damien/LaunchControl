//
//  DebugView.swift
//  LaunchControl
//
//  Created by Damien Corbell on 2/13/26.
//

import SwiftUI

struct DebugView: View {
    @State private var userAgentsPath = ""
    @State private var systemAgentsPath = ""
    @State private var systemDaemonsPath = ""
    @State private var userAgentsExists = false
    @State private var systemAgentsExists = false
    @State private var systemDaemonsExists = false
    @State private var userAgentsCount = 0
    @State private var systemAgentsCount = 0
    @State private var systemDaemonsCount = 0
    @State private var userAgentsError = ""
    @State private var systemAgentsError = ""
    @State private var systemDaemonsError = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("LaunchControl Debug Info")
                .font(.title)
                .padding(.bottom)
            
            // User Agents
            GroupBox(label: Label("User Agents", systemImage: "person.circle")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Path: \(userAgentsPath)")
                        .font(.caption)
                        .textSelection(.enabled)
                    
                    HStack {
                        Text("Exists:")
                        Image(systemName: userAgentsExists ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(userAgentsExists ? .green : .red)
                        
                        if userAgentsExists {
                            Text("\(userAgentsCount) .plist files")
                        }
                    }
                    
                    if !userAgentsError.isEmpty {
                        Text("Error: \(userAgentsError)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(8)
            }
            
            // System Agents
            GroupBox(label: Label("System Agents", systemImage: "gearshape.2")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Path: \(systemAgentsPath)")
                        .font(.caption)
                        .textSelection(.enabled)
                    
                    HStack {
                        Text("Exists:")
                        Image(systemName: systemAgentsExists ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(systemAgentsExists ? .green : .red)
                        
                        if systemAgentsExists {
                            Text("\(systemAgentsCount) .plist files")
                        }
                    }
                    
                    if !systemAgentsError.isEmpty {
                        Text("Error: \(systemAgentsError)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(8)
            }
            
            // System Daemons
            GroupBox(label: Label("System Daemons", systemImage: "gearshape.2.fill")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Path: \(systemDaemonsPath)")
                        .font(.caption)
                        .textSelection(.enabled)
                    
                    HStack {
                        Text("Exists:")
                        Image(systemName: systemDaemonsExists ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(systemDaemonsExists ? .green : .red)
                        
                        if systemDaemonsExists {
                            Text("\(systemDaemonsCount) .plist files")
                        }
                    }
                    
                    if !systemDaemonsError.isEmpty {
                        Text("Error: \(systemDaemonsError)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(8)
            }
            
            Spacer()
            
            Button("Check Again") {
                checkDirectories()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            checkDirectories()
        }
    }
    
    private func checkDirectories() {
        let fileManager = FileManager.default
        
        // User Agents
        userAgentsPath = NSString(string: "~/Library/LaunchAgents").expandingTildeInPath
        var isDir: ObjCBool = false
        userAgentsExists = fileManager.fileExists(atPath: userAgentsPath, isDirectory: &isDir) && isDir.boolValue
        
        if userAgentsExists {
            do {
                let files = try fileManager.contentsOfDirectory(atPath: userAgentsPath)
                userAgentsCount = files.filter { $0.hasSuffix(".plist") }.count
                userAgentsError = ""
            } catch {
                userAgentsError = error.localizedDescription
                userAgentsCount = 0
            }
        } else {
            userAgentsError = "Directory does not exist"
        }
        
        // System Agents
        systemAgentsPath = "/Library/LaunchAgents"
        isDir = false
        systemAgentsExists = fileManager.fileExists(atPath: systemAgentsPath, isDirectory: &isDir) && isDir.boolValue
        
        if systemAgentsExists {
            do {
                let files = try fileManager.contentsOfDirectory(atPath: systemAgentsPath)
                systemAgentsCount = files.filter { $0.hasSuffix(".plist") }.count
                systemAgentsError = ""
            } catch {
                systemAgentsError = error.localizedDescription
                systemAgentsCount = 0
            }
        } else {
            systemAgentsError = "Directory does not exist"
        }
        
        // System Daemons
        systemDaemonsPath = "/Library/LaunchDaemons"
        isDir = false
        systemDaemonsExists = fileManager.fileExists(atPath: systemDaemonsPath, isDirectory: &isDir) && isDir.boolValue
        
        if systemDaemonsExists {
            do {
                let files = try fileManager.contentsOfDirectory(atPath: systemDaemonsPath)
                systemDaemonsCount = files.filter { $0.hasSuffix(".plist") }.count
                systemDaemonsError = ""
            } catch {
                systemDaemonsError = error.localizedDescription
                systemDaemonsCount = 0
            }
        } else {
            systemDaemonsError = "Directory does not exist"
        }
    }
}

#Preview {
    DebugView()
}
