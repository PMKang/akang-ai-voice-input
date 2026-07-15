import AppKit
@preconcurrency import ApplicationServices
import Foundation

enum AccessibilityPermissionState: String {
    case authorized = "已授权"
    case notAuthorized = "未授权"

    static var current: Self {
        AXIsProcessTrusted() ? .authorized : .notAuthorized
    }
}

enum PasteShortcutSafety {
    private static let physicalModifiers: CGEventFlags = [
        .maskCommand,
        .maskAlternate,
        .maskControl,
        .maskShift,
        .maskSecondaryFn,
    ]

    static func hasActivePhysicalModifier(_ flags: CGEventFlags) -> Bool {
        !flags.intersection(physicalModifiers).isEmpty
    }
}

@MainActor
struct AccessibilityTextInserter {
    private struct FocusContext {
        let element: AXUIElement?
        let application: NSRunningApplication?
    }

    private static var trackedFocus: FocusContext?

    static func requestPermissionPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func insertIntoFocusedElement(_ text: String) -> Bool {
        guard AXIsProcessTrusted(), !text.isEmpty else { return false }

        let focus = trackedFocus ?? FocusContext(
            element: currentFocusedElement(),
            application: NSWorkspace.shared.frontmostApplication
        )
        trackedFocus = nil

        // Always keep a recoverable copy. Some Electron/WebKit editors report
        // AX write success without updating their visible document.
        guard writePlainTextToPasteboard(text) else {
            InteractionLog.event("output.insert pasteboard-write-failed")
            return false
        }

        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        if let application = focus.application,
           application.bundleIdentifier != ownBundleIdentifier {
            application.activate(options: [])
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(160))
                guard await waitForModifierKeysToBeReleased() else {
                    InteractionLog.event("output.insert skipped modifiers-still-active clipboard-retained=true")
                    return
                }
                restoreFocus(focus.element)
                guard writePlainTextToPasteboard(text) else {
                    InteractionLog.event("output.insert pasteboard-rewrite-failed clipboard-retained=true")
                    return
                }
                if postCommandV() {
                    InteractionLog.event("output.insert method=command-v")
                } else {
                    InteractionLog.event("output.insert paste-event-failed clipboard-retained=true")
                }
            }
            return true
        }

        if let focusedElement = focus.element {
            let selectedTextStatus = AXUIElementSetAttributeValue(
                focusedElement,
                kAXSelectedTextAttribute as CFString,
                text as CFString
            )
            if selectedTextStatus == .success {
                InteractionLog.event("output.insert method=ax-selected-text")
                return true
            }
        }

        InteractionLog.event("output.insert unavailable clipboard-retained=true")
        return false
    }

    static func trackFocusedElement() {
        let element = currentFocusedElement()
        let application = NSWorkspace.shared.frontmostApplication
        trackedFocus = FocusContext(element: element, application: application)
        InteractionLog.event(
            "output.focus tracked=\(element != nil) app=\(application?.bundleIdentifier ?? "unknown")"
        )
    }

    static func clearTrackedElement() {
        trackedFocus = nil
    }

    private static func currentFocusedElement() -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )

        guard focusedStatus == .success, let focusedValue else { return nil }
        return (focusedValue as! AXUIElement)
    }

    private static func restoreFocus(_ element: AXUIElement?) {
        guard let element else { return }
        let status = AXUIElementSetAttributeValue(
            element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        InteractionLog.event("output.focus restore-status=\(status.rawValue)")
    }

    private static func writePlainTextToPasteboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { return false }
        return pasteboard.string(forType: .string) == text
    }

    private static func waitForModifierKeysToBeReleased() async -> Bool {
        let deadline = Date().addingTimeInterval(2)
        repeat {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if !PasteShortcutSafety.hasActivePhysicalModifier(flags) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(40))
        } while Date() < deadline

        return !PasteShortcutSafety.hasActivePhysicalModifier(
            CGEventSource.flagsState(.combinedSessionState)
        )
    }

    private static func postCommandV() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: 9,
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: 9,
                keyDown: false
              ) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
