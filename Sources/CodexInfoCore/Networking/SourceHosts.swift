import Foundation

/// The hosts of one source that carries a credential.
///
/// A credential never shares an HTTP client with another source: the redirect
/// delegate of each client only accepts the hosts of its own source, so a
/// redirect can never carry a token to a different vendor.
public enum SourceHosts {
    /// The official OpenAI usage endpoints, and only they, receive the Codex
    /// access token.
    public static let official: Set<String> = ["chatgpt.com"]
    /// The public reset sources; they carry no credential.
    public static let radar: Set<String> = [
        "codexradar.com",
        "codex-reset.com",
        "status.openai.com",
    ]
    /// The DeepSeek platform, the issuer of the harness grant.
    public static let deepSeek: Set<String> = ["platform.deepseek.com"]
    /// The MiniMax open platform, the issuer of the OAuth token.
    public static let miniMax: Set<String> = ["www.minimaxi.com"]
}
