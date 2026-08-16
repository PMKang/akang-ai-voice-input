import Foundation
import Network

/// Records connectivity transitions without retaining host names, IP addresses,
/// or any request payload. It is diagnostic context for failures, not telemetry.
final class RuntimeDiagnosticsMonitor: @unchecked Sendable {
    var onNetworkStatusChanged: ((String) -> Void)?

    private let pathMonitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.akang.ai-voice-input.network-diagnostics")
    private var lastStatus: String?

    func start() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let status: String
            switch path.status {
            case .satisfied:
                if path.usesInterfaceType(.wifi) { status = "网络可用（Wi‑Fi）" }
                else if path.usesInterfaceType(.wiredEthernet) { status = "网络可用（有线）" }
                else if path.usesInterfaceType(.cellular) { status = "网络可用（蜂窝）" }
                else { status = "网络可用" }
            case .requiresConnection: status = "网络需要连接"
            case .unsatisfied: status = "网络不可用"
            @unknown default: status = "网络状态未知"
            }
            guard self?.lastStatus != status else { return }
            self?.lastStatus = status
            self?.onNetworkStatusChanged?(status)
        }
        pathMonitor.start(queue: queue)
    }

    func stop() {
        pathMonitor.cancel()
    }
}
