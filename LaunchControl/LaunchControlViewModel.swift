//
//  LaunchControlViewModel.swift
//  LaunchControl
//
//  Created by Damien Corbell on 2/13/26.
//

import Foundation
import SwiftUI

@MainActor
@Observable
class LaunchControlViewModel {
    typealias CommandRunner = @Sendable (_ command: String, _ arguments: [String]) async -> (success: Bool, output: String)

    var launchItems: [LaunchItem] = []
    var isLoading = false
    var errorMessage: String?
    var searchText = ""
    var selectedType: LaunchItemType? = .userAgent
    
    private let authHelper: AuthenticationHelper
    private let fileManager: FileManager
    private let userAgentDirectory: String
    private let commandRunner: CommandRunner?
    private let autoRefreshAfterInstall: Bool

    init(
        authHelper: AuthenticationHelper = AuthenticationHelper(),
        fileManager: FileManager = .default,
        userAgentDirectory: String? = nil,
        commandRunner: CommandRunner? = nil,
        autoRefreshAfterInstall: Bool = true
    ) {
        self.authHelper = authHelper
        self.fileManager = fileManager
        self.userAgentDirectory = userAgentDirectory ?? LaunchItemType.userAgent.expandedDirectory
        self.commandRunner = commandRunner
        self.autoRefreshAfterInstall = autoRefreshAfterInstall
    }
    
    var filteredItems: [LaunchItem] {
        var items = launchItems
        
        if let selectedType {
            items = items.filter { $0.type == selectedType }
        }
        
        if !searchText.isEmpty {
            items = items.filter { item in
                item.displayName.localizedCaseInsensitiveContains(searchText) ||
                item.label.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return items.sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
    }
    
    func loadLaunchItems() async {
        isLoading = true
        errorMessage = nil
        
        let separator = String(repeating: "=", count: 60)
        print(separator)
        print("🚀 Starting to load launch items...")
        print(separator)
        
        var items: [LaunchItem] = []
        var errors: [String] = []
        
        let allTypes = LaunchItemType.allCases
        print("📋 Types to check: \(allTypes.map { $0.rawValue }.joined(separator: ", "))")
        
        for type in allTypes {
            print("\n🔄 Processing type: \(type.rawValue)")
            print("   Path: \(type.expandedDirectory)")
            
            do {
                let typeItems = try await loadItems(for: type)
                items.append(contentsOf: typeItems)
                print("✅ Loaded \(typeItems.count) items from \(type.rawValue)")
            } catch {
                let errorMsg = "Failed to load \(type.rawValue): \(error.localizedDescription)"
                errors.append(errorMsg)
                print("❌ \(errorMsg)")
            }
        }
        
        print("\n\(separator)")
        print("📊 FINAL RESULTS:")
        print("   Total items loaded: \(items.count)")
        print("   Errors: \(errors.count)")
        if !errors.isEmpty {
            print("   Error details: \(errors.joined(separator: "; "))")
        }
        print("\(separator)\n")
        
        self.launchItems = items
        
        if !errors.isEmpty && items.isEmpty {
            errorMessage = errors.joined(separator: "; ")
        }
        
        isLoading = false
    }
    
    private func loadItems(for type: LaunchItemType) async throws -> [LaunchItem] {
        let directory = type.expandedDirectory
        
        print("🔍 Checking directory: \(directory)")
        
        // First check if directory exists
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory, isDirectory: &isDirectory) else {
            print("⚠️ Directory does not exist: \(directory)")
            return []
        }
        
        guard isDirectory.boolValue else {
            print("⚠️ Path is not a directory: \(directory)")
            return []
        }
        
        // Try to read directory contents
        let files: [String]
        do {
            files = try fileManager.contentsOfDirectory(atPath: directory)
            print("📁 Found \(files.count) files in \(directory)")
        } catch {
            print("❌ Error reading directory \(directory): \(error)")
            throw error
        }
        
        let plistFiles = files.filter { $0.hasSuffix(".plist") }
        print("📄 Found \(plistFiles.count) .plist files")
        
        // Process files one by one to see which ones fail
        var items: [LaunchItem] = []
        for file in plistFiles {
            if let item = await createLaunchItem(fileName: file, type: type, directory: directory) {
                items.append(item)
                print("✅ Successfully added: \(item.displayName)")
            } else {
                print("❌ Failed to create item from: \(file)")
            }
        }
        
        print("📦 Loaded \(items.count) items from \(type.rawValue)")
        return items
    }
    
    private func createLaunchItem(fileName: String, type: LaunchItemType, directory: String) async -> LaunchItem? {
        let path = "\(directory)/\(fileName)"
        
        print("🔧 Processing: \(fileName)")
        
        // Try to read the plist file
        guard let plistData = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            print("❌ Could not read file: \(path)")
            return nil
        }
        
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            print("❌ Could not parse plist: \(fileName)")
            return nil
        }
        
