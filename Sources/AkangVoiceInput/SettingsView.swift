import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var chineseDisplayNameDraft = ""
    @State private var englishDisplayNameDraft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("设置")
                    .font(.system(size: 32, weight: .bold))

                SettingsGroup(title: "快捷键与启动") {
                    SettingsRow(icon: "keyboard", title: "全局快捷键") {
                        Picker("", selection: Binding(
                            get: { appState.shortcutChoice },
                            set: { appState.updateShortcut($0) }
                        )) {
                            ForEach(ShortcutChoice.allCases) { choice in
                                Text(choice.label).tag(choice)
                            }
                        }
                        .frame(width: 160)
                    }
                    SettingsRow(
                        icon: "power",
                        title: "开机启动",
                        subtitle: LoginItemService.isSupported ? nil : "需要 macOS 13 或更高版本"
                    ) {
                        Toggle("", isOn: Binding(
                            get: { appState.launchAtLogin },
                            set: { appState.updateLaunchAtLogin($0) }
                        ))
                        .labelsHidden()
                        .disabled(!LoginItemService.isSupported)
                    }
                }

                SettingsGroup(title: "外观") {
                    SettingsRow(
                        icon: "character.bubble",
                        title: "界面语言",
                        subtitle: "仅切换应用界面，不会翻译你的语音内容或表达规则"
                    ) {
                        Picker("", selection: $appState.interfaceLanguage) {
                            ForEach(InterfaceLanguage.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }

                    SettingsRow(
                        icon: "paintpalette",
                        title: "图标与主题",
                        subtitle: "切换后会同步更新界面强调色和当前运行中的 Dock 图标"
                    ) {
                        Picker("", selection: Binding(
                            get: { appState.iconTheme },
                            set: { appState.updateIconTheme($0) }
                        )) {
                            ForEach(AppIconTheme.allCases) { theme in
                                Text(LocalizedStringKey(theme.title)).tag(theme)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 280)
                    }

                    HStack(spacing: 12) {
                        ForEach(AppIconTheme.allCases) { theme in
                            IconThemePreview(
                                theme: theme,
                                isSelected: theme == appState.iconTheme
                            ) {
                                appState.updateIconTheme(theme)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }

                SettingsGroup(title: "自定义") {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(AkangVoiceInputTheme.accent)
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("中英文名称都可以换成你喜欢的称呼")
                                .font(.subheadline.weight(.semibold))
                            Text("“\(AppBrand.defaultDisplayName)”是默认名称。昵称、喜欢的称呼，甚至一句有趣的话都可以改成您想看到的内容；请保持友善并遵守法律法规。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .background(AkangVoiceInputTheme.accentSoft.opacity(0.62))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)

                    SettingsRow(
                        icon: "character.cursor.ibeam",
                        title: "品牌名称",
                        subtitle: "保存后同步侧边栏、菜单栏、关于页和录音悬浮窗；应用名称保持不变"
                    ) {
                        VStack(alignment: .trailing, spacing: 8) {
                            HStack(spacing: 8) {
                                Text("中文")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField(AppBrand.chineseWordmark, text: $chineseDisplayNameDraft)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 170)
                            }
                            HStack(spacing: 8) {
                                Text("English")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField(AppBrand.englishWordmark, text: $englishDisplayNameDraft)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 170)
                                    .onSubmit { saveBrandNames() }
                            }
                            HStack(spacing: 8) {
                                Button("保存") { saveBrandNames() }
                                Button("恢复默认") {
                                    appState.restoreDefaultBrandNames()
                                    chineseDisplayNameDraft = appState.chineseDisplayName
                                    englishDisplayNameDraft = appState.englishDisplayName
                                }
                            }
                        }
                    }
                }

                SettingsGroup(title: "语音模型与连接") {
                    SettingsRow(
                        icon: "waveform.badge.magnifyingglass",
                        title: "模型与 Key",
                        subtitle: "按服务商配置一个 Key，并选择各自支持的实时语音模型"
                    ) {
                        Button("打开模型配置") {
                            appState.selectedSection = .voiceModels
                        }
                    }
                }

                SettingsGroup(title: "权限与状态") {
                    SettingsRow(icon: "mic", title: "麦克风权限") {
                        HStack {
                            StatusLabel(
                                title: appState.microphonePermission.rawValue,
                                ready: appState.microphonePermission == .authorized
                            )
                            if let actionLabel = appState.microphonePermission.actionLabel {
                                Button(actionLabel) {
                                    appState.handleMicrophonePermissionAction()
                                }
                            }
                        }
                    }
                    SettingsRow(
                        icon: "accessibility",
                        title: "辅助功能权限",
                        subtitle: "用于将结果自动写入微信、浏览器等当前输入框；未授权时仅复制到剪贴板"
                    ) {
                        HStack {
                            StatusLabel(
                                title: appState.accessibilityPermission.rawValue,
                                ready: appState.accessibilityPermission == .authorized
                            )
                            if appState.accessibilityPermission != .authorized {
                                Button("请求权限") {
                                    appState.requestAccessibilityPermission()
                                }
                                Button("打开辅助功能设置") {
                                    appState.openAccessibilitySettings()
                                }
                                Button("重新检测") {
                                    appState.refreshPermissionStates()
                                }
                            }
                        }
                    }
                    if appState.accessibilityPermission != .authorized {
                        Label(
                            "在系统设置中开启 Noboard · 自在说的辅助功能权限；替换或重新安装 App 后，请再次检查此项。",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                    }
                    if appState.shortcutChoice.requiresInputMonitoring {
                        SettingsRow(
                            icon: "keyboard.badge.ellipsis",
                            title: "输入监控权限",
                            subtitle: "若系统未自动列出，请点“+”添加上方显示的当前运行副本"
                        ) {
                            HStack {
                                StatusLabel(
                                    title: appState.inputMonitoringPermission.rawValue,
                                    ready: appState.inputMonitoringPermission == .authorized
                                )
                                if appState.inputMonitoringPermission != .authorized {
                                    Button("请求权限") {
                                        appState.requestInputMonitoringPermission()
                                    }
                                    Button("系统设置") {
                                        appState.openInputMonitoringSettings()
                                    }
                                    Button("重新检测") {
                                        appState.refreshPermissionStates()
                                    }
                                }
                            }
                        }
                    }
                }

                SettingsGroup(title: "开发者选项") {
                    SettingsRow(
                        icon: "wrench.and.screwdriver",
                        title: "开发者模式",
                        subtitle: "显示本次运行诊断和脱敏报告"
                    ) {
                        Toggle("", isOn: $appState.developerMode).labelsHidden()
                    }
                }

                if appState.developerMode {
                    SettingsGroup(title: "本次运行诊断") {
                        if appState.diagnosticEntries.isEmpty {
                            SettingsRow(icon: "stethoscope", title: "暂无诊断事件") {
                                EmptyView()
                            }
                        } else {
                            ForEach(appState.diagnosticEntries.suffix(6)) { entry in
                                SettingsRow(
                                    icon: "circle.fill",
                                    title: entry.category,
                                    subtitle: entry.message
                                ) {
                                    Text(entry.timestamp, style: .time)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        SettingsRow(
                            icon: "doc.on.clipboard",
                            title: "脱敏诊断报告",
                            subtitle: "不包含密钥、音频或转写正文"
                        ) {
                            HStack {
                                Button("复制报告") {
                                    appState.copyDiagnosticReport()
                                }
                                Button("清空") {
                                    appState.clearDiagnostics()
                                }
                            }
                        }
                    }
                }
            }
            .padding(38)
            .frame(maxWidth: 940, alignment: .leading)
        }
        .onAppear {
            chineseDisplayNameDraft = appState.chineseDisplayName
            englishDisplayNameDraft = appState.englishDisplayName
            appState.refreshPermissionStates()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.refreshPermissionStates()
        }
    }

    private func saveBrandNames() {
        appState.updateBrandNames(
            chineseName: chineseDisplayNameDraft,
            englishName: englishDisplayNameDraft
        )
        chineseDisplayNameDraft = appState.chineseDisplayName
        englishDisplayNameDraft = appState.englishDisplayName
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(LocalizedStringKey(title))
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
            content
        }
        .akangVoiceInputPanel()
    }
}

private struct IconThemePreview: View {
    let theme: AppIconTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                NoboardBrandIcon(theme: theme)
                    .frame(width: 74, height: 74)
                Text(LocalizedStringKey(theme.title))
                    .font(.caption.weight(isSelected ? .semibold : .regular))
            }
            .frame(width: 104)
            .padding(.vertical, 8)
            .background(isSelected ? theme.accentSoft : .clear)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? theme.accent : Color.clear, lineWidth: 1.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("切换为\(theme.title)主题")
    }
}

private struct SettingsRow<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            Divider().padding(.leading, 50)
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(title))
                    if let subtitle {
                        Text(LocalizedStringKey(subtitle))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                trailing
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
        }
    }
}

