import XCTest
@testable import QuotaPulse

final class UsageMetricsLogicTests: XCTestCase {
    func testTrendPointsRespectWindowAndDownsample() {
        let accountId = UUID()
        let now = Date()
        var snapshots: [UsageSnapshot] = []

        for hour in stride(from: 95, through: 0, by: -1) {
            snapshots.append(
                UsageSnapshot(
                    accountId: accountId,
                    provider: .miniMax,
                    capturedAt: now.addingTimeInterval(-TimeInterval(hour * 3600)),
                    tokenUsed: Double(hour),
                    tokenTotal: 100,
                    monthlyUsed: nil,
                    monthlyTotal: nil,
                    usagePercentage: Double(hour % 100),
                    monthlyUsagePercentage: nil
                )
            )
        }

        let dayPoints = UsageMetricsLogic.trendPoints(
            accountSnapshots: snapshots,
            window: .day,
            now: now
        )
        XCTAssertFalse(dayPoints.isEmpty)
        XCTAssertLessThanOrEqual(dayPoints.count, 36)
        XCTAssertTrue(dayPoints.allSatisfy { $0.timestamp >= now.addingTimeInterval(-86_400) })

        let monthPoints = UsageMetricsLogic.trendPoints(
            accountSnapshots: snapshots,
            window: .month,
            now: now
        )
        XCTAssertLessThanOrEqual(monthPoints.count, 36)
        XCTAssertGreaterThanOrEqual(monthPoints.count, dayPoints.count)
    }

