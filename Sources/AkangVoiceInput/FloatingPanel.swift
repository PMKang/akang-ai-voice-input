import AppKit
import Combine
import SwiftUI

enum ClipboardFallbackReason: Equatable {
    case accessibilityPermissionMissing
    case inputUnavailable

    var title: String {
        switch self {
        case .accessibilityPermissionMissing:
            "未开启辅助功能，已复制"
        case .inputUnavailable:
            "未找到可写入的输入框，已复制"
        }
    }

    var detail: String {
        switch self {
        case .accessibilityPermissionMissing:
            "在设置 > 权限与状态开启后，可自动写入微信、浏览器等输入框。"
        case .inputUnavailable:
            "请先点选需要写入的输入框，再开始下一次录音。"
        }
    }
}

enum FloatingState: Equatable {
    case listening(startedAt: Date)
    case processing
    case clipboard(preview: String, reason: ClipboardFallbackReason)
    case error(message: String)
}

enum FloatingPresentation: String, Codable, Equatable {
    case expanded
    case compact
    case edgeBubble
}

enum FloatingPanelDockSide: String, Codable, Equatable {
    case left
    case right
}

/// The placement intentionally stores a dock, rather than absolute pixels: a
/// voice-input overlay should survive resolution and display changes.
struct FloatingPanelPlacement: Codable, Equatable {
    var side: FloatingPanelDockSide
    /// 0, 0.5 and 1 represent the top, middle and bottom dock targets.
    var verticalRatio: CGFloat
    /// A user-selected placement. The normalized center survives panel-size,
    /// resolution and display changes better than raw pixels.
    var normalizedCenter: CGPoint?

    init(
        side: FloatingPanelDockSide,
        verticalRatio: CGFloat,
        normalizedCenter: CGPoint? = nil
    ) {
        self.side = side
        self.verticalRatio = verticalRatio
        self.normalizedCenter = normalizedCenter
    }

    static let defaultPlacement = FloatingPanelPlacement(side: .right, verticalRatio: 0)

    func origin(in visibleFrame: NSRect, panelSize: NSSize) -> NSPoint {
        if let normalizedCenter {
            let center = NSPoint(
                x: visibleFrame.minX + visibleFrame.width * min(1, max(0, normalizedCenter.x)),
                y: visibleFrame.minY + visibleFrame.height * min(1, max(0, normalizedCenter.y))
            )
            return NSPoint(
                x: min(max(visibleFrame.minX, center.x - panelSize.width / 2), visibleFrame.maxX - panelSize.width),
                y: min(max(visibleFrame.minY, center.y - panelSize.height / 2), visibleFrame.maxY - panelSize.height)
            )
        }
        let inset: CGFloat = 14
        let x = side == .left
            ? visibleFrame.minX + inset
            : visibleFrame.maxX - panelSize.width - inset
        let availableHeight = max(0, visibleFrame.height - panelSize.height - inset * 2)
        let y = visibleFrame.minY + inset + availableHeight * min(1, max(0, verticalRatio))
        return NSPoint(x: x, y: y)
    }

    static func snapped(
        frame: NSRect,
        in visibleFrame: NSRect
    ) -> FloatingPanelPlacement {
        let side: FloatingPanelDockSide = frame.midX < visibleFrame.midX ? .left : .right
        let availableHeight = max(1, visibleFrame.height - frame.height - 28)
        let rawRatio = (frame.minY - visibleFrame.minY - 14) / availableHeight
        let candidates: [CGFloat] = [0, 0.5, 1]
        let ratio = candidates.min(by: { abs($0 - rawRatio) < abs($1 - rawRatio) }) ?? 0
        return FloatingPanelPlacement(side: side, verticalRatio: ratio)
    }

    static func remembered(frame: NSRect, in visibleFrame: NSRect) -> FloatingPanelPlacement {
        let snapped = snapped(frame: frame, in: visibleFrame)
        let center = CGPoint(
            x: (frame.midX - visibleFrame.minX) / max(1, visibleFrame.width),
            y: (frame.midY - visibleFrame.minY) / max(1, visibleFrame.height)
        )
        return FloatingPanelPlacement(
            side: snapped.side,
            verticalRatio: snapped.verticalRatio,
            normalizedCenter: center
        )
    }
}

