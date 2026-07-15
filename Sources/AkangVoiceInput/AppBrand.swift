import Foundation

enum AppBrand {
    static let defaultDisplayName = "阿康AI"
    static let legacyDefaultDisplayNames: Set<String> = ["阿康的 AI", "阿康 AI", "Arkane AI"]
    static let productSuffix = "语音输入法"
    static let maximumDisplayNameLength = 24

    static func normalizedDisplayName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultDisplayName }
        return String(trimmed.prefix(maximumDisplayNameLength))
    }

    static func productDisplayName(for displayName: String) -> String {
        "\(normalizedDisplayName(displayName)) \(productSuffix)"
    }
}
