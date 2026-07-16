import SwiftUI

enum AkangVoiceInputTheme {
    static let accent = Color(red: 0.04, green: 0.43, blue: 0.27)
    static let accentSoft = Color(red: 0.91, green: 0.96, blue: 0.93)
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let border = Color(nsColor: .separatorColor).opacity(0.7)
    static let secondaryText = Color.secondary
}

struct PanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AkangVoiceInputTheme.border, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func akangVoiceInputPanel() -> some View {
        modifier(PanelModifier())
    }
}
