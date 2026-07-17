import AppKit
import Foundation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case home = "主页"
    case history = "历史记录"
    case dictionary = "词典"
    case expression = "表达方式"
    case settings = "设置"
    case about = "关于"

    var id: Self { self }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .history: "clock"
        case .dictionary: "book.closed"
        case .expression: "text.quote"
        case .settings: "gearshape"
        case .about: "info.circle"
        }
    }
}

enum LanguagePreference: String, CaseIterable, Identifiable {
    case automatic = "自动识别"
    case mandarin = "普通话"
    case cantonese = "粤语"

    var id: Self { self }
}

struct HistoryItem: Identifiable, Hashable, Codable {
    let id: UUID
    let date: Date
    let text: String
    let recordingDuration: TimeInterval
    let processingDuration: TimeInterval
    let model: String
    var inputTokens: Int
    var outputTokens: Int

    init(
        id: UUID = UUID(),
        date: Date,
        text: String,
        recordingDuration: TimeInterval,
        processingDuration: TimeInterval,
        model: String,
        inputTokens: Int = 0,
        outputTokens: Int = 0
    ) {
        self.id = id
        self.date = date
        self.text = text
        self.recordingDuration = recordingDuration
        self.processingDuration = processingDuration
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, text, recordingDuration, processingDuration, model, inputTokens, outputTokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        text = try container.decode(String.self, forKey: .text)
        recordingDuration = try container.decode(TimeInterval.self, forKey: .recordingDuration)
        processingDuration = try container.decode(TimeInterval.self, forKey: .processingDuration)
        model = try container.decode(String.self, forKey: .model)
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
    }
}

enum UsageEstimate {
    // China (Beijing) public list price for qwen3.5-omni-flash-realtime, CNY per million tokens.
    static let audioInputCNYPerMillion: Double = 27
    static let textOutputCNYPerMillion: Double = 20
    static let introductoryFreeQuotaTokens = 1_000_000

    static func estimatedCost(inputTokens: Int, outputTokens: Int) -> Double {
        Double(inputTokens) / 1_000_000 * audioInputCNYPerMillion
            + Double(outputTokens) / 1_000_000 * textOutputCNYPerMillion
    }
}

struct DictionaryEntry: Identifiable, Hashable, Codable {
    let id: UUID
    var term: String
    var pronunciation: String
    var replacement: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        term: String,
        pronunciation: String,
        replacement: String,
        createdAt: Date
    ) {
        self.id = id
        self.term = term
        self.pronunciation = pronunciation
        self.replacement = replacement
        self.createdAt = createdAt
    }
}

struct PromptProfile: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var instructions: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        instructions: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.instructions = instructions
        self.createdAt = createdAt
    }
}

enum VoiceSessionState: Equatable {
    case idle
    case requestingPermission
    case listening(startedAt: Date)
    case finishing

    var isListening: Bool {
        if case .listening = self { true } else { false }
    }
}

enum ConnectionTestState: Equatable {
    case idle
    case testing
    case success
    case failure(String)

    var label: String {
        switch self {
        case .idle: "尚未测试"
        case .testing: "正在连接"
        case .success: "连接成功"
        case .failure(let message): "连接失败：\(message)"
        }
    }
}

enum AppReadiness: Equatable {
    case needsCredentials
    case needsMicrophoneRequest
    case microphoneUnavailable
    case ready

    var label: String {
        switch self {
        case .needsCredentials: "待配置"
        case .needsMicrophoneRequest: "待首次录音"
        case .microphoneUnavailable: "麦克风未授权"
        case .ready: "已就绪"
        }
    }

    static func resolve(
        apiKeyConfigured: Bool,
        workspaceIDConfigured: Bool,
        microphonePermission: MicrophonePermissionState
    ) -> Self {
        guard apiKeyConfigured, workspaceIDConfigured else { return .needsCredentials }
        switch microphonePermission {
        case .authorized: return .ready
        case .notDetermined: return .needsMicrophoneRequest
        case .denied, .restricted: return .microphoneUnavailable
        }
    }
}

