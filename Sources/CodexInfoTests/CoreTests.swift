import Foundation
import CodexInfoCore

func registerCoreTests() {
    test("CredentialStore parses top-level access token") { context in
        let data = #"{"access_token":"tok_test"}"#.data(using: .utf8)!
        let credentials = try FileCredentialStore.parse(data)
        context.expectEqual(credentials.accessToken, "tok_test")
    }

    test("CredentialStore parses nested tokens access token") { context in
        let data = #"{"tokens":{"access_token":"tok_nested"}}"#.data(using: .utf8)!
        let credentials = try FileCredentialStore.parse(data)
        context.expectEqual(credentials.accessToken, "tok_nested")
    }

    test("CredentialStore rejects missing token") { context in
        let data = #"{"tokens":{}}"#.data(using: .utf8)!
        context.expectThrows(try FileCredentialStore.parse(data))
    }

    test("RateLimitWindowSelector finds weekly window in secondary slot") { context in
        let snapshot = RateLimitSnapshot(
            limitId: "codex",
            primary: RateLimitWindow(usedPercent: 10, windowDurationMins: 300, resetsAt: 100),
            secondary: RateLimitWindow(usedPercent: 16, windowDurationMins: 10_080, resetsAt: 200),
            planType: "pro"
        )
        let weekly = RateLimitWindowSelector.weekly(from: snapshot)
        context.expectEqual(weekly?.remainingPercent, 84)
        context.expectEqual(weekly?.resetsAt, 200)
    }

    test("RateLimitWindowSelector finds weekly window in primary slot") { context in
        let snapshot = RateLimitSnapshot(
            limitId: "codex",
            primary: RateLimitWindow(usedPercent: 100, windowDurationMins: 10_080, resetsAt: 300),
            secondary: nil,
            planType: "pro"
        )
        context.expectEqual(RateLimitWindowSelector.weekly(from: snapshot)?.remainingPercent, 0)
    }

    test("RateLimitWindowSelector returns nil when only five-hour window exists") { context in
        let snapshot = RateLimitSnapshot(
            limitId: "codex",
            primary: RateLimitWindow(usedPercent: 5, windowDurationMins: 300, resetsAt: nil),
            secondary: nil,
            planType: "pro"
        )
        context.expectEqual(RateLimitWindowSelector.weekly(from: snapshot), nil)
    }

    test("RateLimitWindowSelector clamps used percent") { context in
        let high = RateLimitWindow(usedPercent: 140, windowDurationMins: 10_080, resetsAt: nil)
        let low = RateLimitWindow(usedPercent: -20, windowDurationMins: 10_080, resetsAt: nil)
        context.expectEqual(high.remainingPercent, 0)
        context.expectEqual(low.remainingPercent, 100)
    }

    test("RateLimitBucketSelector filters limit id codex") { context in
        let codex = RateLimitSnapshot(limitId: "codex", primary: nil, secondary: nil, planType: "pro")
        let decoy = RateLimitSnapshot(limitId: "codex_bengalfox", primary: nil, secondary: nil, planType: "pro")
        let selected = RateLimitBucketSelector.select(["decoy": decoy, "codex": codex])
        context.expectEqual(selected?.limitId, "codex")
    }
}
