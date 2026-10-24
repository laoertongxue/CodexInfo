import Foundation

/// Turns a local baseline and the recent turns into the four-state verdict.
///
/// The verdict only compares this machine's own history; it is never an
/// official conclusion about the upstream model.
public enum DegradationAnalyzer {
    /// The signals that measure the performance of a turn.
    static let performanceSignals: [HealthSignalID] = [.outputRate, .ttft, .reasoningShare, .toolDensity]

    /// A turn only counts as current when it finished inside this window.
    static let freshnessWindow: TimeInterval = 86_400

    public static func analyze(
        baselineTurns: [TurnMetrics],
        currentTurns: [TurnMetrics],
        routeMismatch: Bool,
        now: Date,
        windowDays: Int = 7,
        minimumTurns: Int = 8,
        thresholds: HealthThresholds = .standard
    ) -> HealthSnapshot {
        let disclaimer = "基于本机近 \(windowDays) 天基线，不代表官方结论"
        // The turns arrive in session order, so they are sorted before the
        // most recent one is picked.
        let completed = BaselineBuilder.chronological(currentTurns.filter(\.isCompleted))
        let fresh = completed.filter { ($0.completedAt ?? .distantPast) >= now.addingTimeInterval(-freshnessWindow) }

        guard let latest = fresh.last else {
            // Nothing finished in the last 24 hours, so nothing is current.
            return HealthSnapshot(
                status: .insufficient,
                baselineWindowDays: windowDays,
                sampleTurns: usableBaselineCount(baselineTurns, now: now, windowDays: windowDays),
                model: nil,
                effort: nil,
                signals: [],
                disclaimer: "\(disclaimer) · 24 小时内没有已完成轮次"
            )
        }

        guard let model = latest.model, let effort = latest.reasoningEffort else {
            // The route of the current turn is unknown. An unfiltered baseline
            // would mix every session, so the verdict stays 数据不足.
            return HealthSnapshot(
                status: .insufficient,
                baselineWindowDays: windowDays,
                sampleTurns: usableBaselineCount(baselineTurns, now: now, windowDays: windowDays),
                model: latest.model,
                effort: latest.reasoningEffort,
                signals: [],
                disclaimer: "\(disclaimer) · 当前轮次缺少模型或档位信息"
            )
        }

        let sample = BaselineBuilder.eligibleTurns(
            from: baselineTurns,
            now: now,
            windowDays: windowDays,
            model: model,
            effort: effort,
            serviceTier: latest.serviceTier,
            provider: latest.provider
        )
        guard let baseline = BaselineBuilder.build(
            from: baselineTurns,
            now: now,
            windowDays: windowDays,
            minTurns: minimumTurns,
            model: model,
            effort: effort,
            serviceTier: latest.serviceTier,
            provider: latest.provider
        ) else {
            return HealthSnapshot(
                status: .insufficient,
                baselineWindowDays: windowDays,
                sampleTurns: sample.count,
                model: model,
                effort: effort,
                signals: [],
                disclaimer: "\(disclaimer) · 基线样本不足"
            )
        }

        // The current value is the most recent completed turn, the persistence
        // of a signal is judged over the last three of them.
        let recent = Array(fresh.suffix(3))
        let evaluations = recent.map { evaluate($0, baseline: baseline, thresholds: thresholds) }
        let current = evaluations.last ?? TurnEvaluation()

        var signals: [HealthSignal] = []
        var performanceHits = 0
        for metric in performanceSignals {
            guard let value = current.values[metric], let base = baseline.medians[metric] else { continue }
            guard let judgement = current.judgements[metric], judgement != .unknown else { continue }
            if judgement == .hit { performanceHits += 1 }
            signals.append(
                HealthSignal(
                    id: metric,
                    label: label(for: metric),
                    current: value,
                    baseline: base,
                    flagged: judgement == .hit,
                    detail: detail(for: metric, current: value, baseline: base)
                )
            )
        }
        if routeMismatch {
            signals.append(
                HealthSignal(
                    id: .route,
                    label: "路由不一致",
                    current: 1,
                    baseline: 0,
                    flagged: true,
                    detail: "实际模型/档位与选择不一致"
                )
            )
        }

        // A degraded verdict needs a signal that persists over the last three
        // turns, not a single hit.
        let persistent = performanceSignals.contains { metric in
            evaluations.filter { $0.judgements[metric] == .hit }.count >= 2
        }
        let totalSignals = performanceHits + (routeMismatch ? 1 : 0)

        let status: HealthStatus
        if totalSignals >= 3, persistent, recent.count >= 3 {
            status = .degraded
        } else if totalSignals >= 2, performanceHits >= 1 {
            status = .suspected
        } else {
            status = .normal
        }
        return HealthSnapshot(
            status: status,
            baselineWindowDays: windowDays,
            sampleTurns: baseline.turns.count,
            model: baseline.model,
            effort: baseline.effort,
            signals: signals,
            disclaimer: disclaimer
        )
    }

