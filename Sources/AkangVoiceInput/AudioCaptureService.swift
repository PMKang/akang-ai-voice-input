@preconcurrency import AVFoundation
import Foundation

enum MicrophonePermissionState: String {
    case notDetermined = "尚未请求"
    case authorized = "已授权"
    case denied = "未授权"
    case restricted = "受限制"

    static var current: Self {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }

    var actionLabel: String? {
        switch self {
        case .notDetermined: "请求权限"
        case .denied, .restricted: "打开系统设置"
        case .authorized: nil
        }
    }
}

enum AudioCaptureError: LocalizedError {
    case microphoneDenied
    case recordingTooShort
    case noValidSpeech
    case invalidInputFormat
    case converterUnavailable
    case failedToStart(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "未获得麦克风权限，请在系统设置中允许 Noboard · 自在说使用麦克风。"
        case .recordingTooShort:
            "录音时间太短，请稍后再停止。"
        case .noValidSpeech:
            "未识别到有效语音，请再说一次。"
        case .invalidInputFormat:
            "无法读取当前麦克风的音频格式。"
        case .converterUnavailable:
            "无法创建 16 kHz 音频转换器。"
        case .failedToStart(let message):
            "无法开始录音：\(message)"
        }
    }
}

enum AudioCapturePolicy {
    // 16 kHz * mono * Int16 * 0.1 seconds.
    static let minimumPCM16ByteCount = 3_200
    static let outboundPCM16ByteCount = 3_200
    static let waveformUpdatesPerSecond: TimeInterval = 20
    static let noiseNoticeMinimumInterval: TimeInterval = 1.5

    static func hasEnoughAudio(byteCount: Int) -> Bool {
        byteCount >= minimumPCM16ByteCount
    }
}

enum VoiceFrameDisposition: Equatable {
    case quiet
    case speechCandidate
    case suspectedNoise
    case confirmedSpeech
    case speechTail
}

/// A lightweight local gate that learns the current room's noise floor. It
/// requires two consecutive speech-like frames before audio is sent upstream,
/// so isolated knocks and pops do not become transcribed text.
struct AdaptiveVoiceGate {
    private(set) var noiseFloor: Float = 0.006
    private var speechHoldUntil: TimeInterval = 0
    private var consecutiveSpeechFrames = 0

    mutating func classify(
        rms: Float,
        peak: Float,
        zeroCrossingRatio: Float,
        at timestamp: TimeInterval
    ) -> VoiceFrameDisposition {
        let boundedRMS = min(1, max(0, rms))
        let threshold = max(noiseFloor * 2.2, 0.009)
        let isEnergetic = boundedRMS >= threshold
        let crestFactor = peak / max(boundedRMS, 0.000_1)
        // A single knock normally has an extremely high peak compared with
        // its average energy. Do not use zero-crossing count as a hard voice
        // rule: Apple voice processing and different microphones can make
        // perfectly normal speech look almost flat in a short 1,024-frame
        // buffer. That was causing valid speech to be discarded locally.
        let isSpeechLike = isEnergetic && crestFactor <= 18.0

        if isSpeechLike {
            consecutiveSpeechFrames += 1
            guard consecutiveSpeechFrames >= 2 else {
                return .speechCandidate
            }
            speechHoldUntil = timestamp + 0.32
            return .confirmedSpeech
        }

        consecutiveSpeechFrames = 0
        if timestamp < speechHoldUntil {
            return .speechTail
        }

        // Learn a quiet room quickly, but adapt to a louder environment
        // slowly so a spoken word does not become the new noise floor.
        let blend: Float = boundedRMS < noiseFloor ? 0.08 : 0.012
        noiseFloor += (boundedRMS - noiseFloor) * blend
        return isEnergetic ? .suspectedNoise : .quiet
    }

    mutating func reset() {
        noiseFloor = 0.006
        speechHoldUntil = 0
        consecutiveSpeechFrames = 0
    }
}

private final class ConverterInputProvider: @unchecked Sendable {
    private let lock = NSLock()
    private let buffer: AVAudioPCMBuffer
    private var supplied = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        lock.lock()
        defer { lock.unlock() }

        guard !supplied else {
            status.pointee = .noDataNow
            return nil
        }

