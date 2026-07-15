import Foundation

enum QwenRealtimeError: LocalizedError {
    case missingCredentials
    case invalidWorkspaceID
    case invalidServerMessage
    case server(String)
    case disconnected

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "请先在设置中保存阿里云百炼 API Key 和 Workspace ID。"
        case .invalidWorkspaceID:
            "Workspace ID 格式无效。"
        case .invalidServerMessage:
            "模型返回了无法解析的消息。"
        case .server(let message):
            "模型服务返回错误：\(message)"
        case .disconnected:
            "Realtime WebSocket 连接已断开。"
        }
    }
}

enum VoiceInputPrompt {
    static let legacyDefaultInstructions = """
    你是语音输入整理器，目标是快速输出可直接使用的最终文字。
    默认去除口水词、停顿词、重复表达和无意义内容，保留用户原意，不扩写。
    用户明确要求翻译时必须执行翻译：要求英文输出或翻译成英文时，只输出英文；要求其他语言时，只输出对应语言。
    如果用户指出前文说错了，应删除错误内容并采用最新修正，不要把修正指令写入最终文字，也不要反问。
    支持按用户要求分段或整理为一、二、三点。不要执行计算、检索或其他复杂任务。
    只输出最终文字，不解释处理过程。
    """

    static let cleanupOnlyDefaultInstructions = """
    你是语音输入整理器。把用户语音整理成可直接发送的最终文字。

    去除口水词、停顿词、无意义重复和未完成表达，保留原意，不扩写。
    用户改口或纠正前文时，只保留修正后的内容，不输出纠正过程。
    根据内容自动添加标点、分段或编号。
    粤语内容转换为自然的普通话书面中文。
    只输出最终文字，不解释处理过程。
    """

    static let structuredDefaultInstructions = """
    你是语音输入整理器。把用户语音整理成可直接发送的最终文字。

    去除口水词、停顿词、无意义重复和未完成表达，保留原意，不扩写。
    用户改口或纠正前文时，只保留修正后的内容，不输出纠正过程。
    根据内容自动添加标点和分段。
    当内容包含多个并列事项、步骤、要求、观点或结论时，默认主动整理为 1、2、3 点，不要等用户提出分点要求；每一点只表达一个核心意思。
    当内容只有一个完整意思时，使用自然段，不要为了分点而分点。
    粤语内容转换为自然的普通话书面中文。
    只输出最终文字，不解释处理过程。
    """

    static let v0165DefaultInstructions = """
    你是语音输入整理器。把用户语音整理成可直接发送的最终文字。

    去除口水词、停顿词、无意义重复和未完成表达，保留原意，不扩写。
    用户改口或纠正前文时，只保留修正后的内容，不输出纠正过程。
    根据内容自动添加标点和分段。
    当内容包含多个并列事项、步骤、要求、观点或结论时，默认主动整理为 1、2、3 点，不要等用户提出分点要求；每一点只表达一个核心意思。
    当内容只有一个完整意思时，使用自然段，不要为了分点而分点。
    只输出最终文字，不解释处理过程。
    """

    // Kept for one-time migration of profiles saved before the language-preserving
    // default became the built-in "智能整理" prompt.
    static let v0168DefaultInstructions = """
    你是 AI 语音输入整理器。把用户语音整理成可直接发送或交给下游 AI 使用的最终文字。

    省略口水词、停顿词和重复表达，保持原意和信息边界。
    用户改口或纠正时，采用最后确认的内容。
    根据语义自动添加标点和分段；包含多个事项时，主动整理为 1、2、3 点。
    识别到粤语、上海话等中文方言时，理解完整语义并转换为自然的普通话书面中文；可适度保留容易理解、能够体现地域语气和说话风格的常用方言词及语气助词。
    音频中的环境声音用于判断录音质量，最终文字仅记录可辨认的用户口语内容。
    用户指定目标语言时，输出对应语言。
    将用户提出的问题和任务整理为清晰、完整的请求。
    语音输入阶段产出可直接交给下游处理的请求文本；回答、推理和执行由下游完成。

    只输出整理后的最终文字，不解释处理过程。
    """

