//
//  LaunchItem.swift
//  LaunchControl
//
//  Created by Damien Corbell on 2/13/26.
//

import Foundation

enum LaunchItemType: String, Codable, CaseIterable {
    case userAgent = "User Agent"
    case systemAgent = "System Agent"
    case systemDaemon = "System Daemon"
    
    var directory: String {
        switch self {
        case .userAgent:
            return "~/Library/LaunchAgents"
        case .systemAgent:
            return "/Library/LaunchAgents"
        case .systemDaemon:
            return "/Library/LaunchDaemons"
        }
    }
    
    var expandedDirectory: String {
        switch self {
        case .userAgent:
            // Use actual home directory, not sandbox container
            if let home = ProcessInfo.processInfo.environment["HOME"] {
                return "\(home)/Library/LaunchAgents"
            }
            // Fallback to getting real home directory
            let pw = getpwuid(getuid())
            if let pw = pw, let homeDir = pw.pointee.pw_dir {
                return String(cString: homeDir) + "/Library/LaunchAgents"
            }
            // Last resort: tilde expansion (will be sandboxed)
            return NSString(string: directory).expandingTildeInPath
        case .systemAgent, .systemDaemon:
            return directory
        }
    }
    
    var requiresAuth: Bool {
        switch self {
        case .userAgent:
            return false
        case .systemAgent, .systemDaemon:
            return true
        }
    }
}

enum LaunchItemStatus {
    case running
    case stopped
    case unknown
    
    var displayName: String {
        switch self {
        case .running: return "Running"
        case .stopped: return "Stopped"
        case .unknown: return "Unknown"
        }
    }
}

struct LaunchItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let label: String
    let type: LaunchItemType
    let path: String
    var status: LaunchItemStatus
    var isEnabled: Bool
    var isLoaded: Bool
    
    var displayName: String {
        // Remove .plist extension for display
        name.replacingOccurrences(of: ".plist", with: "")
    }
    
    var requiresAuth: Bool {
        type.requiresAuth
    }
}
