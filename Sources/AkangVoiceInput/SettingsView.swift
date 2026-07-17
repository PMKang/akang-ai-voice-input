import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showingAPIKeySheet = false
    @State private var showingCredentialRemovalConfirmation = false
    @State private var apiKey = ""
    @State private var workspaceID = ""
    @State private var displayNameDraft = ""

    var body: some View {
        @Bindable var appState = appState

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
                    SettingsRow(icon: "power", title: "开机启动") {
                        Toggle("", isOn: Binding(
                            get: { appState.launchAtLogin },
                            set: { appState.updateLaunchAtLogin($0) }
                        ))
                        .labelsHidden()
                    }
                }

                SettingsGroup(title: "外观") {
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
                                Text(theme.title).tag(theme)
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
                            Text("默认名称也可以换成你喜欢的称呼")
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
                        title: "显示名称",
                        subtitle: "会同步显示在页面主体、菜单栏和录音悬浮窗；应用名称保持不变"
                    ) {
                        HStack(spacing: 8) {
                            TextField(AppBrand.defaultDisplayName, text: $displayNameDraft)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)
                                .onSubmit { saveDisplayName() }
                            Button("保存") { saveDisplayName() }
                            Button("恢复默认") {
                                appState.restoreDefaultDisplayName()
                                displayNameDraft = appState.displayName
                            }
                        }
                    }
                }

                SettingsGroup(title: "模型与密钥（后续可扩展）") {
                    SettingsRow(icon: "cube", title: "模型") {
                        HStack {
                            Text("Qwen3.5 Omni Flash Realtime")
                                .foregroundStyle(.secondary)
                            Button("测试连接") {
                                appState.testBailianConnection()
                            }
                            .disabled(
                                !appState.apiKeyConfigured ||
                                !appState.workspaceIDConfigured ||
                                appState.connectionTestState == .testing
                            )
                        }
                    }
                    SettingsRow(icon: "key", title: "API Key") {
                        HStack {
                            Label(
                                appState.apiKeyConfigured ? "已安全保存" : "尚未配置",
                                systemImage: appState.apiKeyConfigured ? "checkmark.circle.fill" : "exclamationmark.circle"
                            )
                            .foregroundStyle(appState.apiKeyConfigured ? AkangVoiceInputTheme.accent : .secondary)
                            Button(appState.apiKeyConfigured ? "更新密钥" : "设置密钥") {
                                InteractionLog.event("credentials.expand")
                                apiKey = ""
                                workspaceID = ""
                                showingAPIKeySheet.toggle()
                            }
                            if appState.apiKeyConfigured || appState.workspaceIDConfigured {
                                Button("移除", role: .destructive) {
                                    showingCredentialRemovalConfirmation = true
                                }
                            }
                        }
                    }
                    SettingsRow(icon: "person.text.rectangle", title: "Workspace ID") {
                        Label(
                            appState.workspaceIDConfigured ? "已安全保存" : "尚未配置",
                            systemImage: appState.workspaceIDConfigured ? "checkmark.circle.fill" : "exclamationmark.circle"
                        )
                        .foregroundStyle(appState.workspaceIDConfigured ? AkangVoiceInputTheme.accent : .secondary)
                    }
                    if showingAPIKeySheet {
                        CredentialEditor(
                            apiKey: $apiKey,
                            workspaceID: $workspaceID,
                            cancel: {
                                showingAPIKeySheet = false
                                apiKey = ""
                                workspaceID = ""
                            },
                            save: {
                                if appState.saveBailianCredentials(apiKey: apiKey, workspaceID: workspaceID) {
                                    showingAPIKeySheet = false
                                    apiKey = ""
                                    workspaceID = ""
                                }
                            }
                        )
                    }
                    SettingsRow(icon: "network", title: "连接状态") {
                        ConnectionStatusLabel(state: appState.connectionTestState)
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
                    SettingsRow(icon: "accessibility", title: "辅助功能权限") {
                        HStack {
                            StatusLabel(
                                title: appState.accessibilityPermission.rawValue,
                                ready: appState.accessibilityPermission == .authorized
                            )
                            if appState.accessibilityPermission != .authorized {
                                Button("请求权限") {
                                    appState.requestAccessibilityPermission()
                                }
                                Button("系统设置") {
                                    appState.openAccessibilitySettings()
                                }
                                Button("重新检测") {
                                    appState.refreshPermissionStates()
                                }
                            }
                        }
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
        .confirmationDialog(
            "移除本机凭证？",
            isPresented: $showingCredentialRemovalConfirmation,
            titleVisibility: .visible
        ) {
            Button("移除 API Key 和 Workspace ID", role: .destructive) {
                _ = appState.removeBailianCredentials()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("只会删除当前 Mac Keychain 中由\(appState.productDisplayName)保存的个人凭证。")
        }
        .onAppear {
            displayNameDraft = appState.displayName
            appState.refreshPermissionStates()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.refreshPermissionStates()
        }
    }

    private func saveDisplayName() {
        appState.updateDisplayName(displayNameDraft)
        displayNameDraft = appState.displayName
    }
}

private struct CredentialEditor: View {
    private let apiKeyConsoleURL = URL(string: "https://bailian.console.aliyun.com/?tab=model#/api-key")!
    private let workspaceGuideURL = URL(string: "https://help.aliyun.com/zh/model-studio/obtain-the-app-id-and-workspace-id")!

    @Binding var apiKey: String
    @Binding var workspaceID: String
    let cancel: () -> Void
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("设置个人模型凭证")
                .font(.headline)

            Text("API Key 和 Workspace ID 只保存在当前 Mac 的 Keychain 中，不会写入项目文件或历史记录。")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("请在阿里云百炼选择华北 2（北京）。API Key 与 Workspace ID 必须属于同一工作空间和地域；本应用不需要 App ID。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("控制台显示的 API Host、OpenAI 兼容地址和 DashScope 地址无需填写，应用会自动生成 Realtime 服务地址。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 18) {
                    Link("打开 API Key 控制台", destination: apiKeyConsoleURL)
                    Link("查找 Workspace ID", destination: workspaceGuideURL)
                }
                .font(.callout.weight(.medium))
            }

            SecureField("输入 API Key", text: $apiKey)
                .textFieldStyle(.roundedBorder)

            SecureField("输入 Workspace ID", text: $workspaceID)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("取消", action: cancel)
                Button("安全保存", action: save)
                .buttonStyle(.borderedProminent)
                .disabled(
                    apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    workspaceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(20)
        .background(AkangVoiceInputTheme.accentSoft.opacity(0.45))
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
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
                Text(theme.title)
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
                    Text(title)
                    if let subtitle {
                        Text(subtitle)
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
    @Environment(AppState.self) private var appState
    let title: String
    let ready: Bool

    var body: some View {
        Label(title, systemImage: ready ? "checkmark.circle.fill" : "circle.dashed")
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
                Text(state.label)
            }
            .foregroundStyle(.secondary)
        case .success:
            Label(state.label, systemImage: "checkmark.circle.fill")
                .foregroundStyle(AkangVoiceInputTheme.accent)
        case .failure:
            Label(state.label, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .lineLimit(2)
        case .idle:
            Text(state.label)
                .foregroundStyle(.secondary)
        }
    }
}
