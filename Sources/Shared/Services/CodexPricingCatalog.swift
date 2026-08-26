import Foundation

struct CodexPricingTier: Codable, Equatable {
    let input: Double
    let cachedInput: Double
    let cacheWrite: Double
    let output: Double
}

struct CodexPricingModel: Codable, Equatable {
    let shortContext: CodexPricingTier
    let longContext: CodexPricingTier?
    let longContextThreshold: Int64?
    let expectsCacheWriteTelemetry: Bool

    private enum CodingKeys: String, CodingKey {
        case shortContext = "short"
        case longContext = "long"
        case longContextThreshold
        case expectsCacheWriteTelemetry
    }

    func tier(inputTokens: Int64) -> CodexPricingTier {
        if let longContext,
           let longContextThreshold,
           inputTokens > longContextThreshold {
            return longContext
        }
        return shortContext
    }
}

struct CodexPricingDocument: Codable, Equatable {
    let schemaVersion: Int
    let effectiveDate: String
    let sourceURL: String
    let currency: String
    let unitTokens: Int
    let models: [String: CodexPricingModel]

    static let builtIn = CodexPricingDocument(
        schemaVersion: 1,
        effectiveDate: "2026-08-26",
        sourceURL: "https://developers.openai.com/api/docs/pricing/",
        currency: "USD",
        unitTokens: 1_000_000,
        models: [
            "gpt-5.3-codex": .init(
                shortContext: .init(input: 1.75, cachedInput: 0.175, cacheWrite: 1.75, output: 14),
                longContext: nil,
                longContextThreshold: nil,
                expectsCacheWriteTelemetry: false
            ),
            "gpt-5.4": .init(
                shortContext: .init(input: 2.50, cachedInput: 0.25, cacheWrite: 2.50, output: 15),
                longContext: .init(input: 5, cachedInput: 0.50, cacheWrite: 5, output: 22.50),
                longContextThreshold: 272_000,
                expectsCacheWriteTelemetry: false
            ),
            "gpt-5.4-mini": .init(
                shortContext: .init(input: 0.75, cachedInput: 0.075, cacheWrite: 0.75, output: 4.50),
                longContext: nil,
                longContextThreshold: nil,
                expectsCacheWriteTelemetry: false
            ),
            "gpt-5.5": .init(
                shortContext: .init(input: 5, cachedInput: 0.50, cacheWrite: 5, output: 30),
                longContext: .init(input: 10, cachedInput: 1, cacheWrite: 10, output: 45),
                longContextThreshold: 272_000,
                expectsCacheWriteTelemetry: false
            ),
            "gpt-5.6-sol": .init(
                shortContext: .init(input: 4, cachedInput: 0.40, cacheWrite: 5, output: 20),
                longContext: .init(input: 8, cachedInput: 0.80, cacheWrite: 10, output: 30),
                longContextThreshold: 272_000,
                expectsCacheWriteTelemetry: true
            ),
            "gpt-5.6-terra": .init(
                shortContext: .init(input: 2, cachedInput: 0.20, cacheWrite: 2.50, output: 12),
                longContext: .init(input: 4, cachedInput: 0.40, cacheWrite: 5, output: 18),
                longContextThreshold: 272_000,
                expectsCacheWriteTelemetry: true
            ),
            "gpt-5.6-luna": .init(
                shortContext: .init(input: 0.20, cachedInput: 0.02, cacheWrite: 0.25, output: 1.20),
                longContext: .init(input: 0.40, cachedInput: 0.04, cacheWrite: 0.50, output: 1.80),
                longContextThreshold: 272_000,
                expectsCacheWriteTelemetry: true
            )
        ]
    )

    func mergedOverBuiltIn() -> CodexPricingDocument {
        var mergedModels = Self.builtIn.models
        models.forEach { mergedModels[$0.key] = $0.value }
        return CodexPricingDocument(
            schemaVersion: schemaVersion,
            effectiveDate: effectiveDate,
            sourceURL: sourceURL,
            currency: currency,
            unitTokens: unitTokens,
            models: mergedModels
        )
    }

    func validated() throws -> CodexPricingDocument {
        guard schemaVersion == 1,
              currency == "USD",
              unitTokens == 1_000_000,
              effectiveDate.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              effectiveDate >= Self.builtIn.effectiveDate,
              let source = URL(string: sourceURL),
              source.scheme == "https",
              ["developers.openai.com", "platform.openai.com"].contains(source.host ?? "")
        else { throw CodexPricingUpdateError.invalidDocument }

        let requiredModels = ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"]
        guard requiredModels.allSatisfy({ models[$0] != nil }), models.count <= 100 else {
            throw CodexPricingUpdateError.invalidDocument
        }
        for (name, model) in models {
            guard name == name.lowercased(),
                  name.range(of: #"^[a-z0-9][a-z0-9.-]{1,79}$"#, options: .regularExpression) != nil,
                  Self.valid(model.shortContext),
                  model.longContext.map(Self.valid) ?? true,
                  model.longContext != nil || model.longContextThreshold == nil,
                  model.longContext == nil || (1...2_000_000).contains(model.longContextThreshold ?? 0)
            else { throw CodexPricingUpdateError.invalidDocument }
        }
        return mergedOverBuiltIn()
    }

    private static func valid(_ tier: CodexPricingTier) -> Bool {
        [tier.input, tier.cachedInput, tier.cacheWrite, tier.output].allSatisfy {
            $0.isFinite && $0 > 0 && $0 <= 1_000
        }
    }
}

struct CodexPricingStatus: Equatable {
    var effectiveDate = CodexPricingDocument.builtIn.effectiveDate
    var sourceURL = CodexPricingDocument.builtIn.sourceURL
    var lastCheckedAt: Date?
    var isUsingRemote = false
    var errorMessage: String?

