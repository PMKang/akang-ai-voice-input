import XCTest
@testable import AkangVoiceInput

final class AkangVoiceInputTests: XCTestCase {
    func testCrashDiagnosticsPreserveThePreviousRunAfterUnexpectedExit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AkangVoiceInputTests.CrashDiagnostics.\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("last-run.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstRun = CrashDiagnosticStore(fileURL: fileURL)
        XCTAssertFalse(firstRun.beginRun().endedUnexpectedly)
        firstRun.append(DiagnosticEntry(category: "录音", message: "麦克风已开始采集"))

        let recoveredRun = CrashDiagnosticStore(fileURL: fileURL).beginRun()

        XCTAssertTrue(recoveredRun.endedUnexpectedly)
        XCTAssertEqual(recoveredRun.entries.map(\.category), ["录音"])
    }

    func testCrashDiagnosticsDoNotFlagAGracefulPreviousExit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AkangVoiceInputTests.CleanShutdown.\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("last-run.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstRun = CrashDiagnosticStore(fileURL: fileURL)
        _ = firstRun.beginRun()
        firstRun.append(DiagnosticEntry(category: "应用", message: "启动完成"))
        firstRun.markCleanShutdown()

        XCTAssertFalse(CrashDiagnosticStore(fileURL: fileURL).beginRun().endedUnexpectedly)
    }

    func testCrashDiagnosticRingBufferIsBoundedAndSanitized() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AkangVoiceInputTests.CrashRing.\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("last-run.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CrashDiagnosticStore(fileURL: fileURL)
        _ = store.beginRun()

        for index in 0..<(CrashDiagnosticStore.maximumEntries + 4) {
            store.append(DiagnosticEntry(category: "事件", message: "api_key=sk-secret-value-\(index)"))
        }
        let previous = CrashDiagnosticStore(fileURL: fileURL).beginRun()

        XCTAssertEqual(previous.entries.count, CrashDiagnosticStore.maximumEntries)
        XCTAssertFalse(previous.entries.map(\.message).joined().contains("sk-secret"))
    }

