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

struct RecognitionPeriodSummary: Equatable {
    let sessionCount: Int
    let averageDuration: TimeInterval?
}

struct DailyRecognitionPerformance: Identifiable, Equatable {
    let date: Date
    let sessionCount: Int
    let averageDuration: TimeInterval?

    var id: Date { date }
}

struct RecognitionPerformanceSnapshot: Equatable {
    let recent: RecognitionPeriodSummary
    let baseline: RecognitionPeriodSummary
    let dailyTrend: [DailyRecognitionPerformance]
}

enum RecognitionPerformance {
    static func snapshot(
        for items: [HistoryItem],
        calendar: Calendar = .current,
        now: Date = .now,
        recentDays: Int = 3,
        baselineDays: Int = 30
    ) -> RecognitionPerformanceSnapshot {
        let today = calendar.startOfDay(for: now)
        let recentStart = calendar.date(byAdding: .day, value: -(recentDays - 1), to: today)!
        let baselineStart = calendar.date(byAdding: .day, value: -(baselineDays - 1), to: today)!
        let validItems = items.filter {
            $0.processingDuration > 0 && $0.date >= baselineStart && $0.date <= now
        }

        func summary(since start: Date) -> RecognitionPeriodSummary {
            let durations = validItems.lazy
                .filter { $0.date >= start }
                .map(\.processingDuration)
            let total = durations.reduce(0, +)
            let count = durations.count
            return RecognitionPeriodSummary(
                sessionCount: count,
                averageDuration: count > 0 ? total / Double(count) : nil
            )
        }

        var dailyDurations: [Date: [TimeInterval]] = [:]
        for item in validItems {
            dailyDurations[calendar.startOfDay(for: item.date), default: []]
                .append(item.processingDuration)
        }
        let dailyTrend = (0..<baselineDays).map { offset -> DailyRecognitionPerformance in
            let day = calendar.date(byAdding: .day, value: offset, to: baselineStart)!
            let durations = dailyDurations[day] ?? []
            return DailyRecognitionPerformance(
                date: day,
                sessionCount: durations.count,
                averageDuration: durations.isEmpty
                    ? nil
                    : durations.reduce(0, +) / Double(durations.count)
            )
        }

        return RecognitionPerformanceSnapshot(
            recent: summary(since: recentStart),
            baseline: summary(since: baselineStart),
            dailyTrend: dailyTrend
        )
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

private enum DashboardUsageScope: String, CaseIterable, Identifiable {
    private static let doubaoModelID = "doubao-seed-asr-2-0"
    case allModels
    case doubao
    case bailian

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allModels: "全部语音模型"
        case .doubao: "豆包"
        case .bailian: "阿里云百炼"
        }
    }

    func includes(_ item: HistoryItem) -> Bool {
        switch self {
        case .allModels: true
        case .doubao: item.model == Self.doubaoModelID
        case .bailian: item.model != Self.doubaoModelID
        }
    }
}

private struct DashboardSnapshot {
    let totalCharacters: Int
    let todayCharacters: Int
    let totalRecordingTime: TimeInterval
    let recognitionPerformance: RecognitionPerformanceSnapshot
    let savedTime: TimeInterval
    let averageSpeakingSpeed: Double
    let totalTokens: Int
    let tokenAccountingSupported: Bool
    let tokenAccountingExplanation: String
    let estimatedCost: Double?
    let estimatedCostExplanation: String
    let dailyActivities: [DailyInputActivity]
    let maximumDailyCharacters: Int
    let monthlyInputCount: Int
    let monthlyActiveDays: Int
    let monthlyCharacters: Int
    let monthlyTokens: Int
    let monthlyLongestStreak: Int
    let monthlyPeakCharacters: Int

