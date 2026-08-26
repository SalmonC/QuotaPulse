import Foundation

struct CodexDailyEquivalentValue: Identifiable, Equatable {
    var id: Date { day }
    let day: Date
    let valueUSD: Double
}

struct CodexEquivalentValueSnapshot: Equatable {
    var dailyValues: [CodexDailyEquivalentValue] = []
    var isLowerBound = false
    var unsupportedModels: [String] = []
    var excludedUnverifiedRequestCount = 0
    var lastScannedAt: Date?
    var errorMessage: String?
    var pricingStatus: CodexPricingStatus = .builtIn

    static let empty = CodexEquivalentValueSnapshot()

    var hasVerifiedValue: Bool {
        !dailyValues.isEmpty
    }
}

fileprivate struct CodexTokenUsage: Codable, Equatable {
    var input: Int64 = 0
    var cachedInput: Int64 = 0
    var cacheWriteInput: Int64 = 0
    var output: Int64 = 0
    var cacheWriteWasReported = false

    static let zero = CodexTokenUsage()

    func positiveDelta(from previous: CodexTokenUsage) -> CodexTokenUsage? {
        let next = CodexTokenUsage(
            input: input - previous.input,
            cachedInput: cachedInput - previous.cachedInput,
            cacheWriteInput: cacheWriteInput - previous.cacheWriteInput,
            output: output - previous.output,
            cacheWriteWasReported: cacheWriteWasReported
        )
        guard next.input >= 0, next.cachedInput >= 0, next.cacheWriteInput >= 0, next.output >= 0 else {
            return nil
        }
        guard next.input > 0 || next.output > 0 || next.cacheWriteInput > 0 else { return nil }
        return next
    }
}

private struct CodexValueRequestRecord: Codable, Equatable {
    let branchID: String
    let timestamp: Date
    let model: String?
    let planType: String?
    let usage: CodexTokenUsage
}

private struct CodexBranchCursor: Codable, Equatable {
    var processedOffset: UInt64 = 0
    var currentModel: String?
    var cumulativeUsage: CodexTokenUsage = .zero
    var hasCumulativeUsage = false
    var spawnTimestamp: Date?
    var isSubagent = false
    var identityVerified = false
    var isFresh = false
    var fileSystemNumber: UInt64?
    var fileCreationDate: Date?
    var isDroppingOversizedLine = false
}

private struct CodexValueIndex: Codable {
    var schemaVersion = 1
    var branches: [String: CodexBranchCursor] = [:]
    var records: [CodexValueRequestRecord] = []
    var warningTimestamps: [Date]?
    var lastScannedAt: Date?
}

enum CodexEquivalentValuePricing {
    static var referenceDate: String { CodexPricingDocument.builtIn.effectiveDate }

    static func normalizedModel(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "gpt-5.6" { return "gpt-5.6-sol" }
        return normalized.isEmpty ? nil : normalized
    }

    static func hasPrice(for model: String?) -> Bool {
        guard let model = normalizedModel(model) else { return false }
        return CodexPricingDocument.builtIn.models[model] != nil
    }

    private static func calculatedValueUSD(
        model: String?,
        usage: CodexTokenUsage,
        pricing: CodexPricingDocument
    ) -> Double? {
        guard let model = normalizedModel(model), let modelPrice = pricing.models[model] else { return nil }
        let price = modelPrice.tier(inputTokens: usage.input)
        let cached = min(max(usage.cachedInput, 0), max(usage.input, 0))
        let writes = min(max(usage.cacheWriteInput, 0), max(usage.input - cached, 0))
        let ordinary = max(usage.input - cached - writes, 0)
        let inputValue = Double(ordinary) * price.input
        let cachedValue = Double(cached) * price.cachedInput
        let writeValue = Double(writes) * price.cacheWrite
        let outputValue = Double(max(usage.output, 0)) * price.output
        return (inputValue + cachedValue + writeValue + outputValue) / Double(pricing.unitTokens)
    }

