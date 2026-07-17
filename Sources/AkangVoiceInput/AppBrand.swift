import Foundation

enum AppBrand {
    static let defaultDisplayName = "Noboard · 自在说"
    static let chineseWordmark = "自在说"
    static let englishWordmark = "No Board"
    static let productSuffix = "Talk free. Write naturally."
    static let legacyDefaultDisplayNames: Set<String> = [
        "阿康AI",
        "阿康的 AI",
        "阿康 AI",
        "阿康的 AI 语音输入法",
        "Arkane AI"
    ]
    static let maximumDisplayNameLength = 24

    static func normalizedDisplayName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultDisplayName }
        return String(trimmed.prefix(maximumDisplayNameLength))
    }

    static func productDisplayName(for displayName: String) -> String {
        normalizedDisplayName(displayName)
    }
}
