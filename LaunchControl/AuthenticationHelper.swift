//
//  AuthenticationHelper.swift
//  LaunchControl
//
//  Created by Damien Corbell on 2/13/26.
//

import Foundation
import LocalAuthentication
import Security

actor AuthenticationHelper {
    
    /// Authenticate using Touch ID / biometrics and execute privileged command
    func executeWithAuthentication(command: String, arguments: [String]) async throws -> (success: Bool, output: String) {
        // First, authenticate the user
        try await authenticate()
        
        // Use AppleScript to execute with admin privileges
        return try await executeWithAppleScript(command: command, arguments: arguments)
    }
    
    private func authenticate() async throws {
        let context = LAContext()
        var error: NSError?
        
        // Check if biometric authentication is available
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Fall back to password authentication
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                throw AuthError.biometricsUnavailable
            }
            
            // Authenticate with password
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Authenticate to modify system launch items"
            )
            
            guard success else {
                throw AuthError.authenticationFailed
            }
            return
        }
        
        // Authenticate with biometrics (Touch ID)
        let success = try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Authenticate to modify system launch items"
        )
        
        guard success else {
            throw AuthError.authenticationFailed
        }
    }
    
    private func executeWithAppleScript(command: String, arguments: [String]) async throws -> (success: Bool, output: String) {
        // Build the shell command with proper escaping
        let escapedCommand = command.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedArgs = arguments.map { arg in
            arg.replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "'", with: "\\'")
        }
        
        let fullCommand = ([escapedCommand] + escapedArgs).joined(separator: " ")
        
        // Use osascript to execute with administrator privileges
        let script = """
        do shell script "\(fullCommand)" with administrator privileges
        """
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""
            
            let fullOutput = output.isEmpty ? error : output
            
            return (process.terminationStatus == 0, fullOutput)
        } catch {
            throw AuthError.commandExecutionFailed
        }
    }
    
    /// Alternative: Use sudo with pre-authentication
    func executeWithSudo(command: String, arguments: [String]) async throws -> (success: Bool, output: String) {
        // First authenticate
        try await authenticate()
        
        // Create a temporary script file
        let tempDir = FileManager.default.temporaryDirectory
        let scriptPath = tempDir.appendingPathComponent("launchcontrol_\(UUID().uuidString).sh")
        
        // Build the command
        let fullCommand = ([command] + arguments).joined(separator: " ")
        let scriptContent = """
        #!/bin/bash
        \(fullCommand)
        """
        
        do {
            try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)
            
            // Make it executable
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: scriptPath.path
            )
            
            defer {
                try? FileManager.default.removeItem(at: scriptPath)
            }
            
            // Use osascript to run with admin privileges
            let script = """
            do shell script "\(scriptPath.path)" with administrator privileges
            """
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""
            
            let fullOutput = output.isEmpty ? error : output
            
            return (process.terminationStatus == 0, fullOutput)
        } catch {
            throw AuthError.commandExecutionFailed
        }
    }
}

enum AuthError: LocalizedError {
    case biometricsUnavailable
    case authenticationFailed
    case authorizationFailed
    case authorizationDenied
    case commandExecutionFailed
    
    var errorDescription: String? {
        switch self {
        case .biometricsUnavailable:
            return "Biometric authentication is not available on this device"
        case .authenticationFailed:
            return "Authentication failed"
        case .authorizationFailed:
            return "Failed to create authorization"
        case .authorizationDenied:
            return "Authorization was denied"
        case .commandExecutionFailed:
            return "Failed to execute privileged command"
        }
    }
}
