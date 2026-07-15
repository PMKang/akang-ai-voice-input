import Foundation

struct DiagnosticEntry: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let category: String
    let message: String

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        category: String,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.message = DiagnosticSanitizer.sanitize(message)
    }
}

enum DiagnosticSanitizer {
    private static let patterns = [
        #"(?i)Bearer\s+[A-Za-z0-9._~+\-/]+=*"#,
        #"(?i)(api[_ -]?key\s*[:=]\s*)\S+"#,
        #"(?i)(workspace[_ -]?id\s*[:=]\s*)\S+"#,
        #"(?i)\b(?:sk|ark)-[A-Za-z0-9._-]{8,}\b"#,
        #"(?i)wss://[^/\s]+"#
    ]

    static func sanitize(_ value: String) -> String {
        patterns.reduce(value) { result, pattern in
            result.replacingOccurrences(
                of: pattern,
                with: "[已隐藏]",
                options: .regularExpression
            )
        }
    }
}

enum DiagnosticReportBuilder {
    static func build(
        entries: [DiagnosticEntry],
        readiness: AppReadiness,
        microphonePermission: MicrophonePermissionState,
        accessibilityPermission: AccessibilityPermissionState,
        model: String,
        inputTokens: Int,
        outputTokens: Int
    ) -> String {
        let header = [
            "阿康的 AI 语音输入法诊断报告",
            "生成时间：\(Date.now.ISO8601Format())",
            "就绪状态：\(readiness.label)",
            "麦克风权限：\(microphonePermission.rawValue)",
            "辅助功能权限：\(accessibilityPermission.rawValue)",
            "模型：\(model)",
            "最近 Token：输入 \(inputTokens)，输出 \(outputTokens)",
            "说明：报告不包含 API Key、Workspace ID、音频或转写正文。",
            "",
            "事件："
        ]
        let lines = entries.map { entry in
            "[\(entry.timestamp.ISO8601Format())] \(entry.category)：\(entry.message)"
        }
        return DiagnosticSanitizer.sanitize((header + lines).joined(separator: "\n"))
    }
}
