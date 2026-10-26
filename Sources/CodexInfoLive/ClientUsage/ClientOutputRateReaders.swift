import Foundation
import CodexInfoCore

/// Builds the output-rate summary of the local samples.
enum ClientOutputRateSummary {
    /// The newest sample and the median of the samples, or `nil` when no
    /// sample carries a positive rate.
    static func make(
        _ samples: [(rate: Double, at: Date)],
        unit: String,
        basis: String
    ) -> ClientOutputRate? {
        let usable = samples.filter { $0.rate.isFinite && $0.rate > 0 }
        guard let newest = usable.max(by: { $0.at < $1.at }) else { return nil }
        let rates = usable.map(\.rate).sorted()
        let middle = rates.count / 2
        let median = rates.count.isMultiple(of: 2)
            ? (rates[middle - 1] + rates[middle]) / 2
            : rates[middle]
        return ClientOutputRate(
            latest: newest.rate,
            median: median,
            samples: usable.count,
            window: "最近 \(usable.count) \(unit)",
            basis: basis,
            updatedAt: newest.at
        )
    }
}

/// Runs a read-only SQLite query and returns its tab-separated rows.
enum ReadOnlySQLite {
    static func rows(databaseURL: URL, sql: String, timeout: TimeInterval = 3) -> [[String]]? {
        guard FileManager.default.fileExists(atPath: databaseURL.path),
              FileManager.default.isExecutableFile(atPath: "/usr/bin/sqlite3") else {
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            "-readonly",
            "-noheader",
            "-separator",
            "\t",
            databaseURL.path,
            sql,
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map { line in line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    }
}

/// The recent output rate of OpenCode.
///
/// OpenCode 2.x writes one assistant row per step to `session_message`; the
/// older `message`/`part` tables are kept as a fallback. Only numeric token and
/// time fields are selected; the text of a message or part is never read.
enum OpenCodeOutputRateReader {
    static func read(databaseURL: URL) -> ClientOutputRate {
        if let current = readSessionMessages(databaseURL: databaseURL) {
            return current
        }
        return readMessageParts(databaseURL: databaseURL)
    }

    /// The rate of the v2 `session_message` rows.
    ///
    /// Only the text and reasoning blocks count as generation time; tool
    /// blocks are excluded so a long tool run does not look like a slow model.
    /// A `nil` result means the table is absent or cannot be queried, so the
    /// legacy tables still get a chance. An empty table is not a reason to
    /// fall back: the old rows may be weeks old and would look current.
    private static func readSessionMessages(databaseURL: URL) -> ClientOutputRate? {
        let sql = """
        SELECT completed, tokens, seconds FROM (
          SELECT json_extract(sm.data, '$.time.completed') AS completed,
                 COALESCE(json_extract(sm.data, '$.tokens.output'), 0)
                   + COALESCE(json_extract(sm.data, '$.tokens.reasoning'), 0) AS tokens,
                 (SELECT SUM((json_extract(j.value, '$.time.completed')
                              - json_extract(j.value, '$.time.created')) / 1000.0)
                    FROM json_each(sm.data, '$.content') AS j
                   WHERE json_extract(j.value, '$.type') IN ('text', 'reasoning')
                     AND json_type(j.value, '$.time.created') = 'integer'
                     AND json_type(j.value, '$.time.completed') = 'integer') AS seconds
            FROM session_message AS sm
           WHERE sm.type = 'assistant'
             AND json_valid(sm.data)
             AND json_type(sm.data, '$.time.completed') = 'integer'
           ORDER BY sm.time_created DESC
           LIMIT 100
        )
        WHERE tokens > 0 AND seconds > 0.2
        ORDER BY completed DESC
        LIMIT 20;
        """
        guard let rows = ReadOnlySQLite.rows(databaseURL: databaseURL, sql: sql) else {
            return nil
        }
        let samples = rows.compactMap { columns -> (rate: Double, at: Date)? in
            guard columns.count >= 3,
                  let completed = Double(columns[0]),
                  let tokens = Double(columns[1]),
                  let seconds = Double(columns[2]),
                  seconds > 0 else {
                return nil
            }
            return (tokens / seconds, Date(timeIntervalSince1970: completed / 1000))
        }
        return ClientOutputRateSummary.make(samples, unit: "条消息", basis: "按生成片段耗时")
            ?? .unavailable("近期无已完成消息")
    }

    /// The rate of the legacy `message`/`part` rows.
    private static func readMessageParts(databaseURL: URL) -> ClientOutputRate {
        let sql = """
        SELECT m.time_created, m.tokens, m.seconds FROM (
          SELECT msg.time_created AS time_created,
                 COALESCE(json_extract(msg.data, '$.tokens.output'), 0)
                   + COALESCE(json_extract(msg.data, '$.tokens.reasoning'), 0) AS tokens,
                 (SELECT SUM((json_extract(part.data, '$.time.end')
                              - json_extract(part.data, '$.time.start')) / 1000.0)
                    FROM part
                   WHERE part.message_id = msg.id
                     AND json_valid(part.data)
                     AND json_extract(part.data, '$.type') IN ('text', 'reasoning')
                     AND json_type(part.data, '$.time.start') = 'integer'
                     AND json_type(part.data, '$.time.end') = 'integer') AS seconds
            FROM (SELECT id, time_created, data
                    FROM message
                   WHERE json_valid(data)
                     AND json_extract(data, '$.role') = 'assistant'
                   ORDER BY time_created DESC
                   LIMIT 100) AS msg
        ) AS m
        WHERE m.tokens > 0 AND m.seconds > 0.2
        ORDER BY m.time_created DESC
        LIMIT 20;
        """
        guard let rows = ReadOnlySQLite.rows(databaseURL: databaseURL, sql: sql) else {
            return .unavailable("本地消息未记录生成耗时")
        }
        let samples = rows.compactMap { columns -> (rate: Double, at: Date)? in
            guard columns.count >= 3,
                  let created = Double(columns[0]),
                  let tokens = Double(columns[1]),
                  let seconds = Double(columns[2]),
                  seconds > 0 else {
                return nil
            }
            return (tokens / seconds, Date(timeIntervalSince1970: created / 1000))
        }
        return ClientOutputRateSummary.make(samples, unit: "条消息", basis: "按生成片段耗时")
            ?? .unavailable("本地消息未记录生成耗时")
    }
}

/// The recent output rate of MiniMax Code.
///
/// The runtime database records the decode duration of each call; only the
/// numeric usage fields are selected.
enum MiniMaxOutputRateReader {
    static func read(databaseURL: URL) -> ClientOutputRate {
        let sql = """
        SELECT created_at_ms,
               CAST(json_extract(data_json, '$.usage.output_tokens') AS REAL),
               CAST(json_extract(data_json, '$.usage.decode_duration_ms') AS REAL)
          FROM local_runtime_message_rows
         WHERE role = 'assistant'
           AND json_valid(data_json)
           AND CAST(json_extract(data_json, '$.usage.output_tokens') AS REAL) > 0
           AND CAST(json_extract(data_json, '$.usage.decode_duration_ms') AS REAL) > 0
         ORDER BY created_at_ms DESC
         LIMIT 20;
        """
        guard let rows = ReadOnlySQLite.rows(databaseURL: databaseURL, sql: sql) else {
            return .unavailable("本地调用未记录解码耗时")
        }
        let samples = rows.compactMap { columns -> (rate: Double, at: Date)? in
            guard columns.count >= 3,
                  let created = Double(columns[0]),
                  let tokens = Double(columns[1]),
                  let milliseconds = Double(columns[2]),
                  milliseconds > 0 else {
                return nil
            }
            return (tokens / milliseconds * 1000, Date(timeIntervalSince1970: created / 1000))
        }
        return ClientOutputRateSummary.make(samples, unit: "次调用", basis: "按解码耗时")
            ?? .unavailable("本地调用未记录解码耗时")
    }
}

/// The recent output rate of DeepSeek Harness.
///
/// The session cache carries only the aggregate decode tokens and decode
/// milliseconds of a session. Conversation rows and message bodies are never
/// read.
enum DeepSeekOutputRateReader {
    static func read(sessionCacheURL: URL) -> ClientOutputRate {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sessionCacheURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return .unavailable("本地会话未记录解码耗时")
        }
        var samples: [(rate: Double, at: Date)] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let record = root["record"] as? [String: Any],
                  let rows = record["rows"] as? [String: Any],
                  let stats = (rows["sessionStats"] as? [String: Any])?["val"] as? [String: Any],
                  let decodeMilliseconds = number(stats["decodeMs"]),
                  decodeMilliseconds > 0,
                  let tokens = number(stats["decodeTokens"]),
                  tokens > 0,
                  let time = (rows["timeContext"] as? [String: Any])?["val"] as? [String: Any],
                  let at = number(time["lastMessageTime"]) else {
                continue
            }
            samples.append((
                tokens / decodeMilliseconds * 1000,
                Date(timeIntervalSince1970: at / 1000)
            ))
        }
        let recent = samples
            .sorted { $0.at > $1.at }
            .prefix(3)
        return ClientOutputRateSummary.make(Array(recent), unit: "个会话", basis: "按解码耗时")
            ?? .unavailable("本地会话未记录解码耗时")
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}
