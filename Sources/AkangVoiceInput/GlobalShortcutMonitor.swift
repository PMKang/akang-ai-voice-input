import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum InputMonitoringPermissionState: String {
    case authorized = "已授权"
    case notAuthorized = "未授权"

    static var current: Self {
        let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        )
        guard let tap else { return .notAuthorized }
        CFMachPortInvalidate(tap)
        return .authorized
    }

    static func request() {
        _ = CGRequestListenEventAccess()
    }
}

enum ShortcutChoice: String, CaseIterable, Identifiable {
    case optionCommand = "option-command"
    case controlOption = "control-option"
    case function = "fn"
    case controlSpace = "control-space"
    case optionSpace = "option-space"
    case commandShiftSpace = "command-shift-space"

    var id: Self { self }

    var label: String {
        switch self {
        case .optionCommand: "⌥ ⌘"
        case .controlOption: "⌃ ⌥"
        case .function: "Fn"
        case .controlSpace: "⌃ Space"
        case .optionSpace: "⌥ Space"
        case .commandShiftSpace: "⌘ ⇧ Space"
        }
    }

    fileprivate var eventMask: NSEvent.EventTypeMask {
        modifierChordFlags == nil ? .keyDown : .flagsChanged
    }

    fileprivate var modifierChordFlags: CGEventFlags? {
        switch self {
        case .optionCommand: [.maskAlternate, .maskCommand]
        case .controlOption: [.maskControl, .maskAlternate]
        case .function: .maskSecondaryFn
        case .controlSpace, .optionSpace, .commandShiftSpace: nil
        }
    }

    var requiresInputMonitoring: Bool {
        modifierChordFlags != nil
    }

    var requiresAccessibilityControl: Bool {
        self == .function
    }

    fileprivate func matches(_ event: NSEvent, functionKeyWasDown: inout Bool) -> Bool {
        switch self {
        case .optionCommand:
            let isDown = event.modifierFlags.contains([.option, .command])
            defer { functionKeyWasDown = isDown }
            return isDown && !functionKeyWasDown

        case .controlOption:
            let isDown = event.modifierFlags.contains([.control, .option])
            defer { functionKeyWasDown = isDown }
            return isDown && !functionKeyWasDown

        case .function:
            let isDown = event.modifierFlags.contains(.function)
            defer { functionKeyWasDown = isDown }
            return isDown && !functionKeyWasDown

        case .controlSpace:
            return isSpace(event) && normalizedModifiers(event) == [.control]

        case .optionSpace:
            return isSpace(event) && normalizedModifiers(event) == [.option]

        case .commandShiftSpace:
            return isSpace(event) && normalizedModifiers(event) == [.command, .shift]
        }
    }

    private func isSpace(_ event: NSEvent) -> Bool {
        event.type == .keyDown && event.keyCode == 49 && !event.isARepeat
    }

    private func normalizedModifiers(_ event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection([.command, .shift, .option, .control])
    }
}

@MainActor
final class GlobalShortcutMonitor {
    private let modifierChordMonitor = ModifierChordMonitor()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var functionKeyIsDown = false
    private var onTrigger: (() -> Void)?
    private var choice: ShortcutChoice = .function
    private var lastTriggerAt = Date.distantPast

    func start(choice: ShortcutChoice, onTrigger: @escaping () -> Void) {
        stop()
        self.choice = choice
        self.onTrigger = onTrigger

        if let requiredFlags = choice.modifierChordFlags {
            let started = modifierChordMonitor.start(
                requiredFlags: requiredFlags,
                suppressSystemEvent: choice == .function
            ) { [weak self] in
                Task { @MainActor in
                    self?.trigger()
                }
            }
            InteractionLog.event("shortcut.modifier-monitor ready=\(started)")
            return
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: choice.eventMask) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: choice.eventMask) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
            return event
        }
    }

    func update(choice: ShortcutChoice) {
        guard choice != self.choice, let onTrigger else { return }
        start(choice: choice, onTrigger: onTrigger)
    }

    func stop() {
        modifierChordMonitor.stop()
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
        functionKeyIsDown = false
    }

    private func handle(_ event: NSEvent) {
        if choice.matches(event, functionKeyWasDown: &functionKeyIsDown) {
            trigger()
        }
    }

    private func trigger() {
        let now = Date()
        guard now.timeIntervalSince(lastTriggerAt) > 0.3 else { return }
        lastTriggerAt = now
        InteractionLog.event("shortcut.trigger choice=\(choice.rawValue)")
        onTrigger?()
    }
}

