import AppKit
import SwiftUI

enum InputProductivityEstimate {
    static let typingCharactersPerMinute: Double = 40

    static func savedTime(for items: [HistoryItem]) -> TimeInterval {
        let characters = items.reduce(0) { $0 + $1.text.count }
        let estimatedTyping = Double(characters) / typingCharactersPerMinute * 60
        let voiceTime = items.reduce(0) { $0 + $1.recordingDuration + $1.processingDuration }
        return max(0, estimatedTyping - voiceTime)
    }
}

private struct DailyInputActivity: Identifiable {
    let date: Date
    let characters: Int
    let tokens: Int

    var id: Date { date }
}

private struct HoverTipState: Equatable {
    let text: String
    let anchor: CGRect
}

private struct DashboardSnapshot {
    let totalCharacters: Int
    let todayCharacters: Int
    let totalRecordingTime: TimeInterval
    let savedTime: TimeInterval
    let averageSpeakingSpeed: Double
    let totalTokens: Int
    let estimatedCost: Double
    let dailyActivities: [DailyInputActivity]
    let maximumDailyCharacters: Int
    let monthlyInputCount: Int
    let monthlyActiveDays: Int
    let monthlyCharacters: Int
    let monthlyTokens: Int
    let monthlyLongestStreak: Int
    let monthlyPeakCharacters: Int

    init(items: [HistoryItem], calendar: Calendar = .current, recentDays: Int = 30) {
        let today = calendar.startOfDay(for: .now)
        let firstDay = calendar.date(byAdding: .day, value: -(recentDays - 1), to: today)!
        var totalCharacters = 0
        var todayCharacters = 0
        var totalRecordingTime: TimeInterval = 0
        var inputTokens = 0
        var outputTokens = 0
        var monthlyInputCount = 0
        var dailyTotals: [Date: (characters: Int, tokens: Int)] = [:]

        for item in items {
            let characters = item.text.count
            totalCharacters += characters
            totalRecordingTime += item.recordingDuration
            inputTokens += item.inputTokens
            outputTokens += item.outputTokens

            let day = calendar.startOfDay(for: item.date)
            if day == today { todayCharacters += characters }
            guard day >= firstDay, day <= today else { continue }
            monthlyInputCount += 1
            let previous = dailyTotals[day] ?? (0, 0)
            dailyTotals[day] = (
                previous.characters + characters,
                previous.tokens + item.inputTokens + item.outputTokens
            )
        }

        let activities = (0..<recentDays).map { offset -> DailyInputActivity in
            let day = calendar.date(byAdding: .day, value: offset, to: firstDay)!
            let totals = dailyTotals[day] ?? (0, 0)
            return DailyInputActivity(date: day, characters: totals.characters, tokens: totals.tokens)
        }

        self.totalCharacters = totalCharacters
        self.todayCharacters = todayCharacters
        self.totalRecordingTime = totalRecordingTime
        self.savedTime = InputProductivityEstimate.savedTime(for: items)
        self.averageSpeakingSpeed = totalRecordingTime > 0
            ? Double(totalCharacters) / totalRecordingTime * 60
            : 0
        self.totalTokens = inputTokens + outputTokens
        self.estimatedCost = UsageEstimate.estimatedCost(inputTokens: inputTokens, outputTokens: outputTokens)
        self.dailyActivities = activities
        self.maximumDailyCharacters = max(activities.map(\.characters).max() ?? 0, 1)
        self.monthlyInputCount = monthlyInputCount
        self.monthlyActiveDays = activities.filter { $0.characters > 0 }.count
        self.monthlyCharacters = activities.reduce(0) { $0 + $1.characters }
        self.monthlyTokens = activities.reduce(0) { $0 + $1.tokens }
        self.monthlyLongestStreak = Self.longestStreak(in: activities)
        self.monthlyPeakCharacters = activities.map(\.characters).max() ?? 0
    }

