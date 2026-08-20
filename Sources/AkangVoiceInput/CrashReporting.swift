import Foundation

enum CrashReportKind: String, Codable, Sendable {
    case crash
    case exception
    case test
}

struct CrashReportBreadcrumb: Codable, Equatable, Sendable {
    let occurredAt: String
    let category: String
    let message: String

    init(entry: DiagnosticEntry) {
        occurredAt = entry.timestamp.ISO8601Format()
        category = CrashReportText.clip(DiagnosticSanitizer.sanitize(entry.category), maximumBytes: 64)
        message = CrashReportText.clip(DiagnosticSanitizer.sanitize(entry.message), maximumBytes: 240)
    }
}

struct CrashReportPayload: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let reportID: String
    let installID: String
    let product: String
    let kind: CrashReportKind
    let source: String
    let label: String
    let version: String
    let build: String
    let osVersion: String
    let architecture: String
    let errorType: String
    let errorMessage: String
    let stack: String
    let topFrame: String
    let fingerprintHint: String
    let occurredAt: String
    let incidentID: String
    let breadcrumbs: [CrashReportBreadcrumb]

    var localDeduplicationKey: String {
        if kind == .test {
            return "test:\(reportID)"
        }
        if !incidentID.isEmpty {
            return "incident:\(incidentID)"
        }
        return [source, label, occurredAt].joined(separator: ":")
    }
}

enum CrashReportInstallationIdentity {
    private static let defaultsKey = "NoboardCrashReportInstallID"

    static func current(defaults: UserDefaults = .standard) -> String {
        if let stored = defaults.string(forKey: defaultsKey), isValidUUID(stored) {
            return stored.lowercased()
        }
        let generated = UUID().uuidString.lowercased()
        defaults.set(generated, forKey: defaultsKey)
        return generated
    }

    private static func isValidUUID(_ value: String) -> Bool {
        UUID(uuidString: value) != nil
    }
}

struct CrashReportBuildInfo: Equatable, Sendable {
    let version: String
    let build: String
    let osVersion: String
    let architecture: String

    static func current(bundle: Bundle = .main) -> CrashReportBuildInfo {
        CrashReportBuildInfo(
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: currentArchitecture
        )
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }
}

enum CrashReportConfiguration {
    static let endpointInfoKey = "NoboardCrashReportEndpoint"
    static let endpointEnvironmentKey = "NOBOARD_CRASH_REPORT_ENDPOINT"

    static func endpoint(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        let environmentValue = environment[endpointEnvironmentKey]
        let bundleValue = bundle.object(forInfoDictionaryKey: endpointInfoKey) as? String
        return validatedEndpoint(environmentValue) ?? validatedEndpoint(bundleValue)
    }

    static func validatedEndpoint(_ rawValue: String?) -> URL? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }
        if scheme == "https" {
            return url
        }
        if scheme == "http", ["127.0.0.1", "localhost", "::1"].contains(host) {
            return url
        }
        return nil
    }

}

struct ParsedMacCrashReport: Equatable, Sendable {
    let incidentID: String
    let occurredAt: String
    let version: String
    let build: String
    let osVersion: String
    let exceptionType: String
    let signal: String
    let exceptionSubtype: String
    let terminationReason: String
    let terminationProcess: String
    let frames: [String]

    var topFrame: String { frames.first ?? "" }

    /// Build scripts intentionally stop the previous app before launching a
    /// new copy. macOS records that SIGABRT as an .ips report, but it is not
    /// an application crash worth reporting.
    var isExpectedTermination: Bool {
        ["killall", "pkill"].contains(terminationProcess.lowercased())
    }
}

