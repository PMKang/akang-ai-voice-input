import Foundation

/// Keeps the Fun-ASR hotword list aligned with the local personal dictionary.
/// The public DashScope endpoint deliberately needs only an API key; a workspace
/// identifier is an optional infrastructure optimisation, not user-facing setup.
struct FunASRHotwordService {
    struct SynchronizationResult: Equatable {
        let vocabularyID: String?
        let entryCount: Int
        let changed: Bool
    }

    enum Error: LocalizedError {
        case invalidResponse
        case service(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "热词服务返回了无法解析的响应。"
            case .service(let message):
                "热词同步失败：\(message)"
            }
        }
    }

    private static let endpoint = URL(
        string: "https://dashscope.aliyuncs.com/api/v1/services/audio/asr/customization"
    )!
    private static let vocabularyIDDefaultsKey = "funASRPersonalVocabularyID"
    private static let vocabularyFingerprintDefaultsKey = "funASRPersonalVocabularyFingerprint"
    private static let prefix = "noboard"

    static func synchronize(entries: [DictionaryEntry], apiKey: String) async throws -> SynchronizationResult {
        let vocabulary = makeVocabulary(from: entries)
        guard !vocabulary.isEmpty else {
            UserDefaults.standard.removeObject(forKey: vocabularyIDDefaultsKey)
            UserDefaults.standard.removeObject(forKey: vocabularyFingerprintDefaultsKey)
            return SynchronizationResult(vocabularyID: nil, entryCount: 0, changed: false)
        }

        let fingerprint = stableFingerprint(vocabulary)
        let defaults = UserDefaults.standard
        let existingID = defaults.string(forKey: vocabularyIDDefaultsKey)
        if defaults.string(forKey: vocabularyFingerprintDefaultsKey) == fingerprint,
           let existingID, !existingID.isEmpty {
            return SynchronizationResult(vocabularyID: existingID, entryCount: vocabulary.count, changed: false)
        }

        if let existingID, !existingID.isEmpty {
            _ = try await request(
                action: "update_vocabulary",
                input: ["vocabulary_id": existingID, "vocabulary": vocabulary],
                apiKey: apiKey
            )
            defaults.set(fingerprint, forKey: vocabularyFingerprintDefaultsKey)
            return SynchronizationResult(vocabularyID: existingID, entryCount: vocabulary.count, changed: true)
        }

        let response = try await request(
            action: "create_vocabulary",
            input: [
                "target_model": "fun-asr-realtime",
                "prefix": prefix,
                "vocabulary": vocabulary
            ],
            apiKey: apiKey
        )
        guard let output = response["output"] as? [String: Any],
              let vocabularyID = output["vocabulary_id"] as? String,
              !vocabularyID.isEmpty else {
            throw Error.invalidResponse
        }
        defaults.set(vocabularyID, forKey: vocabularyIDDefaultsKey)
        defaults.set(fingerprint, forKey: vocabularyFingerprintDefaultsKey)
        return SynchronizationResult(vocabularyID: vocabularyID, entryCount: vocabulary.count, changed: true)
    }

    private static func request(action: String, input: [String: Any], apiKey: String) async throws -> [String: Any] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var requestInput = input
        requestInput["action"] = action
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "speech-biasing",
            "input": requestInput
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Error.invalidResponse }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if !(200...299).contains(http.statusCode) {
            let message = (object?["message"] as? String)
                ?? (object?["code"] as? String)
                ?? "HTTP \(http.statusCode)"
            throw Error.service(message)
        }
        guard let object else { throw Error.invalidResponse }
        if let code = object["code"] as? String, !code.isEmpty {
            throw Error.service(code)
        }
        return object
    }

    private static func makeVocabulary(from entries: [DictionaryEntry]) -> [[String: Any]] {
        var seen = Set<String>()
        let candidates = entries.flatMap { entry in
            [entry.term, entry.pronunciation, entry.replacement]
        }
        return candidates.compactMap { raw in
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isSupportedLength(text), seen.insert(text.localizedLowercase).inserted else { return nil }
            var item: [String: Any] = ["text": text, "weight": 4]
            if text.unicodeScalars.allSatisfy({ $0.isASCII }) {
                item["lang"] = "en"
            } else {
                item["lang"] = "zh"
            }
            return item
        }
    }

    private static func isSupportedLength(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        if text.unicodeScalars.contains(where: { !$0.isASCII }) {
            return text.count <= 15
        }
        return text.split(whereSeparator: \.isWhitespace).count <= 7
    }

    private static func stableFingerprint(_ vocabulary: [[String: Any]]) -> String {
        let source = vocabulary.compactMap { item -> String? in
            guard let text = item["text"] as? String else { return nil }
            return "\(text)|\(item["lang"] as? String ?? "")"
        }.joined(separator: "\n")
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in source.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
