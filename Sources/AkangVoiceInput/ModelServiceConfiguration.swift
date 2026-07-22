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
        let capabilityLabel: String
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

    static let doubaoRealtime = Self(
        providerName: "豆包",
        modelID: "doubao-seed-asr-2-0",
        accountBalanceCapability: .unavailable(
            reason: "当前版本尚未接入豆包账户余额查询，请在火山引擎控制台查看。"
        ),
        usageDetailsURL: URL(string: "https://console.volcengine.com/speech/new/overview")!
    )

    static let voiceModelCatalog: [CatalogOption] = [
        .init(
            id: "qwen3.5-omni-flash-realtime",
            provider: "阿里云百炼",
            name: "Qwen 3.5 Omni Flash Realtime",
            subtitle: "当前默认 · 实时语音输入 · 支持表达方式提示词",
            promptCompatible: true,
            capabilityLabel: "支持表达方式提示词",
            availability: .active
        ),
        .init(
            id: "qwen3.5-omni-plus-realtime",
            provider: "阿里云百炼",
            name: "Qwen 3.5 Omni Plus Realtime",
            subtitle: "实时语音输入 · Prompt 上下文、多语种与情感识别",
            promptCompatible: true,
            capabilityLabel: "支持表达方式提示词",
            availability: .active
        ),
        .init(
            id: "fun-asr-realtime",
            provider: "阿里云百炼",
            name: "Fun ASR Realtime",
            subtitle: "实时语音识别 · 热词、多语种及方言；个人词典将映射为热词",
            promptCompatible: false,
            capabilityLabel: "支持热词与个人词典",
            availability: .active
        ),
        .init(
            id: "doubao-seed-asr-2-0",
            provider: "豆包",
            name: "Doubao Streaming ASR 2.0",
            subtitle: "双向流式 WebSocket · 原始实时转写；不执行表达方式提示词",
            promptCompatible: false,
            capabilityLabel: "支持实时转写，不支持表达方式",
            availability: .active
        )
    ]
}
