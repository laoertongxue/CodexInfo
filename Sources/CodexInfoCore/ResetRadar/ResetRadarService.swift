import Foundation

/// The result of one source fetch.
private enum FetchOutcome: Sendable {
    case success([ResetSignal])
    case failure(String)
}

/// Resumes the continuation of a source fetch exactly once.
///
/// The fetch and the timeout race each other; the first one that finishes
/// wins and the other one is ignored.
private final class TimeoutRace: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<FetchOutcome, Never>?
    private var finished = false

    init(_ continuation: CheckedContinuation<FetchOutcome, Never>) {
        self.continuation = continuation
    }

    func finish(_ outcome: FetchOutcome) {
        lock.lock()
        guard !finished, let continuation else {
            lock.unlock()
            return
        }
        finished = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(returning: outcome)
    }
}

/// The aggregation layer of the four reset sources.
///
/// Every source is scanned on its own with a timeout, so a slow source never
/// stalls the others. A failing source is retried with a backoff of 1, 2, 5
/// and 15 minutes and is not scanned while it is blocked.
///
/// The signals of a scan are merged into groups. A group is identified by the
/// local calendar day of the occurrence (the normalized title stays a
/// secondary hint), and it counts as "来源已确认" when at least two of the
/// three reset sources contributed a `kind == .reset` signal to it. The
/// official status source never confirms a reset.
public actor ResetRadarService {
    /// The sources that may confirm a reset.
    ///
    /// The official status source is not one of them: a service incident is
    /// not a quota reset.
    public static let resetSourceNames = ["AI 哨兵记录", "AI 哨兵信号", "Codex Resets"]

    /// The number of signals kept per source.
    public static let maxSignalsPerSource = 10
    /// The number of groups kept in the snapshot.
    public static let maxSignalsTotal = 20
    /// The age limit of a signal. The feeds publish month old items.
    public static let maxSignalAge: TimeInterval = 30 * 24 * 60 * 60
    /// The window two signals of neighbouring days may share. It is the
    /// window of the design spec and covers the edge of a time zone.
    public static let sameEventWindow: TimeInterval = 6 * 60 * 60
    /// The backoff after the first, second, third and every later failure.
    public static let backoffSeconds: [TimeInterval] = [60, 120, 300, 900]
    /// The timeout of one source.
    public static let defaultSourceTimeout: TimeInterval = 10

    private let sources: [ResetSource]
    private let http: HTTPClient
    private let interval: TimeInterval
    private let sourceTimeout: TimeInterval
    private let calendar: Calendar

    private var health: [String: SourceHealth] = [:]
    private var failures: [String: Int] = [:]
    private var blockedUntil: [String: Date] = [:]
    private var signalsBySource: [String: [ResetSignal]] = [:]
    private var lastScanAt: Date?
    private var nextScanAt: Date?
    /// The scan that is in flight; concurrent callers share it.
    private var activeScan: Task<ResetRadarSnapshot, Never>?

    /// Creates the service.
    ///
    /// - Parameters:
    ///   - sources: the sources to scan.
    ///   - http: the client the sources fetch with.
    ///   - interval: the delay between two scans.
    ///   - sourceTimeout: the timeout of one source.
    ///   - calendar: the calendar the occurrence day is read with.
    ///   - seed: the last published radar snapshot; its records and health
    ///     are kept until a source reports something newer.
    public init(
        sources: [ResetSource],
        http: HTTPClient,
        interval: TimeInterval = AppConstants.refreshSourcesSeconds,
        sourceTimeout: TimeInterval = ResetRadarService.defaultSourceTimeout,
        calendar: Calendar = .current,
        seed: ResetRadarSnapshot? = nil
    ) {
        self.sources = sources
        self.http = http
        self.interval = interval
        self.sourceTimeout = sourceTimeout
        self.calendar = calendar
        if let seed {
            apply(seed: seed)
        }
    }

    /// Restores the records and health of a previous process.
    ///
    /// The snapshot only carries grouped records, not the raw per-source
    /// pages. A group is still a valid record of its representative source,
    /// and `latestReset/latestForecast` are added when the group pass did not
    /// carry them.
    private func apply(seed: ResetRadarSnapshot) {
        var seen = Set<String>()
        func add(_ signal: ResetSignal?) {
            guard let signal, seen.insert(signal.id).inserted else { return }
            signalsBySource[signal.sourceId, default: []].append(signal)
        }
        for signal in seed.recent { add(signal) }
        add(seed.latestConfirmed)
        add(seed.latestReset)
        add(seed.latestForecast)
        for entry in seed.sources {
            health[entry.sourceId] = entry
        }
        lastScanAt = seed.lastScanAt
        nextScanAt = seed.nextScanAt
    }

    /// The current snapshot; a scan runs when the cached one is due.
    public func radarSnapshot(now: Date = Date()) async -> ResetRadarSnapshot {
        // A clock rollback makes `nextScanAt` look hours away; a deadline
        // farther than two intervals is treated as skew, not as a real wait.
        if let next = nextScanAt, now < next, next.timeIntervalSince(now) <= interval * 2 {
            return makeSnapshot(now: now)
        }
        return await scan(now: now)
    }

    /// Scans every source that is not blocked and returns the new snapshot.
    ///
    /// Concurrent callers share the same in-flight scan, so a manual scan and
    /// the periodic refresh cannot race each other or double the backoff.
    public func scan(now: Date = Date()) async -> ResetRadarSnapshot {
        if let activeScan {
            return await activeScan.value
        }
        let task = Task { await self.performScan(now: now) }
        activeScan = task
        let snapshot = await task.value
        activeScan = nil
        return snapshot
    }

    private func performScan(now: Date) async -> ResetRadarSnapshot {
        // A backward clock jump must not keep a failed source blocked for the
        // duration of the skew. Retry it with the rest of the sources.
        if let lastScanAt, now < lastScanAt.addingTimeInterval(-interval) {
            blockedUntil.removeAll()
        }
        let http = self.http
        let timeout = self.sourceTimeout
        let due = sources.filter { source in
            guard let until = blockedUntil[source.id] else { return true }
            return now >= until
        }
        let outcomes = await Self.scan(sources: due, http: http, now: now, timeout: timeout)

        for (source, outcome) in outcomes {
            switch outcome {
            case .success(let signals):
                failures[source.id] = 0
                blockedUntil[source.id] = nil
                // A trimmed or empty page is not proof that the record never
                // happened. Merge by id so the last known reset survives.
                signalsBySource[source.id] = Self.merged(
                    signals,
                    with: signalsBySource[source.id] ?? [],
                    now: now
                )
                health[source.id] = SourceHealth(
                    sourceId: source.id,
                    sourceName: source.displayName,
                    state: Self.isDegraded(signals) ? .degraded : .ok,
                    lastSuccessAt: now,
                    lastError: nil,
                    nextScanAt: now.addingTimeInterval(interval)
                )
            case .failure(let message):
                let count = (failures[source.id] ?? 0) + 1
                failures[source.id] = count
                let index = min(count - 1, Self.backoffSeconds.count - 1)
                let until = now.addingTimeInterval(Self.backoffSeconds[index])
                blockedUntil[source.id] = until
                health[source.id] = SourceHealth(
                    sourceId: source.id,
                    sourceName: source.displayName,
                    state: .down,
                    lastSuccessAt: health[source.id]?.lastSuccessAt,
                    lastError: message,
                    nextScanAt: until
                )
            }
        }

        lastScanAt = now
        nextScanAt = now.addingTimeInterval(interval)
        return makeSnapshot(now: now)
    }

    /// Merges the new page into the records already known for a source.
    ///
    /// The feed is a page, not the full history: a successful response with
    /// fewer rows must not erase a reset seen yesterday. New rows win on an
    /// id collision; old rows expire after the 30-day window.
    private static func merged(
        _ new: [ResetSignal],
        with old: [ResetSignal],
        now: Date
    ) -> [ResetSignal] {
        var byID: [String: ResetSignal] = [:]
        for signal in old { byID[signal.id] = signal }
        for signal in new {
            if let old = byID[signal.id] {
                byID[signal.id] = mergedSignal(signal, old: old)
            } else {
                byID[signal.id] = signal
            }
        }
        let cutoff = now.addingTimeInterval(-maxSignalAge)
        let sorted = byID.values
            .filter { signal in
                guard let publishedAt = signal.publishedAt else { return true }
                return publishedAt >= cutoff
            }
            .sorted { lhs, rhs in
                let left = lhs.publishedAt ?? .distantPast
                let right = rhs.publishedAt ?? .distantPast
                if left != right { return left > right }
                return lhs.id < rhs.id
            }
        let capped = Array(sorted.prefix(maxSignalsPerSource))
        // Forecasts are frequent; they must not push the only reset record
        // out of the per-source cap.
        if !capped.contains(where: { $0.kind == .reset }),
           let newestReset = sorted.first(where: { $0.kind == .reset }) {
            return Array(capped.dropLast()) + [newestReset]
        }
        return capped
    }

    /// Merges a re-published row into the record already known under its id.
    ///
    /// A page can return the same raw row that was previously stored as a
    /// grouped record. The raw row knows only its own source, so replacing the
    /// group would silently drop the other confirming source. Keep the union
    /// and never downgrade a completed reset to a forecast.
    private static func mergedSignal(_ new: ResetSignal, old: ResetSignal) -> ResetSignal {
        var sources: [String] = []
        for source in old.confirmingSources + new.confirmingSources where !sources.contains(source) {
            sources.append(source)
        }
        let representative = (old.kind == .reset && new.kind != .reset) ? old : new
        let kind: ResetSignalKind = (old.kind == .reset || new.kind == .reset) ? .reset : new.kind
        let severity: String?
        if old.severity == "strong" || new.severity == "strong" {
            severity = "strong"
        } else {
            severity = new.severity ?? old.severity
        }
        return ResetSignal(
            id: representative.id,
            sourceId: representative.sourceId,
            sourceName: representative.sourceName,
            kind: kind,
            severity: severity,
            title: representative.title,
            summary: representative.summary.isEmpty ? old.summary : representative.summary,
            publishedAt: representative.publishedAt,
            url: representative.url ?? old.url,
            verified: old.verified || new.verified,
            scope: representative.scope ?? old.scope,
            confirmingSources: sources,
            rawHash: representative.rawHash
        )
    }

    // MARK: - Snapshot

    /// Builds the snapshot of the collected signals.
    ///
    /// Signals older than the age limit are ignored. The cache keeps the
    /// newest signals of the whole radar, but no source may fill more than
    /// its own share of it, and the snapshot keeps the newest groups.
    private func makeSnapshot(now: Date) -> ResetRadarSnapshot {
        let cutoff = now.addingTimeInterval(-Self.maxSignalAge)
        var fresh: [ResetSignal] = []
        for source in sources {
            guard let stored = signalsBySource[source.id] else { continue }
            for signal in stored {
                guard let publishedAt = signal.publishedAt else {
                    fresh.append(signal)
                    continue
                }
                if publishedAt >= cutoff { fresh.append(signal) }
            }
        }
        fresh.sort { lhs, rhs in
            let left = lhs.publishedAt ?? .distantPast
            let right = rhs.publishedAt ?? .distantPast
            if left != right { return left > right }
            return lhs.id < rhs.id
        }

        // The newest signals win, but no source may take more than its share
        // of the cache.
        var keptPerSource: [String: Int] = [:]
        var kept: [ResetSignal] = []
        for signal in fresh {
            guard kept.count < Self.maxSignalsTotal else { break }
            let used = keptPerSource[signal.sourceId, default: 0]
            guard used < Self.maxSignalsPerSource else { continue }
            keptPerSource[signal.sourceId] = used + 1
            kept.append(signal)
        }

        let allGroups = Self.group(fresh, calendar: calendar)
        let groups = Self.group(kept, calendar: calendar)
        let recent = Array(groups.prefix(Self.maxSignalsTotal))
        // The latest facts are read from the full fresh set, not the display
        // cap: a capped-out record must still reach the panel and notification.
        let confirmed = allGroups.first { $0.confirmingSources.count >= 2 }
        let latestReset = allGroups.first { $0.kind == .reset }
        // The forecast is read from the ungrouped signals: a forecast of the
        // same day must not disappear behind the reset record it announces.
        let latestForecast = fresh.first { $0.kind == .verifying }
        return ResetRadarSnapshot(
            sources: healthEntries(),
            latestConfirmed: confirmed,
            latestReset: latestReset,
            latestForecast: latestForecast,
            recent: recent,
            lastScanAt: lastScanAt,
            nextScanAt: nextScanAt
        )
    }

    /// The health of every configured source, ordered by the source id.
    private func healthEntries() -> [SourceHealth] {
        sources
            .map { source in
                health[source.id] ?? SourceHealth(
                    sourceId: source.id,
                    sourceName: source.displayName,
                    state: .down,
                    lastSuccessAt: nil,
                    lastError: "尚未扫描",
                    nextScanAt: nil
                )
            }
            .sorted { $0.sourceId < $1.sourceId }
    }

    // MARK: - Grouping

    /// Merges the signals into groups.
    ///
    /// A group is identified by the local calendar day of the occurrence. Two
    /// signals of the same day belong to the same group even when they carry
    /// different titles, and a signal of a neighbouring day joins them when
    /// its instant is still inside the six hour window of the group, which is
    /// what happens at the edge of a time zone. The normalized title only
    /// decides between two groups of the same day. A signal without a date
    /// has no day and therefore stays on its own.
    static func group(_ signals: [ResetSignal], calendar: Calendar) -> [ResetSignal] {
        var eventGroups: [[ResetSignal]] = []
        var statusRows: [ResetSignal] = []
        for signal in signals {
            // A service status row is not part of a reset event, so it keeps
            // its own line instead of joining a reset group.
            guard signal.kind != .status else {
                statusRows.append(signal)
                continue
            }
            guard signal.publishedAt != nil else {
                eventGroups.append([signal])
                continue
            }
            var best: (index: Int, sameTitle: Bool)?
            for (index, group) in eventGroups.enumerated() {
                // The candidate joins the group when it describes the same
                // occurrence as any member of it. The newest member can be an
                // unrelated row, so the anchor must not be the only member
                // that is compared.
                guard group.contains(where: { isSameEvent($0, signal, calendar: calendar) }) else { continue }
                let sameTitle = group.contains { normalizedTitle($0.title) == normalizedTitle(signal.title) }
                if let current = best {
                    let better = sameTitle != current.sameTitle ? sameTitle : index < current.index
                    if !better { continue }
                }
                best = (index, sameTitle)
            }
            if let best {
                eventGroups[best.index].append(signal)
            } else {
                eventGroups.append([signal])
            }
        }
        let groups = eventGroups.map { merge($0) } + statusRows
        return groups.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
    }

    /// Whether two signals describe the same occurrence.
    ///
    /// The day of the occurrence decides. Two signals of neighbouring days
    /// describe the same occurrence when their instants are still close
    /// enough, which is the case when the sources publish the times in
    /// different time zones.
    private static func isSameEvent(
        _ first: ResetSignal,
        _ second: ResetSignal,
        calendar: Calendar
    ) -> Bool {
        guard let firstDate = first.publishedAt, let secondDate = second.publishedAt else { return false }
        if abs(firstDate.timeIntervalSince(secondDate)) <= sameEventWindow { return true }
        guard dayIndex(of: first, calendar: calendar) == dayIndex(of: second, calendar: calendar) else {
            return false
        }
        // A date-only record lands at midnight and stands for the whole day,
        // so it may join a timed record of the same day. Two timed records
        // more than six hours apart are distinct events even on one day.
        return isDateOnly(firstDate, calendar: calendar)
            || isDateOnly(secondDate, calendar: calendar)
    }

    /// Whether the instant is midnight in the calendar of the service.
    private static func isDateOnly(_ date: Date, calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return parts.hour == 0 && parts.minute == 0 && parts.second == 0
    }

    /// Merges the members of one group into a single signal.
    ///
    /// The newest reset member is the representative of the group: it carries
    /// the title, the summary and the moment of the occurrence. The
    /// confirming sources are the reset sources that contributed a
    /// `kind == .reset` signal; the official status source is never one of
    /// them.
    private static func merge(_ members: [ResetSignal]) -> ResetSignal {
        let resetMembers = members.filter { $0.kind == .reset }
        guard let primary = resetMembers.first ?? members.first else { return members[0] }
        let contributors = orderedResetSources(
            resetMembers.flatMap { member in
                ([member.sourceName] + member.confirmingSources)
                    .filter { resetSourceNames.contains($0) }
            }
        )
        let strong = members.contains { $0.isStrongNotificationCandidate }
        return ResetSignal(
            id: primary.id,
            sourceId: primary.sourceId,
            sourceName: primary.sourceName,
            kind: primary.kind,
            severity: strong ? "strong" : primary.severity,
            title: primary.title,
            summary: primary.summary,
            publishedAt: primary.publishedAt,
            url: primary.url,
            verified: members.contains(where: \.verified),
            scope: primary.scope,
            confirmingSources: contributors,
            rawHash: primary.rawHash
        )
    }

    /// The reset sources of a group, in the order of the panel.
    private static func orderedResetSources(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for name in resetSourceNames where names.contains(name) {
            if seen.insert(name).inserted { ordered.append(name) }
        }
        for name in names.sorted() where !seen.contains(name) {
            if seen.insert(name).inserted { ordered.append(name) }
        }
        return ordered
    }

    /// The day of the occurrence of a signal, counted from the epoch.
    ///
    /// The day is read in the calendar of the service, so a record published
    /// as a date only lands at midnight of its own day.
    private static func dayIndex(of signal: ResetSignal, calendar: Calendar) -> Int? {
        guard let publishedAt = signal.publishedAt else { return nil }
        let reference = calendar.startOfDay(for: Date(timeIntervalSince1970: 0))
        let day = calendar.startOfDay(for: publishedAt)
        return calendar.dateComponents([.day], from: reference, to: day).day
    }

    /// The title of a signal without punctuation and case.
    private static func normalizedTitle(_ title: String) -> String {
        title.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // MARK: - Fetching

    /// Scans the given sources at the same time.
    ///
    /// Every source runs on its own, so one slow source never stalls the
    /// others.
    private static func scan(
        sources: [ResetSource],
        http: HTTPClient,
        now: Date,
        timeout: TimeInterval
    ) async -> [(ResetSource, FetchOutcome)] {
        await withTaskGroup(of: (ResetSource, FetchOutcome).self) { group in
            for source in sources {
                group.addTask {
                    (source, await fetch(source: source, http: http, now: now, timeout: timeout))
                }
            }
            var outcomes: [(ResetSource, FetchOutcome)] = []
            for await outcome in group { outcomes.append(outcome) }
            return outcomes
        }
    }

    /// Fetches one source and gives up after the timeout.
    ///
    /// The fetch runs outside the task group, so a source that ignores the
    /// cancellation cannot hold up the scan.
    private static func fetch(
        source: ResetSource,
        http: HTTPClient,
        now: Date,
        timeout: TimeInterval
    ) async -> FetchOutcome {
        await withCheckedContinuation { (continuation: CheckedContinuation<FetchOutcome, Never>) in
            let race = TimeoutRace(continuation)
            let fetchTask = Task {
                do {
                    let signals = try await source.fetch(using: http, now: now)
                    race.finish(.success(signals))
                } catch {
                    race.finish(.failure(describe(error)))
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(timeout, 0) * 1_000_000_000))
                // Cancel the request that lost the race; a hung URLSession
                // task must not outlive the scan that gave up on it.
                fetchTask.cancel()
                race.finish(.failure("timed out after \(timeout) s"))
            }
        }
    }

    /// The message of a failed fetch.
    private static func describe(_ error: Error) -> String {
        guard let httpError = error as? HTTPError else { return String(describing: error) }
        switch httpError {
        case .invalidResponse: return "invalid response"
        case .status(let code): return "HTTP status \(code)"
        case .emptyResponse: return "empty response"
        case .blockedURL: return "host outside the allow-list"
        }
    }

    /// Whether a source reported that it is degraded itself.
    ///
    /// Only a source-level failure degrades the source. A monitored service
    /// that has an incident is reported with the severity `incident` and
    /// leaves the source healthy, because the source answered correctly.
    private static func isDegraded(_ signals: [ResetSignal]) -> Bool {
        signals.contains { $0.kind == .status && $0.severity == "degraded" }
    }
}
