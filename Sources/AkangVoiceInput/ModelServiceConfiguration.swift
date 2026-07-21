import Foundation

/// Describes the currently selected model service, including the account pages that
/// belong to that service. Keep account capabilities here instead of treating them
/// as app-wide settings: credentials and billing semantics are provider-specific.
struct ModelServiceConfiguration: Equatable {
    enum Availability: Equatable {
        case active
        case planned
        case excluded
    }

    struct CatalogOption: Identifiable, Equatable {
        let id: String
        let provider: String
        let name: String
        let subtitle: String
        let promptCompatible: Bool
        let availability: Availability
    }
    enum AccountBalanceCapability: Equatable {
        case unavailable(reason: String)
        case available(currencyCode: String)
    }

    let providerName: String
    let modelID: String
    let accountBalanceCapability: AccountBalanceCapability
    let usageDetailsURL: URL

    static let bailianRealtime = Self(
        providerName: "阿里云百炼",
        modelID: "qwen3.5-omni-flash-realtime",
        accountBalanceCapability: .unavailable(
            reason: "当前供应商暂不支持账户余额查询。"
        ),
        usageDetailsURL: URL(string: "https://bailian.console.aliyun.com/cn-beijing/?tab=costing-balance")!
    )

    static let voiceModelCatalog: [CatalogOption] = [
        .init(
            id: "qwen3.5-omni-flash-realtime",
            provider: "阿里云百炼",
            name: "Qwen Omni Flash Realtime",
            subtitle: "当前默认 · 实时语音输入 · 支持表达方式提示词",
            promptCompatible: true,
            availability: .active
        ),
        .init(
            id: "qwen-omni-realtime-pro-validation",
            provider: "阿里云百炼",
            name: "Qwen Omni Realtime Pro",
            subtitle: "待接入 · 需按官方 Realtime 协议与定价完成兼容验证",
            promptCompatible: true,
            availability: .planned
        ),
        .init(
            id: "doubao-realtime-validation",
            provider: "豆包",
            name: "Doubao Speech Realtime",
            subtitle: "待开发 · 将单独接入鉴权、音频协议与费用统计",
            promptCompatible: true,
            availability: .planned
        ),
        .init(
            id: "fun-music-excluded",
            provider: "阿里云百炼",
            name: "Fun Music",
            subtitle: "不适用 · 音乐生成模型，不是实时语音输入模型",
            promptCompatible: false,
            availability: .excluded
        )
    ]
}
