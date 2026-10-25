import Foundation

public struct HTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int
    public let headers: [String: String]

    public init(data: Data, statusCode: Int, headers: [String: String] = [:]) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers
    }
}

public enum HTTPError: Error, Equatable {
    case invalidResponse
    case status(Int)
    case emptyResponse
    /// The request left the allow-list of the network (design 5.9).
    case blockedURL
}

public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

/// The hosts the app is allowed to talk to (design 5.9).
///
/// Only HTTPS is accepted, the host has to be on the list and a host that
/// points into the local network is never allowed. A source the user enabled
/// in the settings joins the list for the run.
public enum NetworkAllowList {
    /// The hosts of the default sources.
    public static let defaultHosts: Set<String> = SourceHosts.official.union(SourceHosts.radar)

    /// Whether the URL may be requested.
    ///
    /// - Parameters:
    ///   - url: the URL of the request.
    ///   - hosts: the allowed hosts.
    public static func allows(_ url: URL, hosts: Set<String> = defaultHosts) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        guard !isPrivate(host) else { return false }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Whether the host points into the local network.
    ///
    /// A loopback, a private or a link-local address never belongs to one of
    /// the allowed sources.
    static func isPrivate(_ host: String) -> Bool {
        if host == "localhost" { return true }
        if host.contains(":") {
            // An IPv6 literal: loopback, link-local and unique-local.
            if host == "::1" { return true }
            return host.hasPrefix("fe80:") || host.hasPrefix("fc") || host.hasPrefix("fd")
        }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        switch parts[0] {
        case 0, 10, 127:
            return true
        case 172 where parts[1] >= 16 && parts[1] <= 31:
            return true
        case 192 where parts[1] == 168:
            return true
        case 169 where parts[1] == 254:
            return true
        default:
            return false
        }
    }
}

/// Rejects a redirect that leaves the allow-list (design 5.9).
///
/// The delegate answers `nil` for a redirect to another host, so the request
/// ends with the answer of the redirecting host instead of following it.
public final class AllowListRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let hosts: Set<String>

    /// Creates the delegate.
    ///
    /// - Parameter hosts: the allowed hosts; a redirect to another host is
    ///   rejected.
    public init(hosts: Set<String> = NetworkAllowList.defaultHosts) {
        self.hosts = hosts
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, NetworkAllowList.allows(url, hosts: hosts) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession
    private let hosts: Set<String>

    /// Creates a client that only talks to the allowed hosts.
    ///
    /// The session carries the delegate that rejects a redirect to a host
    /// outside the allow-list. The session keeps nothing on the disk, so no
    /// cookie or cache file of the app carries the token.
    public init(hosts: Set<String> = NetworkAllowList.defaultHosts) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let delegate = AllowListRedirectDelegate(hosts: hosts)
        self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        self.hosts = hosts
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        // The host of the request is checked before the request leaves the
        // process, so a source outside the allow-list never sees a byte.
        guard let url = request.url, NetworkAllowList.allows(url, hosts: hosts) else {
            throw HTTPError.blockedURL
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HTTPError.invalidResponse }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            headers[String(describing: key)] = String(describing: value)
        }
        return HTTPResponse(data: data, statusCode: http.statusCode, headers: headers)
    }
}
