//
//  LaunchControlTests.swift
//  LaunchControlTests
//
//  Created by Damien Corbell on 2/13/26.
//

import Foundation
import Testing
@testable import LaunchControl

@MainActor
struct LaunchControlTests {

    @Test
    func filteredItems_appliesTypeSearchAndSort() {
        let viewModel = LaunchControlViewModel(autoRefreshAfterInstall: false)
        viewModel.launchItems = [
            LaunchItem(
                name: "zeta.plist",
                label: "com.example.zeta",
                type: .userAgent,
                path: "/tmp/zeta.plist",
                status: .running,
                isEnabled: true,
                isLoaded: true
            ),
            LaunchItem(
                name: "alpha.plist",
                label: "com.example.alpha",
                type: .userAgent,
                path: "/tmp/alpha.plist",
                status: .stopped,
                isEnabled: false,
                isLoaded: false
            ),
            LaunchItem(
                name: "daemon.plist",
                label: "com.example.daemon",
                type: .systemDaemon,
                path: "/tmp/daemon.plist",
                status: .stopped,
                isEnabled: true,
                isLoaded: false
            )
        ]

        viewModel.selectedType = .userAgent
        viewModel.searchText = ""
        #expect(viewModel.filteredItems.map(\.displayName) == ["alpha", "zeta"])

        viewModel.searchText = "ALPHA"
        #expect(viewModel.filteredItems.count == 1)
        #expect(viewModel.filteredItems.first?.label == "com.example.alpha")
    }

    @Test
    func validatePlist_returnsLabelForValidPlist() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plistURL = tempDir.appendingPathComponent("valid.plist")
        try writePlist(["Label": "com.example.agent"], to: plistURL)