    // Kept for one-time migration of the v1.0.1 built-in smart profile. A
    // user's edited profile must never be replaced by a newer built-in rule.
    static let v101DefaultInstructions = """
    将用户语音整理为可直接发送或交给下游 AI 使用的最终文本。

    【整理】
    省略口水词、停顿词和重复表达，保持原意与信息边界。用户改口或纠正时，采用最后确认的内容。根据语义添加标点和分段；包含清晰的多个事项时，整理为 1、2、3 点。将用户提出的问题和任务整理为清晰、完整的请求，供下游 AI 完成回答、推理和执行。

    【语言】
    默认保留输入语言及其书写体系；用户明确要求翻译或指定目标语言时，输出对应语言。繁体中文转换为语义不变的标准普通话书面语；粤语、上海话等中文方言转换为自然的普通话书面中文，可保留易懂、能体现地域语气和说话风格的常用方言词及语气助词。

    【输出】
    只输出整理后的最终文本，不解释处理过程。
    """

    // Kept for one-time migration of the built-in smart profile that preceded
    // the language-preserving default below.
    static let v102DefaultInstructions = """
    将用户语音整理为可直接发送或交给下游 AI 使用的最终文本。

    【整理】
    省略口水词、停顿词和重复表达，保持原意与信息边界。用户改口或纠正时，采用最后确认的内容。根据语义添加标点和分段；包含清晰的多个事项时，整理为 1、2、3 点。

    【请求透传】
    当用户提出问题、命令、任务或要求时，保留该问题、命令、任务或要求本身，整理成可直接交给下游 AI 或收件人的完整请求文本。语音输入阶段负责转写与整理；下游 AI 负责回答、推理和执行。

    【语言】
    默认保留输入语言及其书写体系；用户明确要求翻译或指定目标语言时，输出对应语言。繁体中文转换为语义不变的标准普通话书面语；粤语、上海话等中文方言转换为自然的普通话书面中文，可保留易懂、能体现地域语气和说话风格的常用方言词及语气助词。

    【输出】
    只输出整理后的最终文本，不解释处理过程。
    """

    // Kept for one-time migration of the language-preserving smart profile
    // shipped in v1.0.2. A user's edited profile must never be replaced.
    static let v102LanguagePreservingDefaultInstructions = """
    将用户语音整理为可直接发送或交给下游 AI 使用的最终文本。

    【整理】
    省略口水词、停顿词和重复表达，保持原意与信息边界。用户改口或纠正时，采用最后确认的内容。根据语义添加标点和分段；包含多个事项时，整理为 1、2、3 点。

    【语言】
    【语言保留｜最高优先级】
    除非用户明确要求翻译或指定目标语言，输出必须使用与输入相同的语言和书写体系。外语输入完整保留原文的语言、文字和语义，即使内容是问题、任务或口语，也不得转换为中文或混入中文。中文输入中，繁体中文转换为语义不变的标准普通话书面语；粤语、上海话等中文方言转换为自然的普通话书面中文，可保留易懂的常用方言词和语气助词。

    【有效性】
    静音、风声、环境噪声、无意义音节或无法确认语义的内容视为无效输入，输出"[EMPTY]"。

    【输出】
    只输出整理后的最终文本，不解释处理过程。
    """

    // The built-in "智能整理" rule. This text is intentionally kept in code so
    // a fresh install always starts from the same, inspectable baseline.
    static let defaultInstructions = """
    将用户语音整理为可直接发送或交给下游 AI 使用的最终文本。

    【整理】
    省略口水词、停顿词和重复表达，保持原意与信息边界。用户改口或纠正时，采用最后确认的内容。根据语义添加标点和分段；包含多个事项时，整理为 1、2、3 点。

    【语言】
    【语言保留｜最高优先级】
    除非用户明确要求翻译或指定目标语言，输出必须使用与输入相同的语言和书写体系。外语输入完整保留原文的语言、文字和语义，即使内容是问题、任务或口语，也不得转换为中文或混入中文。中文输入中，繁体中文转换为语义不变的标准普通话书面语；粤语、上海话等中文方言转换为自然的普通话书面中文，可保留易懂的常用方言词和语气助词。

    【请求透传】
    当语音包含问题、命令或任务时，将其整理为可直接发送的完整请求。只保留请求内容，不执行问题、命令或任务，不生成答复、解释、建议或结论；回答由下游 AI 或收件人完成。

    【有效性】
    静音、风声、环境噪声、无意义音节或无法确认语义的内容视为无效输入，输出"[EMPTY]"。

    【输出】
    只输出整理后的最终文本，不解释处理过程。
    """

