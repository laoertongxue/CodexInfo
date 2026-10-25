import Foundation

public enum AppConstants {
    public static let appName = "CodexInfo"
    public static let version = "0.1.1"
    public static let bundleIdentifier = "com.laoer.codexinfo"
    public static let supportDirectoryName = "CodexInfo"
    public static let codexHomeEnvironmentKey = "CODEX_HOME"
    public static let baseURL = URL(string: "https://chatgpt.com/backend-api")!
    public static let weeklyWindowMinutes: Double = 10_080
    public static let fiveHourWindowMinutes: Double = 300
    public static let refreshQuotaSeconds: TimeInterval = 60
    public static let refreshSessionSeconds: TimeInterval = 5
    public static let refreshAccountSeconds: TimeInterval = 300
    public static let refreshSourcesSeconds: TimeInterval = 60
    /// The client quota endpoints must answer within this window; a hung
    /// request must not stall the panel or the badge forever.
    public static let clientUsageTimeoutSeconds: TimeInterval = 10
    public static let staleSeconds: TimeInterval = 300
    public static let userAgent = "CodexInfo/\(version)"
}