        let viewModel = LaunchControlViewModel(autoRefreshAfterInstall: false)
        let label = try viewModel.validatePlist(at: plistURL)
        #expect(label == "com.example.agent")
    }

    @Test
    func validatePlist_throwsForInvalidPlistAndMissingLabel() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let invalidURL = tempDir.appendingPathComponent("invalid.plist")
        try Data("not a plist".utf8).write(to: invalidURL)

        let missingLabelURL = tempDir.appendingPathComponent("missing-label.plist")
        try writePlist(["ProgramArguments": ["/bin/echo", "hello"]], to: missingLabelURL)

        let viewModel = LaunchControlViewModel(autoRefreshAfterInstall: false)

        do {
            _ = try viewModel.validatePlist(at: invalidURL)
            Issue.record("Expected invalid plist to throw")
        } catch let error as LaunchControlViewModel.InstallError {
            switch error {
            case .invalidPlist(let detail):
                #expect(detail.hasPrefix("invalid.plist"))
            default:
                Issue.record("Unexpected error: \(error.localizedDescription)")
            }
        }

        do {
            _ = try viewModel.validatePlist(at: missingLabelURL)
            Issue.record("Expected missing label to throw")
        } catch let error as LaunchControlViewModel.InstallError {
            switch error {
            case .missingLabel(let fileName):
                #expect(fileName == "missing-label.plist")
            default:
                Issue.record("Unexpected error: \(error.localizedDescription)")
            }
        }
    }

    @Test
    func userAgentExists_and_installUserAgent_copyAndOverwrite() async throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let installDir = tempDir.appendingPathComponent("LaunchAgents", isDirectory: true)
        let sourceDir = tempDir.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let sourceURL = sourceDir.appendingPathComponent("com.example.agent.plist")
        try writePlist(["Label": "com.example.first"], to: sourceURL)

        let viewModel = LaunchControlViewModel(
            userAgentDirectory: installDir.path,
            autoRefreshAfterInstall: false
        )

        #expect(viewModel.userAgentExists(fileName: sourceURL.lastPathComponent) == false)
        try await viewModel.installUserAgent(from: sourceURL, enableAndStart: false)
        #expect(viewModel.userAgentExists(fileName: sourceURL.lastPathComponent) == true)

        let installedURL = installDir.appendingPathComponent(sourceURL.lastPathComponent)
        let firstLabel = try readPlistLabel(from: installedURL)
        #expect(firstLabel == "com.example.first")

        try writePlist(["Label": "com.example.second"], to: sourceURL)
        try await viewModel.installUserAgent(from: sourceURL, enableAndStart: false)
        let secondLabel = try readPlistLabel(from: installedURL)
        #expect(secondLabel == "com.example.second")
    }

    @Test
    func installUserAgent_enableAndStart_invokesLaunchctlCommands() async throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let installDir = tempDir.appendingPathComponent("LaunchAgents", isDirectory: true)
        let sourceDir = tempDir.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let sourceURL = sourceDir.appendingPathComponent("com.example.agent.plist")
        try writePlist(["Label": "com.example.agent"], to: sourceURL)

        let collector = CommandCollector()
        let viewModel = LaunchControlViewModel(
            userAgentDirectory: installDir.path,
            commandRunner: { command, arguments in
                await collector.record(command: command, arguments: arguments)
                return (true, "")
            },
            autoRefreshAfterInstall: false
        )

        try await viewModel.installUserAgent(from: sourceURL, enableAndStart: true)

        let calls = await collector.snapshot()
        #expect(calls.count == 2)
        #expect(calls[0].command == "/bin/launchctl")
        #expect(calls[0].arguments.first == "enable")
        #expect(calls[0].arguments.count == 2)
        #expect(calls[0].arguments[1].contains("/com.example.agent"))

        #expect(calls[1].command == "/bin/launchctl")
        #expect(calls[1].arguments.first == "bootstrap")
        #expect(calls[1].arguments.count == 3)
        #expect(calls[1].arguments[2].hasSuffix("/com.example.agent.plist"))
    }

    @Test
    func installUserAgent_throwsCopyFailed_whenDirectoryUnwritable() async throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceDir = tempDir.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let sourceURL = sourceDir.appendingPathComponent("agent.plist")
        try writePlist(["Label": "com.example.agent"], to: sourceURL)

        let viewModel = LaunchControlViewModel(
            userAgentDirectory: "/nonexistent/deeply/nested/path",
            autoRefreshAfterInstall: false
        )

        do {
            try await viewModel.installUserAgent(from: sourceURL, enableAndStart: false)
            Issue.record("Expected copyFailed error")
        } catch let error as LaunchControlViewModel.InstallError {
            switch error {
            case .copyFailed:
                break // expected
            default:
                Issue.record("Expected copyFailed, got \(error)")
            }
        }
    }

    @Test
    func installUserAgent_enableAndStart_completesWhenLaunchctlFails() async throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let installDir = tempDir.appendingPathComponent("LaunchAgents", isDirectory: true)
        let sourceDir = tempDir.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let sourceURL = sourceDir.appendingPathComponent("agent.plist")
        try writePlist(["Label": "com.example.agent"], to: sourceURL)

        let viewModel = LaunchControlViewModel(
            userAgentDirectory: installDir.path,
            commandRunner: { _, _ in (false, "service not found") },
            autoRefreshAfterInstall: false
        )

        // Should NOT throw even though launchctl fails
        try await viewModel.installUserAgent(from: sourceURL, enableAndStart: true)

        // File should still be installed
        #expect(viewModel.userAgentExists(fileName: "agent.plist") == true)
        // errorMessage should be set to inform the user
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.errorMessage?.contains("copied but") == true)
    }

    private actor CommandCollector {
        private var calls: [(command: String, arguments: [String])] = []

        func record(command: String, arguments: [String]) {
            calls.append((command: command, arguments: arguments))
        }

        func snapshot() -> [(command: String, arguments: [String])] {
            calls
        }
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchControlTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writePlist(_ dictionary: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        try data.write(to: url)
    }

    private enum TestError: Error { case missingLabel }

    private func readPlistLabel(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard
            let dict = plist as? [String: Any],
            let label = dict["Label"] as? String
        else {
            throw TestError.missingLabel
        }
        return label
    }

    // MARK: - PlistDocument Tests

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
        #expect(doc.otherKeys["Label"] == nil)
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
        #expect(outputDict["RunAtLoad"] as? Bool == nil) // false = omitted
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
    func plistDocument_parsesSingleCalendarInterval() throws {
        let dict: [String: Any] = [
            "Label": "com.example.test",
            "ProgramArguments": ["/bin/true"],
            "StartCalendarInterval": ["Hour": 9, "Minute": 15]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        let doc = try PlistDocument(data: data)

        #expect(doc.startCalendarInterval.count == 1)
        #expect(doc.startCalendarInterval[0].hour == 9)
        #expect(doc.startCalendarInterval[0].minute == 15)
    }

    @Test
    func plistDocument_throwsForMissingLabel() throws {
        let dict: [String: Any] = ["ProgramArguments": ["/bin/true"]]
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)

        #expect(throws: (any Error).self) {
            try PlistDocument(data: data)
        }
    }
}