enum MacCrashReportParser {
    static func parse(
        data: Data,
        expectedBundleIdentifier: String,
        expectedProcessName: String
    ) -> ParsedMacCrashReport? {
        guard let objects = decodeObjects(data: data) else { return nil }
        let header = objects.header
        let body = objects.body

        let bundleInfo = dictionary(body["bundleInfo"])
        let bundleIdentifier = firstNonEmpty(
            string(header["bundleID"]),
            string(bundleInfo["CFBundleIdentifier"]),
            string(body["bundleID"])
        )
        let processName = firstNonEmpty(
            string(header["app_name"]),
            string(body["procName"]),
            string(header["name"])
        )
        guard bundleIdentifier == expectedBundleIdentifier
                || processName == expectedProcessName
                || processName.hasPrefix(expectedProcessName) else {
            return nil
        }

        let exception = dictionary(body["exception"])
        let termination = dictionary(body["termination"])
        let exceptionType = firstNonEmpty(string(exception["type"]), "UnknownCrash")
        let signal = string(exception["signal"])
        let subtype = string(exception["subtype"])
        let terminationReason = [
            string(termination["namespace"]),
            string(termination["indicator"]),
            numberString(termination["code"])
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
        let terminationProcess = string(termination["byProc"])

        let frames = parsedFrames(
            body: body,
            expectedBundleIdentifier: expectedBundleIdentifier,
            expectedProcessName: expectedProcessName
        )

        return ParsedMacCrashReport(
            incidentID: CrashReportText.clip(
                firstNonEmpty(string(header["incident_id"]), string(body["incident"])),
                maximumBytes: 128
            ),
            occurredAt: CrashReportText.clip(
                firstNonEmpty(string(header["timestamp"]), string(body["captureTime"])),
                maximumBytes: 96
            ),
            version: CrashReportText.clip(
                firstNonEmpty(
                    string(header["app_version"]),
                    string(bundleInfo["CFBundleShortVersionString"])
                ),
                maximumBytes: 64
            ),
            build: CrashReportText.clip(
                firstNonEmpty(string(header["build_version"]), string(bundleInfo["CFBundleVersion"])),
                maximumBytes: 64
            ),
            osVersion: CrashReportText.clip(
                firstNonEmpty(string(header["os_version"]), string(body["osVersion"])),
                maximumBytes: 160
            ),
            exceptionType: CrashReportText.clip(exceptionType, maximumBytes: 128),
            signal: CrashReportText.clip(signal, maximumBytes: 64),
            exceptionSubtype: CrashReportText.clip(subtype, maximumBytes: 256),
            terminationReason: CrashReportText.clip(terminationReason, maximumBytes: 256),
            terminationProcess: CrashReportText.clip(terminationProcess, maximumBytes: 64),
            frames: Array(frames.prefix(24))
        )
    }

    private static func decodeObjects(data: Data) -> (header: [String: Any], body: [String: Any])? {
        if let object = try? JSONSerialization.jsonObject(with: data),
           let dictionary = object as? [String: Any] {
            return (dictionary, dictionary)
        }
        guard let newline = data.firstIndex(of: 0x0A) else { return nil }
        let bodyStart = data.index(after: newline)
        let headerData = Data(data[..<newline])
        let bodyData = Data(data[bodyStart...])
        guard let header = (try? JSONSerialization.jsonObject(with: headerData)) as? [String: Any],
              let body = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] else {
            return nil
        }
        return (header, body)
    }

    private static func parsedFrames(
        body: [String: Any],
        expectedBundleIdentifier: String,
        expectedProcessName: String
    ) -> [String] {
        let images = array(body["usedImages"]).map(dictionary)
        let threads = array(body["threads"]).map(dictionary)
        let faultingThread = integer(body["faultingThread"])
        let selectedThread: [String: Any]?
        if faultingThread >= 0, threads.indices.contains(faultingThread) {
            selectedThread = threads[faultingThread]
        } else {
            selectedThread = threads.first { boolean($0["triggered"]) }
        }
        guard let selectedThread else { return [] }

        var applicationFrames: [String] = []
        var fallbackFrames: [String] = []
        for frameValue in array(selectedThread["frames"]) {
            let frame = dictionary(frameValue)
            let imageIndex = integer(frame["imageIndex"])
            let image = images.indices.contains(imageIndex) ? images[imageIndex] : [:]
            let imageName = firstNonEmpty(string(image["name"]), "image\(max(0, imageIndex))")
            let imageBundleIdentifier = firstNonEmpty(
                string(image["CFBundleIdentifier"]),
                string(dictionary(image["bundleInfo"])["CFBundleIdentifier"])
            )
            let symbol = firstNonEmpty(string(frame["symbol"]), "offset \(numberString(frame["imageOffset"]))")
            let symbolLocation = numberString(frame["symbolLocation"])
            let rawLine = symbolLocation.isEmpty
                ? "\(imageName) · \(symbol)"
                : "\(imageName) · \(symbol) + \(symbolLocation)"
            let line = CrashReportText.clip(DiagnosticSanitizer.sanitize(rawLine), maximumBytes: 500)
            fallbackFrames.append(line)
            if imageBundleIdentifier == expectedBundleIdentifier || imageName == expectedProcessName {
                applicationFrames.append(line)
            }
        }
        return applicationFrames.isEmpty ? fallbackFrames : applicationFrames
    }

