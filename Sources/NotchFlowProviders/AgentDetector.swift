import Foundation
import NotchFlowCore

public enum AgentInstallationStatus: Equatable, Sendable {
    case installed
    case notInstalled
    case unknown
}

public struct AgentDetector: Sendable {
    public typealias PathProbe = @Sendable (URL) throws -> Bool

    private let homeDirectory: URL
    private let pathProbe: PathProbe

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(homeDirectory: homeDirectory, pathProbe: Self.pathExists)
    }

    public init(homeDirectory: URL, pathProbe: @escaping PathProbe) {
        self.homeDirectory = homeDirectory
        self.pathProbe = pathProbe
    }

    public func detect() -> [IPCAgentID: AgentInstallationStatus] {
        Dictionary(
            uniqueKeysWithValues: IPCAgentID.allCases.map { agentID in
                (agentID, status(for: agentID))
            })
    }

    private func status(for agentID: IPCAgentID) -> AgentInstallationStatus {
        do {
            return try pathProbe(configurationURL(for: agentID)) ? .installed : .notInstalled
        } catch {
            return .unknown
        }
    }

    private func configurationURL(for agentID: IPCAgentID) -> URL {
        switch agentID {
        case .claudeCode:
            homeDirectory.appending(path: ".claude/settings.json")
        case .codex:
            homeDirectory.appending(path: ".codex/config.toml")
        case .opencode:
            homeDirectory.appending(path: ".config/opencode/plugin", directoryHint: .isDirectory)
        }
    }

    private static func pathExists(_ url: URL) throws -> Bool {
        do {
            _ = try FileManager.default.attributesOfItem(atPath: url.path)
            return true
        } catch let error as CocoaError
            where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile
        {
            return false
        }
    }
}