        guard let label = plist["Label"] as? String else {
            print("❌ No Label key in plist: \(fileName)")
            return nil
        }
        
        print("✅ Found label: \(label)")
        
        // Quick check status without blocking
        let (status, isLoaded) = await getStatus(for: label, type: type)
        let isEnabled = await checkIfEnabled(label: label, type: type)
        
        print("📊 \(label):")
        print("   - Status: \(status.displayName)")
        print("   - Loaded: \(isLoaded)")
        print("   - Enabled: \(isEnabled)")
        
        let item = LaunchItem(
            name: fileName,
            label: label,
            type: type,
            path: path,
            status: status,
            isEnabled: isEnabled,
            isLoaded: isLoaded
        )
        
        print("✅ Created launch item: \(item.displayName) (loaded=\(item.isLoaded))")
        
        return item
    }
    
    private func getStatus(for label: String, type: LaunchItemType) async -> (status: LaunchItemStatus, isLoaded: Bool) {
        // For user agents, use gui domain with proper uid
        let domain: String
        if type == .userAgent {
            domain = "gui/\(getuid())"
        } else {
            domain = "system"
        }
        
        print("🔍 Checking status for \(label) in domain: \(domain)")
        
        let result = await runCommand("/bin/launchctl", arguments: ["print", "\(domain)/\(label)"])
        
        if result.success {
            // If the print command succeeds, the service is loaded
            // Now check if it's actually running
            let output = result.output.lowercased()
            let isRunning = output.contains("state = running") || output.contains("state=running")
            
            print("   Service is loaded. Running: \(isRunning)")
            return (isRunning ? .running : .stopped, true)
        } else {
            // If print fails, the service is not loaded at all
            print("   Service is NOT loaded")
            return (.stopped, false)
        }
    }
    
    private func checkIfEnabled(label: String, type: LaunchItemType) async -> Bool {
        // Check if service is in disabled list
        let domain = type == .userAgent ? "gui/\(getuid())" : "system"
        let result = await runCommand("/bin/launchctl", arguments: ["print-disabled", domain])
        
        if result.success {
            // Parse output to check if our label is disabled
            return !result.output.contains("\"\(label)\" => disabled")
        }
        
        return true // Assume enabled if we can't determine
    }
    
    func loadItem(_ item: LaunchItem) async {
        do {
            if item.requiresAuth {
                try await loadItemWithAuth(item)
            } else {
                await loadItemWithoutAuth(item)
            }
            await updateItemStatus(item)
        } catch {
            errorMessage = "Failed to load \(item.displayName): \(error.localizedDescription)"
        }
    }
    
    func unloadItem(_ item: LaunchItem) async {
        do {
            if item.requiresAuth {
                try await unloadItemWithAuth(item)
            } else {
                await unloadItemWithoutAuth(item)
            }
            await updateItemStatus(item)
        } catch {
            errorMessage = "Failed to unload \(item.displayName): \(error.localizedDescription)"
        }
    }
    
    func enableItem(_ item: LaunchItem) async {
        do {
            if item.requiresAuth {
                try await enableItemWithAuth(item)
            } else {
                await enableItemWithoutAuth(item)
            }
            await updateItemStatus(item)
        } catch {
            errorMessage = "Failed to enable \(item.displayName): \(error.localizedDescription)"
        }
    }
    
    func disableItem(_ item: LaunchItem) async {
        do {
            if item.requiresAuth {
                try await disableItemWithAuth(item)
            } else {
                await disableItemWithoutAuth(item)
            }
            await updateItemStatus(item)
        } catch {
            errorMessage = "Failed to disable \(item.displayName): \(error.localizedDescription)"
        }
    }
    
    func deleteItem(_ item: LaunchItem) async {
        do {
            // First, unload if currently loaded
            if item.isLoaded {
                if item.requiresAuth {
                    try await unloadItemWithAuth(item)
                } else {
                    await unloadItemWithoutAuth(item)
                }
            }
            
            // Then delete the file
            if item.requiresAuth {
                try await deleteItemWithAuth(item)
            } else {
                try await deleteItemWithoutAuth(item)
            }
            
            // Remove from our list
            launchItems.removeAll { $0.id == item.id }
            
            print("✅ Deleted \(item.displayName)")
        } catch {
            errorMessage = "Failed to delete \(item.displayName): \(error.localizedDescription)"
            print("❌ Delete failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - User-level operations (no auth required)
    
    private func loadItemWithoutAuth(_ item: LaunchItem) async {
        let domain = "gui/\(getuid())"
        _ = await runCommand("/bin/launchctl", arguments: ["bootstrap", domain, item.path])
    }
    
    private func unloadItemWithoutAuth(_ item: LaunchItem) async {
        let domain = "gui/\(getuid())"
        _ = await runCommand("/bin/launchctl", arguments: ["bootout", "\(domain)/\(item.label)"])
    }
    
    private func enableItemWithoutAuth(_ item: LaunchItem) async {
        let domain = "gui/\(getuid())"
        _ = await runCommand("/bin/launchctl", arguments: ["enable", "\(domain)/\(item.label)"])
    }
    
    private func disableItemWithoutAuth(_ item: LaunchItem) async {
        let domain = "gui/\(getuid())"
        _ = await runCommand("/bin/launchctl", arguments: ["disable", "\(domain)/\(item.label)"])
    }
    
    // MARK: - System-level operations (require auth)
    
    private func loadItemWithAuth(_ item: LaunchItem) async throws {
        let domain = "system"
        _ = try await authHelper.executeWithAuthentication(
            command: "/bin/launchctl",
            arguments: ["bootstrap", domain, item.path]
        )
    }
    
    private func unloadItemWithAuth(_ item: LaunchItem) async throws {
        let domain = "system"
        _ = try await authHelper.executeWithAuthentication(
            command: "/bin/launchctl",
            arguments: ["bootout", "\(domain)/\(item.label)"]
        )
    }
    
    private func enableItemWithAuth(_ item: LaunchItem) async throws {
        let domain = "system"
        _ = try await authHelper.executeWithAuthentication(
            command: "/bin/launchctl",
            arguments: ["enable", "\(domain)/\(item.label)"]
        )
    }
    
    private func disableItemWithAuth(_ item: LaunchItem) async throws {
        let domain = "system"
        _ = try await authHelper.executeWithAuthentication(
            command: "/bin/launchctl",
            arguments: ["disable", "\(domain)/\(item.label)"]
        )
    }
    
    private func deleteItemWithoutAuth(_ item: LaunchItem) async throws {
        try fileManager.removeItem(atPath: item.path)
    }
    
    private func deleteItemWithAuth(_ item: LaunchItem) async throws {
        _ = try await authHelper.executeWithAuthentication(
            command: "/bin/rm",
            arguments: ["-f", item.path]
        )
    }
    
    // MARK: - Status update
    
    private func updateItemStatus(_ item: LaunchItem) async {
        guard let index = launchItems.firstIndex(where: { $0.id == item.id }) else { return }
        
        let (newStatus, isLoaded) = await getStatus(for: item.label, type: item.type)
        let isEnabled = await checkIfEnabled(label: item.label, type: item.type)
        
        launchItems[index].status = newStatus
        launchItems[index].isLoaded = isLoaded
        launchItems[index].isEnabled = isEnabled
    }
    
    func refreshAll() async {
        await loadLaunchItems()
    }

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
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let plist: [String: Any]
        do {
            guard let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                throw InstallError.invalidPlist(url.lastPathComponent)
            }
            plist = parsed
        } catch let installError as InstallError {
            throw installError
        } catch {
            throw InstallError.invalidPlist("\(url.lastPathComponent): \(error.localizedDescription)")
        }
        guard let label = plist["Label"] as? String else {
            throw InstallError.missingLabel(url.lastPathComponent)
        }
        return label
    }

    /// Check if a file with this name already exists in ~/Library/LaunchAgents.
    func userAgentExists(fileName: String) -> Bool {
        let dest = (userAgentDirectory as NSString).appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: dest)
    }

    /// Copy plist to ~/Library/LaunchAgents, optionally enable and start it.
    func installUserAgent(from url: URL, enableAndStart: Bool) async throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let fileName = url.lastPathComponent
        let destDir = userAgentDirectory
        let destPath = (destDir as NSString).appendingPathComponent(fileName)

        // Ensure target directory exists
        do {
            try fileManager.createDirectory(atPath: destDir, withIntermediateDirectories: true)
        } catch {
            throw InstallError.copyFailed(error.localizedDescription)
        }

        // Copy (overwrite if exists)
        do {
            if fileManager.fileExists(atPath: destPath) {
                try fileManager.removeItem(atPath: destPath)
            }
            try fileManager.copyItem(atPath: url.path, toPath: destPath)
        } catch {
            throw InstallError.copyFailed(error.localizedDescription)
        }

        print("📦 Installed \(fileName) to \(destPath)")

        if enableAndStart {
            let label = try validatePlist(at: URL(fileURLWithPath: destPath))
            let domain = "gui/\(getuid())"
            let enableResult = await runCommand("/bin/launchctl", arguments: ["enable", "\(domain)/\(label)"])
            let bootstrapResult = await runCommand("/bin/launchctl", arguments: ["bootstrap", domain, destPath])

            var warnings: [String] = []
            if !enableResult.success {
                warnings.append("enable failed: \(enableResult.output)")
            }
            if !bootstrapResult.success {
                warnings.append("start failed: \(bootstrapResult.output)")
            }
            if warnings.isEmpty {
                print("✅ Enabled and started \(label)")
            } else {
                let msg = "Agent copied but \(warnings.joined(separator: "; "))"
                print("⚠️ \(msg)")
                errorMessage = msg
            }
        }

        if autoRefreshAfterInstall {
            await loadLaunchItems()
        }
    }

    private func runCommand(_ command: String, arguments: [String]) async -> (success: Bool, output: String) {
        if let commandRunner {
            return await commandRunner(command, arguments)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        print("🚀 Running: \(command) \(arguments.joined(separator: " "))")
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""
            
            let success = process.terminationStatus == 0
            let fullOutput = output + error
            
            print("📤 Command finished with status: \(process.terminationStatus)")
            if !fullOutput.isEmpty {
                print("📄 Output: \(fullOutput.prefix(200))")
            }
            
            return (success, fullOutput)
        } catch {
            print("❌ Command failed: \(error.localizedDescription)")
            return (false, error.localizedDescription)
        }
    }
}