    init(items: [HistoryItem], calendar: Calendar = .current, recentDays: Int = 35, now: Date = .now) {
        let today = calendar.startOfDay(for: now)
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
        self.recognitionPerformance = RecognitionPerformance.snapshot(for: items, calendar: calendar, now: now)
        self.savedTime = InputProductivityEstimate.savedTime(for: items)
        self.averageSpeakingSpeed = totalRecordingTime > 0
            ? Double(totalCharacters) / totalRecordingTime * 60
            : 0
        self.totalTokens = inputTokens + outputTokens
        let tokenUnsupportedModels = Set(items.map(\.model)).subtracting([
            "qwen3.5-omni-flash-realtime",
            "qwen3.5-omni-plus-realtime"
        ])
        self.tokenAccountingSupported = tokenUnsupportedModels.isEmpty
        self.tokenAccountingExplanation = tokenUnsupportedModels.isEmpty
            ? "统计模型实际回传的输入与输出 Token。"
            : "当前范围包含豆包或 Fun ASR；这些实时识别接口不回传可与 Omni 合并统计的 Token，因此不显示误导性的 0。"
        let pricedItems = items.filter { $0.model == "qwen3.5-omni-flash-realtime" }
        let excludedCostModels = Set(items.map(\.model)).subtracting(["qwen3.5-omni-flash-realtime"])
        if !pricedItems.isEmpty {
            let pricedInputTokens = pricedItems.reduce(0) { $0 + $1.inputTokens }
            let pricedOutputTokens = pricedItems.reduce(0) { $0 + $1.outputTokens }
            self.estimatedCost = UsageEstimate.estimatedCost(
                inputTokens: pricedInputTokens,
                outputTokens: pricedOutputTokens
            )
            self.estimatedCostExplanation = excludedCostModels.isEmpty
                ? "仅按 Qwen 3.5 Omni Flash Realtime 返回的 Token 估算。实际扣费、优惠和余额以供应商控制台为准。"
                : "仅累计 Qwen 3.5 Omni Flash Realtime 的已知价格记录；Fun ASR、Qwen Plus 与豆包记录因计费口径不同未包含。实际扣费以供应商控制台为准。"
        } else {
            self.estimatedCost = nil
            self.estimatedCostExplanation = "当前范围没有可按 Qwen 3.5 Omni Flash Realtime 价格估算的记录。请在供应商控制台查看实际扣费。"
        }
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
    @Environment(\.locale) private var locale
    @State private var hoverTip: HoverTipState?
    @State private var usageScope: DashboardUsageScope = .allModels

    private var history: [HistoryItem] { appState.historyItems }
    private var scopedHistory: [HistoryItem] { history.filter { usageScope.includes($0) } }
    private var scopedServiceConfiguration: ModelServiceConfiguration? {
        switch usageScope {
        case .allModels: nil
        case .doubao: .doubaoRealtime
        case .bailian: .bailianRealtime
        }
    }

    var body: some View {
        let dashboard = DashboardSnapshot(items: scopedHistory)

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
                        HStack(spacing: 10) {
                            Text("数据范围")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            Picker("数据范围", selection: $usageScope) {
                                ForEach(DashboardUsageScope.allCases) { scope in
                                    Text(scope.title).tag(scope)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 310)
                        }
                        .padding(.top, 4)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
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
                        Text("按下 \(appState.shortcutChoice.label) 开始和停止语音输入")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                RecognitionPerformancePanel(
                    performance: dashboard.recognitionPerformance,
                    hoverTip: $hoverTip
                )

                Text("累计使用")
                    .font(.headline)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 185)), count: 4), spacing: 14) {
                    MetricView(icon: "clock", title: "累计表达时长", value: formatDuration(dashboard.totalRecordingTime), suffix: "", help: "当前统计范围内的本地输入记录累计录音时长。", hoverTip: $hoverTip)
                    MetricView(icon: "text.cursor", title: "累计成文字数", value: dashboard.totalCharacters.formatted(), suffix: isEnglish ? "chars" : "字", help: "当前统计范围内的最终文字字数。", hoverTip: $hoverTip)
                    MetricView(icon: "hourglass", title: "已省下时间", value: formatDuration(dashboard.savedTime), suffix: "", help: "按普通中文键盘输入约 40 字/分钟估算，并扣除录音与模型处理耗时。", hoverTip: $hoverTip)
                    MetricView(icon: "bolt", title: "平均表达速度", value: String(format: "%.0f", dashboard.averageSpeakingSpeed), suffix: isEnglish ? "chars/min" : "字/分钟", help: "当前统计范围内总输出字数除以累计录音时长。", hoverTip: $hoverTip)
                    MetricView(icon: "pencil", title: "今日成文字数", value: dashboard.todayCharacters.formatted(), suffix: isEnglish ? "chars" : "字", help: "当前统计范围内从当天零点开始累计的最终文字字数。", hoverTip: $hoverTip)
                    MetricView(
                        icon: "number",
                        title: "累计 Token",
                        value: dashboard.tokenAccountingSupported ? formatTokenCount(dashboard.totalTokens) : "暂不支持",
                        suffix: "",
                        help: dashboard.tokenAccountingExplanation,
                        hoverTip: $hoverTip
                    )
                    MetricView(
                        icon: "yensign.circle",
                        title: "预估费用",
                        value: dashboard.estimatedCost.map { String(format: "¥%.4f", $0) } ?? "暂不支持",
                        suffix: "",
                        help: dashboard.estimatedCostExplanation,
                        hoverTip: $hoverTip,
                        action: scopedServiceConfiguration.map { configuration in
                            { appState.openUsageDetails(for: configuration) }
                        }
                    )
                    if let scopedServiceConfiguration {
                        ModelAccountBalanceMetric(
                            configuration: scopedServiceConfiguration,
                            hoverTip: $hoverTip
                        )
                    } else {
                        MetricView(
                            icon: "creditcard",
                            title: "账户余额",
                            value: "按供应商查看",
                            suffix: "",
                            help: "余额和额度属于供应商账户，不能跨阿里云百炼与豆包合并计算。请选择一个供应商后查看。",
                            hoverTip: $hoverTip
                        )
                    }
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
        if seconds < 60 { return isEnglish ? "\(Int(seconds.rounded())) sec" : "\(Int(seconds.rounded())) 秒" }
        let minutes = Int(seconds) / 60
        if isEnglish {
            return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
        }
        return minutes >= 60 ? "\(minutes / 60) 时 \(minutes % 60) 分" : "\(minutes) 分"
    }

    private func formatTokenCount(_ value: Int) -> String {
        value >= 10_000 ? String(format: "%.1fK", Double(value) / 1_000) : value.formatted()
    }

    private var isEnglish: Bool { locale.identifier.hasPrefix("en") }
}