/// Shrinking into a bubble is deliberate: regular placement snapping must not
/// make the voice UI disappear. Only a release at the screen edge activates it.
enum FloatingPanelDockingPolicy {
    static let edgeActivationInset: CGFloat = 56
    static let explicitOutwardDragDistance: CGFloat = 24

    static func shouldCollapseToEdge(frame: NSRect, in visibleFrame: NSRect) -> Bool {
        frame.minX - visibleFrame.minX <= edgeActivationInset
            || visibleFrame.maxX - frame.maxX <= edgeActivationInset
    }

    static func hasExplicitEdgeIntent(
        from startFrame: NSRect,
        to endFrame: NSRect,
        in visibleFrame: NSRect
    ) -> Bool {
        guard shouldCollapseToEdge(frame: endFrame, in: visibleFrame) else { return false }
        let startedLeftGap = startFrame.minX - visibleFrame.minX
        let endedLeftGap = endFrame.minX - visibleFrame.minX
        let startedRightGap = visibleFrame.maxX - startFrame.maxX
        let endedRightGap = visibleFrame.maxX - endFrame.maxX
        return endedLeftGap <= edgeActivationInset
            && endedLeftGap < startedLeftGap - explicitOutwardDragDistance
            || endedRightGap <= edgeActivationInset
            && endedRightGap < startedRightGap - explicitOutwardDragDistance
    }
}

enum FloatingPanelPlacementStore {
    static let defaultsKey = "floatingVoiceInputPlacement"

    static func load(from defaults: UserDefaults = .standard) -> FloatingPanelPlacement? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        // Earlier versions stored only a side dock, which is exactly the
        // behaviour users asked to replace. Treat it as no saved preference.
        guard let placement = try? JSONDecoder().decode(FloatingPanelPlacement.self, from: data),
              placement.normalizedCenter != nil else { return nil }
        return placement
    }

    static func save(_ placement: FloatingPanelPlacement, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(placement) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}

enum FloatingPanelPresentationStore {
    static let defaultsKey = "floatingVoiceInputPresentation"

    static func load(from defaults: UserDefaults = .standard) -> FloatingPresentation {
        defaults.string(forKey: defaultsKey)
            .flatMap(FloatingPresentation.init(rawValue:))
            ?? .expanded
    }

    static func save(_ presentation: FloatingPresentation, to defaults: UserDefaults = .standard) {
        defaults.set(presentation.rawValue, forKey: defaultsKey)
    }
}

@MainActor
final class FloatingPanelController {
    var onCancelInput: (() -> Void)?

    private var panel: NSPanel?
    private var sessionScreen: NSScreen?
    private let model = FloatingPanelModel()
    private var placement = FloatingPanelPlacementStore.load()
    private var dragStartOrigin: NSPoint?
    private var nativeDragStartFrame: NSRect?
    private var listeningHintDismissTask: Task<Void, Never>?
    private var errorDismissTask: Task<Void, Never>?

    func prepareForNewSession(displayName: String, interfaceLanguage: InterfaceLanguage) {
        listeningHintDismissTask?.cancel()
        listeningHintDismissTask = nil
        errorDismissTask?.cancel()
        errorDismissTask = nil
        let mouseLocation = NSEvent.mouseLocation
        sessionScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        // Read again at session start. This makes the next shortcut activation
        // use the last completed drag even if the panel was hidden in between.
        placement = FloatingPanelPlacementStore.load()
        model.displayName = AppBrand.normalizedDisplayName(displayName)
        model.usesEnglish = interfaceLanguage == .english
        model.transcript = ""
        model.listeningHint = nil
        model.presentation = FloatingPanelPresentationStore.load()
    }

    func updateDisplayName(_ displayName: String) {
        model.displayName = AppBrand.normalizedDisplayName(displayName)
    }

    func updateInterfaceLanguage(_ interfaceLanguage: InterfaceLanguage) {
        model.usesEnglish = interfaceLanguage == .english
    }

    func updateShowsCompactTranscript(_ showsCompactTranscript: Bool) {
        model.showsCompactTranscript = showsCompactTranscript
    }

    func show(state: FloatingState) {
        model.state = state
        if case .listening = state {
            // Keep a listening hint until its own timeout.
        } else {
            model.listeningHint = nil
        }
        let size = panelSize(for: state, presentation: model.presentation)
        let content = FloatingStatusView(
            model: model,
            close: { [weak self] in self?.hide() },
            cancelInput: { [weak self] in self?.onCancelInput?() },
            changePresentation: { [weak self] presentation in self?.changePresentation(presentation) },
            drag: { [weak self] phase in self?.handleDrag(phase) },
            nativeDragStarted: { [weak self] in self?.beginNativeDrag() },
            nativeDragEnded: { [weak self] in self?.finishNativeDrag() }
        )

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
            panel.acceptsMouseMovedEvents = true
            self.panel = panel
        }

