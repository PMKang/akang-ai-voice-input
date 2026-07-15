import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @State private var query = ""
    @State private var filter = HistoryFilter.all

    private var filteredItems: [HistoryItem] {
        appState.historyItems.filter { item in
            let matchesText = query.isEmpty || item.text.localizedCaseInsensitiveContains(query)
            let matchesDate = filter.includes(item.date)
            return matchesText && matchesDate
        }
    }

    var body: some View {
        @Bindable var appState = appState

        HSplitView {
            VStack(alignment: .leading, spacing: 20) {
                Text("历史记录")
                    .font(.system(size: 32, weight: .bold))

                HStack {
                    Picker("时间", selection: $filter) {
                        ForEach(HistoryFilter.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 390)

                    Spacer()

                    TextField("搜索记录", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }

                List(filteredItems, selection: $appState.selectedHistoryItem) { item in
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(AkangVoiceInputTheme.accent)
                        Text(item.date, style: .time)
                            .frame(width: 66, alignment: .leading)
                        Text(item.text)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            appState.copyHistoryItem(item)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .help("复制此条内容")
                        Text(String(format: "%.2f 秒", item.processingDuration))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 7)
                    .tag(item)
                }
                .listStyle(.inset)
                .akangVoiceInputPanel()
            }
            .padding(34)
            .frame(minWidth: 650)

            HistoryDetailView(item: appState.selectedHistoryItem)
                .frame(minWidth: 310, idealWidth: 350, maxWidth: 390)
        }
    }
}

private enum HistoryFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case today = "今天"
    case sevenDays = "最近 7 天"
    case thirtyDays = "最近 30 天"

    var id: Self { self }

    func includes(_ date: Date) -> Bool {
        let calendar = Calendar.current
        return switch self {
        case .all: true
        case .today: calendar.isDateInToday(date)
        case .sevenDays: date >= calendar.date(byAdding: .day, value: -7, to: .now)!
        case .thirtyDays: date >= calendar.date(byAdding: .day, value: -30, to: .now)!
        }
    }
}

private struct HistoryDetailView: View {
    @Environment(AppState.self) private var appState
    let item: HistoryItem?
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("记录详情")
                .font(.title2.weight(.semibold))

            if let item {
                Text(item.date.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)

                ScrollView {
                    Text(item.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                .frame(minHeight: 220)
                .akangVoiceInputPanel()

                VStack(spacing: 0) {
                    DetailRow(icon: "waveform", title: "录音时长", value: duration(item.recordingDuration))
                    Divider()
                    DetailRow(icon: "clock", title: "处理耗时", value: String(format: "%.2f 秒", item.processingDuration))
                    Divider()
                    DetailRow(icon: "number", title: "Token", value: "\(item.inputTokens + item.outputTokens)")
                    Divider()
                    DetailRow(icon: "yensign.circle", title: "预估费用", value: String(format: "¥%.4f", UsageEstimate.estimatedCost(inputTokens: item.inputTokens, outputTokens: item.outputTokens)))
                    Divider()
                    DetailRow(icon: "cube", title: "模型", value: item.model)
                }
                .akangVoiceInputPanel()

                HStack {
                    Button {
                        appState.copyHistoryItem(item)
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("删除", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ContentUnavailableView("选择一条记录", systemImage: "clock", description: Text("可在这里查看完整文字和处理信息。"))
            }

            Spacer()

            Label("所有记录仅保存在本机", systemImage: "lock")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(28)
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog(
            "确定删除这条记录吗？",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let item {
                    appState.deleteHistoryItem(item)
                }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("删除后无法恢复。")
        }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

private struct DetailRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
    }
}
