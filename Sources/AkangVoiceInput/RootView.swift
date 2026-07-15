import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        HStack(spacing: 0) {
            Sidebar(
                selection: $appState.selectedSection,
                readiness: appState.readiness,
                displayName: appState.displayName
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
            VStack(spacing: 10) {
                if let message = appState.errorMessage {
                    ErrorBanner(message: message) {
                        InteractionLog.event("error.dismiss")
                        appState.errorMessage = nil
                    }
                }
                if let message = appState.noticeMessage {
                    NoticeBanner(message: message) {
                        appState.dismissNotice()
                    }
                }
            }
            .padding(.top, 16)
            .padding(.horizontal, 24)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
        .animation(.easeOut(duration: 0.18), value: appState.errorMessage)
        .animation(.easeOut(duration: 0.18), value: appState.noticeMessage)
    }
}

private struct Sidebar: View {
    @Binding var selection: AppSection
    let readiness: AppReadiness
    let displayName: String

    private var visibleSections: [AppSection] {
        AppSection.allCases.filter { section in
            !BuildInfo.hidesExpressionStyleForLegacyRelease || section != .expression
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AkangVoiceInputTheme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.title2.weight(.bold))
                    Text(AppBrand.productSuffix)
                        .font(.headline)
                    Label(readiness.label, systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(readiness == .ready ? AkangVoiceInputTheme.accent : .secondary)
                        .labelStyle(.titleAndIcon)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 30)
            .padding(.bottom, 38)

            ForEach(visibleSections) { section in
                Button {
                    InteractionLog.event("sidebar.select section=\(section.rawValue)")
                    selection = section
                } label: {
                    Label(section.rawValue, systemImage: section.icon)
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
    @Environment(AppState.self) private var appState
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

                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.title3)
                                .foregroundStyle(AkangVoiceInputTheme.accent)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("来吐槽，也来聊聊")
                                    .font(.subheadline.weight(.medium))
                                Text("觉得哪里不好用、值得改进，或者恰好觉得好用？关注右侧公众号后私信我，我会拉你进讨论群。不定期也会分享一些有意思的 AI 玩法。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(14)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .frame(maxWidth: 620, alignment: .leading)

                    Spacer()

                    HStack(alignment: .top, spacing: 16) {
                        SocialQRCode(
                            image: officialAccountQRImage,
                            title: "公众号",
                            subtitle: "文章与开发记录"
                        )
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
        .task {
            await appState.checkForUpdatesIfNeeded()
        }
    }
}

private struct RecommendedToolsPanel: View {
    private let macPastieURL = URL(string: "https://github.com/PMKang/Mac-TieTie/releases/latest")!

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("阿康的好用工具", systemImage: "sparkles")
                .font(.headline)

            HStack(spacing: 14) {
                Image(systemName: "rectangle.3.group.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(AkangVoiceInputTheme.accent)
                    .frame(width: 48, height: 48)
                    .background(AkangVoiceInputTheme.accentSoft)
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
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.title2)
                .foregroundStyle(AkangVoiceInputTheme.accent)
                .frame(width: 42, height: 42)
                .background(AkangVoiceInputTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("版本与更新")
                    .font(.headline)
                Text(detailText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
            return "当前版本 v\(appState.currentVersion)"
        case .checking:
            return "正在检查 GitHub Release…"
        case .upToDate:
            return "当前版本 v\(appState.currentVersion)，已是最新"
        case .noDownloadAvailable:
            return "暂未发布可下载的新版本"
        case .available(let release):
            return "发现 v\(release.version)，待更新"
        case .downloading(let progress, let totalByteCount):
            let percentage = Int((progress * 100).rounded())
            let sizeLabel = totalByteCount > 0
                ? ByteCountFormatter.string(fromByteCount: Int64(totalByteCount), countStyle: .file) + " "
                : ""
            return "正在下载 \(sizeLabel)更新包 \(percentage)%"
        case .readyToRestart(let package):
            return "v\(package.version) 已下载，重启后安装"
        case .failed(let message):
            return "更新失败：\(message)"
        }
    }

    @ViewBuilder
    private var updateAction: some View {
        switch appState.updateState {
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .downloading(let progress, _):
            VStack(alignment: .trailing, spacing: 7) {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在下载 \(Int((progress * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress)
                    .tint(AkangVoiceInputTheme.accent)
                    .frame(width: 188)
            }
        case .available:
            Button("下载更新") {
                Task { await appState.downloadAvailableUpdate() }
            }
            .buttonStyle(.borderedProminent)
        case .readyToRestart:
            Button("重启并安装") {
                appState.installDownloadedUpdate()
            }
            .buttonStyle(.borderedProminent)
        default:
            Button("检查更新") {
                Task { await appState.checkForUpdates() }
            }
        }
    }
}

private struct ChangelogPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("更新日志", systemImage: "clock.arrow.circlepath")
                .font(.headline)

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
                ContentUnavailableView("二维码缺失", systemImage: "qrcode")
                    .frame(width: 170, height: 170)
            }

            Text(title)
                .font(.caption.weight(.medium))
            Text(subtitle)
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
