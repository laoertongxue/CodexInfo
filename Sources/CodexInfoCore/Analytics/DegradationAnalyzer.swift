import Foundation

/// Turns a local baseline and the recent turns into the four-state verdict.
///
/// The verdict only compares this machine's own history; it is never an
/// official conclusion about the upstream model.
public enum DegradationAnalyzer {
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
        let latest = currentTurns.filter(\.isCompleted).last
        guard let latest,
              let baseline = BaselineBuilder.build(
                from: baselineTurns,
                now: now,
                windowDays: windowDays,
                minTurns: minimumTurns,
                model: latest.model,
                effort: latest.reasoningEffort,
                serviceTier: latest.serviceTier
              )
        else {
            // The reason of an insufficient verdict is shown next to the disclaimer.
            let reason = currentTurns.contains(where: \.isCompleted) ? "基线样本不足" : "24 小时内没有已完成轮次"
            return HealthSnapshot(
                status: .insufficient,
                baselineWindowDays: windowDays,
                sampleTurns: baselineTurns.filter(\.isCompleted).count,
                model: latest?.model,
                effort: latest?.reasoningEffort,
                signals: [],
                disclaimer: "\(disclaimer) · \(reason)"
            )
        }

        let recent = Array(currentTurns.filter(\.isCompleted).suffix(3))
        guard !recent.isEmpty else {
            return HealthSnapshot(
                status: .insufficient, baselineWindowDays: windowDays,
                sampleTurns: baseline.turns.count, model: baseline.model, effort: baseline.effort,
                signals: [], disclaimer: "\(disclaimer) · 24 小时内没有已完成轮次"
            )
        }

        var signals: [HealthSignal] = []
        var performanceFlags = 0

        func addSignal(_ id: HealthSignalID, label: String, current: Double?, baselineValue: Double?, flagged: Bool, detail: String) {
            guard let current, let baselineValue else { return }
            signals.append(HealthSignal(id: id, label: label, current: current, baseline: baselineValue, flagged: flagged, detail: detail))
            if flagged { performanceFlags += 1 }
        }

        let currentValues = Dictionary(uniqueKeysWithValues: [HealthSignalID.outputRate, .ttft, .reasoningShare, .toolDensity].compactMap { metric -> (HealthSignalID, Double)? in
            let values = recent.compactMap { BaselineBuilder.value(for: metric, turn: $0) }
            guard !values.isEmpty else { return nil }
            return (metric, BaselineBuilder.median(values))
        })
        let baselineMedian = baseline.medians
        let baselineMAD = baseline.mads

        func robustZ(_ value: Double, _ median: Double, _ mad: Double, _ iqr: Double) -> Double {
            let scale = mad > 0 ? mad : (iqr > 0 ? iqr / 1.349 : 0)
            guard scale > 0 else { return 0 }
            return 0.6745 * (value - median) / scale
        }

        if let current = currentValues[.outputRate], let base = baselineMedian[.outputRate] {
            let flagged = current <= base * thresholds.rateRatio
                && robustZ(current, base, baselineMAD[.outputRate] ?? 0, baseline.iqrs[.outputRate] ?? 0) <= -2
            addSignal(.outputRate, label: "输出速率", current: current, baselineValue: base, flagged: flagged, detail: "当前 \(String(format: "%.1f", current)) / 基线 \(String(format: "%.1f", base)) tok/s")
        }
        if let current = currentValues[.ttft], let base = baselineMedian[.ttft] {
            let flagged = (current >= base * thresholds.ttftRatio || current >= base + thresholds.ttftDeltaMs)
                && robustZ(current, base, baselineMAD[.ttft] ?? 0, baseline.iqrs[.ttft] ?? 0) >= 2
            addSignal(.ttft, label: "首 token", current: current, baselineValue: base, flagged: flagged, detail: "当前 \(String(format: "%.0f", current))ms / 基线 \(String(format: "%.0f", base))ms")
        }
        if let current = currentValues[.reasoningShare], let base = baselineMedian[.reasoningShare], base >= 0.05 {
            let flagged = current <= base * thresholds.reasoningRatio
            addSignal(.reasoningShare, label: "推理占比", current: current, baselineValue: base, flagged: flagged, detail: "当前 \(Int(current * 100))% / 基线 \(Int(base * 100))%")
        }
        if let current = currentValues[.toolDensity], let base = baselineMedian[.toolDensity], base >= 0.5 {
            let flagged = current <= base * thresholds.toolDensityRatio
            addSignal(.toolDensity, label: "工具调用密度", current: current, baselineValue: base, flagged: flagged, detail: "当前 \(String(format: "%.2f", current)) / 基线 \(String(format: "%.2f", base))")
        }
        if routeMismatch {
            signals.append(HealthSignal(id: .route, label: "路由不一致", current: 1, baseline: 0, flagged: true, detail: "实际模型/档位与选择不一致"))
        }

        let rawStatus: HealthStatus
        if performanceFlags >= 3 || (routeMismatch && performanceFlags >= 2) {
            rawStatus = .degraded
        } else if performanceFlags >= 2 || (routeMismatch && performanceFlags >= 1) {
            rawStatus = .suspected
        } else {
            rawStatus = .normal
        }
        // Fewer than three recent turns can never sustain a degraded verdict.
        let status: HealthStatus = (rawStatus == .degraded && recent.count < 3) ? .suspected : rawStatus
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
}