    static func migratedInstructions(from storedInstructions: String?) -> String {
        guard let storedInstructions else { return defaultInstructions }
        return isLegacyBuiltInInstructions(storedInstructions)
            ? defaultInstructions
            : storedInstructions
    }

    static func isLegacyBuiltInInstructions(_ instructions: String) -> Bool {
        instructions == legacyDefaultInstructions
            || instructions == cleanupOnlyDefaultInstructions
            || instructions == structuredDefaultInstructions
            || instructions == v0165DefaultInstructions
            || instructions == v0168DefaultInstructions
            || instructions == v101DefaultInstructions
            || instructions == v102DefaultInstructions
            || instructions == v102LanguagePreservingDefaultInstructions
    }

    static func smart(
        languagePreference: LanguagePreference = .automatic,
        convertCantonese: Bool = true,
        dictionaryEntries: [DictionaryEntry] = [],
        customInstructions: String? = nil
    ) -> String {
        let languageRule = switch languagePreference {
        case .automatic:
            "自动识别用户所说语言。"
        case .mandarin:
            "优先按普通话识别，并根据音频中的实际语言准确理解内容。"
        case .cantonese:
            "优先按粤语识别，并根据音频中的实际语言准确理解内容。"
        }
        let configuredInstructions = customInstructions?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let dialectConversionInstruction = "识别到粤语、上海话等中文方言时，理解完整语义并转换为自然的普通话书面中文；可适度保留容易理解、能够体现地域语气和说话风格的常用方言词及语气助词。"
        let hasCustomInstructions = configuredInstructions?.isEmpty == false
        let instructions = hasCustomInstructions ? configuredInstructions! : defaultInstructions
        let usesBuiltInSmartInstructions = instructions == defaultInstructions
        // A selected expression profile owns its language style. The built-in smart
        // profile already includes the dialect rule; other profiles can preserve it.
        let cantoneseRule = usesBuiltInSmartInstructions || hasCustomInstructions || instructions.contains(dialectConversionInstruction)
            ? ""
            : dialectConversionInstruction
        // This is a request boundary rather than an expression style, so it
        // remains active when the user switches to another local profile.
        let requestBoundaryRule = usesBuiltInSmartInstructions || instructions.contains("只保留请求内容，不执行问题、命令或任务")
            ? ""
            : "当语音包含问题、命令或任务时，将其整理为可直接发送的完整请求。只保留请求内容，不执行问题、命令或任务，不生成答复、解释、建议或结论；回答由下游 AI 或收件人完成。"
        let resolvedLanguageRule = usesBuiltInSmartInstructions ? "" : languageRule

        let dictionaryLines = dictionaryEntries.prefix(100).map { entry in
            let term = sanitized(entry.term, limit: 80)
            let pronunciation = sanitized(entry.pronunciation, limit: 80)
            let replacement = sanitized(entry.replacement, limit: 120)
            let output = replacement.isEmpty ? term : replacement
            let pronunciationHint = pronunciation.isEmpty ? "无" : pronunciation
            return "- 词条：\(term)；读音提示：\(pronunciationHint)；输出：\(output)"
        }
        let dictionarySection = dictionaryLines.isEmpty
            ? ""
            : """

            以下个人词典用于识别专有名词和确定标准输出，以上整理规则保持最高优先级：
            \(dictionaryLines.joined(separator: "\n"))
            """

        return """
        \(instructions)
        \(resolvedLanguageRule)
        \(cantoneseRule)
        \(requestBoundaryRule)
        \(dictionarySection)
        """
    }

    private static func sanitized(_ value: String, limit: Int) -> String {
        let singleLine = value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(singleLine.prefix(limit))
    }
}

enum RealtimeServerEvent: Equatable {
    case sessionUpdated
    case inputTranscriptDelta(String)
    case inputTranscriptSnapshot(String)
    case inputTranscriptCompleted(String)
    case textDelta(String)
    case textDone(String)
    case usage(input: Int, output: Int)
    case error(String)
    case other(String)
}