        supplied = true
        status.pointee = .haveData
        return buffer
    }
}

private final class AudioTapProcessor: @unchecked Sendable {
    private weak var owner: AudioCaptureService?
    private let inputFormat: AVAudioFormat
    private let targetFormat: AVAudioFormat
    private let converter: AVAudioConverter
    private let lock = NSLock()
    private var voiceGate = AdaptiveVoiceGate()
    private var pendingPCM = Data()
    private var candidatePCM = Data()
    private var lastWaveformDelivery: TimeInterval = 0
    private var lastNoiseDelivery: TimeInterval = 0

    init(
        owner: AudioCaptureService,
        inputFormat: AVAudioFormat,
        targetFormat: AVAudioFormat,
        converter: AVAudioConverter
    ) {
        self.owner = owner
        self.inputFormat = inputFormat
        self.targetFormat = targetFormat
        self.converter = converter
    }

    func process(buffer: AVAudioPCMBuffer) {
        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 8
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
            return
        }

        let inputProvider = ConverterInputProvider(buffer: buffer)
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) { _, inputStatus in
            inputProvider.next(status: inputStatus)
        }

        guard conversionError == nil, status != .error,
              let samples = converted.floatChannelData?[0] else {
            return
        }

        let count = Int(converted.frameLength)
        guard count > 0 else { return }

        var sum: Float = 0
        var peak: Float = 0
        var zeroCrossingCount = 0
        var previousSample: Float = 0
        var pcm = Data(capacity: count * MemoryLayout<Int16>.size)

        for index in 0..<count {
            let sample = max(-1, min(1, samples[index]))
            sum += sample * sample
            peak = max(peak, abs(sample))
            if index > 0, (sample >= 0) != (previousSample >= 0) {
                zeroCrossingCount += 1
            }
            previousSample = sample
            var intSample = Int16(sample * Float(Int16.max)).littleEndian
            withUnsafeBytes(of: &intSample) { pcm.append(contentsOf: $0) }
        }

        let rms = sqrt(sum / Float(count))
        let zeroCrossingRatio = Float(zeroCrossingCount) / Float(count)
        let normalizedLevel = min(1, max(0, (20 * log10(max(rms, 0.000_01)) + 55) / 55))
        let now = ProcessInfo.processInfo.systemUptime

        let delivery = lock.withLock { () -> (pcm: Data?, level: Float?, noiseDetected: Bool) in
            let disposition = voiceGate.classify(
                rms: rms,
                peak: peak,
                zeroCrossingRatio: zeroCrossingRatio,
                at: now
            )
            let containsSpeech = disposition == .speechCandidate
                || disposition == .confirmedSpeech
                || disposition == .speechTail
            var outboundPCM: Data?
            var noiseDetected = false
            switch disposition {
            case .confirmedSpeech:
                pendingPCM.append(candidatePCM)
                candidatePCM.removeAll(keepingCapacity: true)
                pendingPCM.append(pcm)
            case .speechCandidate:
                candidatePCM.append(pcm)
                if candidatePCM.count > AudioCapturePolicy.outboundPCM16ByteCount * 2 {
                    candidatePCM.removeAll(keepingCapacity: true)
                }
            case .speechTail:
                pendingPCM.append(pcm)
            case .suspectedNoise:
                // An impact must never become the beginning of the next
                // utterance when speech resumes shortly afterwards.
                candidatePCM.removeAll(keepingCapacity: true)
                if now - lastNoiseDelivery >= AudioCapturePolicy.noiseNoticeMinimumInterval {
                    lastNoiseDelivery = now
                    noiseDetected = true
                }
            case .quiet:
                candidatePCM.removeAll(keepingCapacity: true)
            }
            if pendingPCM.count >= AudioCapturePolicy.outboundPCM16ByteCount {
                outboundPCM = pendingPCM
                pendingPCM.removeAll(keepingCapacity: true)
            }

            let minimumInterval = 1 / AudioCapturePolicy.waveformUpdatesPerSecond
            let waveformLevel: Float?
            if now - lastWaveformDelivery >= minimumInterval {
                lastWaveformDelivery = now
                waveformLevel = containsSpeech ? normalizedLevel : 0
            } else {
                waveformLevel = nil
            }
            return (outboundPCM, waveformLevel, noiseDetected)
        }

        guard delivery.pcm != nil || delivery.level != nil || delivery.noiseDetected else { return }
        Task { @MainActor [weak owner, delivery] in
            owner?.accept(
                pcm: delivery.pcm,
                normalizedLevel: delivery.level,
                detectedNoise: delivery.noiseDetected
            )
        }
    }

    func drainPendingPCM() -> Data {
        lock.withLock {
            defer {
                pendingPCM.removeAll(keepingCapacity: true)
                candidatePCM.removeAll(keepingCapacity: true)
                voiceGate.reset()
            }
            return pendingPCM
        }
    }
}

