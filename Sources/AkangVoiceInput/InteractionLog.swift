import Foundation
import OSLog

enum InteractionLog {
    private static let logger = Logger(
        subsystem: "com.akang.ai-voice-input",
        category: "interaction"
    )

    static func event(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }
}
