import Foundation
import CodexInfoCore

/// The Qoder quota, read from the account usage lines of the app's own log.
///
/// Qoder keeps its token in an encrypted Chromium store, but the main process
/// logs a summary of every `account.getQuotaUsage` response. The reader takes
/// the last summary of the newest log, so no credential is read or sent.
public struct QoderUsageProvider: Sendable {
    private let logRoot: URL
    private let cache = QoderUsageCache()

    /// Creates the provider.
    ///
    /// - Parameter logRoot: the logs of the Qoder app; the tests point it at
    ///   a temporary directory.
    public init(logRoot: URL = QoderUsageProvider.defaultLogRoot) {
        self.logRoot = logRoot
    }

    /// The default logs of Qoder CN.
    public static var defaultLogRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("com.qodercn.app.stable", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
    }

    /// The panel data of the last account usage line.
    public func snapshot() async -> ClientUsageSnapshot? {
        guard let reading = QoderUsageLog.latestReading(logRoot: logRoot, cache: cache) else {
            return ClientUsageSnapshot(
                client: "qoder",
                name: "Qoder",
                quotaLabel: "额度",
                source: "本地用量日志",
                updatedAt: Date(),
                tone: .muted,
                note: "Qoder 刷新账户用量时更新；数据来自本地日志。",
                outputRate: .unavailable("Qoder 本地日志未记录输出耗时")
            )
        }
        let tone = reading.exceeded
            ? ClientBadgeTone.danger
            : ClientBadgeFormatter.tone(quotaPercent: reading.remainingPercent)
        return ClientUsageSnapshot(
            client: "qoder",
            name: "Qoder",
            quotaPercent: reading.remainingPercent,
            quotaLabel: "额度",
            detail: reading.creditDetail,
            resetsAt: reading.expiresAt,
            resetLabel: "到期",
            source: "本地用量日志",
            updatedAt: reading.fetchedAt ?? Date(),
            tone: tone,
            note: "Qoder 刷新账户用量时更新；数据来自本地日志。",
            limits: reading.limits,
            outputRate: .unavailable("Qoder 本地日志未记录输出耗时")
        )
    }
}

/// One credits window of a Qoder account usage line.
struct QoderQuotaWindow: Equatable, Sendable {
    var total: Int
    var used: Int
    var remaining: Int
    /// The used percentage the app reports; it can differ from `used / total`.
    var usedPercent: Int?
}

/// The remaining quota of one account usage line.
struct QoderUsageReading: Equatable, Sendable {
    var remainingPercent: Int
    var remainingCredits: Int?
    var totalCredits: Int?
    var unit: String?
    var expiresAt: Date?
    var fetchedAt: Date?
    var exceeded: Bool
    /// The credits of the plan itself; refreshed at `expiresAt`.
    var plan: QoderQuotaWindow?
    /// The purchased resource package; the log carries no expiry for it.
    var addOn: QoderQuotaWindow?

    /// The credits line of the panel.
    var creditDetail: String? {
        guard let remainingCredits, let totalCredits, totalCredits > 0 else { return nil }
        let unitText = (unit == nil || unit == "credits") ? "积分" : unit!
        return "剩余 \(remainingCredits) / \(totalCredits) \(unitText)"
    }

    /// The plan and the resource package as used / total credits.
    var limits: [ClientQuotaLimit] {
        var limits: [ClientQuotaLimit] = []
        if let plan, plan.total > 0 {
            limits.append(
                ClientQuotaLimit(
                    id: "plan",
                    label: "套餐内 Credits",
                    usedPoints: plan.used,
                    totalPoints: plan.total,
                    usedPercent: plan.usedPercent,
                    resetAt: expiresAt,
                    resetLabel: "刷新"
                )
            )
        }
        if let addOn, addOn.total > 0 {
            limits.append(
                ClientQuotaLimit(
                    id: "addOn",
                    label: "资源包",
                    usedPoints: addOn.used,
                    totalPoints: addOn.total,
                    usedPercent: addOn.usedPercent
                )
            )
        }
        return limits
    }
}

