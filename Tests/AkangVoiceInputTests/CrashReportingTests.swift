import Foundation
import XCTest
@testable import AkangVoiceInput

final class CrashReportingTests: XCTestCase {
    func testCrashReportEndpointRequiresHTTPSExceptForLoopbackDevelopment() {
        XCTAssertEqual(
            CrashReportConfiguration.validatedEndpoint("https://crash.example.com/v1/report")?.absoluteString,
            "https://crash.example.com/v1/report"
        )
        XCTAssertEqual(
            CrashReportConfiguration.validatedEndpoint("http://127.0.0.1:8787/v1/report")?.absoluteString,
            "http://127.0.0.1:8787/v1/report"
        )
        XCTAssertNil(CrashReportConfiguration.validatedEndpoint("http://crash.example.com/v1/report"))
        XCTAssertNil(CrashReportConfiguration.validatedEndpoint("not a url"))
    }

    func testAcceptedReportMessageDoesNotClaimFeishuDelivery() {
        XCTAssertEqual(
            CrashReportDeliveryResult.sent(count: 1).displayMessage,
            "上报服务已接收 1 份脱敏报告；飞书送达请以群消息为准"
        )
    }

    func testMacCrashReportParserKeepsApplicationFramesWithoutRawPaths() throws {
        let header = #"{"app_name":"AkangVoiceInput","timestamp":"2026-08-12 22:14:00 +0800","app_version":"1.8.0","build_version":"42","bundleID":"com.akang.ai-voice-input","os_version":"macOS 15.0","incident_id":"INCIDENT-123"}"#
        let body = #"{"exception":{"type":"EXC_BAD_ACCESS","signal":"SIGSEGV","subtype":"KERN_INVALID_ADDRESS at 0x0"},"termination":{"namespace":"SIGNAL","indicator":"Segmentation fault: 11","code":11},"faultingThread":0,"threads":[{"triggered":true,"frames":[{"imageIndex":0,"symbol":"ProcessingLine.body.getter","symbolLocation":24},{"imageIndex":1,"symbol":"swift_task_run","symbolLocation":8}]}],"usedImages":[{"name":"AkangVoiceInput","path":"/Users/alice/Secret/AkangVoiceInput","CFBundleIdentifier":"com.akang.ai-voice-input"},{"name":"libswift_Concurrency.dylib","path":"/usr/lib/swift/libswift_Concurrency.dylib"}]}"#

        let report = try XCTUnwrap(
            MacCrashReportParser.parse(
                data: Data("\(header)\n\(body)".utf8),
                expectedBundleIdentifier: "com.akang.ai-voice-input",
                expectedProcessName: "AkangVoiceInput"
            )
        )

        XCTAssertEqual(report.incidentID, "INCIDENT-123")
        XCTAssertEqual(report.exceptionType, "EXC_BAD_ACCESS")
        XCTAssertEqual(report.signal, "SIGSEGV")
        XCTAssertEqual(report.frames, ["AkangVoiceInput · ProcessingLine.body.getter + 24"])
        XCTAssertFalse(report.frames.joined().contains("alice"))
        XCTAssertFalse(report.frames.joined().contains("/Users/"))
    }

