import Foundation

struct UsageTrendPoint: Identifiable, Equatable {
    var id: Date { timestamp }
    let timestamp: Date
    let usagePercent: Double
}

struct DeepSeekBalanceTrendPoint: Identifiable, Equatable {
    var id: String { "\(currency)-\(day.timeIntervalSince1970)" }
    let day: Date
    let balance: Double
    let currency: String
    let deltaFromPrevious: Double?
}

enum DataConfidenceLevel: String {
    case high
    case medium
    case low
    case balance
    case unknown

    func label(language: AppLanguage) -> String {
        switch self {
        case .high:
            return language == .english ? "High" : "高"
        case .medium:
            return language == .english ? "Medium" : "中"
        case .low:
            return language == .english ? "Low" : "低"
        case .balance:
            return language == .english ? "Balance" : "余额"
        case .unknown:
            return language == .english ? "Unknown" : "未知"
        }
    }
}

struct DataConfidence: Equatable {
    let level: DataConfidenceLevel
    let reason: String
}

enum UsageMetricsLogic {
    static func trendPoints(
        accountSnapshots: [UsageSnapshot],
        window: TrendWindow,
        now: Date = Date(),
        targetCount: Int = 36
    ) -> [UsageTrendPoint] {
        let cutoff = now.addingTimeInterval(-TimeInterval(window.days * 86_400))
        let source = accountSnapshots.filter { $0.capturedAt >= cutoff }

        guard !source.isEmpty else { return [] }

        var points: [UsageTrendPoint] = []
        points.reserveCapacity(min(source.count, 160))
        for snapshot in source {
            guard let percent = snapshot.usagePercentage ?? snapshot.monthlyUsagePercentage else {
                continue
            }
            points.append(
                UsageTrendPoint(
                    timestamp: snapshot.capturedAt,
                    usagePercent: min(max(percent, 0), 100)
                )
            )
        }
        return downsample(points: points, targetCount: targetCount)
    }

    static func downsample(points: [UsageTrendPoint], targetCount: Int) -> [UsageTrendPoint] {
        guard points.count > targetCount, targetCount > 2 else { return points }
        let step = Double(points.count - 1) / Double(targetCount - 1)
        var reduced: [UsageTrendPoint] = []
        reduced.reserveCapacity(targetCount)
        for index in 0..<targetCount {
            let sourceIndex = Int((Double(index) * step).rounded())
            reduced.append(points[min(max(sourceIndex, 0), points.count - 1)])
        }
        return reduced
    }

    static func deepSeekDailyBalancePoints(
        accountSnapshots: [UsageSnapshot],
        window: TrendWindow,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DeepSeekBalanceTrendPoint] {
        let effectiveDays = max(window.days, 1)
        let today = calendar.startOfDay(for: now)
        guard let startDay = calendar.date(byAdding: .day, value: -(effectiveDays - 1), to: today) else {
            return []
        }
        guard let endExclusive = calendar.date(byAdding: .day, value: 1, to: today) else {
            return []
        }

        let validSnapshots = accountSnapshots
            .filter {
                $0.provider == .deepSeek &&
                $0.capturedAt < endExclusive &&
                $0.balanceTotal != nil &&
                $0.balanceCurrency != nil
            }
            .sorted { $0.capturedAt < $1.capturedAt }

        let source = validSnapshots.filter { $0.capturedAt >= startDay }

        guard !source.isEmpty else { return [] }

        // Seed each currency with the most recent value before the visible
        // range so the first displayed day still gets a meaningful delta.
        var previousByCurrency: [String: Double] = [:]
        for snapshot in validSnapshots where snapshot.capturedAt < startDay {
            guard
                let balance = snapshot.balanceTotal,
                let currency = snapshot.balanceCurrency?.uppercased()
            else { continue }
            previousByCurrency[currency] = balance
        }

        var lastByDayAndCurrency: [String: UsageSnapshot] = [:]
        for snapshot in source {
            guard let currency = snapshot.balanceCurrency?.uppercased() else { continue }
            let day = calendar.startOfDay(for: snapshot.capturedAt)
            let key = "\(currency)-\(day.timeIntervalSince1970)"
            lastByDayAndCurrency[key] = snapshot
        }

        let sortedLastSnapshots = lastByDayAndCurrency.values.sorted {
            if $0.balanceCurrency?.uppercased() != $1.balanceCurrency?.uppercased() {
                return ($0.balanceCurrency ?? "") < ($1.balanceCurrency ?? "")
            }
            return $0.capturedAt < $1.capturedAt
        }

        return sortedLastSnapshots.compactMap { snapshot in
            guard
                let balance = snapshot.balanceTotal,
                let rawCurrency = snapshot.balanceCurrency
            else { return nil }
            let currency = rawCurrency.uppercased()
            let delta = previousByCurrency[currency].map { balance - $0 }
            previousByCurrency[currency] = balance
            return DeepSeekBalanceTrendPoint(
                day: calendar.startOfDay(for: snapshot.capturedAt),
                balance: balance,
                currency: currency,
                deltaFromPrevious: delta
            )
        }
    }

    static func dataConfidence(for data: UsageData, language: AppLanguage) -> DataConfidence {
        if data.errorMessage != nil {
            return DataConfidence(
                level: .low,
                reason: language == .english ? "Last refresh failed" : "最近一次刷新失败"
            )
        }

        if data.provider == .deepSeek, !data.currencyBalances.isEmpty {
            return DataConfidence(
                level: .balance,
                reason: language == .english
                    ? "Direct balance data from provider"
                    : "供应商直接返回的账户余额数据"
            )
        }

        let hasNumericUsage = (data.tokenTotal ?? 0) > 0 || (data.monthlyTotal ?? 0) > 0
        let hasEstimatedField = data.primaryRefreshIsEstimated || data.secondaryRefreshIsEstimated
        if hasNumericUsage && !hasEstimatedField {
            return DataConfidence(
                level: .high,
                reason: language == .english ? "Direct provider data" : "供应商直接返回数据"
            )
        }
        if hasNumericUsage && hasEstimatedField {
            return DataConfidence(
                level: .medium,
                reason: language == .english ? "Partially estimated reset cycle" : "部分刷新周期为估算"
            )
        }
        return DataConfidence(
            level: .unknown,
            reason: language == .english ? "Limited provider fields" : "供应商可用字段有限"
        )
    }

    static func isRetryableFetchError(_ error: Error) -> Bool {
        if let apiError = error as? APIError {
            switch apiError {
            case .networkError:
                return true
            case .httpError(let code), .httpErrorWithMessage(let code, _):
                return code >= 500 || code == 429
            default:
                return false
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .networkConnectionLost, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }
        let lowered = error.localizedDescription.lowercased()
        return lowered.contains("timeout") || lowered.contains("timed out") || lowered.contains("429")
    }

    static func backoffDelayNanoseconds(attempt: Int, jitterRange: ClosedRange<Double> = 0.05...0.18) -> UInt64 {
        let baseSeconds = pow(2.0, Double(max(0, attempt - 1))) * 0.45
        let jitterSeconds = Double.random(in: jitterRange)
        let totalSeconds = min(baseSeconds + jitterSeconds, 2.8)
        return UInt64(totalSeconds * 1_000_000_000)
    }
}