    private static func array(_ value: Any?) -> [Any] {
        value as? [Any] ?? []
    }

    private static func dictionary(_ value: Any?) -> [String: Any] {
        value as? [String: Any] ?? [:]
    }

    private static func string(_ value: Any?) -> String {
        value as? String ?? ""
    }

    private static func numberString(_ value: Any?) -> String {
        if let number = value as? NSNumber { return number.stringValue }
        return value as? String ?? ""
    }

    private static func integer(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        return (value as? Int) ?? -1
    }

    private static func boolean(_ value: Any?) -> Bool {
        (value as? NSNumber)?.boolValue ?? (value as? Bool) ?? false
    }

    private static func firstNonEmpty(_ values: String...) -> String {
        values.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
    }
}

struct MacCrashReportScanner: Sendable {
    static let maximumCrashFileBytes = 4 * 1024 * 1024

    let directoryURL: URL

    init(directoryURL: URL = MacCrashReportScanner.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    func newestReport(
        since startDate: Date,
        before endDate: Date,
        expectedBundleIdentifier: String,
        expectedProcessName: String
    ) -> ParsedMacCrashReport? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        let lowerBound = startDate.addingTimeInterval(-5)
        let upperBound = endDate.addingTimeInterval(5)
        let candidates = urls.compactMap { url -> (url: URL, modifiedAt: Date)? in
            guard url.pathExtension.lowercased() == "ips",
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  fileSize > 0,
                  fileSize <= Self.maximumCrashFileBytes,
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt >= lowerBound,
                  modifiedAt <= upperBound else {
                return nil
            }
            return (url, modifiedAt)
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
        .prefix(30)

        for candidate in candidates {
            guard let data = try? Data(contentsOf: candidate.url, options: .mappedIfSafe),
                  let report = MacCrashReportParser.parse(
                    data: data,
                    expectedBundleIdentifier: expectedBundleIdentifier,
                    expectedProcessName: expectedProcessName
                  ) else {
                continue
            }
            return report
        }
        return nil
    }

    private static func defaultDirectoryURL() -> URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        return library.appendingPathComponent("Logs/DiagnosticReports", isDirectory: true)
    }
}

enum CrashReportPayloadFactory {
    static let bundleIdentifier = "com.akang.ai-voice-input"
    static let processName = "AkangVoiceInput"

    static func previousRunReport(
        previousRun: PreviousRunDiagnostics,
        scanner: MacCrashReportScanner,
        buildInfo: CrashReportBuildInfo = .current(),
        now: Date = .now
    ) -> CrashReportPayload? {
        guard previousRun.endedUnexpectedly else { return nil }
        let breadcrumbs = previousRun.entries.suffix(40).map(CrashReportBreadcrumb.init)
        let parsedReport = previousRun.startedAt.flatMap { startedAt in
            scanner.newestReport(
                since: startedAt,
                before: now,
                expectedBundleIdentifier: bundleIdentifier,
                expectedProcessName: processName
            )
        }

        if let parsedReport {
            if parsedReport.isExpectedTermination {
                return nil
            }
            let errorMessage = [
                parsedReport.signal,
                parsedReport.exceptionSubtype,
                parsedReport.terminationReason
            ]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
            let topFrame = parsedReport.topFrame
            return CrashReportPayload(
                schemaVersion: 1,
                reportID: UUID().uuidString.lowercased(),
                installID: CrashReportInstallationIdentity.current(),
                product: "noboard",
                kind: .crash,
                source: "macos.ips",
                label: parsedReport.exceptionType,
                version: parsedReport.version.isEmpty ? buildInfo.version : parsedReport.version,
                build: parsedReport.build.isEmpty ? buildInfo.build : parsedReport.build,
                osVersion: parsedReport.osVersion.isEmpty ? buildInfo.osVersion : parsedReport.osVersion,
                architecture: buildInfo.architecture,
                errorType: parsedReport.exceptionType,
                errorMessage: CrashReportText.clip(errorMessage, maximumBytes: 1_000),
                stack: CrashReportText.clip(parsedReport.frames.joined(separator: "\n"), maximumBytes: 12_000),
                topFrame: CrashReportText.clip(topFrame, maximumBytes: 500),
                fingerprintHint: CrashReportText.clip(
                    [parsedReport.exceptionType, parsedReport.signal, topFrame].joined(separator: "|"),
                    maximumBytes: 700
                ),
                occurredAt: parsedReport.occurredAt.isEmpty ? now.ISO8601Format() : parsedReport.occurredAt,
                incidentID: parsedReport.incidentID,
                breadcrumbs: breadcrumbs
            )
        }

        return CrashReportPayload(
            schemaVersion: 1,
            reportID: UUID().uuidString.lowercased(),
            installID: CrashReportInstallationIdentity.current(),
            product: "noboard",
            kind: .crash,
            source: "macos.lifecycle",
            label: "unexpected-exit",
            version: buildInfo.version,
            build: buildInfo.build,
            osVersion: buildInfo.osVersion,
            architecture: buildInfo.architecture,
            errorType: "UnexpectedExit",
            errorMessage: "上次进程未记录正常退出，且未找到同一运行时段内可匹配的 macOS 崩溃报告。",
            stack: "",
            topFrame: "",
            fingerprintHint: "noboard|macos.lifecycle|unexpected-exit",
            occurredAt: now.ISO8601Format(),
            incidentID: "",
            breadcrumbs: breadcrumbs
        )
    }