@MainActor
@Observable
final class AppState {
    var selectedSection: AppSection = .home
    var selectedHistoryItem: HistoryItem?
    var historyItems: [HistoryItem] = []
    var dictionaryEntries: [DictionaryEntry] = []
    var displayName: String
    var iconTheme: AppIconTheme
    var shortcutChoice: ShortcutChoice
    var languagePreference: LanguagePreference {
        didSet { UserDefaults.standard.set(languagePreference.rawValue, forKey: Self.languageDefaultsKey) }
    }
    var convertCantonese: Bool {
        didSet { UserDefaults.standard.set(convertCantonese, forKey: Self.cantoneseDefaultsKey) }
    }
    var copyWhenNoInput: Bool {
        didSet { UserDefaults.standard.set(copyWhenNoInput, forKey: Self.copyDefaultsKey) }
    }
    var promptProfiles: [PromptProfile]
    var selectedPromptProfileID: UUID
    var promptInstructions: String {
        didSet {
            UserDefaults.standard.set(promptInstructions, forKey: Self.promptDefaultsKey)
            syncCurrentPromptProfile()
        }
    }
    var launchAtLogin: Bool
    var developerMode: Bool {
        didSet { UserDefaults.standard.set(developerMode, forKey: Self.developerModeDefaultsKey) }
    }
    var voiceSessionState: VoiceSessionState = .idle
    var microphonePermission = MicrophonePermissionState.current
    var errorMessage: String?
    var noticeMessage: String?
    var lastRecordingSummary = "尚未开始本地录音"
    var apiKeyConfigured = KeychainStore.hasAPIKey()
    var workspaceIDConfigured = KeychainStore.hasWorkspaceID()
    var accessibilityPermission = AccessibilityPermissionState.current
    var inputMonitoringPermission = InputMonitoringPermissionState.current
    var partialModelText = ""
    var latestFinalText = ""
    var lastInputTokens = 0
    var lastOutputTokens = 0
    var connectionTestState: ConnectionTestState = .idle
    var diagnosticEntries: [DiagnosticEntry] = []
    var updateState: AppUpdateState = .idle
    var modelServiceConfiguration: ModelServiceConfiguration {
        QwenRealtimeClient.serviceConfiguration
    }
    var readiness: AppReadiness {
        .resolve(
            apiKeyConfigured: apiKeyConfigured,
            workspaceIDConfigured: workspaceIDConfigured,
            microphonePermission: microphonePermission
        )
    }
    var productDisplayName: String { AppBrand.productDisplayName(for: displayName) }
    private var recordingStartedAt: Date?
    private var processingStartedAt: Date?
    private var lastRecordingDuration: TimeInterval = 0
    private var responseTimeoutTask: Task<Void, Never>?
    private var connectionTestTimeoutTask: Task<Void, Never>?
    private var testingConnection = false
    private var noticeDismissTask: Task<Void, Never>?
    private var latestHistoryItemID: UUID?
    private var updateCheckTask: Task<Void, Never>?
    private var downloadedUpdate: DownloadedUpdatePackage?
    private let persistenceStore: AppPersistenceStore
    private let updateService = GitHubUpdateService()
    private static let shortcutDefaultsKey = "voiceShortcutChoice"
    private static let languageDefaultsKey = "languagePreference"
    private static let cantoneseDefaultsKey = "convertCantonese"
    private static let copyDefaultsKey = "copyWhenNoInput"
    private static let promptDefaultsKey = "voicePromptInstructions"
    private static let promptProfilesDefaultsKey = "voicePromptProfiles"
    private static let selectedPromptProfileDefaultsKey = "selectedVoicePromptProfileID"
    private static let developerModeDefaultsKey = "developerMode"
    private static let displayNameDefaultsKey = "voiceDisplayName"
    private static let displayNameCustomizedDefaultsKey = "voiceDisplayNameCustomized"
    private static let iconThemeDefaultsKey = "appIconTheme"

    let floatingPanel = FloatingPanelController()
    let audioCapture = AudioCaptureService()
    let shortcutMonitor = GlobalShortcutMonitor()
    let realtimeClient = QwenRealtimeClient()

