import SwiftUI

struct DictionaryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var query = ""
    @State private var editingEntry: DictionaryEntry?
    @State private var showingNewEntrySheet = false
    @State private var entryPendingDeletion: DictionaryEntry?

    private var entries: [DictionaryEntry] {
        appState.dictionaryEntries.filter {
            query.isEmpty || $0.term.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("个人词典")
                    .font(.system(size: 32, weight: .bold))
                Button {
                    showingNewEntrySheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .help("添加词条")
                Spacer()
            }

            Label("词条会在每次语音输入时随表达方式一并发送给模型，用于识别专有名词、读音和标准写法。", systemImage: "checkmark.seal")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                TextField("搜索词条", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                Spacer()
                HStack(spacing: 0) {
                    Text("全部")
                        .foregroundStyle(AkangVoiceInputTheme.accent)
                        .padding(.horizontal, 16)
                    Divider().frame(height: 22)
                    Label("自动学习", systemImage: "sparkles")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                    Text("规划中")
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                    Divider().frame(height: 22).padding(.leading, 10)
                    Text("手动添加")
                        .padding(.horizontal, 16)
                }
                .frame(height: 34)
                .akangVoiceInputPanel()
            }

            VStack(spacing: 0) {
                HStack {
                    Text("词条").frame(maxWidth: .infinity, alignment: .leading)
                    Text("读音提示").frame(maxWidth: .infinity, alignment: .leading)
                    Text("替换文本").frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(width: 36)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .frame(height: 38)

                Divider()

                ForEach(entries) { entry in
                    HStack {
                        Text(entry.term).frame(maxWidth: .infinity, alignment: .leading)
                        Text(entry.pronunciation.isEmpty ? "—" : entry.pronunciation)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(entry.replacement.isEmpty ? "—" : entry.replacement)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Menu {
                            Button("编辑") {
                                editingEntry = entry
                            }
                            Button("删除", role: .destructive) {
                                entryPendingDeletion = entry
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 30)
                        }
                        .menuStyle(.borderlessButton)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    Divider()
                }
            }
            .akangVoiceInputPanel()

            Spacer()
        }
        .padding(36)
        .sheet(isPresented: $showingNewEntrySheet) {
            DictionaryEntryEditor(entry: nil)
                .environmentObject(appState)
        }
        .sheet(item: $editingEntry) { entry in
            DictionaryEntryEditor(entry: entry)
                .environmentObject(appState)
        }
        .confirmationDialog(
            "确定删除“\(entryPendingDeletion?.term ?? "")”吗？",
            isPresented: Binding(
                get: { entryPendingDeletion != nil },
                set: { if !$0 { entryPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let entryPendingDeletion {
                    appState.deleteDictionaryEntry(entryPendingDeletion)
                }
                entryPendingDeletion = nil
            }
            Button("取消", role: .cancel) {
                entryPendingDeletion = nil
            }
        } message: {
            Text("删除后不会再用于语音输入。")
        }
    }
}

private struct DictionaryEntryEditor: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let entry: DictionaryEntry?
    @State private var term: String
    @State private var pronunciation: String
    @State private var replacement: String

    init(entry: DictionaryEntry?) {
        self.entry = entry
        _term = State(initialValue: entry?.term ?? "")
        _pronunciation = State(initialValue: entry?.pronunciation ?? "")
        _replacement = State(initialValue: entry?.replacement ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(entry == nil ? "添加词条" : "编辑词条")
                .font(.title2.weight(.semibold))

            DictionaryEditorField(title: "词条名称", placeholder: "例如：Claude Code", text: $term)
            DictionaryEditorField(title: "读音提示（帮助识别，可选）", placeholder: "例如：克劳德 Code", text: $pronunciation)
            DictionaryEditorField(title: "标准输出（留空则沿用词条）", placeholder: "例如：Claude Code", text: $replacement)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button(entry == nil ? "添加" : "保存") {
                    appState.saveDictionaryEntry(
                        .init(
                            id: entry?.id ?? UUID(),
                            term: term.trimmingCharacters(in: .whitespacesAndNewlines),
                            pronunciation: pronunciation.trimmingCharacters(in: .whitespacesAndNewlines),
                            replacement: replacement.trimmingCharacters(in: .whitespacesAndNewlines),
                            createdAt: entry?.createdAt ?? .now
                        )
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(28)
        .frame(width: 520)
    }
}

private struct DictionaryEditorField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .frame(width: 142, alignment: .trailing)
            TextField(placeholder, text: $text)
                .frame(width: 300)
        }
    }
}