private struct StatusLabel: View {
    @EnvironmentObject private var appState: AppState
    let title: String
    let ready: Bool

    var body: some View {
        Label {
            Text(LocalizedStringKey(title))
        } icon: {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle.dashed")
        }
            .foregroundStyle(ready ? appState.iconTheme.accent : .secondary)
    }
}

private struct ConnectionStatusLabel: View {
    let state: ConnectionTestState

    var body: some View {
        switch state {
        case .testing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(LocalizedStringKey(state.label))
            }
            .foregroundStyle(.secondary)
        case .success:
            Label {
                Text(LocalizedStringKey(state.label))
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
                .foregroundStyle(AkangVoiceInputTheme.accent)
        case .failure:
            Label {
                Text(LocalizedStringKey(state.label))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
                .foregroundStyle(.red)
                .lineLimit(2)
        case .idle:
            Text(LocalizedStringKey(state.label))
                .foregroundStyle(.secondary)
        }
    }
}

/// A provider-oriented setup screen. Each provider owns one secret in Keychain;
/// endpoint and audio defaults intentionally remain in the provider adapter.
struct VoiceModelConfigurationView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("preferredDoubaoVoiceModelID") private var preferredDoubaoModelID = "doubao-seed-asr-2-0"

    private var aliyunOptions: [ModelServiceConfiguration.CatalogOption] {
        ModelServiceConfiguration.voiceModelCatalog.filter { $0.provider == "阿里云百炼" }
    }