    private static func cacheWriteMayBeMissing(
        model: String?,
        usage: CodexTokenUsage,
        pricing: CodexPricingDocument
    ) -> Bool {
        guard let model = normalizedModel(model), let price = pricing.models[model] else { return false }
        // Codex has emitted an explicit zero even when the subscription backend did
        // not expose cache-write telemetry, so zero cannot be treated as proof.
        return price.expectsCacheWriteTelemetry
            && (!usage.cacheWriteWasReported || usage.cacheWriteInput == 0)
    }

    static func valueUSD(
        model: String?,
        input: Int64,
        cachedInput: Int64,
        cacheWriteInput: Int64,
        output: Int64,
        cacheWriteWasReported: Bool = true
    ) -> Double? {
        calculatedValueUSD(
            model: model,
            usage: CodexTokenUsage(
                input: input,
                cachedInput: cachedInput,
                cacheWriteInput: cacheWriteInput,
                output: output,
                cacheWriteWasReported: cacheWriteWasReported
            ),
            pricing: .builtIn
        )
    }

    fileprivate static func valueUSD(
        model: String?,
        usage: CodexTokenUsage,
        pricing: CodexPricingDocument
    ) -> Double? {
        calculatedValueUSD(model: model, usage: usage, pricing: pricing)
    }

    fileprivate static func mayBeLowerBound(
        model: String?,
        usage: CodexTokenUsage,
        pricing: CodexPricingDocument
    ) -> Bool {
        cacheWriteMayBeMissing(model: model, usage: usage, pricing: pricing)
    }
}

