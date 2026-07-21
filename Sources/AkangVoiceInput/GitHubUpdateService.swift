import AppKit
import Foundation

enum BuildInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.3"
    }

    static var buildTimestamp: String {
        Bundle.main.object(forInfoDictionaryKey: "AkangBuildTimestamp") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "开发版"
    }

    static var displayVersion: String {
        "\(version)-\(buildTimestamp)"
    }

    /// Debug builds are for local development and test distribution only.
    /// Release archives intentionally omit this label.
    static var isDevelopmentBuild: Bool {
        if (Bundle.main.object(forInfoDictionaryKey: "AkangDevelopmentBuild") as? String) == "YES" {
            return true
        }
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    // Used only when building the downloadable v1.0.2 verification package.
    // Both releases keep the same bundle identifier so the update flow is real.
    static var hidesExpressionStyleForLegacyRelease: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "AkangHideExpressionStyle") as? String) == "YES"
    }

}

struct SemanticVersion: Comparable, Equatable {
    private let components: [Int]

    init(_ value: String) {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "v", with: "", options: [.anchored, .caseInsensitive])
        let releasePart = cleaned.split(separator: "-", maxSplits: 1).first ?? Substring(cleaned)
        let parsed = releasePart.split(separator: ".").map { Int($0) ?? 0 }
        self.components = Array((parsed + [0, 0, 0]).prefix(3))
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        for index in 0..<3 where lhs.components[index] != rhs.components[index] {
            return lhs.components[index] < rhs.components[index]
        }
        return false
    }
}

struct GitHubRelease: Equatable, Sendable {
    let version: String
    let title: String
    let notes: String
    let htmlURL: URL
    let asset: GitHubReleaseAsset

    var displayVersion: String {
        version.lowercased().hasPrefix("v") ? version : "v\(version)"
    }
}

struct GitHubReleaseAsset: Equatable, Sendable {
    let name: String
    let downloadURL: URL
    let byteCount: Int

    var formattedByteCount: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
}

struct DownloadedUpdatePackage: Equatable {
    let version: String
    let stagedAppURL: URL
    let archiveURL: URL

    var displayVersion: String {
        version.lowercased().hasPrefix("v") ? version : "v\(version)"
    }
}

enum UpdateDownloadEvent: Sendable {
    case receiving(downloadedByteCount: Int64, totalByteCount: Int64)
    case preparing
}

enum AppUpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case noDownloadAvailable
    case available(GitHubRelease)
    case downloading(downloadedByteCount: Int64, totalByteCount: Int64)
    case preparing(GitHubRelease)
    case readyToRestart(DownloadedUpdatePackage)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .checking, .downloading(_, _), .preparing: true
        default: false
        }
    }

    var diagnosticLabel: String {
        switch self {
        case .idle: "idle"
        case .checking: "checking"
        case .upToDate: "upToDate"
        case .noDownloadAvailable: "noDownloadAvailable"
        case .available(let release): "available(\(release.version))"
        case .downloading: "downloading"
        case .preparing(let release): "preparing(\(release.version))"
        case .readyToRestart(let package): "readyToRestart(\(package.version))"
        case .failed(let message): "failed(\(message))"
        }
    }
}

enum UpdateCheckResult: Sendable {
    case available(GitHubRelease)
    case upToDate(String)
    case noDownloadAvailable
    case failed(String, diagnostic: String)
}

enum GitHubUpdateError: LocalizedError {
    case invalidResponse
    case noPublishedRelease
    case noMacOSArchive
    case invalidArchive
    case bundleMismatch
    case installationDirectoryNotWritable(URL)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "更新服务返回的数据无法识别。"
        case .noPublishedRelease:
            "尚未发布可下载的新版本。"
        case .noMacOSArchive:
            "该版本未附带 macOS 安装包。"
        case .invalidArchive:
            "下载的更新包无法解压或内容不完整。"
        case .bundleMismatch:
            "更新包与当前应用不匹配，已停止安装。"
        case .installationDirectoryNotWritable(let url):
            "更新已下载，但当前应用目录不可写：\(url.path)。请将应用移到个人“应用程序”目录后再更新。"
        }
    }
}

private struct GitHubReleasePayload: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case assets
    }

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL
        let size: Int

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case size
        }
    }
}

private final class UpdateDownloadDelegate: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let expectedByteCount: Int
    private let onProgress: @Sendable (Int64, Int64) -> Void
    private var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    private var didFinish = false
    // The download task is asynchronous. Retain its URLSession until a terminal callback arrives.
    private var activeSession: URLSession?

    init(expectedByteCount: Int, onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.expectedByteCount = expectedByteCount
        self.onProgress = onProgress
    }

    func start(
        session: URLSession,
        continuation: CheckedContinuation<(URL, URLResponse), Error>
    ) {
        activeSession = session
        self.continuation = continuation
    }

    func urlSession(
        _: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : Int64(expectedByteCount)
        onProgress(max(0, totalBytesWritten), max(0, expected))
    }

    func urlSession(_: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard !didFinish else { return }
        didFinish = true
        do {
            let stableURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("akang-update-\(UUID().uuidString).zip")
            try FileManager.default.moveItem(at: location, to: stableURL)
            onProgress(Int64(expectedByteCount), Int64(expectedByteCount))
            guard let response = downloadTask.response else { throw GitHubUpdateError.invalidResponse }
            InteractionLog.event("update.download.finished bytes=\(expectedByteCount)")
            continuation?.resume(returning: (stableURL, response))
            continuation = nil
            invalidateSession()
        } catch {
            InteractionLog.event("update.download.failed error=\(error.localizedDescription)")
            continuation?.resume(throwing: error)
            continuation = nil
            invalidateSession()
        }
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
        guard !didFinish, let error else { return }
        didFinish = true
        InteractionLog.event("update.download.failed error=\(error.localizedDescription)")
        continuation?.resume(throwing: error)
        continuation = nil
        invalidateSession()
    }

    private func invalidateSession() {
        activeSession?.finishTasksAndInvalidate()
        activeSession = nil
    }
}