    private static func longestStreak(in activities: [DailyInputActivity]) -> Int {
        var streak = 0
        var longest = 0
        for activity in activities {
            if activity.characters > 0 {
                streak += 1
                longest = max(longest, streak)
            } else {
                streak = 0
            }
        }
        return longest
    }
}

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var hoverTip: HoverTipState?

    private var history: [HistoryItem] { appState.historyItems }

    var body: some View {
        let dashboard = DashboardSnapshot(items: history)

        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("自然说话，直接成文")
                            .font(.system(size: 34, weight: .bold))
                        Text(AppBrand.productSuffix)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(appState.iconTheme.accent.opacity(0.68))
                        Text("按下 \(appState.shortcutChoice.label) 开始和停止语音输入。")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        appState.toggleVoiceInput()
                    } label: {
                        Label(appState.voiceSessionState.isListening ? "停止录音" : "开始录音", systemImage: appState.voiceSessionState.isListening ? "stop.fill" : "mic.fill")
                            .frame(minWidth: 132)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AkangVoiceInputTheme.accent)
                    .controlSize(.large)
                    .disabled(appState.voiceSessionState == .requestingPermission || appState.voiceSessionState == .finishing)
                }

                Text("累计使用")
                    .font(.headline)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 185)), count: 4), spacing: 14) {
                    MetricView(icon: "clock", title: "累计表达时长", value: formatDuration(dashboard.totalRecordingTime), suffix: "", help: "所有本地输入记录的累计录音时长。", hoverTip: $hoverTip)
                    MetricView(icon: "text.cursor", title: "累计成文字数", value: dashboard.totalCharacters.formatted(), suffix: "字", help: "所有本地输入记录生成的最终文字字数。", hoverTip: $hoverTip)
                    MetricView(icon: "hourglass", title: "已省下时间", value: formatDuration(dashboard.savedTime), suffix: "", help: "按普通中文键盘输入约 40 字/分钟估算，并扣除录音与模型处理耗时。", hoverTip: $hoverTip)
                    MetricView(icon: "bolt", title: "平均表达速度", value: String(format: "%.0f", dashboard.averageSpeakingSpeed), suffix: "字/分钟", help: "总输出字数除以累计录音时长。", hoverTip: $hoverTip)
                    MetricView(icon: "pencil", title: "今日成文字数", value: dashboard.todayCharacters.formatted(), suffix: "字", help: "从当天零点开始累计的最终文字字数。", hoverTip: $hoverTip)
                    MetricView(icon: "number", title: "累计 Token", value: formatTokenCount(dashboard.totalTokens), suffix: "", help: "模型每次响应回传的输入与输出 Token 累计值。", hoverTip: $hoverTip)
                    MetricView(
                        icon: "yensign.circle",
                        title: "预估费用",
                        value: String(format: "¥%.4f", dashboard.estimatedCost),
                        suffix: "",
                        help: "只按模型每次返回的 Token 估算：音频输入按 ¥27/百万 Token，文本输出按 ¥20/百万 Token。此数值未读取账户余额，也未自动扣除免费额度；实际扣费、优惠和余额以供应商控制台为准。点击可查看当前模型服务的官方费用与额度详情。",
                        hoverTip: $hoverTip,
                        action: appState.openCurrentModelUsageDetails
                    )
                    ModelAccountBalanceMetric(
                        configuration: appState.modelServiceConfiguration,
                        hoverTip: $hoverTip
                    )
                }

                ContributionHeatmap(
                    activities: dashboard.dailyActivities,
                    maximumDailyCharacters: dashboard.maximumDailyCharacters,
                    monthlyInputCount: dashboard.monthlyInputCount,
                    monthlyActiveDays: dashboard.monthlyActiveDays,
                    monthlyCharacters: dashboard.monthlyCharacters,
                    monthlyTokens: dashboard.monthlyTokens,
                    monthlyLongestStreak: dashboard.monthlyLongestStreak,
                    monthlyPeakCharacters: dashboard.monthlyPeakCharacters,
                    hoverTip: $hoverTip
                )

                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("表达方式", systemImage: "text.quote")
                            .font(.headline)
                        Text("当前：\(appState.selectedPromptProfileName)。决定语音如何整理成最终文字。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("管理表达方式") { appState.selectedSection = .expression }
                }
                .padding(18)
                .akangVoiceInputPanel()

                Text(appState.lastRecordingSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("最近输入记录").font(.headline)
                        Spacer()
                        Button("查看全部") { appState.selectedSection = .history }
                            .buttonStyle(.link)
                    }
                    HistoryTable(items: Array(history.prefix(5)))
                }
                    }
                    .padding(38)
                }

                if let hoverTip {
                    ImmediateHoverTip(text: hoverTip.text)
                        .offset(
                            x: tooltipX(for: hoverTip.anchor, containerWidth: proxy.size.width),
                            y: tooltipY(for: hoverTip.anchor, containerHeight: proxy.size.height)
                        )
                        .zIndex(1000)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "homeContent")
        }
    }

    private func tooltipX(for anchor: CGRect, containerWidth: CGFloat) -> CGFloat {
        min(max(12, anchor.midX - 20), max(12, containerWidth - 286))
    }

    private func tooltipY(for anchor: CGRect, containerHeight: CGFloat) -> CGFloat {
        let below = anchor.maxY + 8
        return below + 74 < containerHeight ? below : max(12, anchor.minY - 74)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds.rounded())) 秒" }
        let minutes = Int(seconds) / 60
        return minutes >= 60 ? "\(minutes / 60) 时 \(minutes % 60) 分" : "\(minutes) 分"
    }

    private func formatTokenCount(_ value: Int) -> String {
        value >= 10_000 ? String(format: "%.1fK", Double(value) / 1_000) : value.formatted()
    }
}

