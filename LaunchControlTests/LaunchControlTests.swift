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
}
