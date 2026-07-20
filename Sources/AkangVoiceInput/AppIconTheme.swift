import AppKit
import SwiftUI

enum AppIconTheme: String, CaseIterable, Identifiable {
    case sky
    case violet
    case coral

    var id: String { rawValue }

    static let defaultsKey = "appIconTheme"

    static func resolved(from defaults: UserDefaults = .standard) -> AppIconTheme {
        defaults.string(forKey: defaultsKey)
            .flatMap(AppIconTheme.init(rawValue:))
            ?? .sky
    }

    var title: String {
        switch self {
        case .sky: "晴空蓝"
        case .violet: "靛紫"
        case .coral: "珊瑚"
        }
    }

    var resourceName: String {
        switch self {
        case .sky: "NoboardIconBlue"
        case .violet: "NoboardIconViolet"
        case .coral: "NoboardIconCoral"
        }
    }

    var accent: Color {
        switch self {
        case .sky: Color(red: 0.09, green: 0.47, blue: 1.0)
        case .violet: Color(red: 0.40, green: 0.35, blue: 0.91)
        case .coral: Color(red: 0.95, green: 0.42, blue: 0.36)
        }
    }

    var accentSoft: Color {
        switch self {
        case .sky: Color(red: 0.94, green: 0.97, blue: 1.0)
        case .violet: Color(red: 0.96, green: 0.95, blue: 1.0)
        case .coral: Color(red: 1.0, green: 0.96, blue: 0.95)
        }
    }

    func image(in bundle: Bundle = .main) -> NSImage? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

@MainActor
enum ApplicationIconBootstrap {
    @discardableResult
    static func applySelectedTheme(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        application: NSApplication = NSApp
    ) -> AppIconTheme {
        let theme = AppIconTheme.resolved(from: defaults)
        AkangVoiceInputTheme.apply(theme)
        if let image = theme.image(in: bundle) {
            application.applicationIconImage = image
        }
        return theme
    }
}

@MainActor
enum AkangVoiceInputTheme {
    private static var selectedIconTheme: AppIconTheme = .sky

    static var accent: Color { selectedIconTheme.accent }
    static var accentSoft: Color { selectedIconTheme.accentSoft }
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let border = Color(nsColor: .separatorColor).opacity(0.7)
    static let secondaryText = Color.secondary

    static func apply(_ iconTheme: AppIconTheme) {
        selectedIconTheme = iconTheme
    }
}

struct NoboardBrandIcon: View {
    let theme: AppIconTheme

    var body: some View {
        Group {
            if let image = theme.image() {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "waveform")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(theme.accent)
                    .padding(10)
            }
        }
        .accessibilityLabel("\(theme.title)图标")
    }
}
