import Foundation

public enum AppConstants {
    public static let appName = "CodexInfo"
    public static let version = "0.1.0"
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
    public static let staleSeconds: TimeInterval = 300
    public static let userAgent = "CodexInfo/0.1.0"
}
