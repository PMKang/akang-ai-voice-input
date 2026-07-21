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

/// A Monterey-friendly empty state. `ContentUnavailableView` is only available
/// on newer macOS releases, while this keeps the same calm visual hierarchy.
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}