private struct MetricView: View {
    let icon: String
    let title: String
    let value: String
    let suffix: String
    let help: String
    @Binding var hoverTip: HoverTipState?
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(AkangVoiceInputTheme.accent)
                .frame(width: 44, height: 44)
                .background(AkangVoiceInputTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text(title).font(.callout.weight(.medium)).foregroundStyle(.secondary)
                    ImmediateHoverInfoIcon(text: help, hoverTip: $hoverTip)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).font(.title.weight(.semibold))
                    Text(suffix).font(.callout)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 78)
        .akangVoiceInputPanel()
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onTapGesture {
            action?()
        }
        .onHover { isHovering in
            guard action != nil else { return }
            if isHovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .accessibilityAddTraits(action == nil ? [] : .isButton)
    }
}

private struct ModelAccountBalanceMetric: View {
    let configuration: ModelServiceConfiguration
    @Binding var hoverTip: HoverTipState?

    var body: some View {
        switch configuration.accountBalanceCapability {
        case .available(let currencyCode):
            MetricView(
                icon: "creditcard",
                title: "账户余额",
                value: "正在获取",
                suffix: currencyCode,
                help: "此数据由当前模型服务的账户接口提供。",
                hoverTip: $hoverTip
            )

        case .unavailable(let reason):
            MetricView(
                icon: "creditcard",
                title: "账户余额",
                value: "暂不支持",
                suffix: "",
                help: reason,
                hoverTip: $hoverTip
            )
        }
    }
}

private struct ImmediateHoverInfoIcon: View {
    let text: String
    @Binding var hoverTip: HoverTipState?

    var body: some View {
        GeometryReader { proxy in
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onHover { isHovering in
                    if isHovering {
                        hoverTip = HoverTipState(text: text, anchor: proxy.frame(in: .named("homeContent")))
                    } else if hoverTip?.text == text {
                        hoverTip = nil
                    }
                }
        }
        .frame(width: 14, height: 14)
    }
}

private struct ImmediateHoverTip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 270, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
    }
}

