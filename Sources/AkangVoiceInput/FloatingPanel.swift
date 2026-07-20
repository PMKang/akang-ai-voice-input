import AppKit
import Combine
import SwiftUI

enum FloatingState: Equatable {
    case listening(startedAt: Date)
    case processing
    case clipboard(preview: String)
}

@MainActor
final class FloatingPanelController {
    private var panel: NSPanel?
    private var sessionScreen: NSScreen?
    private let model = FloatingPanelModel()

    func prepareForNewSession(displayName: String) {
        let mouseLocation = NSEvent.mouseLocation
        sessionScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        model.displayName = AppBrand.normalizedDisplayName(displayName)
        model.transcript = ""
        model.listeningHint = nil
    }

    func updateDisplayName(_ displayName: String) {
        model.displayName = AppBrand.normalizedDisplayName(displayName)
    }

    func show(state: FloatingState) {
        model.state = state
        if case .listening = state {
            // Keep a listening hint until its own timeout.
        } else {
            model.listeningHint = nil
        }
        let size = panelSize(for: state)
        let content = FloatingStatusView(model: model) { [weak self] in
            self?.hide()
        }

        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            self.panel = panel
        }

        guard let panel else { return }
        panel.contentView = NSHostingView(rootView: content)
        panel.setContentSize(size)
        position(panel: panel, size: size)
        panel.orderFrontRegardless()

        if case .clipboard = state {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                self?.hide()
            }
        }
    }

    func hide() {
        panel?.orderOut(nil)
        sessionScreen = nil
    }

    func updateAudioLevel(_ level: Float) {
        model.audioLevel = min(1, max(0, level))
    }

    func showListeningHint(_ hint: String) {
        guard case .listening = model.state else { return }
        model.listeningHint = hint
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, case .listening = self.model.state else { return }
            self.model.listeningHint = nil
        }
    }

    func updateTranscript(_ text: String) {
        guard case .listening = model.state else { return }
        model.transcript = text
    }

    private func panelSize(for state: FloatingState) -> NSSize {
        switch state {
        case .listening:
            NSSize(width: 620, height: 144)
        case .processing:
            NSSize(width: 360, height: 92)
        case .clipboard:
            NSSize(width: 560, height: 116)
        }
    }

    private func position(panel: NSPanel, size: NSSize) {
        let screen = sessionScreen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + 80
        )
        panel.setFrameOrigin(origin)
    }
}

@MainActor
private final class FloatingPanelModel: ObservableObject {
    @Published var state: FloatingState = .processing
    @Published var displayName = AppBrand.defaultDisplayName
    @Published var audioLevel: Float = 0
    @Published var listeningHint: String?
    @Published var transcript = ""
}

private struct FloatingStatusView: View {
    @ObservedObject var model: FloatingPanelModel
    let close: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            switch model.state {
            case .listening(let startedAt):
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AkangVoiceInputTheme.accent.opacity(0.13))
                    AkangBrandMark()
                        .foregroundStyle(AkangVoiceInputTheme.accent)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(model.displayName) 正在聆听")
                            .font(.headline)
                        Spacer()
                        ElapsedTimeView(startedAt: startedAt)
                    }
                    LiveWaveform(level: model.audioLevel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 28)
                    RecognizedTextMarquee(text: model.transcript)
                        .frame(height: 17)
                    if let hint = model.listeningHint {
                        Label(hint, systemImage: "waveform.badge.magnifyingglass")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AkangVoiceInputTheme.accent)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }

            case .processing:
                ProgressView()
                    .controlSize(.large)
                    .tint(AkangVoiceInputTheme.accent)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 9) {
                    Text("正在整理")
                        .font(.headline)
                    ProcessingLine()
                        .frame(height: 12)
                }

            case .clipboard(let preview):
                Image(systemName: "clipboard")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(AkangVoiceInputTheme.accent)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 7) {
                    Text("未找到输入框，已复制")
                        .font(.headline)
                    Text(truncatedPreview(preview))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Spacer(minLength: 8)

                Button(action: close) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("关闭")
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AkangVoiceInputTheme.border, lineWidth: 1)
        }
    }

    private func truncatedPreview(_ text: String) -> String {
        guard text.count > 100 else { return text }
        return String(text.prefix(100)) + "……"
    }
}

private struct AkangBrandMark: View {
    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach([14.0, 26.0, 34.0, 22.0, 12.0], id: \.self) { height in
                Capsule()
                    .frame(width: 3, height: height)
            }
        }
    }
}

private struct RecognizedTextMarquee: View {
    let text: String

    var body: some View {
        GeometryReader { proxy in
            let displayText = text.isEmpty ? "正在捕捉你的语音…" : text
            let font = NSFont.systemFont(ofSize: 12, weight: .medium)
            let textWidth = (displayText as NSString).size(withAttributes: [.font: font]).width
            let travel = max(0, textWidth - proxy.size.width + 24)

            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                let progress = marqueeProgress(at: context.date, travel: travel)
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                        .rotationEffect(.degrees(progress * 360))
                    Text(displayText)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .offset(x: travel > 0 ? -travel * progress : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.07),
                        .init(color: .black, location: 0.90),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
    }

    private func marqueeProgress(at date: Date, travel: CGFloat) -> CGFloat {
        guard travel > 0 else { return 0 }
        let cycle = max(2.3, Double(travel) / 78 + 1.2)
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
        // Leave a short pause at each end, then move smoothly in both directions.
        if phase < 0.14 { return 0 }
        if phase > 0.86 { return 1 }
        let movingPhase = (phase - 0.14) / 0.72
        return 0.5 - 0.5 * cos(movingPhase * .pi)
    }
}

private struct ElapsedTimeView: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = max(0, Int(context.date.timeIntervalSince(startedAt)))
            Text(String(format: "%02d:%02d", elapsed / 60, elapsed % 60))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

private struct LiveWaveform: View {
    let level: Float
    private let barCount = 48

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { context in
            GeometryReader { proxy in
                let barWidth: CGFloat = 4
                let spacing = max(2, (proxy.size.width - CGFloat(barCount) * barWidth) / CGFloat(barCount - 1))

                HStack(alignment: .center, spacing: spacing) {
                    ForEach(0..<barCount, id: \.self) { index in
                        Capsule()
                            .fill(AkangVoiceInputTheme.accent)
                            .frame(width: barWidth, height: barHeight(index: index, date: context.date))
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            }
        }
    }

    private func barHeight(index: Int, date: Date) -> CGFloat {
        let time = date.timeIntervalSinceReferenceDate
        // Expand the speaking range so normal voice produces a visibly larger
        // response while silence remains almost flat.
        let gatedLevel = max(0, (CGFloat(level) - 0.015) / 0.985)
        let visibleLevel = pow(gatedLevel, 0.34)
        let movement = 0.15 + Double(visibleLevel) * 0.85
        let wave = abs(sin(time * (2.0 + movement * 5.2) + Double(index) * 0.62))
        let envelope = 0.55 + 0.45 * abs(sin(Double(index) / Double(barCount) * .pi))
        let amplitude = visibleLevel * (7 + CGFloat(wave * envelope) * 22)
        return min(30, 3 + amplitude)
    }
}

private struct ProcessingLine: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { context in
            GeometryReader { proxy in
                let progress = (sin(context.date.timeIntervalSinceReferenceDate * 3) + 1) / 2
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.16))
                    Capsule()
                        .fill(AkangVoiceInputTheme.accent)
                        .frame(width: max(32, proxy.size.width * 0.32))
                        .offset(x: CGFloat(progress) * proxy.size.width * 0.68)
                }
            }
        }
    }
}
