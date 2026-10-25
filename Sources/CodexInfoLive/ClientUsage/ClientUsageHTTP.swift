import Foundation
import CodexInfoCore

/// The HTTP clients of the per-client quota sources.
///
/// Each provider gets its own host-pinned client: a redirect from DeepSeek
/// can never follow to MiniMax (or any other allow-listed host) with the
/// DeepSeek token attached.
public enum ClientUsageHTTP {
    /// The client of the DeepSeek request; only the grant issuer.
    public static func deepSeek() -> URLSessionHTTPClient {
        URLSessionHTTPClient(hosts: SourceHosts.deepSeek)
    }

    /// The client of the MiniMax request; only the OAuth origin.
    public static func miniMax() -> URLSessionHTTPClient {
        URLSessionHTTPClient(hosts: SourceHosts.miniMax)
    }
}