    init(persistenceStore: AppPersistenceStore = AppPersistenceStore()) {
        self.persistenceStore = persistenceStore
        let storedDisplayName = UserDefaults.standard.string(forKey: Self.displayNameDefaultsKey)
        let hasExplicitDisplayNameCustomization = UserDefaults.standard.object(
            forKey: Self.displayNameCustomizedDefaultsKey
        ) as? Bool ?? storedDisplayName.map {
            !AppBrand.legacyDefaultDisplayNames.contains(
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } ?? false
        displayName = AppBrand.normalizedDisplayName(
            hasExplicitDisplayNameCustomization
                ? (storedDisplayName ?? AppBrand.defaultDisplayName)
                : AppBrand.defaultDisplayName
        )
        iconTheme = UserDefaults.standard.string(forKey: Self.iconThemeDefaultsKey)
            .flatMap(AppIconTheme.init(rawValue:))
            ?? .sky
        convertCantonese = UserDefaults.standard.object(forKey: Self.cantoneseDefaultsKey) as? Bool ?? true
        copyWhenNoInput = UserDefaults.standard.object(forKey: Self.copyDefaultsKey) as? Bool ?? true
        let migratedInstructions = VoiceInputPrompt.migratedInstructions(
            from: UserDefaults.standard.string(forKey: Self.promptDefaultsKey)
        )
        let defaultProfiles = Self.defaultPromptProfiles(defaultInstructions: migratedInstructions)
        let storedProfiles = Self.migratedPromptProfiles(
            Self.loadPromptProfiles(),
            defaults: defaultProfiles
        )
        let resolvedPromptProfiles = storedProfiles.isEmpty
            ? defaultProfiles
            : storedProfiles + defaultProfiles.filter { candidate in
                !storedProfiles.contains { $0.name == candidate.name }
            }
        let storedSelectedID = UserDefaults.standard.string(forKey: Self.selectedPromptProfileDefaultsKey)
            .flatMap(UUID.init(uuidString:))
        let resolvedSelectedID = storedSelectedID.flatMap { candidate in
            resolvedPromptProfiles.contains { $0.id == candidate } ? candidate : nil
        } ?? resolvedPromptProfiles[0].id
        let resolvedPromptInstructions = resolvedPromptProfiles
            .first { $0.id == resolvedSelectedID }?.instructions
            ?? migratedInstructions
        promptProfiles = resolvedPromptProfiles
        selectedPromptProfileID = resolvedSelectedID
        promptInstructions = resolvedPromptInstructions
        launchAtLogin = LoginItemService.isEnabled
        developerMode = UserDefaults.standard.bool(forKey: Self.developerModeDefaultsKey)
        let resolvedShortcutChoice = UserDefaults.standard.string(forKey: Self.shortcutDefaultsKey)
            .flatMap(ShortcutChoice.init(rawValue:))
            ?? .optionCommand
        shortcutChoice = resolvedShortcutChoice == .controlOption
            ? .optionCommand
            : resolvedShortcutChoice
        languagePreference = LanguagePreference(
            rawValue: UserDefaults.standard.string(forKey: Self.languageDefaultsKey) ?? ""
        ) ?? .automatic
        UserDefaults.standard.set(shortcutChoice.rawValue, forKey: Self.shortcutDefaultsKey)
        UserDefaults.standard.set(displayName, forKey: Self.displayNameDefaultsKey)
        AkangVoiceInputTheme.apply(iconTheme)
        floatingPanel.updateDisplayName(displayName)
        DispatchQueue.main.async { [weak self] in
            self?.applyDockIcon()
        }
        if storedProfiles.count != resolvedPromptProfiles.count {
            persistPromptProfiles()
        }
        if let snapshot = try? persistenceStore.load() {
            historyItems = snapshot.history.sorted { $0.date > $1.date }
            dictionaryEntries = snapshot.dictionary.sorted {
                $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending
            }
        }

        audioCapture.onLevel = { [weak self] level in
            self?.floatingPanel.updateAudioLevel(level)
        }
        audioCapture.onPCM16Data = { [weak self] data in
            self?.realtimeClient.appendAudio(data)
        }
        audioCapture.onNoiseDetected = { [weak self] in
            self?.floatingPanel.showListeningHint("智能开启降噪")
            self?.recordDiagnostic("降噪", "检测到环境噪声，智能开启降噪")
        }
        realtimeClient.onPartialText = { [weak self] text in
            self?.partialModelText = text
            self?.floatingPanel.updateTranscript(text)
        }
        realtimeClient.onInputTranscript = { [weak self] text in
            self?.floatingPanel.updateTranscript(text)
        }
        realtimeClient.onFinalText = { [weak self] text in
            self?.handleFinalText(text)
        }
        realtimeClient.onUsage = { [weak self] input, output in
            guard let self else { return }
            self.lastInputTokens = input
            self.lastOutputTokens = output
            if let itemID = self.latestHistoryItemID,
               let index = self.historyItems.firstIndex(where: { $0.id == itemID }) {
                self.historyItems[index].inputTokens = input
                self.historyItems[index].outputTokens = output
                self.persistData()
            }
            self.recordDiagnostic("模型", "响应完成，输入 Token \(input)，输出 Token \(output)")
        }
        realtimeClient.onError = { [weak self] error in
            guard let self else { return }
            if self.testingConnection {
                self.finishConnectionTest(with: .failure(error.localizedDescription))
            } else {
                self.handleRealtimeError(error)
            }
        }
        realtimeClient.onSessionReady = { [weak self] in
            guard let self, self.testingConnection else { return }
            self.finishConnectionTest(with: .success)
        }
        shortcutMonitor.start(choice: shortcutChoice) { [weak self] in
            self?.toggleVoiceInput()
        }
        recordDiagnostic("应用", "启动完成，模型 \(QwenRealtimeClient.model)")
    }

    func updateDisplayName(_ candidate: String) {
        let resolvedName = AppBrand.normalizedDisplayName(candidate)
        let hasChanged = displayName != resolvedName
        displayName = resolvedName
        UserDefaults.standard.set(resolvedName, forKey: Self.displayNameDefaultsKey)
        UserDefaults.standard.set(true, forKey: Self.displayNameCustomizedDefaultsKey)
        floatingPanel.updateDisplayName(resolvedName)
        if hasChanged {
            recordDiagnostic("自定义", "显示名称已更新")
        }
    }

    func openCurrentModelUsageDetails() {
        let configuration = modelServiceConfiguration
        recordDiagnostic("费用", "打开 \(configuration.providerName) 官方费用与额度页面")
        NSWorkspace.shared.open(configuration.usageDetailsURL)
    }

    func restoreDefaultDisplayName() {
        displayName = AppBrand.defaultDisplayName
        UserDefaults.standard.set(displayName, forKey: Self.displayNameDefaultsKey)
        UserDefaults.standard.set(false, forKey: Self.displayNameCustomizedDefaultsKey)
        floatingPanel.updateDisplayName(displayName)
        recordDiagnostic("自定义", "显示名称已恢复默认")
    }

    func updateIconTheme(_ theme: AppIconTheme) {
        guard iconTheme != theme else { return }
        iconTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: Self.iconThemeDefaultsKey)
        AkangVoiceInputTheme.apply(theme)
        applyDockIcon()
        InteractionLog.event("appearance.iconTheme.changed value=\(theme.rawValue)")
        showNotice("已切换为\(theme.title)主题")
    }