    private var doubaoOptions: [ModelServiceConfiguration.CatalogOption] {
        ModelServiceConfiguration.voiceModelCatalog.filter { $0.provider == "豆包" }
    }

    private var activeOption: ModelServiceConfiguration.CatalogOption? {
        ModelServiceConfiguration.voiceModelCatalog.first { $0.id == appState.activeVoiceModelID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("语音模型配置")
                    .font(.system(size: 32, weight: .bold))

                CurrentRecordingModelBanner(option: activeOption)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 330), spacing: 18),
                        GridItem(.flexible(minimum: 330), spacing: 18)
                    ],
                    alignment: .leading,
                    spacing: 18
                ) {
                ProviderConfigurationCard(
                    title: "阿里云百炼",
                    icon: "cube.transparent",
                    options: aliyunOptions,
                    keyConfigured: appState.apiKeyConfigured,
                    keyPlaceholder: "输入阿里云百炼 API Key",
                    loadKey: appState.savedBailianAPIKey,
                    saveKey: appState.saveBailianAPIKey,
                    removeKey: appState.removeBailianCredentials,
                    testConnection: appState.testBailianConnection,
                    connectionState: appState.connectionTestState,
                    testingAvailable: true,
                    selectedModelID: appState.activeVoiceModelID,
                    activeModelID: appState.activeVoiceModelID,
                    isCurrentProvider: activeOption?.provider == "阿里云百炼",
                    supplementaryStatus: appState.activeVoiceModelID == "fun-asr-realtime"
                        ? appState.funHotwordSyncMessage
                        : nil,
                    selectModel: appState.activateBailianVoiceModel
                )

                ProviderConfigurationCard(
                    title: "豆包",
                    icon: "waveform.path.ecg.rectangle",
                    options: doubaoOptions,
                    keyConfigured: appState.doubaoAPIKeyConfigured,
                    keyPlaceholder: "输入豆包 API Key 或 Access Token",
                    loadKey: appState.savedDoubaoAPIKey,
                    saveKey: appState.saveDoubaoAPIKey,
                    removeKey: appState.removeDoubaoAPIKey,
                    testConnection: nil,
                    connectionState: .idle,
                    testingAvailable: false,
                    selectedModelID: preferredDoubaoModelID,
                    activeModelID: appState.activeVoiceModelID,
                    isCurrentProvider: activeOption?.provider == "豆包",
                    supplementaryStatus: nil,
                    selectModel: { preferredDoubaoModelID = $0 }
                )
                }
            }
            .padding(38)
            .frame(maxWidth: 1_080, alignment: .leading)
        }
    }
}

private struct CurrentRecordingModelBanner: View {
    let option: ModelServiceConfiguration.CatalogOption?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "record.circle.fill")
                .font(.title2)
                .foregroundStyle(AkangVoiceInputTheme.accent)
            Text("录音当前使用")
                .font(.subheadline.weight(.semibold))
            Text(option?.name ?? "未选择模型")
                .font(.subheadline.weight(.semibold))
            Text(option?.provider ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AkangVoiceInputTheme.accentSoft.opacity(0.55))
        .clipShape(Capsule())
    }
}