actor CodexEquivalentValueIndexer {
    static let shared = CodexEquivalentValueIndexer(pricingStore: .shared)

    private let fileManager: FileManager
    private let roots: [URL]
    private let cacheURL: URL
    private let pricingStore: CodexPricingStore?
    private let retentionDays = 45
    private var index: CodexValueIndex
    private var lastRefreshStartedAt: Date?
    private var lastSnapshot: CodexEquivalentValueSnapshot = .empty
    private var pricingState: CodexPricingState = .builtIn

    init(
        fileManager: FileManager = .default,
        roots: [URL]? = nil,
        cacheURL: URL? = nil,
        pricingStore: CodexPricingStore? = nil
    ) {
        self.fileManager = fileManager
        self.pricingStore = pricingStore
        let home = fileManager.homeDirectoryForCurrentUser
        self.roots = roots ?? [
            home.appendingPathComponent(".codex/sessions", isDirectory: true),
            home.appendingPathComponent(".codex/archived_sessions", isDirectory: true)
        ]
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support", isDirectory: true)
        self.cacheURL = cacheURL
            ?? applicationSupport.appendingPathComponent("QuotaPulse/CodexEquivalentValueIndex-v1.json")
        if let data = try? Data(contentsOf: self.cacheURL),
           let decoded = try? JSONDecoder().decode(CodexValueIndex.self, from: data),
           decoded.schemaVersion == 1 {
            index = decoded
        } else {
            index = CodexValueIndex()
        }
    }

    func refresh(now: Date = Date(), minimumInterval: TimeInterval = 60) async -> CodexEquivalentValueSnapshot {
        await updatePricing(now: now, force: false)
        if let lastRefreshStartedAt,
           now.timeIntervalSince(lastRefreshStartedAt) < minimumInterval,
           lastSnapshot.lastScannedAt != nil {
            return lastSnapshot
        }
        lastRefreshStartedAt = now

        do {
            let files = discoverLogFiles()
            for (branchID, fileURL) in files {
                try Task.checkCancellation()
                try scan(fileURL: fileURL, branchID: branchID)
            }
            pruneRecords(now: now)
            index.lastScannedAt = now
            try persistIndex()
            lastSnapshot = makeSnapshot(now: now)
            return lastSnapshot
        } catch is CancellationError {
            return lastSnapshot
        } catch {
            Logger.critical("Codex equivalent value scan failed: \(error.localizedDescription)")
            var fallback = lastSnapshot
            fallback.errorMessage = error.localizedDescription
            return fallback
        }
    }

    func cachedSnapshot(now: Date = Date()) -> CodexEquivalentValueSnapshot {
        if lastSnapshot.lastScannedAt == nil {
            lastSnapshot = makeSnapshot(now: now)
        }
        return lastSnapshot
    }

    func refreshPricing(now: Date = Date()) async -> CodexEquivalentValueSnapshot {
        await updatePricing(now: now, force: true)
        lastSnapshot = makeSnapshot(now: now)
        return lastSnapshot
    }

    private func updatePricing(now: Date, force: Bool) async {
        guard let pricingStore else { return }
        let next = await pricingStore.refreshIfNeeded(now: now, force: force)
        guard next != pricingState else { return }
        pricingState = next
        if lastSnapshot.lastScannedAt != nil {
            lastSnapshot = makeSnapshot(now: now)
        }
    }

    private func discoverLogFiles() -> [String: URL] {
        var selected: [String: (url: URL, size: UInt64)] = [:]
        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "jsonl" {
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values?.isRegularFile == true else { continue }
                let branchID = Self.branchID(from: url)
                let size = UInt64(max(values?.fileSize ?? 0, 0))
                if selected[branchID] == nil || size > selected[branchID]!.size {
                    selected[branchID] = (url, size)
                }
            }
        }
        return selected.mapValues(\.url)
    }

    private static func branchID(from url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        if let range = name.range(of: #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#, options: .regularExpression) {
            return String(name[range]).lowercased()
        }
        return name
    }

    private func scan(fileURL: URL, branchID: String) throws {
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let fileSystemNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        let fileCreationDate = attributes[.creationDate] as? Date
        var cursor = index.branches[branchID] ?? CodexBranchCursor()
        let fileWasReplaced = fileSize < cursor.processedOffset
            || (cursor.fileSystemNumber != nil && fileSystemNumber != cursor.fileSystemNumber)
            || (cursor.fileCreationDate != nil && fileCreationDate != cursor.fileCreationDate)
        if fileWasReplaced {
            cursor = CodexBranchCursor()
        }
        guard fileSize > cursor.processedOffset else { return }

        var newRecords: [CodexValueRequestRecord] = []
        var newWarnings: [Date] = []

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: cursor.processedOffset)
        var buffer = Data()
        var consumedBytes: UInt64 = 0
        let chunkSize = 256 * 1_024
        let maximumBufferedLineBytes = 8 * 1_024 * 1_024
        var droppingOversizedLine = cursor.isDroppingOversizedLine

        while true {
            var chunk = try autoreleasepool {
                try handle.read(upToCount: chunkSize) ?? Data()
            }
            guard !chunk.isEmpty else { break }
            if droppingOversizedLine {
                if let newline = chunk.firstIndex(of: 0x0A) {
                    let discarded = chunk.distance(from: chunk.startIndex, to: newline) + 1
                    consumedBytes += UInt64(discarded)
                    chunk.removeSubrange(chunk.startIndex...newline)
                    droppingOversizedLine = false
                } else {
                    consumedBytes += UInt64(chunk.count)
                    try Task.checkCancellation()
                    continue
                }
            }
            buffer.append(chunk)
            var lineStart = buffer.startIndex
            while lineStart < buffer.endIndex,
                  let newline = buffer[lineStart...].firstIndex(of: 0x0A) {
                let rawLine = buffer[lineStart..<newline]
                let lineLength = rawLine.count + 1
                if !rawLine.isEmpty, Self.isRelevantLogLine(rawLine) {
                    autoreleasepool {
                        if let object = try? JSONSerialization.jsonObject(with: Data(rawLine)) as? [String: Any] {
                            process(
                                object: object,
                                branchID: branchID,
                                cursor: &cursor,
                                records: &newRecords,
                                warnings: &newWarnings
                            )
                        } else {
                            newWarnings.append(Date())
                        }
                    }
                }
                consumedBytes += UInt64(lineLength)
                lineStart = buffer.index(after: newline)
            }
            if lineStart > buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex..<lineStart)
            }
            if buffer.count > maximumBufferedLineBytes {
                if Self.isRelevantLogLine(buffer[...]) {
                    newWarnings.append(Date())
                }
                consumedBytes += UInt64(buffer.count)
                buffer.removeAll(keepingCapacity: false)
                droppingOversizedLine = true
            }
            try Task.checkCancellation()
        }
        cursor.processedOffset += consumedBytes
        cursor.isDroppingOversizedLine = droppingOversizedLine
        cursor.fileSystemNumber = fileSystemNumber
        cursor.fileCreationDate = fileCreationDate
        if fileWasReplaced {
            index.records.removeAll { $0.branchID == branchID }
        }
        index.records.append(contentsOf: newRecords)
        index.warningTimestamps = (index.warningTimestamps ?? []) + newWarnings
        index.branches[branchID] = cursor
    }

    private static func isRelevantLogLine(_ line: Data.SubSequence) -> Bool {
        let prefix = String(decoding: line.prefix(1_024), as: UTF8.self)
        return prefix.contains("\"type\":\"session_meta\"")
            || prefix.contains("\"type\": \"session_meta\"")
            || prefix.contains("\"type\":\"turn_context\"")
            || prefix.contains("\"type\": \"turn_context\"")
            || prefix.contains("\"type\":\"token_count\"")
            || prefix.contains("\"type\": \"token_count\"")
            || prefix.contains("\"type\":\"task_started\"")
            || prefix.contains("\"type\": \"task_started\"")
    }

    private func process(
        object: [String: Any],
        branchID: String,
        cursor: inout CodexBranchCursor,
        records: inout [CodexValueRequestRecord],
        warnings: inout [Date]
    ) {
        let type = object["type"] as? String
        let payload = object["payload"] as? [String: Any] ?? [:]

        if type == "session_meta", !cursor.identityVerified {
            guard let metaID = payload["id"] as? String,
                  !metaID.isEmpty,
                  metaID.caseInsensitiveCompare(branchID) == .orderedSame
            else {
                warnings.append(Date())
                return
            }
            cursor.spawnTimestamp = Self.parseDate(object["timestamp"] ?? payload["timestamp"])
            let sourceIsSubagent = (payload["source"] as? [String: Any])?["subagent"] != nil
            let sessionID = payload["session_id"] as? String
            let hasForkParent = (payload["forked_from_id"] as? String)?.isEmpty == false
                || (payload["parent_thread_id"] as? String)?.isEmpty == false
            cursor.isSubagent = sourceIsSubagent
                || hasForkParent
                || (sessionID != nil && sessionID != metaID)
            cursor.identityVerified = true
            cursor.isFresh = !cursor.isSubagent
            return
        }

        if type == "event_msg", payload["type"] as? String == "task_started", cursor.isSubagent, !cursor.isFresh {
            if let turnID = payload["turn_id"] as? String, turnID.lowercased() >= branchID.lowercased() {
                cursor.isFresh = true
            } else if payload["turn_id"] == nil,
                      let startedAt = Self.parseDate(payload["started_at"]),
                      let spawn = cursor.spawnTimestamp,
                      floor(startedAt.timeIntervalSince1970) > floor(spawn.timeIntervalSince1970) {
                // Older schemas without turn_id use a strict next-second fallback.
                // Same-second events stay excluded rather than risking replay inflation.
                cursor.isFresh = true
            }
            return
        }

        if type == "turn_context", let model = payload["model"] as? String {
            cursor.currentModel = model
            return
        }

        guard type == "event_msg", payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let total = info["total_token_usage"] as? [String: Any],
              let currentUsage = Self.parseUsage(total)
        else { return }

        let previous = cursor.hasCumulativeUsage ? cursor.cumulativeUsage : .zero
        let hasNegativeReset = cursor.hasCumulativeUsage && (
            currentUsage.input < previous.input
                || currentUsage.cachedInput < previous.cachedInput
                || currentUsage.cacheWriteInput < previous.cacheWriteInput
                || currentUsage.output < previous.output
        )
        let delta = currentUsage.positiveDelta(from: previous)
        cursor.cumulativeUsage = currentUsage
        cursor.hasCumulativeUsage = true
        if hasNegativeReset {
            warnings.append(Date())
            return
        }
        guard cursor.identityVerified, cursor.isFresh, let delta else { return }

        let rateLimits = payload["rate_limits"] as? [String: Any]
            ?? object["rate_limits"] as? [String: Any]
        guard let timestamp = Self.parseDate(object["timestamp"]) else {
            warnings.append(Date())
            return
        }
        records.append(
            CodexValueRequestRecord(
                branchID: branchID,
                timestamp: timestamp,
                model: cursor.currentModel,
                planType: rateLimits?["plan_type"] as? String ?? rateLimits?["planType"] as? String,
                usage: delta
            )
        )
    }

    private static func parseUsage(_ dictionary: [String: Any]) -> CodexTokenUsage? {
        guard let input = int64(dictionary["input_tokens"] ?? dictionary["inputTokens"]),
              let output = int64(dictionary["output_tokens"] ?? dictionary["outputTokens"])
        else { return nil }
        let writeValue = dictionary["cache_write_input_tokens"] ?? dictionary["cacheWriteInputTokens"]
        return CodexTokenUsage(
            input: input,
            cachedInput: int64(dictionary["cached_input_tokens"] ?? dictionary["cachedInputTokens"]) ?? 0,
            cacheWriteInput: int64(writeValue) ?? 0,
            output: output,
            cacheWriteWasReported: writeValue != nil
        )
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) }
        return nil
    }

    private static func parseDate(_ value: Any?) -> Date? {
        if let number = value as? NSNumber { return Date(timeIntervalSince1970: number.doubleValue) }
        guard let string = value as? String else { return nil }
        if let seconds = Double(string) { return Date(timeIntervalSince1970: seconds) }
        return ISO8601DateFormatter.codexLog.date(from: string)
    }

    private func pruneRecords(now: Date) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: now)
            ?? now.addingTimeInterval(-TimeInterval(retentionDays * 86_400))
        index.records.removeAll { $0.timestamp < cutoff }
        index.warningTimestamps = index.warningTimestamps?.filter { $0 >= cutoff }
    }

    private func makeSnapshot(now: Date) -> CodexEquivalentValueSnapshot {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(-TimeInterval(retentionDays * 86_400))
        var valuesByDay: [Date: Double] = [:]
        var unsupported = Set<String>()
        var unverified = index.warningTimestamps?.filter { $0 >= cutoff }.count ?? 0
        var lowerBound = false

        for record in index.records where record.timestamp >= cutoff {
            guard Self.isPaidCodingPlan(record.planType) else {
                if record.planType?.lowercased() != "free" { unverified += 1 }
                continue
            }
            guard let value = CodexEquivalentValuePricing.valueUSD(
                model: record.model,
                usage: record.usage,
                pricing: pricingState.document
            ) else {
                unsupported.insert(record.model ?? "unknown")
                lowerBound = true
                continue
            }
            if CodexEquivalentValuePricing.mayBeLowerBound(
                model: record.model,
                usage: record.usage,
                pricing: pricingState.document
            ) {
                lowerBound = true
            }
            valuesByDay[calendar.startOfDay(for: record.timestamp), default: 0] += value
        }

        if unverified > 0 { lowerBound = true }
        return CodexEquivalentValueSnapshot(
            dailyValues: valuesByDay.map { .init(day: $0.key, valueUSD: $0.value) }.sorted { $0.day < $1.day },
            isLowerBound: lowerBound,
            unsupportedModels: unsupported.sorted(),
            excludedUnverifiedRequestCount: unverified,
            lastScannedAt: index.lastScannedAt,
            errorMessage: nil,
            pricingStatus: pricingState.status
        )
    }

    private static func isPaidCodingPlan(_ raw: String?) -> Bool {
        guard let raw else { return false }
        let normalized = raw.lowercased().filter { $0.isLetter || $0.isNumber }
        return [
            "plus", "pro", "prolite", "team", "business", "enterprise", "edu", "education",
            "selfservebusinessprolite", "businessprolite",
            "chatgptplusplan", "chatgptproplan", "chatgptteamplan", "chatgptbusinessplan", "chatgptenterpriseplan"
        ].contains(normalized)
    }

    private func persistIndex() throws {
        let directory = cacheURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder().encode(index)
        try data.write(to: cacheURL, options: [.atomic])
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
    }
}

private extension ISO8601DateFormatter {
    static let codexLog: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