/// The last reading of a Qoder log, keyed by the file and its mtime/size.
///
/// The panel refresh runs every 30 seconds; without this cache the provider
/// would read the same 4 MB tail again and again while Qoder is open.
final class QoderUsageCache: @unchecked Sendable {
    private struct Entry {
        var modified: Date
        var size: UInt64
        var reading: QoderUsageReading?
    }

    private let lock = NSLock()
    private var entries: [URL: Entry] = [:]

    /// The cached result; `hit` is false when the file changed.
    func cached(for url: URL, modified: Date, size: UInt64) -> (hit: Bool, reading: QoderUsageReading?) {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[url], entry.modified == modified, entry.size == size else {
            return (false, nil)
        }
        return (true, entry.reading)
    }

    /// Remembers the result of a file, including "no summary".
    func store(_ reading: QoderUsageReading?, for url: URL, modified: Date, size: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        entries[url] = Entry(modified: modified, size: size, reading: reading)
    }
}

/// Reads the account usage summaries of the Qoder logs.
enum QoderUsageLog {
    /// The marker of the summary line.
    private static let marker = "[AccountUsage] 用量响应摘要 "
    /// The tail sizes, from the common small read to a long-running log.
    private static let tailSizes: [UInt64] = [4_000_000, 16_000_000, 64_000_000]

    /// The last valid summary of the newest log files.
    ///
    /// - Parameters:
    ///   - logRoot: the `logs` directory of the app.
    ///   - cache: the cache of the files; an unchanged file is not read again.
    static func latestReading(logRoot: URL, cache: QoderUsageCache) -> QoderUsageReading? {
        guard let files = logFiles(in: logRoot) else { return nil }
        for file in files {
            let cached = cache.cached(for: file.url, modified: file.modified, size: file.size)
            if cached.hit {
                if let reading = cached.reading { return reading }
                continue
            }
            for size in tailSizes {
                guard let tail = readTail(file.url, maxBytes: size) else { continue }
                if let reading = reading(in: tail, fallbackDate: file.modified) {
                    cache.store(reading, for: file.url, modified: file.modified, size: file.size)
                    return reading
                }
                if file.size <= size { break }
            }
            cache.store(nil, for: file.url, modified: file.modified, size: file.size)
        }
        return nil
    }

