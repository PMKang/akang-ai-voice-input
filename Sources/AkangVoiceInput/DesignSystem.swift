import SwiftUI

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
