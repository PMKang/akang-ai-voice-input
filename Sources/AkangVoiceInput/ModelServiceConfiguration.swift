import Foundation

/// Describes the currently selected model service, including the account pages that
/// belong to that service. Keep account capabilities here instead of treating them
/// as app-wide settings: credentials and billing semantics are provider-specific.
struct ModelServiceConfiguration: Equatable {
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
}