    static let builtIn = CodexPricingStatus()
}

struct CodexPricingState: Equatable {
    let document: CodexPricingDocument
    let status: CodexPricingStatus

    static let builtIn = CodexPricingState(document: .builtIn, status: .builtIn)
}

private struct CodexPricingCache: Codable {
    var schemaVersion = 1
    var document: CodexPricingDocument?
    var fetchedAt: Date?
    var lastCheckedAt: Date?
    var eTag: String?
    var lastError: String?
}

enum CodexPricingUpdateError: LocalizedError {
    case invalidResponse
    case invalidDocument
    case documentTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "价格服务器返回无效响应"
        case .invalidDocument: return "远程价格表未通过校验"
        case .documentTooLarge: return "远程价格表大小异常"
        }
    }
}

actor CodexPricingStore {
    static let shared = CodexPricingStore()

    private let fileManager: FileManager
    private let cacheURL: URL
    private let remoteURL: URL?
    private let checkInterval: TimeInterval
    private var cache: CodexPricingCache
    private var activeDocument: CodexPricingDocument

    init(
        fileManager: FileManager = .default,
        cacheURL: URL? = nil,
        remoteURL: URL? = URL(string: "https://salmonc.github.io/ApiUsageTrackerForMac/pricing-v1.json"),
        checkInterval: TimeInterval = 24 * 60 * 60
    ) {
        self.fileManager = fileManager
        self.remoteURL = remoteURL
        self.checkInterval = checkInterval
        let home = fileManager.homeDirectoryForCurrentUser
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support", isDirectory: true)
        self.cacheURL = cacheURL
            ?? applicationSupport.appendingPathComponent("QuotaPulse/CodexPricing-v1.json")

        if let data = try? Data(contentsOf: self.cacheURL),
           let decoded = try? JSONDecoder().decode(CodexPricingCache.self, from: data),
           decoded.schemaVersion == 1,
           let document = decoded.document,
           let validated = try? document.validated() {
            cache = decoded
            activeDocument = validated
        } else {
            cache = CodexPricingCache()
            activeDocument = .builtIn
        }
    }

    func currentState() -> CodexPricingState {
        makeState()
    }

    func refreshIfNeeded(now: Date = Date(), force: Bool = false) async -> CodexPricingState {
        guard let remoteURL else { return makeState() }
        if !force,
           let lastCheckedAt = cache.lastCheckedAt,
           now.timeIntervalSince(lastCheckedAt) < checkInterval {
            return makeState()
        }

        var request = URLRequest(url: remoteURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let eTag = cache.eTag {
            request.setValue(eTag, forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw CodexPricingUpdateError.invalidResponse
            }
            cache.lastCheckedAt = now
            if response.statusCode == 304, cache.document != nil {
                cache.lastError = nil
                persistCache()
                return makeState()
            }
            guard response.statusCode == 200 else {
                throw CodexPricingUpdateError.invalidResponse
            }
            guard data.count <= 256 * 1_024 else {
                throw CodexPricingUpdateError.documentTooLarge
            }
            let remote = try JSONDecoder().decode(CodexPricingDocument.self, from: data)
            activeDocument = try remote.validated()
            cache.document = remote
            cache.fetchedAt = now
            cache.eTag = response.value(forHTTPHeaderField: "ETag")
            cache.lastError = nil
            persistCache()
        } catch is CancellationError {
            return makeState()
        } catch {
            cache.lastCheckedAt = now
            cache.lastError = error.localizedDescription
            persistCache()
            Logger.critical("Codex pricing refresh failed; keeping last valid prices: \(error.localizedDescription)")
        }
        return makeState()
    }

    private func makeState() -> CodexPricingState {
        CodexPricingState(
            document: activeDocument,
            status: CodexPricingStatus(
                effectiveDate: activeDocument.effectiveDate,
                sourceURL: activeDocument.sourceURL,
                lastCheckedAt: cache.lastCheckedAt,
                isUsingRemote: cache.document != nil && activeDocument.effectiveDate == cache.document?.effectiveDate,
                errorMessage: cache.lastError
            )
        )
    }

    private func persistCache() {
        do {
            let directory = cacheURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try JSONEncoder().encode(cache)
            try data.write(to: cacheURL, options: [.atomic])
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
        } catch {
            Logger.critical("Codex pricing cache write failed: \(error.localizedDescription)")
        }
    }
}
