import Foundation
import zlib

/// Provider adapter for Doubao Streaming ASR 2.0's optimized duplex WebSocket.
/// It intentionally sends raw 16 kHz PCM with no payload compression: the
/// provider protocol permits this and it keeps the client small and inspectable.
@MainActor
final class DoubaoRealtimeClient {
    static let modelID = "doubao-seed-asr-2-0"
    private static let endpoint = URL(string: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async")!
    private static let resourceID = "volc.seedasr.sauc.duration"

    var onPartialText: ((String) -> Void)?
    var onInputTranscript: ((String) -> Void)?
    var onFinalText: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    var onUsage: ((Int, Int) -> Void)?
    var onSessionReady: (() -> Void)?
    /// Protocol metadata only (never audio, text, or credentials), retained in
    /// the app's local diagnostic report to make provider integration debuggable.
    var onProtocolDiagnostic: ((String) -> Void)?

    private var webSocket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var pendingAudio: [Data] = []
    private var sessionReady = false
    private var finishRequested = false
    private var latestText = ""
    /// The provider requires a positive sequence on every client frame and a
    /// negative sequence on the final audio frame.
    private var nextSequence: Int32 = 1

    func connect() throws {
        guard let apiKey = try KeychainStore.readDoubaoAPIKey(), !apiKey.isEmpty else {
            throw DoubaoRealtimeError.missingCredentials
        }
        disconnect()

        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 20
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue(Self.resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "X-Api-Connect-Id")
        request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue("-1", forHTTPHeaderField: "X-Api-Sequence")

        let socket = URLSession.shared.webSocketTask(with: request)
        webSocket = socket
        pendingAudio.removeAll(keepingCapacity: true)
        sessionReady = false
        finishRequested = false
        latestText = ""
        nextSequence = 1
        socket.resume()
        receiveTask = Task { [weak self] in await self?.receiveLoop() }
        Task { [weak self] in
            do {
                try await self?.sendFullClientRequest()
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
            do { try await self?.sendAudio(data, isFinal: false) }
            catch { self?.fail(error) }
        }
    }

    func finish() {
        guard webSocket != nil else {
            fail(DoubaoRealtimeError.disconnected)
            return
        }
        guard sessionReady else {
            finishRequested = true
            return
        }
        Task { [weak self] in
            do { try await self?.sendAudio(Data(), isFinal: true) }
            catch { self?.fail(error) }
        }
    }

    func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        pendingAudio.removeAll()
        sessionReady = false
        finishRequested = false
    }

    private func sendFullClientRequest() async throws {
        let payload: [String: Any] = [
            "user": ["uid": "noboard-macos"],
            "audio": [
                "format": "pcm", "codec": "raw", "rate": 16_000,
                "bits": 16, "channel": 1
            ],
            "request": [
                "model_name": "bigmodel", "enable_itn": true,
                "enable_punc": true, "result_type": "full"
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let sequence = consumeSequence()
        try await send(
            frame: frame(
                type: 0x1,
                flags: 0x1,
                serialization: 0x1,
                compression: 0x1,
                sequence: sequence,
                payload: try gzip(data)
            )
        )
    }

    private func sendAudio(_ data: Data, isFinal: Bool) async throws {
        let sequence = consumeSequence()
        try await send(
            frame: frame(
                type: 0x2,
                flags: isFinal ? 0x3 : 0x1,
                serialization: 0x0,
                compression: 0x1,
                sequence: isFinal ? -sequence : sequence,
                payload: try gzip(data)
            )
        )
    }

    private func send(frame: Data) async throws {
        guard let webSocket else { throw DoubaoRealtimeError.disconnected }
        try await webSocket.send(.data(frame))
    }

    /// Version 1, four-byte header, no compression. All lengths are big endian.
    private func frame(
        type: UInt8,
        flags: UInt8,
        serialization: UInt8,
        compression: UInt8,
        sequence: Int32,
        payload: Data
    ) -> Data {
        var result = Data([0x11, type << 4 | flags, serialization << 4 | compression, 0x00])
        var sequenceValue = UInt32(bitPattern: sequence).bigEndian
        withUnsafeBytes(of: &sequenceValue) { result.append(contentsOf: $0) }
        var length = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
        result.append(payload)
        return result
    }

    private func receiveLoop() async {
        do {
            while !Task.isCancelled, let webSocket {
                let message = try await webSocket.receive()
                guard case .data(let data) = message else { continue }
                try handle(data)
            }
        } catch {
            guard !Task.isCancelled else { return }
            fail(error)
        }
    }

    private func handle(_ data: Data) throws {
        guard data.count >= 8 else {
            onProtocolDiagnostic?("收到过短二进制帧：\(data.count) B")
            throw DoubaoRealtimeError.invalidServerMessage
        }
        let headerSize = Int(data[0] & 0x0f) * 4
        guard headerSize >= 4, data.count >= headerSize else {
            throw DoubaoRealtimeError.invalidServerMessage
        }
        let messageType = data[1] >> 4
        let flags = data[1] & 0x0f
        let serialization = data[2] >> 4
        let compression = data[2] & 0x0f
        onProtocolDiagnostic?("收到帧 type=0x\(String(messageType, radix: 16)) flags=0x\(String(flags, radix: 16)) serialization=\(serialization) compression=\(compression) bytes=\(data.count)")
        if messageType == 0x0f {
            var cursor = headerSize
            guard data.count >= cursor + 8 else { throw DoubaoRealtimeError.invalidServerMessage }
            let code = readUInt32(data, at: cursor)
            cursor += 4
            let payloadLength = Int(readUInt32(data, at: cursor))
            cursor += 4
            guard data.count >= cursor + payloadLength else { throw DoubaoRealtimeError.invalidServerMessage }
            let encoded = data.subdata(in: cursor..<(cursor + payloadLength))
            let decoded = try decodePayload(encoded, compression: compression)
            let text = String(data: decoded, encoding: .utf8) ?? "未知错误"
            throw DoubaoRealtimeError.server("\(code)：\(text)")
        }
        guard messageType == 0x09 else {
            onProtocolDiagnostic?("忽略非识别结果帧 type=0x\(String(messageType, radix: 16))")
            return
        }
        // The server only includes a sequence when flag bit 0 is set. Future
        // protocol events may also carry an event code under bit 2.
        var cursor = headerSize
        if flags & 0x01 != 0 {
            guard data.count >= cursor + 4 else { throw DoubaoRealtimeError.invalidServerMessage }
            cursor += 4
        }
        if flags & 0x04 != 0 {
            guard data.count >= cursor + 4 else { throw DoubaoRealtimeError.invalidServerMessage }
            cursor += 4
        }
        guard data.count >= cursor + 4 else { throw DoubaoRealtimeError.invalidServerMessage }
        let payloadLength = Int(readUInt32(data, at: cursor))
        cursor += 4
        guard data.count >= cursor + payloadLength else { throw DoubaoRealtimeError.invalidServerMessage }
        let encodedPayload = data.subdata(in: cursor..<(cursor + payloadLength))
        let payload = try decodePayload(encodedPayload, compression: compression)
        guard let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            onProtocolDiagnostic?("结果帧 JSON 解析失败：payload=\(payload.count) B")
            throw DoubaoRealtimeError.invalidServerMessage
        }
        if let code = object["code"] as? Int, code != 0 {
            throw DoubaoRealtimeError.server(object["message"] as? String ?? "服务错误 \(code)")
        }
        if !sessionReady {
            sessionReady = true
            onSessionReady?()
            let queued = pendingAudio
            pendingAudio.removeAll(keepingCapacity: true)
            for chunk in queued { Task { [weak self] in try? await self?.sendAudio(chunk, isFinal: false) } }
            if finishRequested { finishRequested = false; finish() }
        }
        let text = ((object["result"] as? [String: Any])?["text"] as? String) ?? ""
        if !text.isEmpty {
            latestText = text
            onInputTranscript?(text)
            onPartialText?(text)
        }
        if flags == 0x03 {
            guard !latestText.isEmpty else { throw DoubaoRealtimeError.server("识别完成但未返回文字") }
            onFinalText?(latestText)
            onUsage?(0, 0)
            disconnect()
        }
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        data[offset..<(offset + 4)].reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func consumeSequence() -> Int32 {
        defer { nextSequence &+= 1 }
        return nextSequence
    }

    private func decodePayload(_ payload: Data, compression: UInt8) throws -> Data {
        switch compression {
        case 0: return payload
        case 1: return try gunzip(payload)
        default: throw DoubaoRealtimeError.unsupportedCompression(compression)
        }
    }

    /// The provider's binary protocol uses gzip for both request and response
    /// payloads. `zlib` is part of macOS, so no third-party dependency is
    /// necessary and this remains compatible with macOS 12.
    private func gzip(_ data: Data) throws -> Data {
        try transform(data, windowBits: MAX_WBITS + 16, operation: .deflate)
    }

    private func gunzip(_ data: Data) throws -> Data {
        try transform(data, windowBits: MAX_WBITS + 16, operation: .inflate)
    }

    private enum ZlibOperation { case deflate, inflate }

    private func transform(_ data: Data, windowBits: Int32, operation: ZlibOperation) throws -> Data {
        var stream = z_stream()
        let initialise: Int32
        switch operation {
        case .deflate:
            initialise = deflateInit2_(
                &stream,
                Z_DEFAULT_COMPRESSION,
                Z_DEFLATED,
                windowBits,
                8,
                Z_DEFAULT_STRATEGY,
                ZLIB_VERSION,
                Int32(MemoryLayout<z_stream>.size)
            )
        case .inflate:
            initialise = inflateInit2_(&stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        }
        guard initialise == Z_OK else { throw DoubaoRealtimeError.compressionFailure }
        defer {
            switch operation {
            case .deflate: deflateEnd(&stream)
            case .inflate: inflateEnd(&stream)
            }
        }

        return try data.withUnsafeBytes { rawBuffer in
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: rawBuffer.baseAddress?.assumingMemoryBound(to: Bytef.self))
            stream.avail_in = uInt(data.count)
            var output = Data()
            var status: Int32 = Z_OK
            repeat {
                var buffer = [UInt8](repeating: 0, count: 16 * 1024)
                let bufferCount = buffer.count
                status = buffer.withUnsafeMutableBytes { bufferPointer in
                    stream.next_out = bufferPointer.baseAddress?.assumingMemoryBound(to: Bytef.self)
                    stream.avail_out = uInt(bufferCount)
                    switch operation {
                    case .deflate: return deflate(&stream, Z_FINISH)
                    case .inflate: return inflate(&stream, Z_NO_FLUSH)
                    }
                }
                let produced = buffer.count - Int(stream.avail_out)
                output.append(contentsOf: buffer.prefix(produced))
                if status != Z_OK && status != Z_STREAM_END {
                    throw DoubaoRealtimeError.compressionFailure
                }
            } while status != Z_STREAM_END
            return output
        }
    }

    private func fail(_ error: Error) {
        disconnect()
        onError?(error)
    }
}

enum DoubaoRealtimeError: LocalizedError {
    case missingCredentials
    case invalidServerMessage
    case disconnected
    case server(String)
    case unsupportedCompression(UInt8)
    case compressionFailure

    var errorDescription: String? {
        switch self {
        case .missingCredentials: "请先在语音模型配置中保存豆包 API Key。"
        case .invalidServerMessage: "豆包模型返回了无法解析的消息。"
        case .disconnected: "豆包流式 WebSocket 连接已断开。"
        case .server(let message): "豆包模型服务返回错误：\(message)"
        case .unsupportedCompression(let value): "豆包模型使用了暂不支持的压缩格式：\(value)。"
        case .compressionFailure: "豆包模型返回的数据无法完成 Gzip 解压。"
        }
    }
}