    /// The newest `main*.log` files of the runs.
    static func logFiles(in root: URL) -> [(url: URL, modified: Date, size: UInt64)]? {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        var files: [(url: URL, modified: Date, size: UInt64)] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            guard name.hasPrefix("main"), url.pathExtension == "log" else { continue }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            files.append((
                url,
                values.contentModificationDate ?? .distantPast,
                UInt64(values.fileSize ?? 0)
            ))
        }
        return Array(files.sorted { $0.modified > $1.modified }.prefix(8))
    }

    /// The end of a log file, starting at a character boundary.
    ///
    /// A byte offset can fall inside a multi-byte CJK character. The reader
    /// starts after the first newline of the slice (a newline cannot occur
    /// inside a UTF-8 character) and decodes lossily as a second guard.
    static func readTail(_ url: URL, maxBytes: UInt64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let start = end > maxBytes ? end - maxBytes : 0
        guard (try? handle.seek(toOffset: start)) != nil else { return nil }
        guard let data = try? handle.readToEnd() else { return nil }
        var slice = data
        if start > 0, let newline = data.firstIndex(of: 0x0A) {
            slice = data[data.index(after: newline)...]
        }
        return String(decoding: slice, as: UTF8.self)
    }

    /// The last parseable summary in a piece of log text.
    static func reading(in text: String, fallbackDate: Date = Date()) -> QoderUsageReading? {
        var searchEnd = text.endIndex
        while let range = text.range(of: marker, options: .backwards, range: text.startIndex..<searchEnd) {
            let after = range.upperBound
            let lineStart = text[..<range.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
            if let lineEnd = text[after...].firstIndex(of: "\n") {
                if var reading = reading(json: String(text[after..<lineEnd])) {
                    reading.fetchedAt = fetchedAt(in: text[lineStart..<range.lowerBound]) ?? fallbackDate
                    return reading
                }
            } else if var reading = reading(json: String(text[after...])) {
                // The tail starts before the end of the line.
                reading.fetchedAt = fetchedAt(in: text[lineStart..<range.lowerBound]) ?? fallbackDate
                return reading
            }
            searchEnd = range.lowerBound
        }
        return nil
    }

    /// The quota of the JSON object of a summary.
    static func reading(json text: String) -> QoderUsageReading? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else { return nil }
        let json = String(text[start...end])
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let status = number(root["status"]), Int(status) != 200 { return nil }
        guard (root["hasQoderUsage"] as? Bool) == true,
              let usage = root["qoderUsage"] as? [String: Any] else { return nil }
        let exceeded = (usage["isQuotaExceeded"] as? Bool) == true
        var total = 0.0
        var remaining = 0.0
        var unit: String?
        for key in ["userQuota", "addOnQuota"] {
            guard let quota = usage[key] as? [String: Any] else { continue }
            total += number(quota["total"]) ?? 0
            remaining += number(quota["remaining"]) ?? 0
            if unit == nil { unit = quota["unit"] as? String }
        }
        let remainingPercent: Int
        if let fraction = number(usage["totalUsagePercentage"]) {
            remainingPercent = Self.remainingPercent(usedFraction: fraction)
        } else if total > 0 {
            remainingPercent = Self.remainingPercent(usedFraction: 1 - remaining / total)
        } else {
            return nil
        }
        let expiresAt = number(usage["expiresAt"]).flatMap(expiryDate)
        return QoderUsageReading(
            remainingPercent: exceeded ? 0 : remainingPercent,
            remainingCredits: total > 0 ? Int(remaining.rounded()) : nil,
            totalCredits: total > 0 ? Int(total.rounded()) : nil,
            unit: unit,
            expiresAt: expiresAt,
            fetchedAt: nil,
            exceeded: exceeded,
            plan: quotaWindow(usage["userQuota"]),
            addOn: quotaWindow(usage["addOnQuota"])
        )
    }

    /// One `userQuota` or `addOnQuota` object.
    private static func quotaWindow(_ value: Any?) -> QoderQuotaWindow? {
        guard let quota = value as? [String: Any],
              let totalValue = number(quota["total"]),
              totalValue > 0 else { return nil }
        let total = Int(totalValue.rounded())
        let remainingValue = number(quota["remaining"]) ?? 0
        let usedValue = number(quota["used"]) ?? (totalValue - remainingValue)
        let usedPercent = number(quota["percentage"]).map {
            Int((min(max($0, 0), 1) * 100).rounded())
        }
        return QoderQuotaWindow(
            total: total,
            used: max(0, Int(usedValue.rounded())),
            remaining: max(0, Int(remainingValue.rounded())),
            usedPercent: usedPercent
        )
    }

    /// The timestamp at the start of a log line.
    private static func fetchedAt(in prefix: Substring) -> Date? {
        guard let firstSpace = prefix.firstIndex(where: { $0 == " " }) else { return nil }
        let stamp = String(prefix[..<firstSpace])
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: stamp) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: stamp)
    }

    /// A millisecond timestamp, but not the `253402214400000` placeholder of
    /// an account without a real expiry.
    private static func expiryDate(_ milliseconds: Double) -> Date? {
        guard milliseconds > 0 else { return nil }
        let date = Date(timeIntervalSince1970: milliseconds / 1000)
        return date < Date(timeIntervalSince1970: 4_102_444_800) ? date : nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func remainingPercent(usedFraction: Double) -> Int {
        let used = min(max(usedFraction, 0), 1)
        return Int(((1 - used) * 100).rounded())
    }
}