        guard let panel else { return }
        panel.contentView = NSHostingView(rootView: content)
        resize(panel: panel, to: size, repositions: true)
        panel.orderFrontRegardless()

        if case .clipboard = state {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                self?.hide()
            }
        }
    }

    func hide() {
        errorDismissTask?.cancel()
        errorDismissTask = nil
        rememberCurrentPlacement()
        panel?.orderOut(nil)
        sessionScreen = nil
    }

    func updateAudioLevel(_ level: Float) {
        model.audioLevel = min(1, max(0, level))
    }

    func showListeningHint(_ hint: String, autoDismissAfter duration: TimeInterval? = 2) {
        guard case .listening = model.state else { return }
        listeningHintDismissTask?.cancel()
        model.listeningHint = hint
        guard let duration else {
            listeningHintDismissTask = nil
            return
        }
        listeningHintDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled, let self, case .listening = self.model.state,
                  self.model.listeningHint == hint else { return }
            self.model.listeningHint = nil
            self.listeningHintDismissTask = nil
        }
    }

    func showError(_ message: String, autoDismissAfter duration: TimeInterval = 4) {
        errorDismissTask?.cancel()
        show(state: .error(message: message))
        errorDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func updateTranscript(_ text: String) {
        guard case .listening = model.state else { return }
        if !text.isEmpty {
            listeningHintDismissTask?.cancel()
            listeningHintDismissTask = nil
            model.listeningHint = nil
        }
        model.transcript = text
    }

    private func changePresentation(_ presentation: FloatingPresentation) {
        guard case .listening = model.state else { return }
        if presentation == .edgeBubble, placement == nil, let panel {
            let screen = NSScreen.screens.first { $0.frame.intersects(panel.frame) }
                ?? sessionScreen
                ?? NSScreen.main
            if let visibleFrame = screen?.visibleFrame {
                let remembered = FloatingPanelPlacement.remembered(frame: panel.frame, in: visibleFrame)
                placement = remembered
                sessionScreen = screen
                FloatingPanelPlacementStore.save(remembered)
            }
        }
        model.presentation = presentation
        FloatingPanelPresentationStore.save(presentation)
        guard let panel else { return }
        let size = panelSize(for: model.state, presentation: presentation)
        panel.contentView = NSHostingView(rootView: FloatingStatusView(
            model: model,
            close: { [weak self] in self?.hide() },
            cancelInput: { [weak self] in self?.onCancelInput?() },
            changePresentation: { [weak self] value in self?.changePresentation(value) },
            drag: { [weak self] phase in self?.handleDrag(phase) },
            nativeDragStarted: { [weak self] in self?.beginNativeDrag() },
            nativeDragEnded: { [weak self] in self?.finishNativeDrag() }
        ))
        resize(panel: panel, to: size, repositions: true)
    }

    private func panelSize(for state: FloatingState, presentation: FloatingPresentation) -> NSSize {
        switch state {
        case .listening:
            switch presentation {
            case .expanded: NSSize(width: 620, height: 144)
            case .compact: NSSize(width: 282, height: 58)
            case .edgeBubble: NSSize(width: model.showsCompactTranscript ? 260 : 98, height: 62)
            }
        case .processing:
            NSSize(width: 360, height: 92)
        case .clipboard:
            NSSize(width: 560, height: 138)
        case .error:
            NSSize(width: 460, height: 92)
        }
    }

    private func resize(panel: NSPanel, to size: NSSize, repositions: Bool) {
        let previousFrame = panel.frame
        let preservesVisibleAnchor = panel.isVisible && previousFrame.width > 0
        panel.setContentSize(size)
        guard repositions else { return }
        if preservesVisibleAnchor {
            position(panel: panel, preservingCenterOf: previousFrame)
            rememberCurrentPlacement()
        } else if let placement {
            position(panel: panel, size: size, placement: placement)
        } else if previousFrame.width > 0 {
            positionAtDefault(panel: panel, size: size)
        }
    }

    private func position(panel: NSPanel, preservingCenterOf previousFrame: NSRect) {
        let screen = NSScreen.screens.first { $0.frame.intersects(previousFrame) }
            ?? sessionScreen
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let desired = NSPoint(
            x: previousFrame.midX - panel.frame.width / 2,
            y: previousFrame.midY - panel.frame.height / 2
        )
        panel.setFrameOrigin(NSPoint(
            x: min(max(visibleFrame.minX, desired.x), visibleFrame.maxX - panel.frame.width),
            y: min(max(visibleFrame.minY, desired.y), visibleFrame.maxY - panel.frame.height)
        ))
        sessionScreen = screen
    }

    private func position(panel: NSPanel, size: NSSize, placement: FloatingPanelPlacement) {
        let screen = sessionScreen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(placement.origin(in: visibleFrame, panelSize: size))
    }

    private func positionAtDefault(panel: NSPanel, size: NSSize) {
        let screen = sessionScreen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + 80
        ))
    }

    private func handleDrag(_ phase: FloatingDragPhase) {
        guard let panel else { return }
        switch phase {
        case .changed(let translation):
            if dragStartOrigin == nil { dragStartOrigin = panel.frame.origin }
            guard let origin = dragStartOrigin else { return }
            panel.setFrameOrigin(NSPoint(
                x: origin.x + translation.width,
                y: origin.y - translation.height
            ))
        case .ended:
            dragStartOrigin = nil
            finishDrag(panel: panel)
        }
    }

    /// Called once native `performDrag(with:)` ends. Moving the window through
    /// AppKit prevents the flicker caused by SwiftUI gesture updates.
    private func finishNativeDrag() {
        guard let panel else { return }
        let startFrame = nativeDragStartFrame
        nativeDragStartFrame = nil
        finishDrag(panel: panel, nativeStartFrame: startFrame)
    }

    private func beginNativeDrag() {
        nativeDragStartFrame = panel?.frame
    }

    private func finishDrag(panel: NSPanel, nativeStartFrame: NSRect? = nil) {
        let screen = NSScreen.screens.first { $0.frame.intersects(panel.frame) }
            ?? sessionScreen
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        sessionScreen = screen

        let releasedAtEdge = nativeStartFrame.map {
            FloatingPanelDockingPolicy.hasExplicitEdgeIntent(
                from: $0,
                to: panel.frame,
                in: visibleFrame
            )
        } ?? false
        let remembered = FloatingPanelPlacement.remembered(frame: panel.frame, in: visibleFrame)
        placement = remembered
        FloatingPanelPlacementStore.save(remembered)

        if releasedAtEdge, model.presentation != .edgeBubble {
            changePresentation(.edgeBubble)
            return
        }

        // The user deliberately chose this exact position. Preserve it rather
        // than silently snapping it back to a screen-side preset.
    }

    private func rememberCurrentPlacement() {
        guard let panel,
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) })
                ?? sessionScreen
                ?? NSScreen.main else { return }
        let remembered = FloatingPanelPlacement.remembered(
            frame: panel.frame,
            in: screen.visibleFrame
        )
        placement = remembered
        sessionScreen = screen
        FloatingPanelPlacementStore.save(remembered)
    }
}

