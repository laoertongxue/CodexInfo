import SwiftUI
import CodexInfoCore

/// The settings window of the app.
///
/// The window is native SwiftUI; the panel only shows the data and asks for
/// the few actions the settings cover.
@MainActor
struct SettingsView: View {
    /// The settings of the app.
    @ObservedObject var store: SettingsStore
    /// The notifications of the app.
    let notifications: NotificationController
    /// Removes the files the app wrote.
    var onClearLocalData: (() -> Void)?

    var body: some View {
        Form {
            Section("常驻条片段") {
                ForEach(StatusSegment.allCases, id: \.self) { segment in
                    Toggle(label(for: segment), isOn: Binding(
                        get: { store.settings.segments.contains(segment) },
                        set: { enabled in
                            store.update { settings in
                                if enabled {
                                    if !settings.segments.contains(segment) {
                                        settings.segments.append(segment)
                                    }
                                } else {
                                    settings.segments.removeAll { $0 == segment }
                                }
                            }
                        }
                    ))
                }
            }

            Section("片段顺序") {
                if store.settings.segments.isEmpty {
                    Text("常驻条没有片段。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(store.settings.segments.enumerated()), id: \.element) { index, segment in
                        HStack {
                            Text(label(for: segment))
                            Spacer()
                            Button {
                                move(segment, by: -1)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .disabled(index == 0)
                            Button {
                                move(segment, by: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .disabled(index == store.settings.segments.count - 1)
                        }
                    }
                }
            }

            Section("模型基线") {
                Picker("基线窗口", selection: Binding(
                    get: { store.settings.baselineWindowDays },
                    set: { value in store.update { $0.baselineWindowDays = value } }
                )) {
                    Text("7 天").tag(7)
                    Text("14 天").tag(14)
                    Text("30 天").tag(30)
                }
                Stepper(
                    "最少轮数：\(store.settings.minimumTurns)",
                    value: Binding(
                        get: { store.settings.minimumTurns },
                        set: { value in store.update { $0.minimumTurns = min(max(value, 3), 30) } }
                    ),
                    in: 3...30
                )
                Picker("阈值档位", selection: Binding(
                    get: { store.settings.thresholdTier },
                    set: { value in store.update { $0.thresholdTier = value } }
                )) {
                    ForEach(HealthThresholdTier.allCases, id: \.self) { tier in
                        Text(tier.label).tag(tier)
                    }
                }
                Text("判定至少需要 20 轮可比基线、近 5 轮中位；速度/首 token 受网络、上下文和工具影响，不作降智结论。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("保守档只在速率与首 token 上更严格。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("通知") {
                Toggle("启用系统通知", isOn: Binding(
                    get: { store.settings.notificationsEnabled },
                    set: { enabled in
                        store.update { $0.notificationsEnabled = enabled }
                        if enabled {
                            Task { _ = await notifications.requestAuthorization() }
                        }
                    }
                ))
                Text("通知关闭时，新动态仍在面板高亮。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("启动") {
                Toggle("登录时启动", isOn: Binding(
                    get: { store.settings.launchAtLogin },
                    set: { enabled in
                        do {
                            try LaunchAtLogin.set(enabled)
                            store.update { $0.launchAtLogin = enabled }
                        } catch {
                            store.update { $0.launchAtLogin = LaunchAtLogin.isEnabled }
                        }
                    }
                ))
            }

            Section("隐私") {
                Text("凭证只驻留内存；不读取对话正文。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("MiniMax 与 DeepSeek 的令牌只发往各自官方域；Qoder 只读本地用量日志。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("设置保存在应用支持目录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("本地数据") {
                Button("清除本地数据") {
                    onClearLocalData?()
                }
                Text("删除索引、快照、源缓存与设置文件；面板与插件会重新计算数据。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 560)
    }

    /// Moves a part of the title one place up or down.
    private func move(_ segment: StatusSegment, by offset: Int) {
        store.update { settings in
            guard let index = settings.segments.firstIndex(of: segment) else { return }
            let target = index + offset
            guard settings.segments.indices.contains(target) else { return }
            settings.segments.swapAt(index, target)
        }
    }

    /// The name of a part of the title.
    private func label(for segment: StatusSegment) -> String {
        switch segment {
        case .quota: return "周额度"
        case .rate: return "输出速率"
        case .health: return "模型状态"
        case .credits: return "重置卡"
        case .updated: return "更新时间"
        }
    }
}