private struct RecognitionPerformancePanel: View {
    let performance: RecognitionPerformanceSnapshot
    @Binding var hoverTip: HoverTipState?

    private let metricHelp = "AI 平均识别耗时，是每次成功会话从停止录音到最终文字可用的等待时间平均值，不包含说话和录音时长；数值越短，识别越快。"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(AkangVoiceInputTheme.accent)
                    .frame(width: 28, height: 28)
                    .background(AkangVoiceInputTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text("识别表现")
                    .font(.headline)
                ImmediateHoverInfoIcon(text: metricHelp, hoverTip: $hoverTip)
                Text("从停止录音到文字可用，AI 识别耗时越短越快")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(alignment: .center, spacing: 20) {
                RecognitionSummaryView(
                    icon: "stopwatch",
                    title: "近期 AI 平均识别耗时",
                    period: "最近 3 天",
                    summary: performance.recent,
                    help: metricHelp,
                    hoverTip: $hoverTip
                )
                .frame(minWidth: 190, maxWidth: 230, alignment: .leading)

                Divider()
                    .frame(height: 112)

                RecognitionSummaryView(
                    icon: "clock.arrow.circlepath",
                    title: "长期 AI 平均识别耗时",
                    period: "近 30 天",
                    summary: performance.baseline,
                    help: metricHelp,
                    hoverTip: $hoverTip
                )
                .frame(minWidth: 190, maxWidth: 230, alignment: .leading)

                Divider()
                    .frame(height: 112)

                RecognitionTrendChart(activities: performance.dailyTrend)
                    .frame(minWidth: 280, maxWidth: .infinity, minHeight: 126)
            }
        }
        .padding(18)
        .akangVoiceInputPanel()
        .accessibilityElement(children: .contain)
    }
}

private struct RecognitionSummaryView: View {
    let icon: String
    let title: String
    let period: String
    let summary: RecognitionPeriodSummary
    let help: String
    @Binding var hoverTip: HoverTipState?

    private var durationText: String {
        guard let averageDuration = summary.averageDuration else { return "—" }
        return String(format: "%.3f", averageDuration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(AkangVoiceInputTheme.accent)
                Text(LocalizedStringKey(title))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ImmediateHoverInfoIcon(text: help, hoverTip: $hoverTip)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(durationText)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(summary.averageDuration == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(AkangVoiceInputTheme.accent))
                    .monospacedDigit()
                if summary.averageDuration != nil {
                    Text("秒")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(AkangVoiceInputTheme.accent)
                }
            }
            Text("\(period) · \(summary.sessionCount) 次")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(durationText)秒，\(period)，\(summary.sessionCount)次")
    }
}

private struct RecognitionTrendChart: View {
    let activities: [DailyRecognitionPerformance]
    @State private var hoveredActivity: DailyRecognitionPerformance?

    private var activeActivities: [DailyRecognitionPerformance] {
        activities.filter { $0.averageDuration != nil }
    }