    private func applyDockIcon() {
        guard let image = iconTheme.image() else {
            InteractionLog.event("appearance.iconTheme.missingAsset value=\(iconTheme.rawValue)")
            return
        }
        NSApp.applicationIconImage = image
    }

    func toggleVoiceInput() {
        switch voiceSessionState {
        case .idle:
            Task { await startVoiceInput() }
        case .listening:
            stopVoiceInput()
        case .requestingPermission, .finishing:
            break
        }
    }

    func startVoiceInput() async {
        guard voiceSessionState == .idle else { return }
        AccessibilityTextInserter.trackFocusedElement()
        floatingPanel.prepareForNewSession(displayName: displayName)
        voiceSessionState = .requestingPermission
        recordDiagnostic("录音", "请求开始语音输入")

        do {
            guard apiKeyConfigured, workspaceIDConfigured else {
                selectedSection = .settings
                throw QwenRealtimeError.missingCredentials
            }

            guard await audioCapture.requestPermission() else {
                microphonePermission = audioCapture.permissionState
                throw AudioCaptureError.microphoneDenied
            }
            microphonePermission = audioCapture.permissionState

            try realtimeClient.connect(
                instructions: VoiceInputPrompt.smart(
                    dictionaryEntries: dictionaryEntries,
                    customInstructions: promptInstructions
                )
            )
            recordDiagnostic("连接", "已发起 Realtime WebSocket 连接")
            try await audioCapture.start()
            microphonePermission = audioCapture.permissionState
            let startedAt = audioCapture.startedAt ?? .now
            recordingStartedAt = startedAt
            processingStartedAt = nil
            partialModelText = ""
            floatingPanel.updateTranscript("")
            latestFinalText = ""
            lastInputTokens = 0
            lastOutputTokens = 0
            latestHistoryItemID = nil
            voiceSessionState = .listening(startedAt: startedAt)
            lastRecordingSummary = "正在采集并实时发送 16 kHz 单声道 PCM 音频"
            floatingPanel.updateAudioLevel(0)
            floatingPanel.show(state: .listening(startedAt: startedAt))
            recordDiagnostic("录音", "麦克风已开始采集 16 kHz 单声道 PCM")
        } catch {
            AccessibilityTextInserter.clearTrackedElement()
            microphonePermission = audioCapture.permissionState
            realtimeClient.disconnect()
            voiceSessionState = .idle
            errorMessage = error.localizedDescription
            recordDiagnostic("错误", error.localizedDescription)
            floatingPanel.hide()
        }
    }

