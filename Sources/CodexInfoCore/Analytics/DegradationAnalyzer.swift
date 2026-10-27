import Foundation

/// Turns a local baseline and the recent turns into a performance/route verdict.
///
/// The verdict never claims that the model's capability dropped. Local
/// telemetry cannot measure IQ without a fixed task set; it can only show a
/// sustained performance deviation or a route downgrade.
public enum DegradationAnalyzer {
    /// The performance metrics that take part in the verdict.
    static let performanceSignals: [HealthSignalID] = [.outputRate, .ttft]

    /// The number of recent turns compared with the baseline.
    static let recentWindow = 5

    /// The minimum baseline sample behind a non-normal verdict.
    static let verdictMinimumBaselineTurns = 20

    /// How many of the recent turns must cross a threshold.
    static let minimumRecentHits = 3

    /// A turn only counts as current when it finished inside this window.
    static let freshnessWindow: TimeInterval = 86_400

    public static func analyze(
        baselineTurns: [TurnMetrics],
        currentTurns: [TurnMetrics],
        routeMismatch: Bool,
        routeDowngrade: Bool = false,
        now: Date,
        windowDays: Int = 7,
        minimumTurns: Int = 8,
        thresholds: HealthThresholds = .standard
    ) -> HealthSnapshot {
        let disclaimer = "仅比较本机近 \(windowDays) 天性能与路由，不判断模型能力"
        let completed = BaselineBuilder.chronological(currentTurns.filter(\.isCompleted))
        let comparable = completed.filter(BaselineBuilder.isComparable)
        let fresh = comparable.filter {
            ($0.completedAt ?? .distantPast) >= now.addingTimeInterval(-freshnessWindow)
        }

        guard let latest = fresh.last else {
            return HealthSnapshot(
                status: .insufficient,
                baselineWindowDays: windowDays,
                sampleTurns: usableBaselineCount(baselineTurns, now: now, windowDays: windowDays),
                recentTurns: 0,
                model: nil,
                effort: nil,
                signals: [],
                disclaimer: "\(disclaimer) · 24 小时内没有已完成的可比轮次"
            )
        }

        guard let model = latest.model, let effort = latest.reasoningEffort else {
            return HealthSnapshot(
                status: .insufficient,
                baselineWindowDays: windowDays,
                sampleTurns: usableBaselineCount(baselineTurns, now: now, windowDays: windowDays),
                recentTurns: 0,
                model: latest.model,
                effort: latest.reasoningEffort,
                signals: [],
                disclaimer: "\(disclaimer) · 当前轮次缺少模型或档位信息"
            )
        }

        let routeRecent = fresh.filter { turn in
            turn.model == model
                && turn.reasoningEffort == effort
                && turn.serviceTier == latest.serviceTier
                && turn.provider == latest.provider
        }
        let recent = Array(routeRecent.suffix(Self.recentWindow))
        let sample = BaselineBuilder.eligibleTurns(
            from: baselineTurns,
            now: now,
            windowDays: windowDays,
            model: model,
            effort: effort,
            serviceTier: latest.serviceTier,
            provider: latest.provider
        )
        let requiredTurns = max(minimumTurns, Self.verdictMinimumBaselineTurns)
        guard let baseline = BaselineBuilder.build(
            from: baselineTurns,
            now: now,
            windowDays: windowDays,
            minTurns: requiredTurns,
            model: model,
            effort: effort,
            serviceTier: latest.serviceTier,
            provider: latest.provider
        ) else {
            return HealthSnapshot(
                status: .insufficient,
                baselineWindowDays: windowDays,
                sampleTurns: sample.count,
                recentTurns: recent.count,
                model: model,
                effort: effort,
                signals: [],
                disclaimer: "\(disclaimer) · 基线至少 \(requiredTurns) 轮"
            )
        }

        guard recent.count >= Self.recentWindow else {
            return HealthSnapshot(
                status: .insufficient,
                baselineWindowDays: windowDays,
                sampleTurns: baseline.turns.count,
                recentTurns: recent.count,
                model: model,
                effort: effort,
                signals: [],
                disclaimer: "\(disclaimer) · 近 \(Self.recentWindow) 轮可比样本不足"
            )
        }

        let rateValues = recent.compactMap { BaselineBuilder.value(for: .outputRate, turn: $0) }
        let ttftValues = recent.compactMap { BaselineBuilder.value(for: .ttft, turn: $0) }
        let rateBase = baseline.medians[.outputRate]
        let ttftBase = baseline.medians[.ttft]

        let rateHits = recent.filter {
            judgement(for: .outputRate, turn: $0, baseline: baseline, thresholds: thresholds) == .hit
        }.count
        let ttftHits = recent.filter {
            judgement(for: .ttft, turn: $0, baseline: baseline, thresholds: thresholds) == .hit
        }.count

        let rateMedian = median(rateValues)
        let ttftMedian = median(ttftValues)
        let rateZ = rateMedian.flatMap { value in
            rateBase.flatMap {
                robustZ(
                    value,
                    $0,
                    baseline.mads[.outputRate] ?? 0,
                    baseline.iqrs[.outputRate] ?? 0
                )
            }
        }
        let ttftZ = ttftMedian.flatMap { value in
            ttftBase.flatMap {
                robustZ(
                    value,
                    $0,
                    baseline.mads[.ttft] ?? 0,
                    baseline.iqrs[.ttft] ?? 0
                )
            }
        }

        let rateFlagged: Bool
        if let rateMedian, let rateBase, rateBase > 0,
           rateValues.count >= Self.minimumRecentHits,
           rateHits >= Self.minimumRecentHits,
           rateMedian <= rateBase * thresholds.rateRatio,
           let rateZ {
            rateFlagged = rateZ <= -2
        } else {
            rateFlagged = false
        }

        let ttftFlagged: Bool
        if let ttftMedian, let ttftBase, ttftBase > 0,
           ttftValues.count >= Self.minimumRecentHits,
           ttftHits >= Self.minimumRecentHits,
           ttftMedian >= ttftBase * thresholds.ttftRatio,
           ttftMedian >= ttftBase + thresholds.ttftDeltaMs,
           let ttftZ {
            ttftFlagged = ttftZ >= 2
        } else {
            ttftFlagged = false
        }

        var signals: [HealthSignal] = []
        if let rateMedian, let rateBase {
            signals.append(
                HealthSignal(
                    id: .outputRate,
                    label: label(for: .outputRate),
                    current: rateMedian,
                    baseline: rateBase,
                    flagged: rateFlagged,
                    detail: detail(
                        for: .outputRate,
                        current: rateMedian,
                        baseline: rateBase,
                        turns: recent.count
                    )
                )
            )
        }
        if let ttftMedian, let ttftBase {
            signals.append(
                HealthSignal(
                    id: .ttft,
                    label: label(for: .ttft),
                    current: ttftMedian,
                    baseline: ttftBase,
                    flagged: ttftFlagged,
                    detail: detail(
                        for: .ttft,
                        current: ttftMedian,
                        baseline: ttftBase,
                        turns: recent.count
                    )
                )
            )
        }
        if routeMismatch {
            signals.append(
                HealthSignal(
                    id: .route,
                    label: routeDowngrade ? "路由降档" : "路由不一致",
                    current: routeDowngrade ? 1 : 0,
                    baseline: 0,
                    flagged: routeDowngrade,
                    detail: routeDowngrade ? "实际档位低于选择的档位" : "实际模型/档位与选择不一致，未确认降档"
                )
            )
        }

        let status: HealthStatus
        if routeDowngrade {
            status = .route
        } else if rateFlagged && ttftFlagged {
            status = .degraded
        } else if rateFlagged || ttftFlagged {
            status = .suspected
        } else {
            status = .normal
        }

        return HealthSnapshot(
            status: status,
            baselineWindowDays: windowDays,
            sampleTurns: baseline.turns.count,
            recentTurns: recent.count,
            model: baseline.model,
            effort: baseline.effort,
            signals: signals,
            disclaimer: disclaimer
        )
    }