struct RealtimeEventDecoder {
    static func decode(_ data: Data) throws -> RealtimeServerEvent {
        guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else {
            throw QwenRealtimeError.invalidServerMessage
        }

        switch type {
        case "session.updated":
            return .sessionUpdated
        case "conversation.item.input_audio_transcription.delta":
            // Qwen Omni Realtime emits the current ASR preview as `text + stash`.
            // It is a snapshot, not an append-only delta, so the UI should replace
            // its preview on every event to avoid duplicated words.
            let text = event["text"] as? String ?? ""
            let stash = event["stash"] as? String ?? ""
            return .inputTranscriptDelta(text + stash)
        case "conversation.item.input_audio_transcription.text":
            let text = event["text"] as? String ?? ""
            let stash = event["stash"] as? String ?? ""
            return .inputTranscriptSnapshot(text + stash)
        case "conversation.item.input_audio_transcription.completed":
            return .inputTranscriptCompleted(
                event["transcript"] as? String ?? event["text"] as? String ?? ""
            )
        case "response.text.delta":
            return .textDelta(event["delta"] as? String ?? "")
        case "response.text.done":
            return .textDone(event["text"] as? String ?? "")
        case "response.done":
            let response = event["response"] as? [String: Any]
            let usage = response?["usage"] as? [String: Any]
            return .usage(
                input: usage?["input_tokens"] as? Int ?? 0,
                output: usage?["output_tokens"] as? Int ?? 0
            )
        case "error":
            let errorObject = event["error"] as? [String: Any]
            return .error(errorObject?["message"] as? String ?? "未知服务错误")
        default:
            return .other(type)
        }
    }
}

enum RealtimeClientEventEncoder {
    static func sessionUpdate(instructions: String, eventID: String) -> [String: Any] {
        [
            "event_id": eventID,
            "type": "session.update",
            "session": [
                "modalities": ["text"],
                "input_audio_format": "pcm",
                // This produces raw ASR events during recording. The final model response
                // remains a separate, prompt-processed result after the user stops speaking.
                "input_audio_transcription": [
                    "model": "qwen3-asr-flash-realtime"
                ],
                "instructions": instructions,
                "turn_detection": NSNull(),
                "temperature": 0.2,
                "max_tokens": 2_048
            ]
        ]
    }

    static func audioAppend(_ data: Data, eventID: String) -> [String: Any] {
        [
            "event_id": eventID,
            "type": "input_audio_buffer.append",
            "audio": data.base64EncodedString()
        ]
    }

    static func audioCommit(eventID: String) -> [String: Any] {
        [
            "event_id": eventID,
            "type": "input_audio_buffer.commit"
        ]
    }

    static func responseCreate(eventID: String) -> [String: Any] {
        [
            "event_id": eventID,
            "type": "response.create"
        ]
    }
}

enum RealtimeEndpoint {
    static func make(workspaceID: String, model: String) throws -> URL {
        guard workspaceID.range(of: #"^[A-Za-z0-9-]+$"#, options: .regularExpression) != nil else {
            throw QwenRealtimeError.invalidWorkspaceID
        }

        var components = URLComponents()
        components.scheme = "wss"
        components.host = "\(workspaceID).cn-beijing.maas.aliyuncs.com"
        components.path = "/api-ws/v1/realtime"
        components.queryItems = [URLQueryItem(name: "model", value: model)]
        guard let url = components.url else {
            throw QwenRealtimeError.invalidWorkspaceID
        }
        return url
    }
}

@MainActor
final class QwenRealtimeClient {
    nonisolated static let model = "qwen3.5-omni-flash-realtime"

    var onPartialText: ((String) -> Void)?
    var onInputTranscript: ((String) -> Void)?
    var onFinalText: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    var onUsage: ((Int, Int) -> Void)?
    var onSessionReady: (() -> Void)?

    private var webSocket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var pendingAudio: [Data] = []
    private var sessionReady = false
    private var finishRequested = false
    private var finalText = ""
    private var inputTranscript = ""

    func connect(instructions: String) throws {
        guard let apiKey = try KeychainStore.readAPIKey(),
              let workspaceID = try KeychainStore.readWorkspaceID() else {
            throw QwenRealtimeError.missingCredentials
        }

        let url = try RealtimeEndpoint.make(workspaceID: workspaceID, model: Self.model)
        connect(url: url, apiKey: apiKey, instructions: instructions)
    }