    static func testReport(
        entries: [DiagnosticEntry],
        buildInfo: CrashReportBuildInfo = .current(),
        now: Date = .now
    ) -> CrashReportPayload {
        CrashReportPayload(
            schemaVersion: 1,
            reportID: UUID().uuidString.lowercased(),
            installID: CrashReportInstallationIdentity.current(),
            product: "noboard",
            kind: .test,
            source: "macos.manual-test",
            label: "feishu-webhook-test",
            version: buildInfo.version,
            build: buildInfo.build,
            osVersion: buildInfo.osVersion,
            architecture: buildInfo.architecture,
            errorType: "CrashReporterTest",
            errorMessage: "这是一条由自在说开发者选项主动发送的崩溃上报测试。",
            stack: "",
            topFrame: "CrashReportPayloadFactory.testReport",
            fingerprintHint: "noboard|manual-test",
            occurredAt: now.ISO8601Format(),
            incidentID: "",
            breadcrumbs: entries.suffix(10).map(CrashReportBreadcrumb.init)
        )
    }
}

final class CrashReportQueueStore {
    static let maximumReports = 20

    private struct Snapshot: Codable {
        var reports: [CrashReportPayload]
    }

    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL = CrashReportQueueStore.defaultFileURL(), fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() -> [CrashReportPayload] {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return []
        }
        return snapshot.reports
    }

    func enqueue(_ report: CrashReportPayload) throws {
        var reports = load()
        guard !reports.contains(where: { $0.localDeduplicationKey == report.localDeduplicationKey }) else {
            return
        }
        reports.append(report)
        if reports.count > Self.maximumReports {
            reports.removeFirst(reports.count - Self.maximumReports)
        }
        try save(reports)
    }

    func remove(reportID: String) throws {
        let reports = load().filter { $0.reportID != reportID }
        try save(reports)
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    private func save(_ reports: [CrashReportPayload]) throws {
        if reports.isEmpty {
            try clear()
            return
        }
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let data = try JSONEncoder().encode(Snapshot(reports: reports))
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("AkangVoiceInput", isDirectory: true)
            .appendingPathComponent("pending-crash-reports.json")
    }
}

protocol CrashReportTransport: Sendable {
    func send(_ data: Data, to endpoint: URL) async throws
}

struct URLSessionCrashReportTransport: CrashReportTransport {
    private let bundle: Bundle
    private let environment: [String: String]

    init(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.bundle = bundle
        self.environment = environment
    }

    func send(_ data: Data, to endpoint: URL) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
        request.setValue("Noboard-CrashReporter/1", forHTTPHeaderField: "User-Agent")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw CrashReportTransportError.rejected(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0
            )
        }
    }
}

enum CrashReportTransportError: LocalizedError {
    case rejected(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .rejected(let statusCode):
            "上报服务返回 HTTP \(statusCode)"
        }
    }
}

enum CrashReportDeliveryResult: Equatable, Sendable {
    case nothingToSend
    case sent(count: Int)
    case queued(pending: Int, reason: String)

    var displayMessage: String {
        switch self {
        case .nothingToSend:
            "没有待发送的崩溃报告"
        case .sent(let count):
            "上报服务已接收 \(count) 份脱敏报告；飞书送达请以群消息为准"
        case .queued(let pending, let reason):
            "已有 \(pending) 份报告留在本机队列：\(reason)"
        }
    }
}