    private var scaleMaximum: TimeInterval {
        let observedMaximum = activeActivities.compactMap(\.averageDuration).max() ?? 0
        return max(1.2, ceil(observedMaximum * 12) / 10)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("AI 平均识别耗时趋势")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let hoveredActivity, let duration = hoveredActivity.averageDuration {
                    Text("\(hoveredActivity.date.formatted(.dateTime.month().day())) · \(String(format: "%.3f", duration)) 秒 · \(hoveredActivity.sessionCount) 次")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if activeActivities.isEmpty {
                EmptyStateView(
                    title: "暂无趋势",
                    systemImage: "chart.xyaxis.line",
                    description: "积累更多使用记录后展示"
                )
                .frame(maxWidth: .infinity, minHeight: 86)
            } else {
                HStack(alignment: .top, spacing: 7) {
                    VStack {
                        Text(String(format: "%.1fs", scaleMaximum))
                        Spacer()
                        Text(String(format: "%.1fs", scaleMaximum / 2))
                        Spacer()
                        Text("0s")
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 82)

                    GeometryReader { proxy in
                        ZStack {
                            Canvas { context, size in
                                for fraction in [0.0, 0.5, 1.0] {
                                    var grid = Path()
                                    grid.move(to: CGPoint(x: 0, y: size.height * fraction))
                                    grid.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                                    context.stroke(
                                        grid,
                                        with: .color(Color(nsColor: .separatorColor).opacity(0.55)),
                                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                                    )
                                }

                                var line = Path()
                                var previousWasValid = false
                                for (index, activity) in activities.enumerated() {
                                    guard let duration = activity.averageDuration else {
                                        previousWasValid = false
                                        continue
                                    }
                                    let x = activities.count > 1
                                        ? size.width * CGFloat(index) / CGFloat(activities.count - 1)
                                        : size.width / 2
                                    let y = size.height * (1 - min(duration / scaleMaximum, 1))
                                    let point = CGPoint(x: x, y: y)
                                    if previousWasValid {
                                        line.addLine(to: point)
                                    } else {
                                        line.move(to: point)
                                    }
                                    previousWasValid = true
                                    context.fill(
                                        Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4)),
                                        with: .color(AkangVoiceInputTheme.accent)
                                    )
                                }
                                context.stroke(line, with: .color(AkangVoiceInputTheme.accent), lineWidth: 1.6)
                            }

                            HStack(spacing: 0) {
                                ForEach(activities) { activity in
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .onHover { isHovering in
                                            if isHovering {
                                                hoveredActivity = activity.averageDuration == nil ? nil : activity
                                            } else if hoveredActivity?.id == activity.id {
                                                hoveredActivity = nil
                                            }
                                        }
                                }
                            }
                        }
                    }
                    .frame(height: 82)
                }
                HStack {
                    Text("近 30 天")
                    Spacer()
                    Text("越低越快")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("近三十天 AI 平均识别耗时趋势，越低越快")
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
                .font(.title)
                .foregroundStyle(AkangVoiceInputTheme.accent)
                .frame(width: 50, height: 50)
                .background(AkangVoiceInputTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text(LocalizedStringKey(title)).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    ImmediateHoverInfoIcon(text: help, hoverTip: $hoverTip)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).font(.title2.weight(.semibold))
                    Text(suffix).font(.subheadline)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 88)
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
                .font(.callout)
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
        .frame(width: 17, height: 17)
    }
}

private struct ImmediateHoverTip: View {
    let text: String

    var body: some View {
        Text(LocalizedStringKey(text))
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
    @Environment(\.locale) private var locale
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
                    Text("本月使用情况").font(.headline)
                    Text("过去一个多月的每日最终文字字数与 Token 使用情况")
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
                    MonthlySummaryValue(title: "本月输入", value: count(monthlyInputCount, chineseUnit: "次"))
                    MonthlySummaryValue(title: "活跃天数", value: count(monthlyActiveDays, chineseUnit: "天"))
                    MonthlySummaryValue(title: "本月字数", value: monthlyCharacters.formatted())
                    MonthlySummaryValue(title: "本月 Token", value: formatTokenCount(monthlyTokens))
                    MonthlySummaryValue(title: "最长连续", value: count(monthlyLongestStreak, chineseUnit: "天"))
                    MonthlySummaryValue(title: "最高单日", value: "\(monthlyPeakCharacters.formatted()) \(isEnglish ? "chars" : "字")")
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

    private var isEnglish: Bool { locale.identifier.hasPrefix("en") }

    private func count(_ value: Int, chineseUnit: String) -> String {
        isEnglish ? "\(value)" : "\(value) \(chineseUnit)"
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
            Text(LocalizedStringKey(title))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HistoryTable: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.locale) private var locale
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
                            Text(String(format: locale.identifier.hasPrefix("en") ? "%.2f sec" : "%.2f 秒", item.processingDuration)).frame(width: 64, alignment: .trailing)
                        }.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help("点击复制此条内容").font(.callout).padding(.horizontal, 14).frame(height: 48)
                    if item.id != items.last?.id { Divider() }
                }
            }.akangVoiceInputPanel()
        }
    }
}