@MainActor
private final class FloatingPanelModel: ObservableObject {
    @Published var state: FloatingState = .processing
    @Published var displayName = AppBrand.defaultDisplayName
    @Published var audioLevel: Float = 0
    @Published var listeningHint: String?
    @Published var transcript = ""
    @Published var usesEnglish = false
    @Published var presentation: FloatingPresentation = .expanded
    @Published var showsCompactTranscript = true
}

private enum FloatingDragPhase {
    case changed(CGSize)
    case ended
}

private struct FloatingStatusView: View {
    @ObservedObject var model: FloatingPanelModel
    let close: () -> Void
    let cancelInput: () -> Void
    let changePresentation: (FloatingPresentation) -> Void
    let drag: (FloatingDragPhase) -> Void
    let nativeDragStarted: () -> Void
    let nativeDragEnded: () -> Void

    var body: some View {
        Group {
            switch model.state {
            case .listening(let startedAt):
                listeningView(startedAt: startedAt)
            case .processing:
                processingView
            case .clipboard(let preview, let reason):
                clipboardView(preview: preview, reason: reason)
            case .error(let message):
                errorView(message: message)
            }
        }
    }

    @ViewBuilder
    private func listeningView(startedAt: Date) -> some View {
        switch model.presentation {
        case .expanded:
            HStack(spacing: 16) {
                DragHandle(onDragStarted: nativeDragStarted, onDragEnded: nativeDragEnded)
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AkangVoiceInputTheme.accent.opacity(0.13))
                    AkangBrandMark()
                        .foregroundStyle(AkangVoiceInputTheme.accent)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(model.usesEnglish ? "\(model.displayName) is listening" : "\(model.displayName) 正在聆听")
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

                VStack(spacing: 2) {
                    CancelInputButton(usesEnglish: model.usesEnglish, action: cancelInput)
                    CollapseButton { changePresentation(.compact) }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .floatingCard(cornerRadius: 14)

        case .compact:
            HStack(spacing: 10) {
                DragHandle(onDragStarted: nativeDragStarted, onDragEnded: nativeDragEnded, compact: true)
                CompactWaveform(level: model.audioLevel)
                    .frame(width: 44, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    CompactTranscript(text: model.transcript, isVisible: model.showsCompactTranscript)
                    ElapsedTimeView(startedAt: startedAt)
                        .font(.caption2)
                }
                Spacer(minLength: 2)
                CancelInputButton(
                    usesEnglish: model.usesEnglish,
                    compact: true,
                    action: cancelInput
                )
                Button { changePresentation(.expanded) } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.plain)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
                .help("展开；拖到屏幕边缘可贴边缩小")
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .floatingCard(cornerRadius: 29)

        case .edgeBubble:
            HStack(spacing: 8) {
                if model.showsCompactTranscript {
                    CompactTranscript(text: model.transcript, isVisible: true)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                CancelInputButton(
                    usesEnglish: model.usesEnglish,
                    compact: true,
                    action: cancelInput
                )
                Button { changePresentation(.compact) } label: {
                    ZStack {
                        Circle()
                            .fill(AkangVoiceInputTheme.accent)
                            .shadow(color: AkangVoiceInputTheme.accent.opacity(0.34), radius: 10)
                        CompactWaveform(level: model.audioLevel, foreground: .white)
                            .frame(width: 28, height: 29)
                    }
                    .frame(width: 50, height: 50)
                }
                .buttonStyle(.plain)
                .help("展开语音输入")
                .simultaneousGesture(dragGesture)
            }
            .padding(.horizontal, model.showsCompactTranscript ? 10 : 6)
            .padding(.vertical, 6)
            .floatingCard(cornerRadius: 31)
        }
    }

    private var processingView: some View {
        HStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(AkangVoiceInputTheme.accent)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 9) {
                Text(model.usesEnglish ? "Polishing" : "正在整理")
                    .font(.headline)
                ProcessingLine().frame(height: 12)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .floatingCard(cornerRadius: 14)
    }

    private func errorView(message: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(.orange)
                .frame(width: 30)
            Text(message)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Button(action: close) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("关闭")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .floatingCard(cornerRadius: 14)
    }

    private func clipboardView(preview: String, reason: ClipboardFallbackReason) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "clipboard")
                .font(.system(size: 27, weight: .medium))
                .foregroundStyle(AkangVoiceInputTheme.accent)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 7) {
                Text(LocalizedStringKey(reason.title)).font(.headline)
                Text(LocalizedStringKey(reason.detail))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(truncatedPreview(preview))
                    .font(.callout).foregroundStyle(.secondary).lineLimit(3)
            }
            Spacer(minLength: 8)
            Button(action: close) { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("关闭")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .floatingCard(cornerRadius: 14)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { drag(.changed($0.translation)) }
            .onEnded { _ in drag(.ended) }
    }

