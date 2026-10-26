import Foundation
import CodexInfoCore

/// The moment the fixtures of the app tests are built at.
private let fixtureNow = Date(timeIntervalSince1970: 1_790_000_000)

/// Builds a snapshot for the tests of the app support.
private func appSnapshot(
    quotaPercent: Int? = nil,
    weeklyResetsAt: Date? = nil,
    radar: ResetRadarSnapshot = .empty,
    cards: [ResetCredit] = [],
    generatedAt: Date = fixtureNow
) -> UsageSnapshot {
    UsageSnapshot(
        generatedAt: generatedAt,
        freshness: Freshness(quota: .fresh, session: .fresh, account: .fresh, sources: .fresh),
        quota: QuotaSnapshot(
            planType: "pro",
            weeklyRemainingPercent: quotaPercent,
            weeklyResetsAt: weeklyResetsAt,
            source: .official,
            fetchedAt: fixtureNow
        ),
        resetCredits: ResetCreditsSnapshot(
            availableCount: cards.count,
            reportedAvailableCount: cards.count,
            items: cards,
            fetchedAt: fixtureNow
        ),
        session: .empty,
        account: AccountSnapshot(todayTokens: 1, totalTokens: 2, source: "local", updatedAt: fixtureNow),
        health: .empty,
        resetRadar: radar
    )
}

/// A reset signal two sources confirmed.
private func confirmedSignal(
    id: String = "signal-1",
    severity: String? = "strong",
    verified: Bool = true
) -> ResetSignal {
    ResetSignal(
        id: id,
        sourceId: "codex-radar",
        sourceName: "AI 哨兵信号",
        kind: .reset,
        severity: severity,
        title: "额度已重置",
        summary: "两个来源确认了一次重置",
        publishedAt: fixtureNow,
        url: nil,
        verified: verified,
        scope: nil,
        confirmingSources: ["AI 哨兵记录", "AI 哨兵信号"]
    )
}