private enum AudioTapBlockFactory {
    nonisolated static func make(processor: AudioTapProcessor) -> AVAudioNodeTapBlock {
        { [processor] buffer, _ in
            processor.process(buffer: buffer)
        }
    }
}

@MainActor
final class AudioCaptureService {
    private let engine = AVAudioEngine()
    private var tapProcessor: AudioTapProcessor?
    private var tapInstalled = false

    private(set) var isRecording = false
    private(set) var level: Float = 0
    private(set) var capturedByteCount = 0
    private(set) var startedAt: Date?
    private(set) var isNativeVoiceProcessingEnabled = false

    var onPCM16Data: (@MainActor (Data) -> Void)?
    var onLevel: (@MainActor (Float) -> Void)?
    var onNoiseDetected: (@MainActor () -> Void)?

    var permissionState: MicrophonePermissionState {
        .current
    }

    func requestPermission() async -> Bool {
        switch MicrophonePermissionState.current {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        }
    }

    func start() async throws {
        guard await requestPermission() else {
            throw AudioCaptureError.microphoneDenied
        }

        stop()

        let inputNode = engine.inputNode

        // Keep the capture path on the raw input node. On some Mac audio
        // devices, AVAudioEngine's VoiceProcessing mode reports a successful
        // start while CoreAudio repeatedly drops buffers with invalid audio
        // timestamps. That leaves the UI in the recording state with no PCM
        // delivered to the model. Local voice gating below remains responsible
        // for the first-stage noise filtering.
        if inputNode.isVoiceProcessingEnabled {
            do {
                try inputNode.setVoiceProcessingEnabled(false)
            } catch {
                // A device that cannot toggle this mode can still be sampled;
                // do not fail the entire recording session for that reason.
            }
        }
        isNativeVoiceProcessingEnabled = false
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioCaptureError.invalidInputFormat
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioCaptureError.converterUnavailable
        }

        let tapProcessor = AudioTapProcessor(
            owner: self,
            inputFormat: inputFormat,
            targetFormat: targetFormat,
            converter: converter
        )
        self.tapProcessor = tapProcessor
        capturedByteCount = 0
        level = 0
        startedAt = .now

        inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: inputFormat,
            block: AudioTapBlockFactory.make(processor: tapProcessor)
        )
        tapInstalled = true

        do {
            engine.prepare()
            try engine.start()
            isRecording = true
        } catch {
            if tapInstalled {
                inputNode.removeTap(onBus: 0)
                tapInstalled = false
            }
            self.tapProcessor = nil
            startedAt = nil
            throw AudioCaptureError.failedToStart(error.localizedDescription)
        }
    }

    func stop() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if let pendingPCM = tapProcessor?.drainPendingPCM(), !pendingPCM.isEmpty {
            accept(pcm: pendingPCM, normalizedLevel: nil, detectedNoise: false)
        }
        if engine.isRunning {
            engine.stop()
        }
        tapProcessor = nil
        isRecording = false
        level = 0
        startedAt = nil
    }

    fileprivate func accept(pcm: Data?, normalizedLevel: Float?, detectedNoise: Bool) {
        guard isRecording else { return }
        if let normalizedLevel {
            level = level * 0.64 + normalizedLevel * 0.36
            onLevel?(level)
        }
        if let pcm, !pcm.isEmpty {
            capturedByteCount += pcm.count
            onPCM16Data?(pcm)
        }
        if detectedNoise {
            onNoiseDetected?()
        }
    }
}