    /// The number of turns of the window that can carry a baseline sample.
    ///
    /// Without a known route the sample cannot be narrowed down, so the count
    /// covers the turns that are usable at all.
    private static func usableBaselineCount(
        _ baselineTurns: [TurnMetrics],
        now: Date,
        windowDays: Int
    ) -> Int {
        BaselineBuilder.eligibleTurns(from: baselineTurns, now: now, windowDays: windowDays).count
    }

    /// The robust z score of one value, or `nil` when the baseline has no
    /// spread at all and the signal must not be judged (design 5.6.1).
    private static func robustZ(_ value: Double, _ median: Double, _ mad: Double, _ iqr: Double) -> Double? {
        if mad > 0 { return 0.6745 * (value - median) / mad }
        if iqr > 0 { return (value - median) / (iqr / 1.349) }
        return nil
    }

    /// The judgement of every performance signal inside one turn.
    private static func evaluate(
        _ turn: TurnMetrics,
        baseline: BaselineStats,
        thresholds: HealthThresholds
    ) -> TurnEvaluation {
        var evaluation = TurnEvaluation()

        if let current = BaselineBuilder.value(for: .outputRate, turn: turn),
           let base = baseline.medians[.outputRate], base > 0 {
            evaluation.values[.outputRate] = current
            if current > base * thresholds.rateRatio {
                evaluation.judgements[.outputRate] = .clear
            } else if let z = robustZ(current, base, baseline.mads[.outputRate] ?? 0, baseline.iqrs[.outputRate] ?? 0) {
                evaluation.judgements[.outputRate] = z <= -2 ? .hit : .clear
            } else {
                evaluation.judgements[.outputRate] = .unknown
            }
        }

        if let current = BaselineBuilder.value(for: .ttft, turn: turn),
           let base = baseline.medians[.ttft], base > 0 {
            evaluation.values[.ttft] = current
            if current < base * thresholds.ttftRatio, current < base + thresholds.ttftDeltaMs {
                evaluation.judgements[.ttft] = .clear
            } else if let z = robustZ(current, base, baseline.mads[.ttft] ?? 0, baseline.iqrs[.ttft] ?? 0) {
                evaluation.judgements[.ttft] = z >= 2 ? .hit : .clear
            } else {
                evaluation.judgements[.ttft] = .unknown
            }
        }

        if let current = BaselineBuilder.value(for: .reasoningShare, turn: turn),
           let base = baseline.medians[.reasoningShare], base >= 0.05 {
            evaluation.values[.reasoningShare] = current
            evaluation.judgements[.reasoningShare] = current <= base * thresholds.reasoningRatio ? .hit : .clear
        }

        if let current = BaselineBuilder.value(for: .toolDensity, turn: turn),
           let base = baseline.medians[.toolDensity], base >= 0.5 {
            evaluation.values[.toolDensity] = current
            evaluation.judgements[.toolDensity] = current <= base * thresholds.toolDensityRatio ? .hit : .clear
        }

        return evaluation
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

    private static func detail(for metric: HealthSignalID, current: Double, baseline: Double) -> String {
        switch metric {
        case .outputRate:
            return "当前 \(String(format: "%.1f", current)) / 基线 \(String(format: "%.1f", baseline)) tok/s"
        case .ttft:
            return "当前 \(String(format: "%.0f", current))ms / 基线 \(String(format: "%.0f", baseline))ms"
        case .reasoningShare:
            return "当前 \(Int(current * 100))% / 基线 \(Int(baseline * 100))%"
        case .toolDensity:
            return "当前 \(String(format: "%.2f", current)) / 基线 \(String(format: "%.2f", baseline))"
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

/// The values and judgements of one turn.
private struct TurnEvaluation {
    var values: [HealthSignalID: Double] = [:]
    var judgements: [HealthSignalID: Judgement] = [:]
}
