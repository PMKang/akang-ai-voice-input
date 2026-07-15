import SwiftUI

struct ExpressionStyleView: View {
    @Environment(AppState.self) private var appState
    @State private var inspectingProfile: PromptProfile?

    private let presetNames = ["智能整理", "原声直达", "清晰表达", "正式成文", "要点速记"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("表达方式")
                    .font(.system(size: 32, weight: .bold))

                Text("选择语音最终写出来的样子。切换后立即在下一次录音中生效，所有方案仅保存在这台 Mac。")
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text("当前激活")
                        .foregroundStyle(.secondary)
                    Label(appState.selectedPromptProfileName, systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(AkangVoiceInputTheme.accent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AkangVoiceInputTheme.accent.opacity(0.10))
                .clipShape(Capsule())

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 300), spacing: 16)],
                    spacing: 16
                ) {
                    ForEach(appState.promptProfiles) { profile in
                        ExpressionStyleCard(
                            profile: profile,
                            summary: summary(for: profile.name),
                            isActive: profile.id == appState.selectedPromptProfileID
                        ) {
                            appState.selectPromptProfile(profile.id)
                            appState.announce("已启用「\(profile.name)」")
                        } inspect: {
                            inspectingProfile = profile
                        }
                    }

                    CustomExpressionCard {
                        inspectingProfile = appState.createPromptProfile(
                            named: appState.nextCustomPromptProfileName(),
                            instructions: "",
                            activate: false
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("当前方案会作为模型的语音整理指令", systemImage: "lock.shield")
                        .font(.headline)
                    Text("预设规则可以查看并复制为本地副本；本地副本支持编辑、删除，也可一键设为「智能整理」。表达方式不改变录音、词典或本地历史记录。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .akangVoiceInputPanel()
            }
            .padding(38)
            .frame(maxWidth: 940, alignment: .leading)
        }
        .sheet(item: $inspectingProfile) { profile in
            ExpressionStyleDetailSheet(
                profile: profile,
                isPreset: presetNames.contains(profile.name),
                onAdjust: { preset in
                    inspectingProfile = appState.createAdjustedPromptProfile(from: preset)
                }
            )
        }
    }

    private func summary(for name: String) -> String {
        switch name {
        case "智能整理":
            "去除口语冗余，补足标点与段落；适合大多数日常输入。"
        case "原声直达":
            "忠实保留原有措辞和语气，只进行必要的断句整理。"
        case "清晰表达":
            "把零散口述组织成自然完整、读者容易理解的日常表达。"
        case "正式成文":
            "转换为完整、克制、礼貌的书面表达，适合邮件和正式沟通。"
        case "要点速记":
            "提炼结论、事项和待办，用清晰要点快速呈现。"
        default:
            "这是本机保存的自定义规则，可按你的偏好随时调整。"
        }
    }
}

private struct ExpressionStyleCard: View {
    let profile: PromptProfile
    let summary: String
    let isActive: Bool
    let activate: () -> Void
    let inspect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(profile.name)
                        .font(.title3.weight(.semibold))
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if isActive {
                    Label("激活中", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AkangVoiceInputTheme.accent)
                }
            }

            Spacer(minLength: 2)

            HStack(spacing: 10) {
                Button("查看规则", systemImage: "text.document") {
                    inspect()
                }
                .buttonStyle(.bordered)

                Button {
                    activate()
                } label: {
                    Label(isActive ? "激活中" : "立即启用", systemImage: isActive ? "checkmark" : "power")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(isActive ? AkangVoiceInputTheme.accent.opacity(0.75) : AkangVoiceInputTheme.accent)
                .disabled(isActive)
            }
        }
        .padding(20)
        .frame(minHeight: 188, alignment: .topLeading)
        .background(isActive ? AkangVoiceInputTheme.accent.opacity(0.07) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? AkangVoiceInputTheme.accent.opacity(0.45) : AkangVoiceInputTheme.border, lineWidth: 1)
        }
    }
}

private struct CustomExpressionCard: View {
    let create: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "plus.circle")
                .font(.title2)
                .foregroundStyle(AkangVoiceInputTheme.accent)
            VStack(alignment: .leading, spacing: 6) {
                Text("自定义表达方式")
                    .font(.title3.weight(.semibold))
                Text("从空白规则开始，写出符合个人习惯的语音整理方式。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            Button("新建自定义方式", systemImage: "plus") {
                create()
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .frame(minHeight: 188, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(AkangVoiceInputTheme.border, style: StrokeStyle(lineWidth: 1, dash: [5]))
        }
    }
}

private struct ExpressionStyleDetailSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let profile: PromptProfile
    let isPreset: Bool
    let onAdjust: (PromptProfile) -> Void
    @State private var instructions: String

    init(profile: PromptProfile, isPreset: Bool, onAdjust: @escaping (PromptProfile) -> Void) {
        self.profile = profile
        self.isPreset = isPreset
        self.onAdjust = onAdjust
        _instructions = State(initialValue: profile.instructions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(profile.name)
                        .font(.title2.weight(.bold))
                    Text(isPreset ? "预设规则，可复制为本地副本后调整。" : "本地自定义规则，可直接编辑并保存。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭") { dismiss() }
            }

            Label("模型提示词", systemImage: "text.quote")
                .font(.headline)

            Group {
                if isPreset {
                    ScrollView {
                        Text(profile.instructions)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor))
                } else {
                    TextEditor(text: $instructions)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                }
            }
            .frame(minHeight: 280)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AkangVoiceInputTheme.border, lineWidth: 1)
            }

            HStack {
                if isPreset {
                    Button("调整此方案", systemImage: "doc.on.doc") {
                        onAdjust(profile)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AkangVoiceInputTheme.accent)
                } else {
                    Button("设为智能整理", systemImage: "arrow.triangle.2.circlepath") {
                        appState.setSmartPromptProfile(from: profile)
                        appState.announce("已用「\(profile.name)」更新智能整理")
                        dismiss()
                    }

                    Button("删除此自定义方式", systemImage: "trash", role: .destructive) {
                        appState.deletePromptProfile(profile.id)
                        dismiss()
                    }

                    Spacer()

                    Button("保存并启用", systemImage: "checkmark") {
                        appState.updatePromptProfile(profile.id, instructions: instructions)
                        appState.selectPromptProfile(profile.id)
                        appState.announce("已保存并启用「\(profile.name)」")
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AkangVoiceInputTheme.accent)
                    .disabled(instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Spacer()
            }
        }
        .padding(24)
        .frame(width: 680, height: 510)
    }
}