private struct ContributionHeatmap: View {
    @EnvironmentObject private var appState: AppState
    let activities: [DailyInputActivity]
    let maximumDailyCharacters: Int
    let monthlyInputCount: Int
    let monthlyActiveDays: Int
    let monthlyCharacters: Int
    let monthlyTokens: Int
    let monthlyLongestStreak: Int
    let monthlyPeakCharacters: Int
    @Binding var hoverTip: HoverTipState?
    private let columns = 7
    private let rows = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("本月输入概览").font(.headline)
                    Text("最近一个月的每日最终文字字数与 Token 使用情况")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Text("少").font(.caption2).foregroundStyle(.secondary)
                    ForEach(0..<4, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2).fill(color(for: level)).frame(width: 11, height: 11)
                    }
                    Text("多").font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .center, spacing: 30) {
                VStack(alignment: .leading, spacing: 8) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 6), count: columns), spacing: 6) {
                        ForEach(0..<(columns * rows), id: \.self) { index in
                            HeatmapDayCell(
                                activity: index < activities.count ? activities[index] : nil,
                                color: color(for:),
                                level: level(for:),
                                hoverTip: $hoverTip
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().frame(height: 122)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 14) {
                    MonthlySummaryValue(title: "本月输入", value: "\(monthlyInputCount) 次")
                    MonthlySummaryValue(title: "活跃天数", value: "\(monthlyActiveDays) 天")
                    MonthlySummaryValue(title: "本月字数", value: monthlyCharacters.formatted())
                    MonthlySummaryValue(title: "本月 Token", value: formatTokenCount(monthlyTokens))
                    MonthlySummaryValue(title: "最长连续", value: "\(monthlyLongestStreak) 天")
                    MonthlySummaryValue(title: "最高单日", value: "\(monthlyPeakCharacters.formatted()) 字")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .akangVoiceInputPanel()
    }

    private func level(for activity: DailyInputActivity) -> Int {
        guard activity.characters > 0 else { return 0 }
        return min(3, max(1, Int(ceil(Double(activity.characters) / Double(maximumDailyCharacters) * 3))))
    }

    private func color(for level: Int) -> Color {
        switch level {
        case 0: Color(nsColor: .separatorColor).opacity(0.32)
        case 1: appState.iconTheme.accent.opacity(0.24)
        case 2: appState.iconTheme.accent.opacity(0.56)
        default: appState.iconTheme.accent
        }
    }

    private func formatTokenCount(_ value: Int) -> String {
        value >= 10_000 ? String(format: "%.1fK", Double(value) / 1_000) : value.formatted()
    }
}

private struct HeatmapDayCell: View {
    let activity: DailyInputActivity?
    let color: (Int) -> Color
    let level: (DailyInputActivity) -> Int
    @Binding var hoverTip: HoverTipState?
    var body: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 2)
                .fill(activity.map { color(level($0)) } ?? color(0))
                .contentShape(Rectangle())
                .onHover { isHovering in
                    if isHovering {
                        hoverTip = HoverTipState(text: helpText, anchor: proxy.frame(in: .named("homeContent")))
                    } else if hoverTip?.text == helpText {
                        hoverTip = nil
                    }
                }
        }
        .frame(width: 22, height: 22)
    }

    private var helpText: String {
        guard let activity else { return "该日期不在最近一个月范围内" }
        return "\(activity.date.formatted(date: .long, time: .omitted))\n最终文字：\(activity.characters) 字\nToken：\(activity.tokens)"
    }
}

private struct MonthlySummaryValue: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HistoryTable: View {
    @EnvironmentObject private var appState: AppState
    let items: [HistoryItem]

    var body: some View {
        if items.isEmpty {
            EmptyStateView(
                title: "还没有输入记录",
                systemImage: "waveform",
                description: "按下快捷键开始第一次语音输入。"
            )
                .frame(maxWidth: .infinity).frame(height: 220).akangVoiceInputPanel()
        } else {
            VStack(spacing: 0) {
                HStack { Text("时间").frame(width: 90, alignment: .leading); Text("最终文字"); Spacer(); Text("耗时").frame(width: 64, alignment: .trailing) }
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14).frame(height: 34)
                Divider()
                ForEach(items) { item in
                    Button {
                        appState.copyHistoryItem(item)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text").foregroundStyle(AkangVoiceInputTheme.accent)
                            Text(item.date, style: .time).frame(width: 64, alignment: .leading)
                            Text(item.text).lineLimit(1)
                            Spacer()
                            Image(systemName: "doc.on.doc").foregroundStyle(.secondary)
                            Text(String(format: "%.2f 秒", item.processingDuration)).frame(width: 64, alignment: .trailing)
                        }.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help("点击复制此条内容").font(.callout).padding(.horizontal, 14).frame(height: 48)
                    if item.id != items.last?.id { Divider() }
                }
            }.akangVoiceInputPanel()
        }
    }
}
