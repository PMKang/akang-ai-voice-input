import Foundation
import ServiceManagement

@MainActor
struct LoginItemService {
    enum Error: LocalizedError {
        case unsupportedSystem

        var errorDescription: String? {
            "开机启动需要 macOS 13 或更高版本。"
        }
    }

    static var isSupported: Bool {
        if #available(macOS 13.0, *) {
            true
        } else {
            false
        }
    }

    static var isEnabled: Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            throw Error.unsupportedSystem
        }
        if enabled {
            guard SMAppService.mainApp.status != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard SMAppService.mainApp.status == .enabled else { return }
            try SMAppService.mainApp.unregister()
        }
    }
}