    /// The number of turns of the window that can carry a baseline sample.
    private static func usableBaselineCount(
        _ baselineTurns: [TurnMetrics],
        now: Date,
        windowDays: Int
    ) -> Int {
        BaselineBuilder.usableTurns(from: baselineTurns, now: now, windowDays: windowDays).count
    }

    /// The robust z score of one value, or `nil` when the baseline has no
    /// spread at all and the signal must not be judged.
    private static func robustZ(_ value: Double, _ median: Double, _ mad: Double, _ iqr: Double) -> Double? {
        if mad > 0 { return 0.6745 * (value - median) / mad }
        if iqr > 0 { return (value - median) / (iqr / 1.349) }
        return nil
    }

    /// The judgement of one performance signal inside one turn.
    private static func judgement(
        for metric: HealthSignalID,
        turn: TurnMetrics,
        baseline: BaselineStats,
        thresholds: HealthThresholds
    ) -> Judgement {
        guard let current = BaselineBuilder.value(for: metric, turn: turn),
              let base = baseline.medians[metric], base > 0 else {
            return .unknown
        }
        switch metric {
        case .outputRate:
            if current > base * thresholds.rateRatio { return .clear }
            guard let z = robustZ(
                current,
                base,
                baseline.mads[metric] ?? 0,
                baseline.iqrs[metric] ?? 0
            ) else { return .unknown }
            return z <= -2 ? .hit : .clear
        case .ttft:
            if current < base * thresholds.ttftRatio, current < base + thresholds.ttftDeltaMs {
                return .clear
            }
            guard let z = robustZ(
                current,
                base,
                baseline.mads[metric] ?? 0,
                baseline.iqrs[metric] ?? 0
            ) else { return .unknown }
            return z >= 2 ? .hit : .clear
        default:
            return .unknown
        }
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func label(for metric: HealthSignalID) -> String {
        switch metric {
        case .outputRate: return "输出速率"
        case .ttft: return "首 token"
        case .reasoningShare: return "推理占比"
        case .toolDensity: return "工具调用密度"
        case .route: return "路由不一致"
        }
    }

    private static func detail(
        for metric: HealthSignalID,
        current: Double,
        baseline: Double,
        turns: Int
    ) -> String {
        let delta = baseline > 0 ? (current / baseline - 1) * 100 : 0
        let percent = String(format: "%+.0f%%", delta)
        switch metric {
        case .outputRate:
            return "近 \(turns) 轮中位 \(String(format: "%.1f", current)) / 基线 \(String(format: "%.1f", baseline)) tok/s（\(percent)）"
        case .ttft:
            return "近 \(turns) 轮中位 \(String(format: "%.0f", current))ms / 基线 \(String(format: "%.0f", baseline))ms（\(percent)）"
        case .reasoningShare:
            return "近 \(turns) 轮中位 \(Int(current * 100))% / 基线 \(Int(baseline * 100))%"
        case .toolDensity:
            return "近 \(turns) 轮中位 \(String(format: "%.2f", current)) / 基线 \(String(format: "%.2f", baseline))"
        case .route:
            return "实际模型/档位与选择不一致"
        }
    }
}

/// The judgement of one signal inside one turn.
private enum Judgement {
    /// The signal hit its threshold.
    case hit
    /// The signal was judged and stayed inside its threshold.
    case clear
    /// The signal cannot be judged, so it never counts as a hit.
    case unknown
}