    func testDeepSeekDailyBalanceUsesLastSnapshotAndSkipsMissingDays() throws {
        let accountId = UUID()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 24, hour: 12)))
        let day1Morning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 9)))
        let day1Later = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 18)))
        let day3Morning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 23, hour: 8)))
        let day4Morning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 24, hour: 8)))

        let snapshots = [
            makeDeepSeekBalanceSnapshot(accountID: accountId, date: day1Morning, balance: 10),
            makeDeepSeekBalanceSnapshot(accountID: accountId, date: day1Later, balance: 9),
            makeDeepSeekBalanceSnapshot(accountID: accountId, date: day3Morning, balance: 7),
            makeDeepSeekBalanceSnapshot(accountID: accountId, date: day4Morning, balance: 12)
        ]

        let points = UsageMetricsLogic.deepSeekDailyBalancePoints(
            accountSnapshots: snapshots,
            window: .twoWeeks,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(points.map(\.balance), [9, 7, 12])
        XCTAssertNil(points[0].deltaFromPrevious)
        XCTAssertEqual(points[1].deltaFromPrevious, -2)
        XCTAssertEqual(points[2].deltaFromPrevious, 5)
        XCTAssertEqual(points.map { calendar.component(.day, from: $0.day) }, [21, 23, 24])
    }

    func testDeepSeekFirstVisibleDayUsesPreviousAvailableBalance() throws {
        let accountId = UUID()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 12)))
        let beforeWindow = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 17, hour: 18)))
        let firstVisibleDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 9)))
        let unchangedDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 9)))

        let points = UsageMetricsLogic.deepSeekDailyBalancePoints(
            accountSnapshots: [
                makeDeepSeekBalanceSnapshot(accountID: accountId, date: beforeWindow, balance: 0.25),
                makeDeepSeekBalanceSnapshot(accountID: accountId, date: firstVisibleDay, balance: -1.73),
                makeDeepSeekBalanceSnapshot(accountID: accountId, date: unchangedDay, balance: -1.73)
            ],
            window: .week,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(points.map(\.balance), [-1.73, -1.73])
        XCTAssertEqual(points[0].deltaFromPrevious ?? 0, -1.98, accuracy: 0.000_001)
        XCTAssertEqual(points[1].deltaFromPrevious ?? 1, 0, accuracy: 0.000_001)
    }

    func testDataConfidenceClassification() {
        let base = UsageData(
            accountId: UUID(),
            accountName: "A",
            provider: .miniMax,
            tokenRemaining: 50,
            tokenUsed: 50,
            tokenTotal: 100,
            refreshTime: nil,
            lastUpdated: Date(),
            errorMessage: nil,
            monthlyRemaining: nil,
            monthlyTotal: nil,
            monthlyUsed: nil,
            monthlyRefreshTime: nil,
            nextRefreshTime: nil,
            subscriptionPlan: nil
        )

        let high = UsageMetricsLogic.dataConfidence(for: base, language: .english)
        XCTAssertEqual(high.level, .high)

        var estimated = base
        estimated.primaryRefreshIsEstimated = true
        let medium = UsageMetricsLogic.dataConfidence(for: estimated, language: .english)
        XCTAssertEqual(medium.level, .medium)

        var errored = base
        errored.errorMessage = "failed"
        let low = UsageMetricsLogic.dataConfidence(for: errored, language: .english)
        XCTAssertEqual(low.level, .low)

        var deepSeekBalance = base
        deepSeekBalance.provider = .deepSeek
        deepSeekBalance.tokenRemaining = 4.54
        deepSeekBalance.tokenUsed = nil
        deepSeekBalance.tokenTotal = nil
        deepSeekBalance.balanceDetails = [
            CurrencyBalance(currency: "CNY", total: 4.54, granted: 0, toppedUp: 4.54)
        ]
        let balanceConfidence = UsageMetricsLogic.dataConfidence(for: deepSeekBalance, language: .chinese)
        XCTAssertEqual(balanceConfidence.level, .balance)
        XCTAssertEqual(balanceConfidence.level.label(language: .chinese), "余额")
    }

    func testDeepSeekDisplayBalancesFallbackToCachedRemainingBalance() {
        let cachedLegacyBalance = UsageData(
            accountId: UUID(),
            accountName: "DeepSeek",
            provider: .deepSeek,
            tokenRemaining: 4.54,
            tokenUsed: nil,
            tokenTotal: nil,
            refreshTime: nil,
            lastUpdated: Date(),
            errorMessage: "查询失败：鉴权失败（401/403），请更新凭证",
            monthlyRemaining: nil,
            monthlyTotal: nil,
            monthlyUsed: nil,
            monthlyRefreshTime: nil,
            nextRefreshTime: nil,
            subscriptionPlan: nil,
            balanceDetails: nil
        )

        XCTAssertEqual(cachedLegacyBalance.currencyBalances.count, 0)
        XCTAssertEqual(cachedLegacyBalance.displayCurrencyBalances.count, 1)
        XCTAssertEqual(cachedLegacyBalance.displayCurrencyBalances.first?.currency, "CNY")
        XCTAssertEqual(cachedLegacyBalance.displayCurrencyBalances.first?.total, 4.54)
    }

    func testRetryableErrorClassification() {
        XCTAssertTrue(UsageMetricsLogic.isRetryableFetchError(APIError.httpError(500)))
        XCTAssertTrue(UsageMetricsLogic.isRetryableFetchError(APIError.httpError(429)))
        XCTAssertTrue(UsageMetricsLogic.isRetryableFetchError(APIError.networkError(URLError(.timedOut))))
        XCTAssertFalse(UsageMetricsLogic.isRetryableFetchError(APIError.httpError(401)))
        XCTAssertFalse(UsageMetricsLogic.isRetryableFetchError(APIError.decodingError(NSError(domain: "x", code: 1))))
    }

    func testBackoffGrowsWithAttemptAndHonorsCap() {
        let a1 = UsageMetricsLogic.backoffDelayNanoseconds(attempt: 1, jitterRange: 0...0)
        let a2 = UsageMetricsLogic.backoffDelayNanoseconds(attempt: 2, jitterRange: 0...0)
        let a5 = UsageMetricsLogic.backoffDelayNanoseconds(attempt: 5, jitterRange: 0...0)

        XCTAssertGreaterThan(a2, a1)
        XCTAssertLessThanOrEqual(a5, UInt64(2.8 * 1_000_000_000))
    }

    private func makeDeepSeekBalanceSnapshot(accountID: UUID, date: Date, balance: Double) -> UsageSnapshot {
        UsageSnapshot(
            accountId: accountID,
            provider: .deepSeek,
            capturedAt: date,
            tokenUsed: nil,
            tokenTotal: nil,
            monthlyUsed: nil,
            monthlyTotal: nil,
            usagePercentage: nil,
            monthlyUsagePercentage: nil,
            balanceTotal: balance,
            balanceCurrency: "CNY"
        )
    }
}
