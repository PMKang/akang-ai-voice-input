import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(
                selection: $appState.selectedSection,
                readiness: appState.readiness,
                iconTheme: appState.iconTheme,
                chineseDisplayName: appState.chineseDisplayName,
                englishDisplayName: appState.englishDisplayName
            )
                .frame(width: 220)

            Divider()

            Group {
                switch appState.selectedSection {
                case .home:
                    HomeView()
                case .history:
                    HistoryView()
                case .dictionary:
                    DictionaryView()
                case .expression:
                    ExpressionStyleView()
                case .voiceModels:
                    VoiceModelConfigurationView()
                case .settings:
                    SettingsView()
                case .about:
                    AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(AkangVoiceInputTheme.accent)
        .overlay(alignment: .top) {
            // Do not leave an empty overlay above the entire window: it can consume clicks.
            if let message = appState.errorMessage {
                ErrorBanner(message: message) {
                    InteractionLog.event("error.dismiss")
                    appState.errorMessage = nil
                }
                .padding(.top, 16)
                .padding(.horizontal, 24)
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if let message = appState.noticeMessage {
                NoticeBanner(message: message) {
                    appState.dismissNotice()
                }
                .padding(.top, 16)
                .padding(.horizontal, 24)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: appState.errorMessage)
        .animation(.easeOut(duration: 0.18), value: appState.noticeMessage)
    }
}

private struct Sidebar: View {
    @Binding var selection: AppSection
    let readiness: AppReadiness
    let iconTheme: AppIconTheme
    let chineseDisplayName: String
    let englishDisplayName: String

    private var visibleSections: [AppSection] {
        AppSection.allCases.filter { section in
            !BuildInfo.hidesExpressionStyleForLegacyRelease || section != .expression
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    NoboardBrandIcon(theme: iconTheme)
                        .frame(width: 58, height: 58)

                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            Text(chineseDisplayName)
                                .font(.system(size: 22, weight: .semibold))
                            if BuildInfo.isDevelopmentBuild {
                                Text("DEV")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 3)
                                    .background(.orange)
                                    .clipShape(Capsule())
                                    .accessibilityLabel("开发测试版")
                            }
                        }
                        Spacer(minLength: 0)
                        Text(englishDisplayName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 58, alignment: .leading)
                }

                Label {
                    Text(LocalizedStringKey(readiness.label))
                } icon: {
                    Image(systemName: "circle.fill")
                }
                .font(.caption)
                .foregroundStyle(readiness == .ready ? AkangVoiceInputTheme.accent : .secondary)
                .labelStyle(.titleAndIcon)
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 28)

            ForEach(visibleSections) { section in
                Button {
                    InteractionLog.event("sidebar.select section=\(section.rawValue)")
                    selection = section
                } label: {
                    Label {
                        Text(LocalizedStringKey(section.rawValue))
                    } icon: {
                        Image(systemName: section.icon)
                    }
                        .font(.system(size: 15, weight: selection == section ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                        .background(selection == section ? AkangVoiceInputTheme.accentSoft : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .foregroundStyle(selection == section ? AkangVoiceInputTheme.accent : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 2)
            }

            Spacer()

            Text("v\(BuildInfo.displayVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(22)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct AboutView: View {
    @EnvironmentObject private var appState: AppState
    private let githubURL = URL(string: "https://github.com/PMKang/akang-ai-voice-input")!

    private var officialAccountQRImage: NSImage? {
        guard let url = Bundle.main.url(forResource: "OfficialAccountQR", withExtension: "jpg") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private var videoChannelQRImage: NSImage? {
        guard let url = Bundle.main.url(forResource: "VideoChannelQR", withExtension: "jpg") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("关于")
                    .font(.system(size: 32, weight: .bold))

                UpdatePanel()

                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(appState.productDisplayName)
                            .font(.title2.weight(.semibold))
                        Text(AppBrand.productSuffix)
                            .font(.subheadline.weight(.medium))
                        Text("一个由个人开发和维护的 macOS AI 语音输入工具。")
                            .foregroundStyle(.secondary)

                        Divider()
                            .padding(.vertical, 6)

                        Text("开发者说明")
                            .font(.headline)

                        Text("我是阿康，10 年产品老兵，做过互联网大厂产品负责人，也在金融保险行业当过产品总监。现在最大的业余爱好，是把原本要花钱买的软件先研究一遍，再认真思考：要不自己做一个？")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("这个输入法就是这么来的。我负责提需求、挑体验和追着 Bug 跑，AI 负责陪我加班。项目会随缘更新，但每条反馈都会认真看，只是回复可能慢一点，毕竟产品、开发、测试和客服目前是同一个人。")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 12) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("觉得好用，欢迎在 GitHub 点个 Star")
                                    .font(.subheadline.weight(.medium))
                                Text("您的每一个 Star，都是对这次探索的一份认可。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                InteractionLog.event("about.github.open")
                                NSWorkspace.shared.open(githubURL)
                            } label: {
                                Label("打开 GitHub", systemImage: "arrow.up.right")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(14)
                        .background(AkangVoiceInputTheme.accent.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 7))

                    }
                    .frame(maxWidth: 620, alignment: .leading)

                    Spacer()

                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 18) {
                            SocialQRCode(
                                image: officialAccountQRImage,
                                title: "公众号",
                                subtitle: "文章与开发记录"
                            )

                            FeedbackQRCodeNote()
                        }

                        SocialQRCode(
                            image: videoChannelQRImage,
                            title: "视频号",
                            subtitle: "视频实测与分享",
                            cropToSquare: true
                        )
                    }
                }
                .padding(24)
                .akangVoiceInputPanel()

                RecommendedToolsPanel()

                ChangelogPanel()
            }
            .padding(24)
            .padding(38)
        }
    }
}

