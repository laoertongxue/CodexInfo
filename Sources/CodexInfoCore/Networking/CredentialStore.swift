import Foundation

public struct CodexCredentials: Equatable, Sendable {
    public let accessToken: String

    public init(accessToken: String) {
        self.accessToken = accessToken
    }
}

public enum CredentialError: Error, Equatable {
    case fileNotFound(String)
    case invalidJSON
    case tokenMissing
}

public protocol CredentialProviding: Sendable {
    func load() throws -> CodexCredentials
}

public struct FileCredentialStore: CredentialProviding {
    public let authURL: URL

    public init(authURL: URL = FileCredentialStore.defaultAuthURL()) {
        self.authURL = authURL
    }

    public func load() throws -> CodexCredentials {
        guard FileManager.default.fileExists(atPath: authURL.path) else {
            throw CredentialError.fileNotFound(authURL.path)
        }
        return try Self.parse(Data(contentsOf: authURL))
    }

    public static func parse(_ data: Data) throws -> CodexCredentials {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CredentialError.invalidJSON
        }
        let tokens = root["tokens"] as? [String: Any]
        let candidates: [Any?] = [
            root["access_token"],
            root["accessToken"],
            tokens?["access_token"],
            tokens?["accessToken"],
        ]
        guard let token = candidates.compactMap({ $0 as? String }).first(where: { !$0.isEmpty }) else {
            throw CredentialError.tokenMissing
        }
        return CodexCredentials(accessToken: token)
    }

    public static func defaultAuthURL() -> URL {
        let environment = ProcessInfo.processInfo.environment
        let codexHome = environment[AppConstants.codexHomeEnvironmentKey]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
        return codexHome.appendingPathComponent("auth.json")
    }
}