    private func truncatedPreview(_ text: String) -> String {
        guard text.count > 100 else { return text }
        return String(text.prefix(100)) + "……"
    }
}

private struct DragHandle: View {
    let onDragStarted: () -> Void
    let onDragEnded: () -> Void
    var compact = false
    @State private var isHovering = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovering ? AkangVoiceInputTheme.accent.opacity(0.12) : .clear)
            HStack(spacing: 5) {
                Image(systemName: "circle.grid.2x2.fill")
                    .font(compact ? .body : .title3)
                if isHovering {
                    Text("拖动")
                        .font(.caption.weight(.semibold))
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .foregroundStyle(isHovering ? AkangVoiceInputTheme.accent : Color.secondary.opacity(0.62))
            NativeWindowDragHandle(
                onDragStarted: onDragStarted,
                onDragEnded: onDragEnded,
                onHoverChanged: { hovering in
                    withAnimation(.easeOut(duration: 0.14)) { isHovering = hovering }
                }
            )
        }
        .frame(width: compact ? 50 : 66, height: compact ? 42 : 48)
        .help("按住拖动；拖到屏幕边缘可贴边缩小")
    }
}

/// Cancelling is intentionally available only inside the recording surface, so
/// the host app keeps keyboard focus and never receives a synthetic Escape key.
private struct CancelInputButton: View {
    let usesEnglish: Bool
    var compact = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                if isHovering && !compact {
                    Text(usesEnglish ? "Cancel" : "取消")
                        .font(.caption.weight(.semibold))
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .foregroundStyle(isHovering ? Color.red.opacity(0.82) : Color.secondary.opacity(0.72))
            .frame(minWidth: compact ? 30 : (isHovering ? 64 : 40), minHeight: compact ? 30 : 40)
            .background {
                RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
                    .fill(isHovering ? Color.red.opacity(0.09) : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) { isHovering = hovering }
        }
        .help(usesEnglish ? "Cancel this voice input" : "取消本次输入")
        .accessibilityLabel(usesEnglish ? "Cancel this voice input" : "取消本次输入")
    }
}

