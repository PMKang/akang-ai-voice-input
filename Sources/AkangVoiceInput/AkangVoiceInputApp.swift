import AppKit
import Combine
import SwiftUI

@main
struct AkangVoiceInputApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environmentObject(appState)
                .environment(\.locale, appState.interfaceLanguage.locale)
                .frame(minWidth: 1080, minHeight: 680)
                .onAppear {
                    appDelegate.configure(with: appState)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        if #available(macOS 13.0, *) {
            MenuBarExtra {
                MenuBarContent()
                    .environmentObject(appState)
                    .environment(\.locale, appState.interfaceLanguage.locale)
            } label: {
                Image(nsImage: NoboardMenuBarIcon.image(isListening: appState.voiceSessionState.isListening))
                    .accessibilityLabel(
                        appState.voiceSessionState.isListening ? "Noboard 正在录音" : "Noboard"
                    )
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mouseMonitor: Any?
    private weak var appState: AppState?
    private var appStateObservation: AnyCancellable?
    private var legacyStatusItem: NSStatusItem?

    func configure(with appState: AppState) {
        guard self.appState !== appState else { return }
        self.appState = appState

        guard #unavailable(macOS 13.0) else { return }
        appStateObservation = appState.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshLegacyStatusItem()
            }
        }
        refreshLegacyStatusItem()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Apply the saved icon before the first app window/Dock frame is presented.
        // The bundle icon is also blue, so a new install never flashes the legacy green icon.
        ApplicationIconBootstrap.applySelectedTheme()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateOtherCopies()
        NSApp.setActivationPolicy(.regular)
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            let point = event.locationInWindow
            let hitView = event.window?.contentView?.hitTest(point)
            let hitName = hitView.map { String(describing: type(of: $0)) } ?? "none"
            InteractionLog.event(
                "mouse.down window=\(event.window?.title ?? "none") point=\(Int(point.x)),\(Int(point.y)) hit=\(hitName)"
            )
            return event
        }
        DispatchQueue.main.async { [weak self] in
            self?.activateMainWindow()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        InteractionLog.event("app.didBecomeActive")
        activateMainWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        appStateObservation = nil
    }

    private func activateMainWindow() {
        guard let window = NSApp.windows.first(where: { !($0 is NSPanel) }) else { return }
        InteractionLog.event("window.makeKeyAndOrderFront")
        NSApp.activate(ignoringOtherApps: true)
        window.ignoresMouseEvents = false
        window.makeKeyAndOrderFront(nil)
    }

    private func refreshLegacyStatusItem() {
        guard #unavailable(macOS 13.0), let appState else { return }
        let item: NSStatusItem
        if let legacyStatusItem {
            item = legacyStatusItem
        } else {
            item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            legacyStatusItem = item
        }

        item.button?.image = NoboardMenuBarIcon.image(isListening: appState.voiceSessionState.isListening)
        item.button?.image?.isTemplate = true
        item.button?.toolTip = appState.voiceSessionState.isListening
            ? "Noboard 正在录音"
            : appState.productDisplayName

        let menu = NSMenu()
        let openItem = NSMenuItem(
            title: "打开 \(appState.productDisplayName)",
            action: #selector(openMainWindowFromLegacyMenu),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())

        let recordingItem = NSMenuItem(
            title: appState.voiceSessionState.isListening ? "停止录音" : "开始录音",
            action: #selector(toggleVoiceInputFromLegacyMenu),
            keyEquivalent: ""
        )
        recordingItem.target = self
        recordingItem.isEnabled = appState.voiceSessionState != .requestingPermission
            && appState.voiceSessionState != .finishing
        menu.addItem(recordingItem)
        let shortcutItem = NSMenuItem(title: "快捷键：\(appState.shortcutChoice.label)", action: nil, keyEquivalent: "")
        shortcutItem.isEnabled = false
        menu.addItem(shortcutItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 \(appState.productDisplayName)",
            action: #selector(quitFromLegacyMenu),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
    }

    @objc private func openMainWindowFromLegacyMenu() {
        activateMainWindow()
    }

    @objc private func toggleVoiceInputFromLegacyMenu() {
        appState?.toggleVoiceInput()
    }

    @objc private func quitFromLegacyMenu() {
        NSApp.terminate(nil)
    }

    private func terminateOtherCopies() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let otherCopies = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentPID }
        for application in otherCopies {
            InteractionLog.event("app.terminate-duplicate pid=\(application.processIdentifier)")
            application.terminate()
        }
        InteractionLog.event("app.runtime path=\(Bundle.main.bundleURL.path) pid=\(currentPID)")
    }
}

@available(macOS 13.0, *)
private struct MenuBarContent: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("打开 \(appState.productDisplayName)") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button(appState.voiceSessionState.isListening ? "停止录音" : "开始录音") {
            appState.toggleVoiceInput()
        }

        Text("快捷键：\(appState.shortcutChoice.label)")

        Divider()

        Button("退出 \(appState.productDisplayName)") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

private enum NoboardMenuBarIcon {
    static func image(isListening: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()
        NSColor.black.setFill()

        // A custom upright microphone: thick, hollow and symmetrical instead of
        // copying the system's filled microphone glyph.
        let microphone = NSBezierPath(
            roundedRect: NSRect(x: 6.2, y: 7.0, width: 5.6, height: 8.2),
            xRadius: 2.8,
            yRadius: 2.8
        )
        microphone.lineWidth = 1.7
        microphone.stroke()

        let yoke = NSBezierPath()
        yoke.move(to: NSPoint(x: 4.7, y: 10.2))
        yoke.line(to: NSPoint(x: 4.7, y: 7.2))
        yoke.curve(
            to: NSPoint(x: 9.0, y: 4.3),
            controlPoint1: NSPoint(x: 4.7, y: 5.3),
            controlPoint2: NSPoint(x: 6.6, y: 4.3)
        )
        yoke.curve(
            to: NSPoint(x: 13.3, y: 7.2),
            controlPoint1: NSPoint(x: 11.4, y: 4.3),
            controlPoint2: NSPoint(x: 13.3, y: 5.3)
        )
        yoke.line(to: NSPoint(x: 13.3, y: 10.2))
        yoke.lineWidth = 1.55
        yoke.lineCapStyle = .round
        yoke.stroke()

        let stem = NSBezierPath()
        stem.move(to: NSPoint(x: 9.0, y: 4.3))
        stem.line(to: NSPoint(x: 9.0, y: 2.6))
        stem.lineWidth = 1.55
        stem.lineCapStyle = .round
        stem.stroke()

        let base = NSBezierPath()
        base.move(to: NSPoint(x: 5.9, y: 2.6))
        base.line(to: NSPoint(x: 12.1, y: 2.6))
        base.lineWidth = 1.7
        base.lineCapStyle = .round
        base.stroke()

        if isListening {
            NSBezierPath(
                roundedRect: NSRect(x: 8.1, y: 8.7, width: 1.8, height: 4.9),
                xRadius: 0.9,
                yRadius: 0.9
            ).fill()
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