private struct FeedbackQRCodeNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("来吐槽，也来聊聊", systemImage: "bubble.left.and.bubble.right.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AkangVoiceInputTheme.accent)

            Text("哪里不好用、值得改进，或恰好觉得好用？关注公众号后私信我。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 178, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct RecommendedToolsPanel: View {
    private let macPastieURL = URL(string: "https://github.com/PMKang/Mac-TieTie/releases/latest")!
    private let macPastieBlue = Color(red: 0.13, green: 0.47, blue: 0.95)
    private let macPastieBlueSoft = Color(red: 0.93, green: 0.96, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("阿康的好用工具", systemImage: "sparkles")
                .font(.headline)

            HStack(spacing: 14) {
                Image(systemName: "rectangle.3.group.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(macPastieBlue)
                    .frame(width: 48, height: 48)
                    .background(macPastieBlueSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("阿康的 Mac 贴贴")
                        .font(.subheadline.weight(.semibold))
                    Text("轻量的 macOS 贴窗工具。按需了解，不捆绑安装。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("了解一下") {
                    InteractionLog.event("about.recommended.mac-pastie.open")
                    NSWorkspace.shared.open(macPastieURL)
                }
            }
        }
        .padding(18)
        .akangVoiceInputPanel()
    }
}

private struct UpdatePanel: View {
    @EnvironmentObject private var appState: AppState
    @State private var updateIconTurns = 0

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.title2)
                .foregroundStyle(AkangVoiceInputTheme.accent)
                .frame(width: 42, height: 42)
                .background(AkangVoiceInputTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .rotationEffect(.degrees(Double(updateIconTurns) * 360))
                .animation(.easeInOut(duration: 0.58), value: updateIconTurns)

            VStack(alignment: .leading, spacing: 4) {
                Text("版本与更新")
                    .font(.headline)
                HStack(spacing: 8) {
                    Text(detailText)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    if showsInlineCheckLink {
                        UpdateActionButton(
                            title: "检查更新",
                            systemImage: nil,
                            accessibilityIdentifier: "update.check",
                            appearance: .link
                        ) {
                            triggerUpdateCheck()
                        }
                        .help("检查 GitHub Release 是否有新版本")
                    }
                }
            }

            Spacer()

            updateAction
        }
        .padding(18)
        .akangVoiceInputPanel()
    }

    private var detailText: String {
        switch appState.updateState {
        case .idle:
            return appState.interfaceLanguage == .english ? "Current version v\(appState.currentVersion)" : "当前版本 v\(appState.currentVersion)"
        case .checking:
            return appState.interfaceLanguage == .english ? "Checking GitHub Releases…" : "正在检查 GitHub Release…"
        case .upToDate:
            return appState.interfaceLanguage == .english ? "Version v\(appState.currentVersion) is up to date" : "当前版本 v\(appState.currentVersion)，已是最新"
        case .noDownloadAvailable:
            return "暂未发布可下载的新版本"
        case .available(let release):
            return "发现 \(release.displayVersion)，安装包 \(release.asset.formattedByteCount)"
        case .downloading(let downloadedByteCount, let totalByteCount):
            return "已下载 \(formattedByteCount(downloadedByteCount)) / \(formattedByteCount(totalByteCount))"
        case .preparing(let release):
            return "\(release.displayVersion) 下载完成，正在校验更新包…"
        case .readyToRestart(let package):
            return "\(package.displayVersion) 已就绪，重启后安装"
        case .failed(let message):
            return "更新失败：\(message)"
        }
    }

    private var showsInlineCheckLink: Bool {
        switch appState.updateState {
        case .idle, .upToDate, .noDownloadAvailable, .failed:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private var updateAction: some View {
        switch appState.updateState {
        case .checking:
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                Text("正在检查…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .downloading(let downloadedByteCount, let totalByteCount):
            VStack(alignment: .trailing, spacing: 7) {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在下载 \(percentage(downloadedByteCount, totalByteCount))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: downloadProgress(downloadedByteCount, totalByteCount))
                    .tint(AkangVoiceInputTheme.accent)
                    .frame(width: 220)
                Text("\(formattedByteCount(downloadedByteCount)) / \(formattedByteCount(totalByteCount))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        case .preparing:
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                Text("正在校验")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .available:
            UpdateActionButton(
                title: "下载更新",
                systemImage: "arrow.down.circle.fill",
                accessibilityIdentifier: "update.download",
                appearance: .system
            ) {
                handleDownloadTap()
            }
            .help("下载更新包并显示实时进度")
        case .readyToRestart:
            UpdateActionButton(
                title: "重启并安装",
                systemImage: "arrow.clockwise.circle.fill",
                accessibilityIdentifier: "update.install",
                appearance: .system
            ) {
                handleInstallTap()
            }
            .help("替换当前应用并重新启动")
        default:
            EmptyView()
        }
    }

    private func downloadProgress(_ downloadedByteCount: Int64, _ totalByteCount: Int64) -> Double {
        guard totalByteCount > 0 else { return 0 }
        return min(1, max(0, Double(downloadedByteCount) / Double(totalByteCount)))
    }

    private func percentage(_ downloadedByteCount: Int64, _ totalByteCount: Int64) -> Int {
        Int((downloadProgress(downloadedByteCount, totalByteCount) * 100).rounded())
    }

    private func formattedByteCount(_ byteCount: Int64) -> String {
        guard byteCount > 0 else { return "正在计算容量" }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private func handleDownloadTap() {
        InteractionLog.event("update.download.tap")
        appState.startAvailableUpdateDownload()
    }

    private func handleInstallTap() {
        InteractionLog.event("update.install.tap")
        appState.installDownloadedUpdate()
    }

    private func triggerUpdateCheck() {
        InteractionLog.event("update.check.tap")
        appState.showNotice("正在检查更新…")
        updateIconTurns += 1
        appState.startUpdateCheck()
    }
}

private enum UpdateActionButtonAppearance {
    case system
    case link
}

private struct UpdateActionButton: NSViewRepresentable {
    let title: String
    let systemImage: String?
    let accessibilityIdentifier: String
    let appearance: UpdateActionButtonAppearance
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action, accessibilityIdentifier: accessibilityIdentifier)
    }

    func makeNSView(context: Context) -> UpdateActionButtonContainer {
        let button = UpdateActionNSButton(
            title: title,
            systemImage: systemImage,
            accessibilityIdentifier: accessibilityIdentifier,
            appearance: appearance
        )
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction(_:))
        return UpdateActionButtonContainer(button: button)
    }

    func updateNSView(_ container: UpdateActionButtonContainer, context: Context) {
        context.coordinator.action = action
        container.button.configure(title: title, systemImage: systemImage, appearance: appearance)
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void
        private let accessibilityIdentifier: String

        init(action: @escaping () -> Void, accessibilityIdentifier: String) {
            self.action = action
            self.accessibilityIdentifier = accessibilityIdentifier
        }

        @objc func performAction(_ sender: NSButton) {
            InteractionLog.event("update.native-button.action id=\(accessibilityIdentifier)")
            action()
        }
    }
}

private final class UpdateActionButtonContainer: NSView {
    let button: UpdateActionNSButton

    init(button: UpdateActionNSButton) {
        self.button = button
        super.init(frame: .zero)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        button.intrinsicContentSize
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        return button
    }
}

private final class UpdateActionNSButton: NSButton {
    private let interactionIdentifier: String

    init(
        title: String,
        systemImage: String?,
        accessibilityIdentifier: String,
        appearance: UpdateActionButtonAppearance
    ) {
        self.interactionIdentifier = accessibilityIdentifier
        super.init(frame: .zero)
        imagePosition = .imageLeading
        imageScaling = .scaleProportionallyDown
        font = .systemFont(ofSize: 14, weight: .semibold)
        controlSize = .regular
        identifier = NSUserInterfaceItemIdentifier(accessibilityIdentifier)
        setAccessibilityIdentifier(accessibilityIdentifier)
        configure(title: title, systemImage: systemImage, appearance: appearance)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func mouseDown(with event: NSEvent) {
        InteractionLog.event("update.native-button.mouseDown id=\(interactionIdentifier)")
        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if usesPointingHandCursor {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if usesPointingHandCursor {
            NSCursor.pointingHand.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    func configure(
        title: String,
        systemImage: String?,
        appearance: UpdateActionButtonAppearance
    ) {
        let foregroundColor: NSColor
        switch appearance {
        case .system:
            isBordered = true
            bezelStyle = .rounded
            bezelColor = nil
            foregroundColor = .labelColor
            usesPointingHandCursor = false
        case .link:
            isBordered = false
            bezelStyle = .inline
            bezelColor = nil
            foregroundColor = .secondaryLabelColor
            usesPointingHandCursor = true
        }
        contentTintColor = foregroundColor
        if let systemImage {
            let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)?
                .withSymbolConfiguration(configuration)
            image?.isTemplate = true
        } else {
            image = nil
        }
        let font: NSFont = appearance == .link
            ? .systemFont(ofSize: 12, weight: .regular)
            : .systemFont(ofSize: 14, weight: .semibold)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: foregroundColor
        ]
        if appearance == .link {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attributes[.underlineColor] = foregroundColor
        }
        attributedTitle = NSAttributedString(
            string: title,
            attributes: attributes
        )
        window?.invalidateCursorRects(for: self)
    }

    private var usesPointingHandCursor = false
}

private struct ChangelogPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("更新日志", systemImage: "clock.arrow.circlepath")
                .font(.headline)

            ChangelogRow(
                version: "v1.5.0",
                date: "2026 年 7 月 22 日",
                details: "接入豆包流式语音识别 2.0：新版控制台仅需配置一个 API Key，可选择为当前录音模型并测试连接；采用双向流式 WebSocket 原始转写，不执行表达方式提示词。"
            )
            Divider()
            ChangelogRow(
                version: "v1.3.0",
                date: "2026 年 7 月 22 日",
                details: "新增带拖拽引导的 DMG 安装镜像；同时保留 ZIP 自动更新包，并验证 macOS 12、Intel 与 Apple 芯片兼容性。"
            )
            Divider()
            ChangelogRow(
                version: "v1.2.3",
                date: "2026 年 7 月 21 日",
                details: "补全英文界面的首页、历史、词典、设置、关于页和录音悬浮窗；仅翻译界面，不改写提示词、语音内容或自定义规则。"
            )
            Divider()
            ChangelogRow(
                version: "v1.2.2",
                date: "2026 年 7 月 21 日",
                details: "新增简体中文与 English 界面切换，默认中文；内置表达方式在英文界面显示英文名称与说明，不改写用户的提示词或自定义规则。"
            )
            Divider()
            ChangelogRow(
                version: "v1.2.1",
                date: "2026 年 7 月 21 日",
                details: "支持 macOS 12（Monterey）及 Intel Mac；优化旧系统微信等复杂输入框的自动写入，并增加辅助功能权限的自助引导。"
            )
            Divider()
            ChangelogRow(
                version: "v1.2.0",
                date: "2026 年 7 月 21 日",
                details: "首页新增最近 3 天与近 30 天 AI 平均识别耗时及趋势；系统默认 Logo 统一为晴空蓝，并优化启动初始化，避免旧图标闪现。"
            )
            Divider()
            ChangelogRow(
                version: "v1.1.1",
                date: "2026 年 7 月 18 日",
                details: "菜单栏升级为自定义中空话筒图标；设置新增中文与英文品牌名称，保存后同步侧边栏、菜单栏、关于页与录音悬浮窗。"
            )
            Divider()
            ChangelogRow(
                version: "v1.1.0",
                date: "2026 年 7 月 17 日",
                details: "启用 Noboard · 自在说全新品牌与 Dock 图标；新增晴空蓝、靛紫、珊瑚三款图标主题，可在设置中即时切换。"
            )
            Divider()
            ChangelogRow(
                version: "v1.0.4",
                date: "2026 年 7 月 16 日",
                details: "修复“关于”页在特殊窗口布局下无法触发检查更新的 Bug；新增轻量检查链接与状态反馈。"
            )
            Divider()
            ChangelogRow(
                version: "v1.0.3",
                date: "2026 年 7 月 15 日",
                details: "新增本机显示名称自定义：可在设置中修改页面、菜单栏和录音悬浮窗中的品牌名称，应用名称保持不变。"
            )
            Divider()
            ChangelogRow(
                version: "v1.0.2",
                date: "2026 年 7 月 15 日",
                details: "优化请求透传：问题、命令和任务会整理为下游请求，不由输入法提前作答；升级内置“智能整理”规则，强化语言保留、方言书面化与无效输入识别，并自动迁移旧版系统默认规则，保留本地自定义内容。"
            )
            Divider()
            ChangelogRow(
                version: "v1.0.1",
                date: "2026 年 7 月 15 日",
                details: "优化悬浮窗实时转写与智能降噪状态；新增关于页更新检查、后台下载和重启安装入口。"
            )
            Divider()
            ChangelogRow(
                version: "v1.0.0",
                date: "2026 年 7 月 12 日",
                details: "支持 Realtime 语音输入、表达方式、历史记录、词典与本地统计。"
            )
        }
        .padding(18)
        .akangVoiceInputPanel()
    }
}

private struct ChangelogRow: View {
    let version: String
    let date: String
    let details: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(version)
                .font(.subheadline.weight(.semibold))
                .frame(width: 54, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(date).font(.caption).foregroundStyle(.secondary)
                Text(details).font(.callout)
            }
        }
    }
}

private struct SocialQRCode: View {
    let image: NSImage?
    let title: String
    let subtitle: String
    var cropToSquare = false

    var body: some View {
        VStack(spacing: 8) {
            if let image {
                Group {
                    if cropToSquare {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                            .scaleEffect(1.28)
                            .offset(y: 14)
                    } else {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                    }
                }
                .frame(width: 154, height: 154)
                .clipped()
                .padding(8)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            } else {
                EmptyStateView(
                    title: "二维码缺失",
                    systemImage: "qrcode",
                    description: "请稍后重新打开此页面。"
                )
                    .frame(width: 170, height: 170)
            }

            Text(LocalizedStringKey(title))
                .font(.caption.weight(.medium))
            Text(LocalizedStringKey(subtitle))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 178)
    }
}

private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
            Spacer(minLength: 16)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("关闭提示")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .frame(maxWidth: 720)
    }
}

private struct NoticeBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AkangVoiceInputTheme.accent)
            Text(message)
                .font(.callout)
            Spacer(minLength: 16)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("关闭提示")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AkangVoiceInputTheme.accent.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .frame(maxWidth: 520)
    }
}