/// Keep the resting control quiet, then reveal its meaning at the exact moment
/// the pointer shows intent. This matches the drag handle's hover language.
private struct CollapseButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "minus")
                    .font(.callout.weight(.semibold))
                if isHovering {
                    Text("收起")
                        .font(.caption.weight(.semibold))
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .foregroundStyle(isHovering ? AkangVoiceInputTheme.accent : Color.secondary)
            .frame(minWidth: isHovering ? 64 : 40, minHeight: 40)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovering ? AkangVoiceInputTheme.accent.opacity(0.12) : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) { isHovering = hovering }
        }
        .help("收起为悬浮胶囊")
    }
}

/// AppKit owns the window drag, avoiding the re-layout/flicker that happens
/// when a SwiftUI `DragGesture` repeatedly calls `setFrameOrigin`.
private struct NativeWindowDragHandle: NSViewRepresentable {
    let onDragStarted: () -> Void
    let onDragEnded: () -> Void
    let onHoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> WindowDragHandleView {
        let view = WindowDragHandleView()
        view.onDragStarted = onDragStarted
        view.onDragEnded = onDragEnded
        view.onHoverChanged = onHoverChanged
        return view
    }

    func updateNSView(_ nsView: WindowDragHandleView, context: Context) {
        nsView.onDragStarted = onDragStarted
        nsView.onDragEnded = onDragEnded
        nsView.onHoverChanged = onHoverChanged
    }
}

private final class WindowDragHandleView: NSView {
    var onDragStarted: (() -> Void)?
    var onDragEnded: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }

    override func mouseDown(with event: NSEvent) {
        onDragStarted?()
        window?.performDrag(with: event)
        onDragEnded?()
    }
}

private struct CompactTranscript: View {
    let text: String
    let isVisible: Bool

    var body: some View {
        Group {
            if isVisible {
                HStack(spacing: 3) {
                    Text(shortText)
                        .lineLimit(1)
                    Rectangle()
                        .fill(AkangVoiceInputTheme.accent)
                        .frame(width: 1.5, height: 12)
                        .opacity(text.isEmpty ? 0.4 : 0.9)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: text)
    }

    private var shortText: String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "正在听…" }
        let suffix = String(normalized.suffix(16))
        return normalized.count > 16 ? "…\(suffix)" : suffix
    }
}

private struct CompactWaveform: View {
    let level: Float
    var foreground: Color = AkangVoiceInputTheme.accent

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { context in
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(foreground)
                        .frame(width: 3.5, height: height(index: index, date: context.date))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func height(index: Int, date: Date) -> CGFloat {
        let active = max(0.10, pow(CGFloat(level), 0.38))
        let wave = 0.35 + abs(sin(date.timeIntervalSinceReferenceDate * 4 + Double(index) * 0.9)) * 0.65
        return 5 + active * CGFloat(8 + 18 * wave)
    }
}

private extension View {
    func floatingCard(cornerRadius: CGFloat) -> some View {
        background(.ultraThickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AkangVoiceInputTheme.border, lineWidth: 1)
            }
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
        ProgressView()
            .progressViewStyle(.linear)
            .tint(AkangVoiceInputTheme.accent)
    }
}