final class GitHubUpdateService: @unchecked Sendable {
    private let owner = "PMKang"
    private let repository = "akang-ai-voice-input"

    func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("AkangVoiceInput/\(BuildInfo.version)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubUpdateError.invalidResponse }
        guard http.statusCode != 404 else { throw GitHubUpdateError.noPublishedRelease }
        guard (200..<300).contains(http.statusCode) else { throw GitHubUpdateError.invalidResponse }

        let payload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
        guard let asset = payload.assets.first(where: { asset in
            let name = asset.name.lowercased()
            return name.hasSuffix(".zip") && name.contains("macos")
        }) ?? payload.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }) else {
            throw GitHubUpdateError.noMacOSArchive
        }
        return GitHubRelease(
            version: payload.tagName,
            title: payload.name ?? payload.tagName,
            notes: payload.body ?? "",
            htmlURL: payload.htmlURL,
            asset: GitHubReleaseAsset(name: asset.name, downloadURL: asset.browserDownloadURL, byteCount: asset.size)
        )
    }

    func downloadAndPrepare(
        release: GitHubRelease,
        onEvent: @escaping @Sendable (UpdateDownloadEvent) -> Void
    ) async throws -> DownloadedUpdatePackage {
        let (temporaryURL, response) = try await downloadArchive(
            from: release.asset.downloadURL,
            expectedByteCount: release.asset.byteCount,
            onProgress: { downloadedByteCount, totalByteCount in
                onEvent(.receiving(
                    downloadedByteCount: downloadedByteCount,
                    totalByteCount: totalByteCount
                ))
            }
        )
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GitHubUpdateError.invalidResponse
        }

        onEvent(.preparing)

        let updatesRoot = try updateRootDirectory()
        let versionDirectory = updatesRoot.appendingPathComponent(
            sanitizedVersion(release.version),
            isDirectory: true
        )
        try? FileManager.default.removeItem(at: versionDirectory)
        try FileManager.default.createDirectory(at: versionDirectory, withIntermediateDirectories: true)

        let archiveURL = versionDirectory.appendingPathComponent(release.asset.name)
        try FileManager.default.copyItem(at: temporaryURL, to: archiveURL)

        let extractionURL = versionDirectory.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extractionURL, withIntermediateDirectories: true)
        try runProcess("/usr/bin/ditto", arguments: ["-x", "-k", archiveURL.path, extractionURL.path])

        guard let appURL = try firstAppBundle(in: extractionURL) else {
            throw GitHubUpdateError.invalidArchive
        }
        let expectedBundleID = Bundle.main.bundleIdentifier
        let stagedBundle = Bundle(url: appURL)
        guard expectedBundleID == nil || stagedBundle?.bundleIdentifier == expectedBundleID else {
            throw GitHubUpdateError.bundleMismatch
        }
        return DownloadedUpdatePackage(version: release.version, stagedAppURL: appURL, archiveURL: archiveURL)
    }

    private func downloadArchive(
        from url: URL,
        expectedByteCount: Int,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> (URL, URLResponse) {
        let delegate = UpdateDownloadDelegate(expectedByteCount: expectedByteCount, onProgress: onProgress)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        return try await withCheckedThrowingContinuation { continuation in
            delegate.start(session: session, continuation: continuation)
            InteractionLog.event("update.download.request url=\(url.absoluteString)")
            session.downloadTask(with: url).resume()
        }
    }

    @MainActor
    func scheduleInstallAndRestart(package: DownloadedUpdatePackage) throws {
        let targetAppURL = Bundle.main.bundleURL.standardizedFileURL
        let targetDirectory = targetAppURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: targetDirectory.path) else {
            throw GitHubUpdateError.installationDirectoryNotWritable(targetDirectory)
        }

        let scriptURL = package.archiveURL.deletingLastPathComponent()
            .appendingPathComponent("install-update.sh")
        let script = """
        #!/bin/sh
        set -eu
        SOURCE_APP=\(shellQuote(package.stagedAppURL.path))
        TARGET_APP=\(shellQuote(targetAppURL.path))
        TARGET_DIR=\(shellQuote(targetDirectory.path))
        PID=\(ProcessInfo.processInfo.processIdentifier)
        while kill -0 \"$PID\" 2>/dev/null; do sleep 0.2; done
        TEMP_APP=\"$TARGET_APP.updating\"
        /bin/rm -rf \"$TEMP_APP\"
        /usr/bin/ditto \"$SOURCE_APP\" \"$TEMP_APP\"
        /bin/rm -rf \"$TARGET_APP\"
        /bin/mv \"$TEMP_APP\" \"$TARGET_APP\"
        /usr/bin/open -n \"$TARGET_APP\"
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path]
        try process.run()
        NSApplication.shared.terminate(nil)
    }

    private func updateRootDirectory() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let updates = root
            .appendingPathComponent("AkangVoiceInput", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
        try FileManager.default.createDirectory(at: updates, withIntermediateDirectories: true)
        return updates
    }

    private func firstAppBundle(in directory: URL) throws -> URL? {
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        while let candidate = enumerator?.nextObject() as? URL {
            if candidate.pathExtension == "app" { return candidate }
        }
        return nil
    }

    private func runProcess(_ executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw GitHubUpdateError.invalidArchive }
    }

    private func sanitizedVersion(_ value: String) -> String {
        value.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\\"'\\\"'"))'"
    }
}