private struct ProviderConfigurationCard: View {
    let title: String
    let icon: String
    let options: [ModelServiceConfiguration.CatalogOption]
    let keyConfigured: Bool
    let keyPlaceholder: String
    let loadKey: () -> String?
    let saveKey: (String) -> Bool
    let removeKey: () -> Bool
    let testConnection: (() -> Void)?
    let connectionState: ConnectionTestState
    let testingAvailable: Bool
    let selectedModelID: String
    let activeModelID: String
    let isCurrentProvider: Bool
    let supplementaryStatus: String?
    let selectModel: (String) -> Void
    @State private var keyDraft = ""
    @State private var revealingKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(statusColor)
                    .frame(width: 36, height: 36)
                    .background(statusColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(LocalizedStringKey(title)).font(.title3.weight(.semibold))
                Spacer()
                Text(keyConfigured ? "已配置" : "未配置")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(statusColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            if isCurrentProvider {
                Label("当前服务商", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AkangVoiceInputTheme.accent)
            }

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Group {
                        if revealingKey {
                            TextField(LocalizedStringKey(keyPlaceholder), text: $keyDraft)
                        } else {
                            SecureField(LocalizedStringKey(keyPlaceholder), text: $keyDraft)
                        }
                    }
                    .textFieldStyle(.roundedBorder)

                    Button {
                        revealingKey.toggle()
                    } label: {
                        Image(systemName: revealingKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(revealingKey ? "隐藏 Key" : "显示 Key")
                    .disabled(keyDraft.isEmpty)
                }
                Button(keyConfigured ? "更新" : "保存") {
                    guard saveKey(keyDraft) else { return }
                    keyDraft = ""
                }
                .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if keyConfigured {
                    Button("移除", role: .destructive) {
                        guard removeKey() else { return }
                        keyDraft = ""
                    }
                }
            }

            HStack(spacing: 8) {
                Label(keyConfigured ? "Key 已安全保存在此 Mac 的 Keychain 中" : "尚未配置 Key", systemImage: keyConfigured ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(keyConfigured ? AkangVoiceInputTheme.accent : .secondary)

                if testingAvailable, let testConnection {
                    Button("测试连接", action: testConnection)
                        .buttonStyle(.link)
                        .disabled(!keyConfigured || connectionState == .testing)
                    ConnectionStatusLabel(state: connectionState)
                } else {
                    Text("测试连接即将支持")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("模型")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(options) { option in
                    ModelOptionRow(
                        option: option,
                        isSelected: option.availability == .active && option.id == selectedModelID,
                        isActive: option.id == activeModelID,
                        select: { selectModel(option.id) }
                    )
                }
            }

            if let supplementaryStatus {
                Label(supplementaryStatus, systemImage: "text.book.closed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 620, alignment: .topLeading)
        .background(keyConfigured ? AkangVoiceInputTheme.accentSoft.opacity(0.28) : Color(nsColor: .controlBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(keyConfigured ? AkangVoiceInputTheme.accent.opacity(0.55) : Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear {
            if keyDraft.isEmpty, let storedKey = loadKey() {
                keyDraft = storedKey
            }
        }
    }

    private var statusColor: Color {
        keyConfigured ? AkangVoiceInputTheme.accent : .secondary
    }
}

private struct ModelOptionRow: View {
    let option: ModelServiceConfiguration.CatalogOption
    let isSelected: Bool
    let isActive: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AkangVoiceInputTheme.accent : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.name)
                        .font(.subheadline.weight(.semibold))
                    Text(LocalizedStringKey(capabilityDescription))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                if !badge.isEmpty {
                    Text(LocalizedStringKey(badge))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(badgeColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(badgeColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(option.availability != .active)
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? AkangVoiceInputTheme.accentSoft.opacity(0.55) : Color(nsColor: .windowBackgroundColor).opacity(0.7))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isActive ? AkangVoiceInputTheme.accent.opacity(0.9) : Color(nsColor: .separatorColor),
                    lineWidth: isActive ? 1.5 : 1
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var badge: String {
        if isActive { return "使用中" }
        if isSelected { return "已选择" }
        if option.availability == .planned { return "即将支持" }
        return ""
    }

    private var badgeColor: Color {
        isActive || isSelected ? AkangVoiceInputTheme.accent : .secondary
    }

    private var capabilityDescription: String {
        switch option.id {
        case "qwen3.5-omni-flash-realtime", "qwen3.5-omni-plus-realtime":
            "支持表达方式模式 · LLM Prompt 整理"
        case "fun-asr-realtime":
            "不支持表达方式模式 · 个人词典会自动同步为热词"
        case "doubao-seed-asr-2-0":
            "不支持表达方式模式 · 当前仅规划实时转写接入"
        default:
            option.capabilityLabel
        }
    }
}
