import AppKit
import SwiftUI

struct ShortcutSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @State private var candidate: CustomShortcutBinding?
    @State private var liveModifiers: ShortcutModifiers = []
    @State private var captureMessage: String?
    @State private var registrationMessage: String?

    init(currentBinding: CustomShortcutBinding?) {
        _candidate = State(initialValue: currentBinding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("自定义快捷键")
                    .font(.title2.weight(.semibold))
                Text("直接按下想使用的按键或组合键")
                    .foregroundStyle(.secondary)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AkangVoiceInputTheme.accent.opacity(0.7), lineWidth: 1.5)

                Text(capturedText)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)

                ShortcutCaptureView(
                    onKeyDown: handleKeyDown,
                    onModifiersChanged: handleModifiersChanged
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .frame(height: 82)

            HStack(spacing: 8) {
                Text("推荐")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(recommendedBindings, id: \.self) { binding in
                    Button(binding.displayText) {
                        candidate = binding
                        liveModifiers = binding.modifiers
                        captureMessage = nil
                        registrationMessage = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Label(validationMessage, systemImage: validationIcon)
                .font(.callout)
                .foregroundStyle(validationColor)
                .fixedSize(horizontal: false, vertical: true)

            Text("macOS 只能确认 Noboard 是否成功注册系统级监听，无法可靠发现所有应用内部快捷键。保存后若与某个应用冲突，请换一个组合。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                Text("Esc 取消 · Backspace 清除")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("使用此快捷键") {
                    useCandidate()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(candidate?.validation.canUse != true)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private var capturedText: String {
        if let candidate {
            return candidate.displayText
        }
        if !liveModifiers.isEmpty {
            return "\(liveModifiers.displayPrefix) …"
        }
        return "等待按键…"
    }

    private var recommendedBindings: [CustomShortcutBinding] {
        [
            CustomShortcutBinding(modifiers: [.control, .option], keyCode: 38),
            CustomShortcutBinding(modifiers: [.control, .shift], keyCode: 38),
            CustomShortcutBinding(modifiers: [.command, .shift], keyCode: 38)
        ]
    }

    private var currentValidation: ShortcutValidation {
        if let registrationMessage {
            return .invalid(registrationMessage)
        }
        if let captureMessage {
            return .invalid(captureMessage)
        }
        if let candidate {
            return candidate.validation
        }
        return .invalid("组合键需要包含主键；F2–F12 可以单独使用。")
    }

    private var validationMessage: String { currentValidation.message }

    private var validationIcon: String {
        switch currentValidation.kind {
        case .valid, .warning: "checkmark.circle.fill"
        case .invalid: candidate == nil && captureMessage == nil && registrationMessage == nil
            ? "keyboard"
            : "xmark.circle.fill"
        }
    }

    private var validationColor: Color {
        switch currentValidation.kind {
        case .valid, .warning: .green
        case .invalid:
            candidate == nil && captureMessage == nil && registrationMessage == nil
                ? .secondary
                : .red
        }
    }

    private func handleModifiersChanged(
        _ modifiers: ShortcutModifiers,
        capsLock: Bool,
        function: Bool
    ) {
        liveModifiers = modifiers
        registrationMessage = nil
        if capsLock {
            candidate = nil
            captureMessage = "Caps Lock 由系统管理，不能作为全局快捷键。"
        } else if function {
            candidate = nil
            captureMessage = "Fn/Globe 键请使用设置页中的现有 Fn 预设。"
        } else {
            captureMessage = nil
        }
    }

    private func handleKeyDown(
        keyCode: UInt16,
        modifiers: ShortcutModifiers,
        function: Bool
    ) {
        registrationMessage = nil
        if keyCode == CustomShortcutBinding.escapeKeyCode {
            dismiss()
            return
        }
        if keyCode == CustomShortcutBinding.backspaceKeyCode {
            candidate = nil
            liveModifiers = []
            captureMessage = nil
            return
        }
        if keyCode == CustomShortcutBinding.capsLockKeyCode {
            candidate = nil
            captureMessage = "Caps Lock 由系统管理，不能作为全局快捷键。"
            return
        }
        if function {
            candidate = nil
            captureMessage = "Fn/Globe 键不能加入自定义组合，请使用现有 Fn 预设。"
            return
        }

        liveModifiers = modifiers
        captureMessage = nil
        candidate = CustomShortcutBinding(modifiers: modifiers, keyCode: keyCode)
    }

    private func useCandidate() {
        guard let candidate, candidate.validation.canUse else { return }
        switch appState.updateCustomShortcut(candidate) {
        case .success:
            dismiss()
        case .failure(let error):
            registrationMessage = error.localizedDescription
        }
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    let onKeyDown: (UInt16, ShortcutModifiers, Bool) -> Void
    let onModifiersChanged: (ShortcutModifiers, Bool, Bool) -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        ShortcutCaptureNSView(
            onKeyDown: onKeyDown,
            onModifiersChanged: onModifiersChanged
        )
    }

    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
        nsView.onKeyDown = onKeyDown
        nsView.onModifiersChanged = onModifiersChanged
        nsView.focus()
    }

    static func dismantleNSView(_ nsView: ShortcutCaptureNSView, coordinator: Void) {
        nsView.stopMonitoring()
    }
}

private final class ShortcutCaptureNSView: NSView {
    var onKeyDown: (UInt16, ShortcutModifiers, Bool) -> Void
    var onModifiersChanged: (ShortcutModifiers, Bool, Bool) -> Void
    private var localMonitor: Any?

    init(
        onKeyDown: @escaping (UInt16, ShortcutModifiers, Bool) -> Void,
        onModifiersChanged: @escaping (ShortcutModifiers, Bool, Bool) -> Void
    ) {
        self.onKeyDown = onKeyDown
        self.onModifiersChanged = onModifiersChanged
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopMonitoring()
        } else {
            startMonitoring()
            focus()
        }
    }

    func focus() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }

    func stopMonitoring() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        localMonitor = nil
    }

    private func startMonitoring() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged]
        ) { [weak self] event in
            guard let self,
                  let window = self.window,
                  window.isKeyWindow,
                  NSApp.keyWindow === window else {
                return event
            }
            self.process(event)
            return nil
        }
    }

    private func process(_ event: NSEvent) {
        let modifiers = ShortcutModifiers(eventFlags: event.modifierFlags)
        let usesFunction = event.modifierFlags.contains(.function)
        if event.type == .flagsChanged {
            onModifiersChanged(
                modifiers,
                event.keyCode == CustomShortcutBinding.capsLockKeyCode,
                usesFunction
            )
            return
        }
        guard event.type == .keyDown, !event.isARepeat else { return }
        onKeyDown(event.keyCode, modifiers, usesFunction)
    }
}