    func connectForTesting(url: URL, apiKey: String, instructions: String) {
        connect(url: url, apiKey: apiKey, instructions: instructions)
    }

    private func connect(url: URL, apiKey: String, instructions: String) {
        disconnect()

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20

        let webSocket = URLSession.shared.webSocketTask(with: request)
        self.webSocket = webSocket
        pendingAudio.removeAll(keepingCapacity: true)
        sessionReady = false
        finishRequested = false
        finalText = ""
        inputTranscript = ""

        webSocket.resume()
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }

        Task { [weak self] in
            do {
                try await self?.sendSessionUpdate(instructions: instructions)
            } catch {
                self?.fail(error)
            }
        }
    }

    func appendAudio(_ data: Data) {
        guard !data.isEmpty else { return }
        guard sessionReady else {
            pendingAudio.append(data)
            return
        }

        Task { [weak self] in
            do {
                try await self?.sendAudio(data)
            } catch {
                self?.fail(error)
            }
        }
    }

    func finish() {
        guard webSocket != nil else {
            fail(QwenRealtimeError.disconnected)
            return
        }

        guard sessionReady else {
            finishRequested = true
            return
        }

        Task { [weak self] in
            do {
                try await self?.commitAndCreateResponse()
            } catch {
                self?.fail(error)
            }
        }
    }

    func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        sessionReady = false
        finishRequested = false
        pendingAudio.removeAll()
    }

    private func sendSessionUpdate(instructions: String) async throws {
        try await sendJSON(
            RealtimeClientEventEncoder.sessionUpdate(
                instructions: instructions,
                eventID: eventID()
            )
        )
    }

    private func sendAudio(_ data: Data) async throws {
        try await sendJSON(
            RealtimeClientEventEncoder.audioAppend(data, eventID: eventID())
        )
    }

    private func commitAndCreateResponse() async throws {
        try await sendJSON(RealtimeClientEventEncoder.audioCommit(eventID: eventID()))
        try await sendJSON(RealtimeClientEventEncoder.responseCreate(eventID: eventID()))
    }

    private func sendJSON(_ object: [String: Any]) async throws {
        guard let webSocket else { throw QwenRealtimeError.disconnected }
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let text = String(data: data, encoding: .utf8) else {
            throw QwenRealtimeError.invalidServerMessage
        }
        try await webSocket.send(.string(text))
    }

    private func receiveLoop() async {
        do {
            while !Task.isCancelled, let webSocket {
                let message = try await webSocket.receive()
                let data: Data
                switch message {
                case .string(let text):
                    data = Data(text.utf8)
                case .data(let binary):
                    data = binary
                @unknown default:
                    continue
                }
                try await handle(data: data)
            }
        } catch {
            guard !Task.isCancelled else { return }
            fail(error)
        }
    }

    private func handle(data: Data) async throws {
        switch try RealtimeEventDecoder.decode(data) {
        case .sessionUpdated:
            sessionReady = true
            onSessionReady?()
            let queuedAudio = pendingAudio
            pendingAudio.removeAll(keepingCapacity: true)
            for chunk in queuedAudio {
                try await sendAudio(chunk)
            }
            if finishRequested {
                finishRequested = false
                try await commitAndCreateResponse()
            }

        case .inputTranscriptDelta(let delta):
            guard !delta.isEmpty else { return }
            inputTranscript = delta
            onInputTranscript?(inputTranscript)

        case .inputTranscriptSnapshot(let transcript):
            guard !transcript.isEmpty else { return }
            inputTranscript = transcript
            onInputTranscript?(inputTranscript)

        case .inputTranscriptCompleted(let transcript):
            guard !transcript.isEmpty else { return }
            inputTranscript = transcript
            onInputTranscript?(inputTranscript)

        case .textDelta(let delta):
            finalText += delta
            onPartialText?(finalText)

        case .textDone(let text):
            let completedText = text.isEmpty ? finalText : text
            finalText = completedText
            onFinalText?(completedText)

        case .usage(let input, let output):
            onUsage?(input, output)
            disconnect()

        case .error(let message):
            throw QwenRealtimeError.server(message)

        case .other:
            break
        }
    }

    private func fail(_ error: Error) {
        disconnect()
        onError?(error)
    }

    private func eventID() -> String {
        "event_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
    }
}