actor CrashReportService {
    private let endpoint: URL?
    private let queueStore: CrashReportQueueStore
    private let scanner: MacCrashReportScanner
    private let transport: any CrashReportTransport
    private let buildInfo: CrashReportBuildInfo

    init(
        endpoint: URL? = CrashReportConfiguration.endpoint(),
        queueURL: URL = CrashReportQueueStore.defaultQueueURL,
        diagnosticReportsDirectoryURL: URL = MacCrashReportScanner.defaultReportsDirectoryURL,
        transport: any CrashReportTransport = URLSessionCrashReportTransport(),
        buildInfo: CrashReportBuildInfo = .current()
    ) {
        self.endpoint = endpoint
        queueStore = CrashReportQueueStore(fileURL: queueURL)
        scanner = MacCrashReportScanner(directoryURL: diagnosticReportsDirectoryURL)
        self.transport = transport
        self.buildInfo = buildInfo
    }

    func capturePreviousRunAndFlush(
        _ previousRun: PreviousRunDiagnostics,
        now: Date = .now
    ) async -> CrashReportDeliveryResult {
        var report = CrashReportPayloadFactory.previousRunReport(
            previousRun: previousRun,
            scanner: scanner,
            buildInfo: buildInfo,
            now: now
        )

        // macOS may write the .ips file well after the app is relaunched.
        // If the first scan only produced the lifecycle fallback, keep the
        // retry loop in this background service so the UI remains usable.
        if report?.source == "macos.lifecycle" {
            for delaySeconds in [10, 20, 40] {
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
                if let retry = CrashReportPayloadFactory.previousRunReport(
                    previousRun: previousRun,
                    scanner: scanner,
                    buildInfo: buildInfo,
                    now: .now
                ), retry.source == "macos.ips" {
                    report = retry
                    break
                }
            }
        }

        if let report {
            do {
                try queueStore.enqueue(report)
            } catch {
                return .queued(pending: queueStore.load().count, reason: "本地队列写入失败")
            }
        }
        return await flush()
    }

    func sendTestReport(entries: [DiagnosticEntry], now: Date = .now) async -> CrashReportDeliveryResult {
        do {
            try queueStore.enqueue(
                CrashReportPayloadFactory.testReport(entries: entries, buildInfo: buildInfo, now: now)
            )
        } catch {
            return .queued(pending: queueStore.load().count, reason: "本地队列写入失败")
        }
        return await flush()
    }

    func flush() async -> CrashReportDeliveryResult {
        var pending = queueStore.load()
        guard !pending.isEmpty else { return .nothingToSend }
        guard let endpoint else {
            return .queued(pending: pending.count, reason: "尚未配置 Worker 地址")
        }
        var sentCount = 0
        for report in pending {
            guard !Task.isCancelled else {
                return .queued(pending: queueStore.load().count, reason: "发送已取消")
            }
            do {
                let data = try JSONEncoder().encode(report)
                try await transport.send(data, to: endpoint)
                try queueStore.remove(reportID: report.reportID)
                sentCount += 1
            } catch {
                pending = queueStore.load()
                let reason = DiagnosticSanitizer.sanitize(error.localizedDescription)
                return .queued(pending: pending.count, reason: CrashReportText.clip(reason, maximumBytes: 240))
            }
        }
        return .sent(count: sentCount)
    }

    func clearPending() -> Bool {
        do {
            try queueStore.clear()
            return true
        } catch {
            return false
        }
    }

    func pendingCount() -> Int {
        queueStore.load().count
    }
}

private enum CrashReportText {
    static func clip(_ value: String, maximumBytes: Int) -> String {
        guard value.utf8.count > maximumBytes else { return value }
        var result = ""
        result.reserveCapacity(min(value.count, maximumBytes))
        for character in value {
            let candidate = result + String(character)
            if candidate.utf8.count > maximumBytes { break }
            result = candidate
        }
        return result
    }
}

private extension CrashReportQueueStore {
    static var defaultQueueURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("AkangVoiceInput", isDirectory: true)
            .appendingPathComponent("pending-crash-reports.json")
    }
}

private extension MacCrashReportScanner {
    static var defaultReportsDirectoryURL: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        return library.appendingPathComponent("Logs/DiagnosticReports", isDirectory: true)
    }
}
