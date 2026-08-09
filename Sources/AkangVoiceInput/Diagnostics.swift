import Foundation

struct DiagnosticEntry: Identifiable, Equatable, Codable {
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

struct PreviousRunDiagnostics: Equatable {
    let entries: [DiagnosticEntry]
    let endedUnexpectedly: Bool
}

/// Persists a small, already-redacted ring buffer. This does not try to catch
/// every process signal (that is not safe from a signal handler); instead it
/// makes the next launch able to identify that the previous run never reached
/// the normal-termination marker and preserves its final useful events.
final class CrashDiagnosticStore {
    private struct Snapshot: Codable {
        var entries: [DiagnosticEntry]
        var didExitNormally: Bool
    }

    static let maximumEntries = 160

    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL = CrashDiagnosticStore.defaultFileURL(), fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func beginRun() -> PreviousRunDiagnostics {
        let previous = load()
        let result = PreviousRunDiagnostics(
            entries: previous.entries,
            endedUnexpectedly: !previous.didExitNormally && !previous.entries.isEmpty
        )
        save(Snapshot(entries: previous.entries, didExitNormally: false))
        return result
    }

    func append(_ entry: DiagnosticEntry) {
        var snapshot = load()
        snapshot.entries.append(entry)
        if snapshot.entries.count > Self.maximumEntries {
            snapshot.entries.removeFirst(snapshot.entries.count - Self.maximumEntries)
        }
        snapshot.didExitNormally = false
        save(snapshot)
    }

    func markCleanShutdown() {
        var snapshot = load()
        snapshot.didExitNormally = true
        save(snapshot)
    }

    func clear() {
        save(Snapshot(entries: [], didExitNormally: false))
    }

    private func load() -> Snapshot {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return Snapshot(entries: [], didExitNormally: true)
        }
        return snapshot
    }

    private func save(_ snapshot: Snapshot) {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Diagnostics must never destabilize the input method. Unified log
            // remains available when local disk persistence is unavailable.
            InteractionLog.event("diagnostic.persistence.failed error=\(error.localizedDescription)")
        }
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("AkangVoiceInput", isDirectory: true)
            .appendingPathComponent("last-run-diagnostics.json")
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
            "Noboard · 自在说诊断报告",
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
