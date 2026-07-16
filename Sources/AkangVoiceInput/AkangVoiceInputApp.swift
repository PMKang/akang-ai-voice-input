import AppKit
import SwiftUI

@main
struct AkangVoiceInputApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(appState)
                .frame(minWidth: 1080, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(appState)
        } label: {
            Label(appState.productDisplayName, systemImage: appState.voiceSessionState.isListening ? "waveform.circle.fill" : "waveform")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mouseMonitor: Any?

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
    }

    private func activateMainWindow() {
        guard let window = NSApp.windows.first(where: { !($0 is NSPanel) }) else { return }
        InteractionLog.event("window.makeKeyAndOrderFront")
        NSApp.activate(ignoringOtherApps: true)
        window.ignoresMouseEvents = false
        window.makeKeyAndOrderFront(nil)
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

private struct MenuBarContent: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("打开\(appState.productDisplayName)") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button(appState.voiceSessionState.isListening ? "停止录音" : "开始录音") {
            appState.toggleVoiceInput()
        }

        Text("快捷键：\(appState.shortcutChoice.label)")

        Divider()

        Button("退出\(appState.productDisplayName)") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