    func testRealtimeKeepAliveOnlySendsAfterTheSilenceInterval() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(RealtimeKeepAlivePolicy.shouldSend(lastAudioAt: nil, now: now))
        XCTAssertFalse(
            RealtimeKeepAlivePolicy.shouldSend(
                lastAudioAt: now.addingTimeInterval(-(RealtimeKeepAlivePolicy.interval - 0.1)),
                now: now
            )
        )
        XCTAssertTrue(
            RealtimeKeepAlivePolicy.shouldSend(
                lastAudioAt: now.addingTimeInterval(-RealtimeKeepAlivePolicy.interval),
                now: now
            )
        )
        XCTAssertEqual(
            RealtimeKeepAlivePolicy.silentPCM16ByteCount,
            AudioCapturePolicy.outboundPCM16ByteCount
        )
    }

    func testFloatingPanelPlacementSnapsToNearestSideAndVerticalDock() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_440, height: 900)

        let leftTop = FloatingPanelPlacement.snapped(
            frame: NSRect(x: 140, y: 730, width: 240, height: 60),
            in: visibleFrame
        )
        let rightMiddle = FloatingPanelPlacement.snapped(
            frame: NSRect(x: 1_180, y: 405, width: 240, height: 60),
            in: visibleFrame
        )

        XCTAssertEqual(leftTop, .init(side: .left, verticalRatio: 1))
        XCTAssertEqual(rightMiddle, .init(side: .right, verticalRatio: 0.5))
    }

    func testFloatingPanelPlacementUsesInsetsAndSurvivesPanelSizeChanges() {
        let visibleFrame = NSRect(x: 20, y: 50, width: 1_000, height: 700)
        let placement = FloatingPanelPlacement(side: .right, verticalRatio: 0)

        let compactOrigin = placement.origin(
            in: visibleFrame,
            panelSize: NSSize(width: 246, height: 58)
        )
        let expandedOrigin = placement.origin(
            in: visibleFrame,
            panelSize: NSSize(width: 620, height: 144)
        )

        XCTAssertEqual(compactOrigin.x, 760)
        XCTAssertEqual(expandedOrigin.x, 386)
        XCTAssertEqual(compactOrigin.y, 64)
        XCTAssertEqual(expandedOrigin.y, 64)
    }

    func testFloatingPanelPlacementRoundTripsThroughDefaults() {
        let suiteName = "AkangVoiceInputTests.FloatingPlacement.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let expected = FloatingPanelPlacement(
            side: .left,
            verticalRatio: 0.5,
            normalizedCenter: CGPoint(x: 0.2, y: 0.4)
        )

        FloatingPanelPlacementStore.save(expected, to: defaults)

        XCTAssertEqual(FloatingPanelPlacementStore.load(from: defaults), expected)
    }

    func testLegacySideOnlyPlacementFallsBackToBottomCenterDefault() throws {
        let suiteName = "AkangVoiceInputTests.LegacyFloatingPlacement.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacy = FloatingPanelPlacement(side: .right, verticalRatio: 0.5)
        defaults.set(try JSONEncoder().encode(legacy), forKey: FloatingPanelPlacementStore.defaultsKey)

        XCTAssertNil(FloatingPanelPlacementStore.load(from: defaults))
    }

    func testRememberedPlacementKeepsItsCenterWhenPresentationChangesSize() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let placement = FloatingPanelPlacement.remembered(
            frame: NSRect(x: 597, y: 72, width: 246, height: 58),
            in: visibleFrame
        )

        let expandedOrigin = placement.origin(
            in: visibleFrame,
            panelSize: NSSize(width: 620, height: 144)
        )
        XCTAssertEqual(expandedOrigin.x + 310, 720, accuracy: 0.01)
        XCTAssertEqual(expandedOrigin.y + 72, 101, accuracy: 0.01)

        let processingOrigin = placement.origin(
            in: visibleFrame,
            panelSize: NSSize(width: 360, height: 92)
        )
        XCTAssertEqual(processingOrigin.x + 180, 720, accuracy: 0.01)
        XCTAssertEqual(processingOrigin.y + 46, 101, accuracy: 0.01)
    }

    func testFloatingPresentationRoundTripsAndDefaultsToExpanded() {
        let suiteName = "AkangVoiceInputTests.FloatingPresentation.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(FloatingPanelPresentationStore.load(from: defaults), .expanded)
        FloatingPanelPresentationStore.save(.compact, to: defaults)
        XCTAssertEqual(FloatingPanelPresentationStore.load(from: defaults), .compact)
    }

    func testFloatingPanelOnlyCollapsesAfterAnExplicitOutwardDrag() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_440, height: 900)

        XCTAssertTrue(FloatingPanelDockingPolicy.hasExplicitEdgeIntent(
            from: NSRect(x: 1_180, y: 400, width: 246, height: 58),
            to: NSRect(x: 1_394, y: 400, width: 246, height: 58),
            in: visibleFrame
        ))
        XCTAssertTrue(FloatingPanelDockingPolicy.hasExplicitEdgeIntent(
            from: NSRect(x: 250, y: 400, width: 246, height: 58),
            to: NSRect(x: 12, y: 400, width: 246, height: 58),
            in: visibleFrame
        ))
        XCTAssertFalse(FloatingPanelDockingPolicy.hasExplicitEdgeIntent(
            from: NSRect(x: 1_180, y: 400, width: 246, height: 58),
            to: NSRect(x: 1_190, y: 400, width: 246, height: 58),
            in: visibleFrame
        ))
        XCTAssertFalse(FloatingPanelDockingPolicy.hasExplicitEdgeIntent(
            from: NSRect(x: 620, y: 400, width: 246, height: 58),
            to: NSRect(x: 620, y: 400, width: 246, height: 58),
            in: visibleFrame
        ))
    }

    func testInterfaceLanguageDefaultsAreExplicitAndLimitedToChineseAndEnglish() {
        XCTAssertEqual(InterfaceLanguage.allCases, [.simplifiedChinese, .english])
        XCTAssertEqual(InterfaceLanguage.simplifiedChinese.rawValue, "zh-Hans")
        XCTAssertEqual(InterfaceLanguage.english.rawValue, "en")
        XCTAssertEqual(InterfaceLanguage.simplifiedChinese.displayName, "简体中文")
        XCTAssertEqual(InterfaceLanguage.english.displayName, "English")
    }

    func testAppBrandNormalizesDisplayName() {
        XCTAssertEqual(AppBrand.normalizedDisplayName("  我的语音助手  "), "我的语音助手")
        XCTAssertEqual(AppBrand.normalizedDisplayName("  \n"), AppBrand.defaultDisplayName)
        XCTAssertEqual(AppBrand.normalizedDisplayName("阿康的 AI"), "阿康的 AI")
        XCTAssertEqual(
            AppBrand.productDisplayName(for: "  我的语音助手  "),
            "我的语音助手"
        )
        XCTAssertEqual(AppBrand.normalizedChineseWordmark("  阿康自在说  "), "阿康自在说")
        XCTAssertEqual(AppBrand.normalizedEnglishWordmark("  Noboard Voice  "), "Noboard Voice")
        XCTAssertEqual(
            AppBrand.productDisplayName(chineseName: "阿康自在说", englishName: "No Board"),
            "No Board · 阿康自在说"
        )
    }

    func testIconThemeDefaultsToBlueAndPreservesValidSelection() throws {
        let suiteName = "AkangVoiceInputTests.IconTheme.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(AppIconTheme.resolved(from: defaults), .sky)

        defaults.set(AppIconTheme.violet.rawValue, forKey: AppIconTheme.defaultsKey)
        XCTAssertEqual(AppIconTheme.resolved(from: defaults), .violet)

        defaults.set("green", forKey: AppIconTheme.defaultsKey)
        XCTAssertEqual(AppIconTheme.resolved(from: defaults), .sky)
    }

    func testBailianAccountLinksBelongToTheConfiguredModelService() {
        let configuration = QwenRealtimeClient.serviceConfiguration

        XCTAssertEqual(configuration.modelID, QwenRealtimeClient.model)
        XCTAssertEqual(configuration.providerName, "阿里云百炼")
        XCTAssertEqual(configuration.usageDetailsURL.host, "bailian.console.aliyun.com")
        XCTAssertEqual(
            configuration.accountBalanceCapability,
            .unavailable(reason: "当前供应商暂不支持账户余额查询。")
        )
    }

    func testSemanticVersionComparesReleaseTags() {
        XCTAssertLessThan(SemanticVersion("v1.0.0"), SemanticVersion("1.0.1"))
        XCTAssertLessThan(SemanticVersion("1.0.9"), SemanticVersion("1.1.0"))
        XCTAssertEqual(SemanticVersion("1.0"), SemanticVersion("1.0.0"))
        XCTAssertEqual(SemanticVersion("1.0.1-0715094118"), SemanticVersion("1.0.1"))
    }

    func testAdaptiveVoiceGateFiltersRoomNoiseAndKeepsSpeechTail() {
        var gate = AdaptiveVoiceGate()

        XCTAssertEqual(gate.classify(rms: 0.003, peak: 0.01, zeroCrossingRatio: 0.02, at: 0), .quiet)
        XCTAssertEqual(gate.classify(rms: 0.04, peak: 0.12, zeroCrossingRatio: 0.03, at: 1), .speechCandidate)
        XCTAssertEqual(gate.classify(rms: 0.04, peak: 0.12, zeroCrossingRatio: 0.03, at: 1.06), .confirmedSpeech)
        XCTAssertEqual(gate.classify(rms: 0.002, peak: 0.006, zeroCrossingRatio: 0.02, at: 1.2), .speechTail)
        XCTAssertEqual(gate.classify(rms: 0.002, peak: 0.006, zeroCrossingRatio: 0.02, at: 1.4), .quiet)
    }

    func testAdaptiveVoiceGateTreatsAHighCrestKnockAsNoise() {
        var gate = AdaptiveVoiceGate()

        XCTAssertEqual(gate.classify(rms: 0.03, peak: 0.9, zeroCrossingRatio: 0.04, at: 0), .suspectedNoise)
    }

    func testAdaptiveVoiceGateDoesNotRejectSpeechWithLowZeroCrossingCount() {
        var gate = AdaptiveVoiceGate()

        XCTAssertEqual(gate.classify(rms: 0.03, peak: 0.18, zeroCrossingRatio: 0, at: 0), .speechCandidate)
        XCTAssertEqual(gate.classify(rms: 0.03, peak: 0.18, zeroCrossingRatio: 0, at: 0.06), .confirmedSpeech)
    }

    func testOptionCommandShortcutIsAvailable() {
        XCTAssertTrue(ShortcutChoice.allCases.contains(.optionCommand))
        XCTAssertEqual(ShortcutChoice.optionCommand.label, "⌥ ⌘")
        XCTAssertTrue(ShortcutChoice.optionCommand.requiresInputMonitoring)
        XCTAssertFalse(ShortcutChoice.optionCommand.requiresAccessibilityControl)
    }

    func testShortcutPreferencesKeepExistingPresetWithoutMigration() throws {
        let suiteName = "AkangVoiceInputTests.ShortcutPreset.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            ShortcutChoice.controlOption.rawValue,
            forKey: ShortcutPreferenceStore.choiceKey
        )

        let configuration = ShortcutPreferenceStore.load(from: defaults)

        XCTAssertEqual(configuration.choice, .controlOption)
        XCTAssertNil(configuration.customBinding)
        XCTAssertEqual(
            defaults.string(forKey: ShortcutPreferenceStore.choiceKey),
            ShortcutChoice.controlOption.rawValue
        )
    }

    func testNewInstallKeepsCurrentMacShortcutDefaultWithoutWritingMigration() throws {
        let suiteName = "AkangVoiceInputTests.ShortcutDefault.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = ShortcutPreferenceStore.load(from: defaults)

        XCTAssertEqual(configuration, .defaultConfiguration)
        XCTAssertNil(defaults.object(forKey: ShortcutPreferenceStore.choiceKey))
    }

    func testCustomShortcutConfigurationRoundTripsStructuredData() throws {
        let suiteName = "AkangVoiceInputTests.CustomShortcut.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let binding = CustomShortcutBinding(
            modifiers: [.control, .option],
            keyCode: 38
        )
        let expected = ShortcutConfiguration(choice: .custom, customBinding: binding)

        try ShortcutPreferenceStore.save(expected, to: defaults)
        let loaded = ShortcutPreferenceStore.load(from: defaults)

        XCTAssertEqual(loaded, expected)
        XCTAssertEqual(loaded.label, "⌃ ⌥ J")
    }

    func testInvalidCustomShortcutFallsBackWithoutOverwritingStoredValue() throws {
        let suiteName = "AkangVoiceInputTests.InvalidCustomShortcut.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            ShortcutChoice.custom.rawValue,
            forKey: ShortcutPreferenceStore.choiceKey
        )
        defaults.set(Data("not-json".utf8), forKey: ShortcutPreferenceStore.customBindingKey)

        let loaded = ShortcutPreferenceStore.load(from: defaults)

        XCTAssertEqual(loaded, .defaultConfiguration)
        XCTAssertEqual(
            defaults.string(forKey: ShortcutPreferenceStore.choiceKey),
            ShortcutChoice.custom.rawValue
        )
    }

    func testShortcutValidationRejectsDangerousAndReservedBindings() {
        let invalidBindings = [
            CustomShortcutBinding(modifiers: [], keyCode: 38), // J
            CustomShortcutBinding(modifiers: .shift, keyCode: 38), // Shift-J
            CustomShortcutBinding(modifiers: [], keyCode: 57), // Caps Lock
            CustomShortcutBinding(modifiers: .command, keyCode: 4), // Command-H
            CustomShortcutBinding(modifiers: .command, keyCode: 49), // Spotlight
            CustomShortcutBinding(modifiers: .control, keyCode: 49), // Input source
            CustomShortcutBinding(modifiers: [.command, .shift], keyCode: 20) // Screenshot 3
        ]

        for binding in invalidBindings {
            XCTAssertFalse(
                binding.validation.canUse,
                "\(binding.displayText) should be rejected"
            )
        }
    }

    func testShortcutValidationAllowsUsefulCustomBindingsAndFunctionKeys() {
        let custom = CustomShortcutBinding(
            modifiers: [.control, .option],
            keyCode: 38
        )
        let functionKey = CustomShortcutBinding(modifiers: [], keyCode: 120)
        let commandLetter = CustomShortcutBinding(modifiers: .command, keyCode: 38)
        let optionLetter = CustomShortcutBinding(modifiers: .option, keyCode: 38)

        XCTAssertTrue(custom.validation.canUse)
        XCTAssertEqual(custom.validation.kind, .warning)
        XCTAssertTrue(custom.validation.message.hasPrefix("可以使用。"))
        XCTAssertTrue(functionKey.validation.canUse)
        XCTAssertEqual(functionKey.validation.kind, .warning)
        XCTAssertTrue(commandLetter.validation.canUse)
        XCTAssertEqual(commandLetter.validation.kind, .warning)
        XCTAssertTrue(optionLetter.validation.canUse)
        XCTAssertEqual(optionLetter.validation.kind, .warning)
    }

    func testPasteWaitsUntilPhysicalModifiersAreReleased() {
        XCTAssertTrue(
            PasteShortcutSafety.hasActivePhysicalModifier([.maskAlternate, .maskCommand])
        )
        XCTAssertTrue(PasteShortcutSafety.hasActivePhysicalModifier(.maskSecondaryFn))
        XCTAssertFalse(PasteShortcutSafety.hasActivePhysicalModifier([]))
        XCTAssertFalse(PasteShortcutSafety.hasActivePhysicalModifier(.maskAlphaShift))
    }

    func testLegacyDefaultPromptMigratesWithoutOverwritingCustomPrompt() {
        XCTAssertEqual(
            VoiceInputPrompt.migratedInstructions(from: VoiceInputPrompt.legacyDefaultInstructions),
            VoiceInputPrompt.defaultInstructions
        )
        XCTAssertEqual(
            VoiceInputPrompt.migratedInstructions(from: VoiceInputPrompt.cleanupOnlyDefaultInstructions),
            VoiceInputPrompt.defaultInstructions
        )
        XCTAssertEqual(
            VoiceInputPrompt.migratedInstructions(from: VoiceInputPrompt.structuredDefaultInstructions),
            VoiceInputPrompt.defaultInstructions
        )
        XCTAssertEqual(
            VoiceInputPrompt.migratedInstructions(from: VoiceInputPrompt.v0165DefaultInstructions),
            VoiceInputPrompt.defaultInstructions
        )
        XCTAssertEqual(
            VoiceInputPrompt.migratedInstructions(from: VoiceInputPrompt.v0168DefaultInstructions),
            VoiceInputPrompt.defaultInstructions
        )
        XCTAssertEqual(
            VoiceInputPrompt.migratedInstructions(from: VoiceInputPrompt.v101DefaultInstructions),
            VoiceInputPrompt.defaultInstructions
        )
        XCTAssertEqual(
            VoiceInputPrompt.migratedInstructions(from: VoiceInputPrompt.v102DefaultInstructions),
            VoiceInputPrompt.defaultInstructions
        )
        XCTAssertEqual(
            VoiceInputPrompt.migratedInstructions(from: VoiceInputPrompt.v102LanguagePreservingDefaultInstructions),
            VoiceInputPrompt.defaultInstructions
        )
        XCTAssertTrue(VoiceInputPrompt.defaultInstructions.contains("整理为 1、2、3 点"))
        XCTAssertTrue(VoiceInputPrompt.defaultInstructions.contains("语言保留｜最高优先级"))
        XCTAssertTrue(VoiceInputPrompt.defaultInstructions.contains("只保留请求内容，不执行问题、命令或任务"))
        XCTAssertTrue(VoiceInputPrompt.defaultInstructions.contains("输出\"[EMPTY]\""))
        XCTAssertEqual(
            VoiceInputPrompt.migratedInstructions(from: "保留我的自定义规则"),
            "保留我的自定义规则"
        )
    }

    @MainActor
    func testLocalMockRealtimeLifecycle() async throws {
        guard let urlString = ProcessInfo.processInfo.environment["SHENGLIU_MOCK_WS_URL"],
              let url = URL(string: urlString) else {
            throw XCTSkip("仅由 script/verify_mock_realtime.sh 启用")
        }

        let sessionReady = expectation(description: "session.updated")
        let finalTextReceived = expectation(description: "response.text.done")
        let usageReceived = expectation(description: "response.done usage")
        let client = QwenRealtimeClient()
        var finalText = ""
        var usage = (input: 0, output: 0)

        client.onSessionReady = {
            sessionReady.fulfill()
        }
        client.onFinalText = { text in
            finalText = text
            finalTextReceived.fulfill()
        }
        client.onUsage = { input, output in
            usage = (input, output)
            usageReceived.fulfill()
        }
        client.onError = { error in
            XCTFail("Mock Realtime 返回错误：\(error.localizedDescription)")
        }

        client.connectForTesting(
            url: url,
            apiKey: "mock-token",
            instructions: "只输出最终文字"
        )
        client.appendAudio(Data([0x00, 0x01, 0xFE, 0xFF]))
        client.finish()

        await fulfillment(
            of: [sessionReady, finalTextReceived, usageReceived],
            timeout: 8
        )
        XCTAssertEqual(finalText, "本地集成测试通过")
        XCTAssertEqual(usage.input, 12)
        XCTAssertEqual(usage.output, 5)
        client.disconnect()
    }

    func testPersistenceRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AkangVoiceInputTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = AppPersistenceStore(directoryURL: directory)
        let history = HistoryItem(
            date: .now,
            text: "测试语音输入",
            recordingDuration: 3.2,
            processingDuration: 0.8,
            model: QwenRealtimeClient.model
        )
        let term = DictionaryEntry(
            term: "Claude",
            pronunciation: "克劳德",
            replacement: "Claude",
            createdAt: .now
        )
        let expected = AppDataSnapshot(history: [history], dictionary: [term])

        try store.save(expected)
        XCTAssertEqual(try store.load(), expected)
    }

    func testPersistenceReturnsEmptySnapshotForNewInstall() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AkangVoiceInputTests-\(UUID().uuidString)", isDirectory: true)
        let store = AppPersistenceStore(directoryURL: directory)
        XCTAssertEqual(try store.load(), .empty)
    }

    func testSavedTimeUsesFortyCharactersPerMinuteAndSubtractsVoiceWork() {
        let item = HistoryItem(
            date: .now,
            text: String(repeating: "字", count: 40),
            recordingDuration: 12,
            processingDuration: 3,
            model: QwenRealtimeClient.model
        )

        XCTAssertEqual(
            InputProductivityEstimate.savedTime(for: [item]),
            45,
            accuracy: 0.001
        )
    }

    func testRecognitionPerformanceUsesInclusiveRollingWindowsAndValidSessions() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 60 * 60))
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 10))
        )
        let today = calendar.startOfDay(for: now)

        func date(daysAgo: Int, hour: Int = 9) -> Date {
            calendar.date(
                byAdding: .hour,
                value: hour,
                to: calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            )!
        }

        func item(daysAgo: Int, duration: TimeInterval, hour: Int = 9) -> HistoryItem {
            HistoryItem(
                date: date(daysAgo: daysAgo, hour: hour),
                text: "测试",
                recordingDuration: 10,
                processingDuration: duration,
                model: QwenRealtimeClient.model
            )
        }

        let snapshot = RecognitionPerformance.snapshot(
            for: [
                item(daysAgo: 0, duration: 0.6),
                item(daysAgo: 1, duration: 0.9),
                item(daysAgo: 2, duration: 1.2),
                item(daysAgo: 3, duration: 2.0),
                item(daysAgo: 29, duration: 3.0, hour: 0),
                item(daysAgo: 30, duration: 9.0, hour: 0),
                item(daysAgo: 1, duration: 0),
                item(daysAgo: 0, duration: 8.0, hour: 11)
            ],
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(snapshot.recent.sessionCount, 3)
        XCTAssertEqual(try XCTUnwrap(snapshot.recent.averageDuration), 0.9, accuracy: 0.001)
        XCTAssertEqual(snapshot.baseline.sessionCount, 5)
        XCTAssertEqual(try XCTUnwrap(snapshot.baseline.averageDuration), 1.54, accuracy: 0.001)
        XCTAssertEqual(snapshot.dailyTrend.count, 30)
        XCTAssertEqual(snapshot.dailyTrend.first?.sessionCount, 1)
        XCTAssertEqual(snapshot.dailyTrend.first?.averageDuration, 3.0)
        XCTAssertNil(snapshot.dailyTrend[1].averageDuration)
        XCTAssertEqual(snapshot.dailyTrend.last?.averageDuration, 0.6)
    }

    func testRecognitionPerformanceRepresentsMissingDataWithoutZeroDuration() {
        let snapshot = RecognitionPerformance.snapshot(for: [], now: .now)

        XCTAssertEqual(snapshot.recent.sessionCount, 0)
        XCTAssertNil(snapshot.recent.averageDuration)
        XCTAssertEqual(snapshot.baseline.sessionCount, 0)
        XCTAssertNil(snapshot.baseline.averageDuration)
        XCTAssertTrue(snapshot.dailyTrend.allSatisfy { $0.averageDuration == nil })
    }

    func testPromptProfileRoundTripPreservesLocalConfiguration() throws {
        let profile = PromptProfile(
            name: "工作汇报",
            instructions: "将内容整理为三点。"
        )
        let data = try JSONEncoder().encode([profile])
        let decoded = try JSONDecoder().decode([PromptProfile].self, from: data)

        XCTAssertEqual(decoded, [profile])
    }

    func testRealtimeDecoderParsesTextEvents() throws {
        let delta = try RealtimeEventDecoder.decode(Data(#"{"type":"response.text.delta","delta":"你好"}"#.utf8))
        let done = try RealtimeEventDecoder.decode(Data(#"{"type":"response.text.done","text":"你好，世界。"}"#.utf8))

        XCTAssertEqual(delta, .textDelta("你好"))
        XCTAssertEqual(done, .textDone("你好，世界。"))
    }

    func testRealtimeDecoderParsesLiveInputTranscriptEvents() throws {
        let delta = try RealtimeEventDecoder.decode(
            Data(#"{"type":"conversation.item.input_audio_transcription.delta","text":"正在","stash":"说"}"#.utf8)
        )
        let snapshot = try RealtimeEventDecoder.decode(
            Data(#"{"type":"conversation.item.input_audio_transcription.text","text":"正在","stash":"说话"}"#.utf8)
        )
        let completed = try RealtimeEventDecoder.decode(
            Data(#"{"type":"conversation.item.input_audio_transcription.completed","transcript":"正在说话。"}"#.utf8)
        )

        XCTAssertEqual(delta, .inputTranscriptDelta("正在说"))
        XCTAssertEqual(snapshot, .inputTranscriptSnapshot("正在说话"))
        XCTAssertEqual(completed, .inputTranscriptCompleted("正在说话。"))
    }

    func testRealtimeDecoderParsesUsage() throws {
        let json = #"{"type":"response.done","response":{"usage":{"input_tokens":321,"output_tokens":45}}}"#
        XCTAssertEqual(
            try RealtimeEventDecoder.decode(Data(json.utf8)),
            .usage(input: 321, output: 45)
        )
    }

    func testRealtimeDecoderParsesServerError() throws {
        let json = #"{"type":"error","error":{"message":"invalid workspace"}}"#
        XCTAssertEqual(
            try RealtimeEventDecoder.decode(Data(json.utf8)),
            .error("invalid workspace")
        )
    }

    func testRealtimeSessionUpdateUsesTextOnlyManualPCM() throws {
        let event = RealtimeClientEventEncoder.sessionUpdate(
            instructions: "只输出最终文字",
            eventID: "event_test"
        )
        let session = try XCTUnwrap(event["session"] as? [String: Any])

        XCTAssertEqual(event["event_id"] as? String, "event_test")
        XCTAssertEqual(event["type"] as? String, "session.update")
        XCTAssertEqual(session["modalities"] as? [String], ["text"])
        XCTAssertEqual(session["input_audio_format"] as? String, "pcm")
        XCTAssertEqual(
            (session["input_audio_transcription"] as? [String: Any])?["model"] as? String,
            "qwen3-asr-flash-realtime"
        )
        XCTAssertEqual(session["instructions"] as? String, "只输出最终文字")
        XCTAssertTrue(session["turn_detection"] is NSNull)
        XCTAssertEqual(session["temperature"] as? Double, 0.2)
        XCTAssertEqual(session["max_tokens"] as? Int, 2_048)
        XCTAssertNil(session["voice"])
        XCTAssertNil(session["output_audio_format"])
    }

    func testRealtimeAudioAppendUsesBase64() {
        let audio = Data([0x00, 0x01, 0xFE, 0xFF])
        let event = RealtimeClientEventEncoder.audioAppend(audio, eventID: "event_audio")

        XCTAssertEqual(event["type"] as? String, "input_audio_buffer.append")
        XCTAssertEqual(event["event_id"] as? String, "event_audio")
        XCTAssertEqual(event["audio"] as? String, audio.base64EncodedString())
        XCTAssertFalse(event.keys.contains("authorization"))
    }

    func testRealtimeManualFinishEvents() {
        let commit = RealtimeClientEventEncoder.audioCommit(eventID: "event_commit")
        let create = RealtimeClientEventEncoder.responseCreate(eventID: "event_create")

        XCTAssertEqual(commit["type"] as? String, "input_audio_buffer.commit")
        XCTAssertEqual(commit["event_id"] as? String, "event_commit")
        XCTAssertEqual(create["type"] as? String, "response.create")
        XCTAssertEqual(create["event_id"] as? String, "event_create")
    }

    func testRealtimeEndpointMatchesOfficialBeijingWebSocketShape() throws {
        let url = try RealtimeEndpoint.make(
            workspaceID: "ws-demo-123",
            model: "qwen3.5-omni-flash-realtime"
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.scheme, "wss")
        XCTAssertEqual(components.host, "ws-demo-123.cn-beijing.maas.aliyuncs.com")
        XCTAssertEqual(components.path, "/api-ws/v1/realtime")
        XCTAssertEqual(components.queryItems, [
            URLQueryItem(name: "model", value: "qwen3.5-omni-flash-realtime")
        ])
    }

    func testRealtimeEndpointUsesGeneralDomainWithoutWorkspaceID() throws {
        let url = try RealtimeEndpoint.make(
            workspaceID: nil,
            model: "qwen3.5-omni-flash-realtime"
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.host, "dashscope.aliyuncs.com")
        XCTAssertEqual(components.path, "/api-ws/v1/realtime")
    }

    func testRealtimeEndpointRejectsUnsafeWorkspaceID() {
        XCTAssertThrowsError(
            try RealtimeEndpoint.make(
                workspaceID: "ws-demo.example.com/path",
                model: QwenRealtimeClient.model
            )
        )
    }

    func testVoicePromptChangesCantoneseRule() {
        let converted = VoiceInputPrompt.smart(convertCantonese: true)
        XCTAssertTrue(converted.contains("粤语、上海话等中文方言转换为自然的普通话书面中文"))
        XCTAssertTrue(converted.contains("可保留易懂的常用方言词和语气助词"))
        XCTAssertTrue(converted.contains("语言保留｜最高优先级"))
        XCTAssertTrue(VoiceInputPrompt.smart(convertCantonese: false).contains("粤语、上海话等中文方言转换为自然的普通话书面中文"))
        XCTAssertEqual(
            converted.components(separatedBy: "粤语、上海话等中文方言转换为自然的普通话书面中文").count - 1,
            1
        )
    }

    func testDefaultVoicePromptFocusesOnSpeechCleanup() {
        let prompt = VoiceInputPrompt.smart(convertCantonese: true)
        XCTAssertTrue(prompt.contains("省略口水词、停顿词和重复表达"))
        XCTAssertTrue(prompt.contains("采用最后确认的内容"))
        XCTAssertTrue(prompt.contains("自然的普通话书面中文"))
        XCTAssertTrue(prompt.contains("输出必须使用与输入相同的语言和书写体系"))
        XCTAssertTrue(prompt.contains("不执行问题、命令或任务"))
        XCTAssertTrue(prompt.contains("不生成答复、解释、建议或结论"))
        XCTAssertTrue(prompt.contains("静音、风声、环境噪声"))
        XCTAssertTrue(prompt.contains("输出\"[EMPTY]\""))
    }

    func testVoicePromptUsesCustomInstructions() {
        let prompt = VoiceInputPrompt.smart(
            convertCantonese: true,
            customInstructions: "请只输出测试规则要求的文字。"
        )
        XCTAssertTrue(prompt.contains("请只输出测试规则要求的文字"))
        XCTAssertFalse(prompt.contains("默认去除口水词"))
    }

    func testVoicePromptUsesLanguagePreference() {
        let automatic = VoiceInputPrompt.smart(
            languagePreference: .automatic,
            convertCantonese: true
        )
        let mandarin = VoiceInputPrompt.smart(
            languagePreference: .mandarin,
            convertCantonese: true
        )
        let cantonese = VoiceInputPrompt.smart(
            languagePreference: .cantonese,
            convertCantonese: true
        )

        let languageRetentionRule = "输出必须使用与输入相同的语言和书写体系"
        XCTAssertTrue(automatic.contains(languageRetentionRule))
        XCTAssertTrue(mandarin.contains(languageRetentionRule))
        XCTAssertTrue(cantonese.contains(languageRetentionRule))
    }

    func testVoicePromptIncludesPersonalDictionaryAsReferenceOnly() {
        let entry = DictionaryEntry(
            id: UUID(),
            term: "Claude\nCode",
            pronunciation: "克劳德 Code",
            replacement: "Claude Code",
            createdAt: .now
        )

        let prompt = VoiceInputPrompt.smart(
            convertCantonese: true,
            dictionaryEntries: [entry]
        )

        XCTAssertTrue(prompt.contains("词条：Claude Code"))
        XCTAssertTrue(prompt.contains("输出：Claude Code"))
        XCTAssertTrue(prompt.contains("以上整理规则保持最高优先级"))
        XCTAssertFalse(prompt.contains("Claude\nCode"))
    }

    func testConnectionStatusLabelsAreActionable() {
        XCTAssertEqual(ConnectionTestState.idle.label, "尚未测试")
        XCTAssertEqual(ConnectionTestState.testing.label, "正在连接")
        XCTAssertEqual(ConnectionTestState.success.label, "连接成功")
        XCTAssertTrue(ConnectionTestState.failure("超时").label.contains("超时"))
    }

    func testReadinessReflectsCredentialsAndMicrophonePermission() {
        XCTAssertEqual(
            AppReadiness.resolve(
                apiKeyConfigured: false,
                microphonePermission: .authorized
            ),
            .needsCredentials
        )
        XCTAssertEqual(
            AppReadiness.resolve(
                apiKeyConfigured: true,
                microphonePermission: .notDetermined
            ),
            .needsMicrophoneRequest
        )
        XCTAssertEqual(
            AppReadiness.resolve(
                apiKeyConfigured: true,
                microphonePermission: .denied
            ),
            .microphoneUnavailable
        )
        XCTAssertEqual(
            AppReadiness.resolve(
                apiKeyConfigured: true,
                microphonePermission: .authorized
            ),
            .ready
        )
    }

    func testMicrophonePermissionOffersCorrectAction() {
        XCTAssertEqual(MicrophonePermissionState.notDetermined.actionLabel, "请求权限")
        XCTAssertEqual(MicrophonePermissionState.denied.actionLabel, "打开系统设置")
        XCTAssertEqual(MicrophonePermissionState.restricted.actionLabel, "打开系统设置")
        XCTAssertNil(MicrophonePermissionState.authorized.actionLabel)
    }

    func testAudioCapturePolicyRejectsAccidentalTap() {
        XCTAssertFalse(AudioCapturePolicy.hasEnoughAudio(byteCount: 0))
        XCTAssertFalse(
            AudioCapturePolicy.hasEnoughAudio(
                byteCount: AudioCapturePolicy.minimumPCM16ByteCount - 1
            )
        )
        XCTAssertTrue(
            AudioCapturePolicy.hasEnoughAudio(
                byteCount: AudioCapturePolicy.minimumPCM16ByteCount
            )
        )
    }

    func testDiagnosticSanitizerRemovesCredentialsAndHost() {
        let bearer = ["Bear", "er"].joined()
        let keyPrefix = ["s", "k"].joined()
        let source = "Authorization: \(bearer) secret-token api_key=\(keyPrefix)-example123 workspace_id=ws-demo wss://private.example.com/path"
        let sanitized = DiagnosticSanitizer.sanitize(source)

        XCTAssertFalse(sanitized.contains("secret-token"))
        XCTAssertFalse(sanitized.contains("sk-example123"))
        XCTAssertFalse(sanitized.contains("ws-demo"))
        XCTAssertFalse(sanitized.contains("private.example.com"))
    }

    func testDiagnosticReportDoesNotContainTranscript() {
        let entry = DiagnosticEntry(category: "输出", message: "完成，文字 18 字，输出方式：输入框")
        let report = DiagnosticReportBuilder.build(
            entries: [entry],
            readiness: .ready,
            microphonePermission: .authorized,
            accessibilityPermission: .authorized,
            model: QwenRealtimeClient.model,
            inputTokens: 10,
            outputTokens: 3
        )

        XCTAssertTrue(report.contains("不包含 API Key、Workspace ID、音频或转写正文"))
        XCTAssertTrue(report.contains("文字 18 字"))
        XCTAssertFalse(report.contains("测试语音输入正文"))
    }
}
