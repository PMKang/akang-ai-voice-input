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
            NoboardMenuBarGlyph(isListening: appState.voiceSessionState.isListening)
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
        Button("打开 \(AppBrand.defaultDisplayName)") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button(appState.voiceSessionState.isListening ? "停止录音" : "开始录音") {
            appState.toggleVoiceInput()
        }

        Text("快捷键：\(appState.shortcutChoice.label)")

        Divider()

        Button("退出 \(AppBrand.defaultDisplayName)") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

private struct NoboardMenuBarGlyph: View {
    let isListening: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NoboardMenuBarRibbon()
                .fill(.primary)
                .frame(width: 18, height: 18)

            if isListening {
                Circle()
                    .fill(.primary)
                    .frame(width: 4, height: 4)
                    .offset(x: 1, y: -1)
                    .accessibilityLabel("正在录音")
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityLabel(isListening ? "Noboard 正在录音" : "Noboard")
    }
}

private struct NoboardMenuBarRibbon: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        var path = Path()

        path.move(to: CGPoint(x: width * 0.06, y: height * 0.70))
        path.addCurve(
            to: CGPoint(x: width * 0.48, y: height * 0.28),
            control1: CGPoint(x: width * 0.23, y: height * 0.68),
            control2: CGPoint(x: width * 0.33, y: height * 0.22)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.94, y: height * 0.62),
            control1: CGPoint(x: width * 0.66, y: height * 0.30),
            control2: CGPoint(x: width * 0.80, y: height * 0.66)
        )
        path.addLine(to: CGPoint(x: width * 0.94, y: height * 0.86))
        path.addCurve(
            to: CGPoint(x: width * 0.50, y: height * 0.55),
            control1: CGPoint(x: width * 0.78, y: height * 0.77),
            control2: CGPoint(x: width * 0.65, y: height * 0.51)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.10, y: height * 0.88),
            control1: CGPoint(x: width * 0.36, y: height * 0.62),
            control2: CGPoint(x: width * 0.23, y: height * 0.91)
        )
        path.closeSubpath()
        return path
    }
}