func registerAppTests() {
    test("PanelMessage parses the messages of the panel") { context in
        context.expectEqual(PanelMessage.parse(["type": "ready"]), .ready)
        context.expectEqual(PanelMessage.parse(["type": "refresh"]), .refresh)
        context.expectEqual(PanelMessage.parse(["type": "scan"]), .scan)
        context.expectEqual(PanelMessage.parse(["type": "openSettings"]), .openSettings)
        context.expectEqual(PanelMessage.parse(["type": "close"]), .close)
        context.expectEqual(PanelMessage.parse(["type": "height", "height": 651]), .height(651))
        context.expectEqual(PanelMessage.parse(["type": "height", "height": 0]), nil)
        context.expectEqual(PanelMessage.parse(["type": "height", "height": -10]), nil)
        context.expectEqual(PanelMessage.parse(["type": "height", "height": "651"]), nil)
        context.expectEqual(
            PanelMessage.parse(["type": "openURL", "url": "https://example.com/reset"]),
            .openURL("https://example.com/reset")
        )
    }

    test("PanelMessage refuses unknown and unsafe messages") { context in
        context.expectEqual(PanelMessage.parse(["type": "unknown"]), nil)
        context.expectEqual(PanelMessage.parse(["type": "openURL"]), nil)
        context.expectEqual(PanelMessage.parse("ready"), nil)
        context.expectEqual(PanelMessage.parse([:]), nil)
        // Only web links may be opened; a file or a script is refused.
        context.expectEqual(PanelMessage.parse(["type": "openURL", "url": "file:///etc/passwd"]), nil)
        context.expectEqual(PanelMessage.parse(["type": "openURL", "url": "javascript:alert(1)"]), nil)
    }

    test("AppSettings survive a round trip through the settings file") { context in
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexinfo-settings-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsFileStore(url: directory.appendingPathComponent("settings.json"))
        let settings = AppSettings(
            baselineWindowDays: 14,
            minimumTurns: 12,
            notificationsEnabled: true,
            launchAtLogin: true,
            segments: [.quota, .health, .updated]
        )
        do {
            try store.save(settings)
        } catch {
            context.fail("the settings were not written: \(error)")
            return
        }
        context.expectEqual(store.load(), settings)
    }

    test("AppSettings fall back to the defaults when the file is missing") { context in
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexinfo-settings-\(UUID().uuidString)", isDirectory: true)
        let store = SettingsFileStore(url: directory.appendingPathComponent("settings.json"))
        context.expectEqual(store.load(), AppSettings.default)
        context.expectEqual(AppSettings.default.segments, [.quota, .rate, .health])
    }

    test("Notification events cover the weekly reset, reset signals, cards and low quota") { context in
        let signal = confirmedSignal()
        let radar = ResetRadarSnapshot(
            sources: [],
            latestConfirmed: signal,
            recent: [signal],
            lastScanAt: fixtureNow,
            nextScanAt: fixtureNow
        )
        let card = ResetCredit(
            id: "credit-abcdef123456",
            status: "available",
            grantedAt: fixtureNow,
            expiresAt: fixtureNow.addingTimeInterval(2 * 3600),
            title: "Full reset"
        )
        let snapshot = appSnapshot(
            quotaPercent: 7,
            weeklyResetsAt: fixtureNow.addingTimeInterval(10 * 60),
            radar: radar,
            cards: [card]
        )
        let events = NotificationEventEvaluator.events(snapshot: snapshot, now: fixtureNow)
        let kinds = Set(events.map(\.kind))
        context.expectTrue(kinds.contains(.confirmedReset), "a confirmed reset raises an event")
        context.expectTrue(kinds.contains(.strongSignal), "a strong signal raises an event")
        context.expectTrue(kinds.contains(.resetApproaching), "a reset within 15 minutes raises an event")
        context.expectTrue(kinds.contains(.cardExpiring), "a card that expires soon raises an event")
        context.expectTrue(kinds.contains(.lowQuota), "a low weekly quota raises an event")
    }

    test("The reset reminder key is stable across a one-second drift") { context in
        let first = appSnapshot(
            quotaPercent: 7,
            weeklyResetsAt: fixtureNow.addingTimeInterval(10 * 60)
        )
        let second = appSnapshot(
            quotaPercent: 7,
            weeklyResetsAt: fixtureNow.addingTimeInterval(10 * 60 + 1)
        )
        let firstKey = NotificationEventEvaluator.events(snapshot: first, now: fixtureNow)
            .first { $0.kind == .resetApproaching }?.key
        let secondKey = NotificationEventEvaluator.events(snapshot: second, now: fixtureNow)
            .first { $0.kind == .resetApproaching }?.key
        context.expectTrue(firstKey != nil, "the reminder is raised inside the lead time")
        context.expectEqual(firstKey, secondKey)
    }

    test("The reset reminder key does not split at the ISO week boundary") { context in
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        guard let boundary = calendar.date(
            from: DateComponents(year: 2026, month: 10, day: 19, hour: 0, minute: 0, second: 0)
        ) else {
            context.fail("the boundary date was not built")
            return
        }
        let now = boundary.addingTimeInterval(-5 * 60)
        let first = appSnapshot(quotaPercent: 7, weeklyResetsAt: boundary)
        let second = appSnapshot(
            quotaPercent: 7, weeklyResetsAt: boundary.addingTimeInterval(-1)
        )
        let firstKey = NotificationEventEvaluator.events(snapshot: first, now: now)
            .first { $0.kind == .resetApproaching }?.key
        let secondKey = NotificationEventEvaluator.events(snapshot: second, now: now)
            .first { $0.kind == .resetApproaching }?.key
        context.expectTrue(firstKey != nil)
        context.expectEqual(firstKey, secondKey)
    }

    test("Low quota keys stay stable for a week without a reset time") { context in
        let first = appSnapshot(quotaPercent: 7)
        let second = appSnapshot(
            quotaPercent: 7,
            generatedAt: fixtureNow.addingTimeInterval(3600)
        )
        let firstKey = NotificationEventEvaluator.events(snapshot: first, now: fixtureNow)
            .first { $0.kind == .lowQuota }?.key
        let secondKey = NotificationEventEvaluator.events(snapshot: second, now: fixtureNow)
            .first { $0.kind == .lowQuota }?.key
        context.expectTrue(firstKey != nil)
        context.expectEqual(firstKey, secondKey)
    }

    test("Two resets in one week get different reminder keys") { context in
        let firstReset = fixtureNow.addingTimeInterval(10 * 60)
        let secondReset = fixtureNow.addingTimeInterval(4 * 86_400 + 10 * 60)
        let first = appSnapshot(quotaPercent: 7, weeklyResetsAt: firstReset)
        let second = appSnapshot(quotaPercent: 7, weeklyResetsAt: secondReset)
        let firstKey = NotificationEventEvaluator.events(snapshot: first, now: fixtureNow)
            .first { $0.kind == .resetApproaching }?.key
        let secondKey = NotificationEventEvaluator.events(
            snapshot: second,
            now: fixtureNow.addingTimeInterval(4 * 86_400)
        ).first { $0.kind == .resetApproaching }?.key
        context.expectTrue(firstKey != nil)
        context.expectTrue(secondKey != nil)
        context.expectTrue(firstKey != secondKey)
    }

    test("Notification key history drops the oldest key, not the smallest string") { context in
        let existing = (0..<200).map { "old-\($0)" }
        let result = NotificationKeyHistory.appended(existing, fresh: ["new"])
        context.expectEqual(result.count, 200)
        context.expectEqual(result.first, "old-1")
        context.expectEqual(result.last, "new")
        context.expectEqual(NotificationKeyHistory.appended(["a", "b"], fresh: ["a"]), ["a", "b"])
    }

    test("The reset reminder does not invent a zero quota") { context in
        let snapshot = appSnapshot(
            quotaPercent: nil,
            weeklyResetsAt: fixtureNow.addingTimeInterval(10 * 60)
        )
        let event = NotificationEventEvaluator.events(snapshot: snapshot, now: fixtureNow)
            .first { $0.kind == .resetApproaching }
        context.expectTrue(event?.body.contains("—") == true)
        context.expectTrue(event?.body.contains("0%") == false)
    }

    test("Notification events fire only once") { context in
        let signal = confirmedSignal()
        let radar = ResetRadarSnapshot(
            sources: [],
            latestConfirmed: signal,
            recent: [signal],
            lastScanAt: fixtureNow,
            nextScanAt: fixtureNow
        )
        let snapshot = appSnapshot(quotaPercent: 7, radar: radar)
        let first = NotificationEventEvaluator.newEvents(snapshot: snapshot, now: fixtureNow, sentKeys: [])
        context.expectTrue(!first.isEmpty, "the first evaluation raises the events")
        let sent = Set(first.map(\.key))
        let second = NotificationEventEvaluator.newEvents(snapshot: snapshot, now: fixtureNow, sentKeys: sent)
        context.expectEqual(second.count, 0, "a known event is not raised twice")
    }

    test("Notification events ignore a plain reset and a card that expires late") { context in
        let plain = confirmedSignal(severity: nil, verified: false)
        let radar = ResetRadarSnapshot(
            sources: [],
            latestConfirmed: plain,
            recent: [plain],
            lastScanAt: fixtureNow,
            nextScanAt: fixtureNow
        )
        let card = ResetCredit(
            id: "credit-abcdef123456",
            status: "available",
            grantedAt: fixtureNow,
            expiresAt: fixtureNow.addingTimeInterval(48 * 3600),
            title: "Full reset"
        )
        let snapshot = appSnapshot(quotaPercent: 84, radar: radar, cards: [card])
        let kinds = Set(NotificationEventEvaluator.events(snapshot: snapshot, now: fixtureNow).map(\.kind))
        context.expectTrue(!kinds.contains(.strongSignal), "a plain reset is not a strong signal")
        context.expectTrue(!kinds.contains(.cardExpiring), "a card that expires in two days is quiet")
        context.expectTrue(!kinds.contains(.lowQuota), "a healthy quota is quiet")
        context.expectTrue(!kinds.contains(.resetApproaching), "a reset far away is quiet")
    }
}