private final class ModifierChordMonitor: @unchecked Sendable {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var healthTimer: Timer?
    private var wakeObserver: Any?
    private var functionKeyWasDown = false
    private var requiredFlags: CGEventFlags = []
    private var suppressSystemEvent = false
    private var onTrigger: (() -> Void)?

    @discardableResult
    func start(
        requiredFlags: CGEventFlags,
        suppressSystemEvent: Bool,
        onTrigger: @escaping () -> Void
    ) -> Bool {
        stop()
        self.requiredFlags = requiredFlags
        self.suppressSystemEvent = suppressSystemEvent
        self.onTrigger = onTrigger

        guard CGPreflightListenEventAccess() else {
            InteractionLog.event("shortcut.modifier-event-tap unavailable input-monitoring=false")
            return false
        }
        if suppressSystemEvent, !AXIsProcessTrusted() {
            InteractionLog.event("shortcut.fn-event-tap unavailable accessibility=false")
            return false
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: suppressSystemEvent ? .defaultTap : .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<ModifierChordMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                let shouldSuppress = monitor.handle(type: type, event: event)
                if shouldSuppress {
                    return nil
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            InteractionLog.event("shortcut.fn-event-tap unavailable")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        self.eventTap = eventTap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        healthTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.ensureEventTapIsHealthy()
        }
        if let healthTimer {
            RunLoop.main.add(healthTimer, forMode: .common)
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshEventTapAfterWake()
        }
        InteractionLog.event("shortcut.modifier-event-tap started suppress=\(suppressSystemEvent)")
        return true
    }

    func stop() {
        healthTimer?.invalidate()
        healthTimer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        eventTap = nil
        runLoopSource = nil
        functionKeyWasDown = false
        onTrigger = nil
        suppressSystemEvent = false
    }

    private func ensureEventTapIsHealthy() {
        guard let eventTap else { return }
        guard !CGEvent.tapIsEnabled(tap: eventTap) else { return }
        functionKeyWasDown = false
        CGEvent.tapEnable(tap: eventTap, enable: true)
        InteractionLog.event("shortcut.modifier-event-tap health-recovered")
    }

    private func refreshEventTapAfterWake() {
        guard let eventTap else { return }
        functionKeyWasDown = false
        CGEvent.tapEnable(tap: eventTap, enable: true)
        InteractionLog.event("shortcut.modifier-event-tap refreshed-after-wake")
    }

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            functionKeyWasDown = false
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            InteractionLog.event("shortcut.modifier-event-tap re-enabled type=\(type.rawValue)")
            return false
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyDown || type == .keyUp {
            let isFunctionKeyEvent = keyCode == 63
            if isFunctionKeyEvent {
                InteractionLog.event("shortcut.fn-key-event type=\(type.rawValue) code=\(keyCode)")
            }
            return suppressSystemEvent && isFunctionKeyEvent
        }
        guard type == .flagsChanged else { return false }

        let isDown = event.flags.contains(requiredFlags)
        let wasDown = functionKeyWasDown
        let shouldTrigger = isDown && !functionKeyWasDown
        functionKeyWasDown = isDown
        if shouldTrigger {
            DispatchQueue.main.async { [weak self] in
                self?.onTrigger?()
            }
        }
        // Fn flagsChanged key codes differ across built-in and external
        // keyboards. Consuming the down/up pair by flag state prevents macOS
        // from also running its configured Globe/Fn action.
        return suppressSystemEvent && (isDown || wasDown)
    }
}