    func testCrashQueueDeduplicatesIncidentReportsAndUsesOwnerOnlyPermissions() throws {
        let directory = temporaryDirectory(name: "queue")
        defer { try? FileManager.default.removeItem(at: directory) }
        let queueURL = directory.appendingPathComponent("pending.json")
        let store = CrashReportQueueStore(fileURL: queueURL)
        let report = samplePayload(incidentID: "same-incident")

        try store.enqueue(report)
        try store.enqueue(report)

        XCTAssertEqual(store.load().count, 1)
        let attributes = try FileManager.default.attributesOfItem(atPath: queueURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testCrashQueueKeepsIndependentManualTests() throws {
        let directory = temporaryDirectory(name: "test-queue")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CrashReportQueueStore(fileURL: directory.appendingPathComponent("pending.json"))
        let first = CrashReportPayloadFactory.testReport(entries: [])
        let second = CrashReportPayloadFactory.testReport(entries: [])

        try store.enqueue(first)
        try store.enqueue(second)

        XCTAssertEqual(store.load().map(\.reportID), [first.reportID, second.reportID])
    }

    func testPreviousRunReportFallsBackWithoutMatchingIPS() throws {
        let directory = temporaryDirectory(name: "empty-reports")
        defer { try? FileManager.default.removeItem(at: directory) }
        let previous = PreviousRunDiagnostics(
            entries: [DiagnosticEntry(category: "应用", message: "启动完成")],
            endedUnexpectedly: true,
            startedAt: Date(timeIntervalSince1970: 100)
        )
        let report = try XCTUnwrap(
            CrashReportPayloadFactory.previousRunReport(
                previousRun: previous,
                scanner: MacCrashReportScanner(directoryURL: directory),
                buildInfo: CrashReportBuildInfo(
                    version: "1.8.1",
                    build: "43",
                    osVersion: "macOS test",
                    architecture: "arm64"
                ),
                now: Date(timeIntervalSince1970: 200)
            )
        )

        XCTAssertEqual(report.source, "macos.lifecycle")
        XCTAssertEqual(report.errorType, "UnexpectedExit")
        XCTAssertEqual(report.breadcrumbs.count, 1)
    }

    func testCrashReportServiceKeepsFailedUploadAndRetriesAfterRecovery() async throws {
        let directory = temporaryDirectory(name: "retry")
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = RecordingCrashReportTransport(shouldFail: true)
        let service = CrashReportService(
            endpoint: URL(string: "https://crash.example.com/v1/report"),
            queueURL: directory.appendingPathComponent("queue.json"),
            diagnosticReportsDirectoryURL: directory,
            transport: transport,
            buildInfo: CrashReportBuildInfo(
                version: "1.8.1",
                build: "43",
                osVersion: "macOS test",
                architecture: "arm64"
            )
        )
        let sensitiveEntry = DiagnosticEntry(
            category: "错误",
            message: "api_key=sk-test-super-secret /Users/alice/project user@example.com"
        )

        let firstResult = await service.sendTestReport(entries: [sensitiveEntry])
        guard case .queued(let pending, _) = firstResult else {
            return XCTFail("Expected a queued report, got \(firstResult)")
        }
        XCTAssertEqual(pending, 1)
        let pendingAfterFailure = await service.pendingCount()
        XCTAssertEqual(pendingAfterFailure, 1)

        await transport.setShouldFail(false)
        let retryResult = await service.flush()
        XCTAssertEqual(retryResult, .sent(count: 1))
        let pendingAfterRetry = await service.pendingCount()
        XCTAssertEqual(pendingAfterRetry, 0)

        let payloads = await transport.decodedPayloads()
        let lastPayload = try XCTUnwrap(payloads.last)
        let messages = lastPayload.breadcrumbs.map(\.message).joined(separator: " ")
        XCTAssertFalse(messages.contains("sk-test-super-secret"))
        XCTAssertFalse(messages.contains("alice"))
        XCTAssertFalse(messages.contains("user@example.com"))
    }

    private func temporaryDirectory(name: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoboardCrashReportingTests.\(name).\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func samplePayload(incidentID: String) -> CrashReportPayload {
        CrashReportPayload(
            schemaVersion: 1,
            reportID: UUID().uuidString,
            product: "noboard",
            kind: .crash,
            source: "macos.ips",
            label: "EXC_BAD_ACCESS",
            version: "1.8.1",
            build: "43",
            osVersion: "macOS test",
            architecture: "arm64",
            errorType: "EXC_BAD_ACCESS",
            errorMessage: "SIGSEGV",
            stack: "ProcessingLine.body",
            topFrame: "ProcessingLine.body",
            fingerprintHint: "EXC_BAD_ACCESS|ProcessingLine.body",
            occurredAt: "2026-08-12T14:14:00Z",
            incidentID: incidentID,
            breadcrumbs: []
        )
    }
}

private actor RecordingCrashReportTransport: CrashReportTransport {
    private var shouldFail: Bool
    private var payloads: [CrashReportPayload] = []

    init(shouldFail: Bool) {
        self.shouldFail = shouldFail
    }

    func send(_ data: Data, to endpoint: URL) async throws {
        payloads.append(try JSONDecoder().decode(CrashReportPayload.self, from: data))
        if shouldFail {
            throw URLError(.notConnectedToInternet)
        }
    }

    func setShouldFail(_ value: Bool) {
        shouldFail = value
    }

    func decodedPayloads() -> [CrashReportPayload] {
        payloads
    }
}