    func stopVoiceInput() {
        guard case .listening(let startedAt) = voiceSessionState else { return }
        voiceSessionState = .finishing
        let duration = Date().timeIntervalSince(startedAt)
        lastRecordingDuration = duration
        audioCapture.stop()
        // stop() drains the final partial PCM batch before this guard runs.
        let capturedByteCount = audioCapture.capturedByteCount
        guard AudioCapturePolicy.hasEnoughAudio(byteCount: capturedByteCount) else {
            recordDiagnostic("录音", "未检测到足够的有效人声，已在本地清空本次输出")
            handleRealtimeError(AudioCaptureError.noValidSpeech)
            return
        }
        processingStartedAt = .now
        floatingPanel.show(state: .processing)
        lastRecordingSummary = String(format: "录音 %.1f 秒，正在等待最终文字", duration)
        realtimeClient.finish()
        recordDiagnostic("录音", String(format: "停止采集，录音时长 %.2f 秒，等待最终文字", duration))
        responseTimeoutTask?.cancel()
        responseTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self, self.voiceSessionState == .finishing else { return }
            self.handleRealtimeError(QwenRealtimeError.server("等待最终文字超时，请重试"))
        }
    }

    func saveBailianCredentials(apiKey: String, workspaceID: String) -> Bool {
        do {
            try KeychainStore.saveCredentials(apiKey: apiKey, workspaceID: workspaceID)
            apiKeyConfigured = KeychainStore.hasAPIKey()
            workspaceIDConfigured = KeychainStore.hasWorkspaceID()
            connectionTestState = .idle
            recordDiagnostic("凭证", "API Key 与 Workspace ID 已保存并完成本机回读校验")
            return apiKeyConfigured && workspaceIDConfigured
        } catch {
            apiKeyConfigured = KeychainStore.hasAPIKey()
            workspaceIDConfigured = KeychainStore.hasWorkspaceID()
            errorMessage = error.localizedDescription
            recordDiagnostic("凭证", "保存或回读校验失败：\(error.localizedDescription)")
            return false
        }
    }

    func removeBailianCredentials() -> Bool {
        guard voiceSessionState == .idle, !testingConnection else { return false }
        do {
            try KeychainStore.removeCredentials()
            apiKeyConfigured = false
            workspaceIDConfigured = false
            connectionTestState = .idle
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func testBailianConnection() {
        guard voiceSessionState == .idle, !testingConnection else { return }
        guard apiKeyConfigured, workspaceIDConfigured else {
            errorMessage = QwenRealtimeError.missingCredentials.localizedDescription
            return
        }

        testingConnection = true
        connectionTestState = .testing
        recordDiagnostic("连接测试", "开始验证个人凭证与 Realtime 会话")

        do {
            try realtimeClient.connect(
                instructions: VoiceInputPrompt.smart(
                    dictionaryEntries: dictionaryEntries,
                    customInstructions: promptInstructions
                )
            )
            connectionTestTimeoutTask?.cancel()
            connectionTestTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled, let self, self.testingConnection else { return }
                self.finishConnectionTest(with: .failure("连接超时"))
            }
        } catch {
            finishConnectionTest(with: .failure(error.localizedDescription))
        }
    }

    private func finishConnectionTest(with state: ConnectionTestState) {
        connectionTestTimeoutTask?.cancel()
        connectionTestTimeoutTask = nil
        testingConnection = false
        realtimeClient.disconnect()
        connectionTestState = state
        recordDiagnostic("连接测试", state.label)
    }

    func updateShortcut(_ choice: ShortcutChoice) {
        shortcutChoice = choice
        UserDefaults.standard.set(choice.rawValue, forKey: Self.shortcutDefaultsKey)
        shortcutMonitor.update(choice: choice)
    }

    var currentVersion: String { BuildInfo.version }

    func startUpdateCheck() {
        guard !updateState.isBusy else {
            InteractionLog.event("update.check.ignored state=\(updateState.diagnosticLabel)")
            return
        }

        InteractionLog.event("update.check.started current=\(currentVersion)")
        updateState = .checking
        let updateService = updateService
        let currentVersion = currentVersion

        updateCheckTask = Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                await Self.fetchUpdateCheckResult(
                    updateService: updateService,
                    currentVersion: currentVersion
                )
            }.value

            guard let self, !Task.isCancelled else { return }
            self.applyUpdateCheckResult(result)
            self.updateCheckTask = nil
        }
    }

    private nonisolated static func fetchUpdateCheckResult(
        updateService: GitHubUpdateService,
        currentVersion: String
    ) async -> UpdateCheckResult {
        do {
            let release = try await updateService.fetchLatestRelease()
            return SemanticVersion(release.version) > SemanticVersion(currentVersion)
                ? .available(release)
                : .upToDate(release.version)
        } catch is CancellationError {
            return .failed("更新检查已取消，请重试。", diagnostic: "cancelled")
        } catch let error as URLError where error.code == .cancelled {
            return .failed("更新检查已取消，请重试。", diagnostic: "cancelled")
        } catch GitHubUpdateError.noPublishedRelease, GitHubUpdateError.noMacOSArchive {
            return .noDownloadAvailable
        } catch {
            return .failed(error.localizedDescription, diagnostic: error.localizedDescription)
        }
    }

    private func applyUpdateCheckResult(_ result: UpdateCheckResult) {
        switch result {
        case .available(let release):
            updateState = .available(release)
            InteractionLog.event("update.check.available latest=\(release.version) size=\(release.asset.byteCount)")
        case .upToDate(let version):
            updateState = .upToDate
            InteractionLog.event("update.check.upToDate latest=\(version)")
        case .noDownloadAvailable:
            updateState = .noDownloadAvailable
            InteractionLog.event("update.check.noDownloadAvailable")
        case .failed(let message, let diagnostic):
            updateState = .failed(message)
            InteractionLog.event("update.check.failed error=\(diagnostic)")
        }
    }

    func startAvailableUpdateDownload() {
        InteractionLog.event("update.download.tap state=\(updateState.diagnosticLabel)")
        guard case .available(let release) = updateState else {
            InteractionLog.event("update.download.ignored state=\(updateState.diagnosticLabel)")
            return
        }
        updateState = .downloading(downloadedByteCount: 0, totalByteCount: Int64(release.asset.byteCount))
        InteractionLog.event("update.download.started version=\(release.version) size=\(release.asset.byteCount)")
        showNotice("开始下载 \(release.displayVersion)，安装包 \(release.asset.formattedByteCount)")
        recordDiagnostic("更新", "开始下载 \(release.displayVersion)，\(release.asset.formattedByteCount)")

        Task { [weak self] in
            await self?.downloadAvailableUpdate(release)
        }
    }

    private func downloadAvailableUpdate(_ release: GitHubRelease) async {
        do {
            let package = try await updateService.downloadAndPrepare(release: release) { [weak self] event in
                Task { @MainActor [weak self] in
                    switch event {
                    case .receiving(let downloadedByteCount, let totalByteCount):
                        self?.updateState = .downloading(
                            downloadedByteCount: downloadedByteCount,
                            totalByteCount: totalByteCount
                        )
                    case .preparing:
                        self?.updateState = .preparing(release)
                        InteractionLog.event("update.download.preparing version=\(release.version)")
                    }
                }
            }
            downloadedUpdate = package
            updateState = .readyToRestart(package)
            InteractionLog.event("update.download.ready version=\(package.version)")
            showNotice("\(package.displayVersion) 下载完成，重启应用即可安装")
            recordDiagnostic("更新", "下载完成，等待重启安装")
        } catch {
            updateState = .failed(error.localizedDescription)
            InteractionLog.event("update.download.failed error=\(error.localizedDescription)")
            recordDiagnostic("更新", "下载失败：\(error.localizedDescription)")
        }
    }

    func installDownloadedUpdate() {
        InteractionLog.event("update.install.tap state=\(updateState.diagnosticLabel)")

        guard let downloadedUpdate else {
            InteractionLog.event("update.install.skipped reason=noPackage")
            showNotice("更新包尚未就绪，请重新下载")
            return
        }

        do {
            showNotice("正在准备安装 \(downloadedUpdate.displayVersion)，应用将重新启动")
            InteractionLog.event("update.install.schedule version=\(downloadedUpdate.version)")
            try updateService.scheduleInstallAndRestart(package: downloadedUpdate)
        } catch {
            InteractionLog.event("update.install.failed error=\(error.localizedDescription)")
            updateState = .failed(error.localizedDescription)
            showNotice("安装准备失败：\(error.localizedDescription)")
        }
    }

    func restoreDefaultPrompt() {
        promptInstructions = VoiceInputPrompt.defaultInstructions
        recordDiagnostic("提示词", "已恢复默认语音整理规则")
    }

    func selectPromptProfile(_ id: UUID) {
        guard let profile = promptProfiles.first(where: { $0.id == id }) else { return }
        selectedPromptProfileID = id
        UserDefaults.standard.set(id.uuidString, forKey: Self.selectedPromptProfileDefaultsKey)
        promptInstructions = profile.instructions
        recordDiagnostic("提示词", "已切换规则方案：\(profile.name)")
    }

    func announce(_ message: String) {
        showNotice(message)
    }

    @discardableResult
    func createPromptProfile(
        named name: String,
        instructions: String = "",
        activate: Bool = true
    ) -> PromptProfile {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = PromptProfile(
            name: cleanedName.isEmpty ? "新规则" : cleanedName,
            instructions: instructions
        )
        promptProfiles.append(profile)
        persistPromptProfiles()
        if activate {
            selectPromptProfile(profile.id)
        }
        return profile
    }

    @discardableResult
    func createAdjustedPromptProfile(from profile: PromptProfile) -> PromptProfile {
        createPromptProfile(
            named: "\(profile.name)（已调整）",
            instructions: profile.instructions,
            activate: true
        )
    }

    func nextCustomPromptProfileName() -> String {
        let baseName = "自定义表达"
        var index = 1
        var candidate = baseName
        while promptProfiles.contains(where: { $0.name == candidate }) {
            index += 1
            candidate = "\(baseName) \(index)"
        }
        return candidate
    }

    func updatePromptProfile(_ id: UUID, instructions: String) {
        let cleanedInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedInstructions.isEmpty,
              let index = promptProfiles.firstIndex(where: { $0.id == id }) else {
            return
        }
        promptProfiles[index].instructions = cleanedInstructions
        persistPromptProfiles()
        if selectedPromptProfileID == id {
            promptInstructions = cleanedInstructions
        }
        recordDiagnostic("提示词", "已更新规则方案：\(promptProfiles[index].name)")
    }

    func setSmartPromptProfile(from profile: PromptProfile) {
        guard let smartIndex = promptProfiles.firstIndex(where: { $0.name == "智能整理" }) else {
            return
        }

        promptProfiles[smartIndex].instructions = profile.instructions
        persistPromptProfiles()
        selectPromptProfile(promptProfiles[smartIndex].id)
        recordDiagnostic("提示词", "已将「\(profile.name)」设为智能整理")
    }

    func deletePromptProfile(_ id: UUID) {
        guard promptProfiles.count > 1,
              let index = promptProfiles.firstIndex(where: { $0.id == id }) else {
            return
        }
        promptProfiles.remove(at: index)
        persistPromptProfiles()
        if selectedPromptProfileID == id {
            selectPromptProfile(promptProfiles[min(index, promptProfiles.count - 1)].id)
        }
    }

    func renameSelectedPromptProfile(to name: String) {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty,
              let index = promptProfiles.firstIndex(where: { $0.id == selectedPromptProfileID }) else {
            return
        }
        promptProfiles[index].name = cleanedName
        persistPromptProfiles()
    }

    func deleteSelectedPromptProfile() {
        guard promptProfiles.count > 1,
              let index = promptProfiles.firstIndex(where: { $0.id == selectedPromptProfileID }) else {
            return
        }
        promptProfiles.remove(at: index)
        persistPromptProfiles()
        selectPromptProfile(promptProfiles[min(index, promptProfiles.count - 1)].id)
    }

    var selectedPromptProfileName: String {
        promptProfiles.first { $0.id == selectedPromptProfileID }?.name ?? "智能整理"
    }

    private static func defaultPromptProfiles(defaultInstructions: String) -> [PromptProfile] {
        [
            PromptProfile(name: "智能整理", instructions: defaultInstructions),
            PromptProfile(
                name: "原声直达",
                instructions: """
                你是语音输入记录器。把用户语音整理成准确、自然、可直接发送的文字。
                保留用户的语言风格、语气和信息重点，补充必要的标点与分段。
                输出整理后的最终文字，不解释处理过程。
                """
            ),
            PromptProfile(
                name: "清晰表达",
                instructions: """
                你是语音输入表达助手。将零散口述组织成自然、完整、可直接发送的日常文字。
                保留用户的立场、语气和信息重点，补足必要衔接，使读者无需了解上下文也能清楚理解；根据语义自动分段和组织重点。
                输出整理后的最终文字，不解释处理过程。
                """
            ),
            PromptProfile(
                name: "正式成文",
                instructions: """
                你是正式书面表达助手。将用户语音整理为完整、克制、礼貌、可直接发送的书面文字。
                保留事实、立场和信息边界，使用清晰的逻辑和自然段落；适合邮件、工作沟通和对外说明。
                输出整理后的最终文字，不解释处理过程。
                """
            ),
            PromptProfile(
                name: "要点速记",
                instructions: """
                你是要点速记助手。将用户语音提炼为清晰、可执行的重点内容。
                先呈现结论，再按事项、待办或问题组织为简洁的编号要点；每一点只表达一个核心信息。
                输出整理后的最终文字，不解释处理过程。
                """
            )
        ]
    }

    private static func migratedPromptProfiles(
        _ storedProfiles: [PromptProfile],
        defaults: [PromptProfile]
    ) -> [PromptProfile] {
        let clearExpression = defaults.first { $0.name == "清晰表达" }
        let smartExpression = defaults.first { $0.name == "智能整理" }

        return storedProfiles.map { profile in
            if profile.name == "贴心润色", let clearExpression {
                return PromptProfile(
                    id: profile.id,
                    name: clearExpression.name,
                    instructions: clearExpression.instructions,
                    createdAt: profile.createdAt
                )
            }

            // Migrate only a known built-in smart rule. A custom rule that was
            // copied into "智能整理" remains the user's local source of truth.
            if profile.name == "智能整理",
               VoiceInputPrompt.isLegacyBuiltInInstructions(profile.instructions),
               let smartExpression {
                return PromptProfile(
                    id: profile.id,
                    name: smartExpression.name,
                    instructions: smartExpression.instructions,
                    createdAt: profile.createdAt
                )
            }

            return profile
        }
    }

    func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemService.setEnabled(enabled)
            launchAtLogin = LoginItemService.isEnabled
        } catch {
            launchAtLogin = LoginItemService.isEnabled
            errorMessage = "无法更新开机启动：\(error.localizedDescription)"
        }
    }

    func saveDictionaryEntry(_ entry: DictionaryEntry) {
        if let index = dictionaryEntries.firstIndex(where: { $0.id == entry.id }) {
            dictionaryEntries[index] = entry
        } else {
            dictionaryEntries.append(entry)
        }
        dictionaryEntries.sort {
            $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending
        }
        persistData()
    }

    func deleteDictionaryEntry(_ entry: DictionaryEntry) {
        dictionaryEntries.removeAll { $0.id == entry.id }
        persistData()
    }

    func deleteHistoryItem(_ item: HistoryItem) {
        historyItems.removeAll { $0.id == item.id }
        if selectedHistoryItem?.id == item.id {
            selectedHistoryItem = nil
        }
        persistData()
    }

    func copyHistoryItem(_ item: HistoryItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
        showNotice("已复制此条内容")
        recordDiagnostic("历史记录", "已复制一条历史文字")
    }

    func dismissNotice() {
        noticeDismissTask?.cancel()
        noticeDismissTask = nil
        noticeMessage = nil
    }

    func requestAccessibilityPermission() {
        recordDiagnostic("权限", "请求辅助功能权限")
        AccessibilityTextInserter.requestPermissionPrompt()
        Task { @MainActor [weak self] in
            for _ in 0..<30 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.accessibilityPermission = .current
                if self.accessibilityPermission == .authorized {
                    self.recordDiagnostic("权限", "辅助功能权限已授权")
                    return
                }
            }
        }
    }

    func handleMicrophonePermissionAction() {
        switch microphonePermission {
        case .notDetermined:
            recordDiagnostic("权限", "请求麦克风权限")
            Task { @MainActor [weak self] in
                guard let self else { return }
                let granted = await self.audioCapture.requestPermission()
                self.microphonePermission = self.audioCapture.permissionState
                self.recordDiagnostic("权限", granted ? "麦克风权限已授权" : "麦克风权限未授权")
            }
        case .denied, .restricted:
            openPrivacySettings(anchor: "Privacy_Microphone")
        case .authorized:
            break
        }
    }

    func openAccessibilitySettings() {
        openPrivacySettings(anchor: "Privacy_Accessibility")
    }

    func requestInputMonitoringPermission() {
        recordDiagnostic("权限", "请求输入监控权限")
        let probe = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        )
        if let probe {
            CFMachPortInvalidate(probe)
        }
        InputMonitoringPermissionState.request()
        inputMonitoringPermission = .current
        openInputMonitoringSettings()
        Task { @MainActor [weak self] in
            for _ in 0..<30 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.refreshPermissionStates()
                if self.inputMonitoringPermission == .authorized {
                    self.recordDiagnostic("权限", "输入监控权限已授权")
                    return
                }
            }
        }
    }

    func openInputMonitoringSettings() {
        openPrivacySettings(anchor: "Privacy_ListenEvent")
    }

    func revealCurrentApp() {
        recordDiagnostic("权限", "在 Finder 中定位当前运行副本")
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func refreshPermissionStates() {
        microphonePermission = audioCapture.permissionState
        let previousAccessibilityPermission = accessibilityPermission
        accessibilityPermission = .current
        let previousInputMonitoringPermission = inputMonitoringPermission
        inputMonitoringPermission = .current
        if shortcutChoice.requiresInputMonitoring,
           previousInputMonitoringPermission != .authorized,
           inputMonitoringPermission == .authorized,
           (!shortcutChoice.requiresAccessibilityControl || accessibilityPermission == .authorized) {
            shortcutMonitor.start(choice: shortcutChoice) { [weak self] in
                self?.toggleVoiceInput()
            }
            recordDiagnostic("权限", "输入监控权限已授权，快捷键监听已重启")
        }
        if shortcutChoice.requiresAccessibilityControl,
           previousAccessibilityPermission != .authorized,
           accessibilityPermission == .authorized,
           (!shortcutChoice.requiresInputMonitoring || inputMonitoringPermission == .authorized) {
            shortcutMonitor.start(choice: shortcutChoice) { [weak self] in
                self?.toggleVoiceInput()
            }
            recordDiagnostic("权限", "辅助功能权限已授权，Fn 全局监听已重启")
        }
    }

    func copyDiagnosticReport() {
        let report = DiagnosticReportBuilder.build(
            entries: diagnosticEntries,
            readiness: readiness,
            microphonePermission: microphonePermission,
            accessibilityPermission: accessibilityPermission,
            model: QwenRealtimeClient.model,
            inputTokens: lastInputTokens,
            outputTokens: lastOutputTokens
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        recordDiagnostic("诊断", "诊断报告已复制到剪贴板")
    }

    func clearDiagnostics() {
        diagnosticEntries.removeAll()
        recordDiagnostic("诊断", "当前会话诊断已清空")
    }

    private func handleFinalText(_ text: String) {
        let finalText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalText.isEmpty else {
            handleRealtimeError(QwenRealtimeError.server("模型未返回文字"))
            return
        }

        latestFinalText = finalText
        let recordingDuration = lastRecordingDuration
        let processingDuration = processingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let inserted = AccessibilityTextInserter.insertIntoFocusedElement(finalText)

        if inserted {
            floatingPanel.hide()
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(finalText, forType: .string)
            floatingPanel.show(state: .clipboard(preview: finalText))
        }

        historyItems.insert(
            .init(
                date: .now,
                text: finalText,
                recordingDuration: recordingDuration,
                processingDuration: processingDuration,
                model: QwenRealtimeClient.model,
                inputTokens: lastInputTokens,
                outputTokens: lastOutputTokens
            ),
            at: 0
        )
        latestHistoryItemID = historyItems[0].id
        persistData()
        recordDiagnostic(
            "输出",
            String(format: "完成，文字 %d 字，停止到结果 %.2f 秒，输出方式：%@", finalText.count, processingDuration, inserted ? "输入框" : "剪贴板")
        )
        lastRecordingSummary = String(
            format: "完成：录音 %.1f 秒，停止到结果 %.2f 秒",
            recordingDuration,
            processingDuration
        )
        responseTimeoutTask?.cancel()
        responseTimeoutTask = nil
        voiceSessionState = .idle
        recordingStartedAt = nil
        processingStartedAt = nil
    }

    private func handleRealtimeError(_ error: Error) {
        AccessibilityTextInserter.clearTrackedElement()
        audioCapture.stop()
        responseTimeoutTask?.cancel()
        responseTimeoutTask = nil
        realtimeClient.disconnect()
        floatingPanel.hide()
        voiceSessionState = .idle
        recordingStartedAt = nil
        processingStartedAt = nil
        errorMessage = error.localizedDescription
        recordDiagnostic("错误", error.localizedDescription)
    }

    private func persistData() {
        do {
            try persistenceStore.save(
                AppDataSnapshot(history: historyItems, dictionary: dictionaryEntries)
            )
        } catch {
            errorMessage = "无法保存本地数据：\(error.localizedDescription)"
        }
    }

    private func syncCurrentPromptProfile() {
        guard let index = promptProfiles.firstIndex(where: { $0.id == selectedPromptProfileID }),
              promptProfiles[index].instructions != promptInstructions else {
            return
        }
        promptProfiles[index].instructions = promptInstructions
        persistPromptProfiles()
    }

    private func persistPromptProfiles() {
        guard let data = try? JSONEncoder().encode(promptProfiles) else { return }
        UserDefaults.standard.set(data, forKey: Self.promptProfilesDefaultsKey)
        UserDefaults.standard.set(selectedPromptProfileID.uuidString, forKey: Self.selectedPromptProfileDefaultsKey)
    }

    private static func loadPromptProfiles() -> [PromptProfile] {
        guard let data = UserDefaults.standard.data(forKey: promptProfilesDefaultsKey),
              let profiles = try? JSONDecoder().decode([PromptProfile].self, from: data) else {
            return []
        }
        return profiles.filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func showNotice(_ message: String) {
        noticeDismissTask?.cancel()
        noticeMessage = message
        noticeDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.noticeMessage = nil
        }
    }

    private func openPrivacySettings(anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        recordDiagnostic("权限", "打开 macOS 隐私与安全设置：\(anchor)")
        NSWorkspace.shared.open(url)
    }

    private func recordDiagnostic(_ category: String, _ message: String) {
        diagnosticEntries.append(.init(category: category, message: message))
        if diagnosticEntries.count > 100 {
            diagnosticEntries.removeFirst(diagnosticEntries.count - 100)
        }
    }
}
