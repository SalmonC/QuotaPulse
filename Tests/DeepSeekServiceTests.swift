import XCTest
@testable import QuotaPulse

final class DeepSeekServiceTests: XCTestCase {
    func testParsesOnlyCurrenciesReturnedByBalanceAPI() throws {
        let payload = """
        {
          "is_available": true,
          "balance_infos": [
            {
              "currency": "CNY",
              "total_balance": "110.00",
              "granted_balance": "10.00",
              "topped_up_balance": "100.00"
            },
            {
              "currency": "USD",
              "total_balance": "8.50",
              "granted_balance": "0.50",
              "topped_up_balance": "8.00"
            }
          ]
        }
        """

        let result = try DeepSeekService.parseBalanceResponse(Data(payload.utf8))

        XCTAssertEqual(result.balanceDetails.map(\.currency), ["CNY", "USD"])
        XCTAssertEqual(result.balanceDetails[0].total, 110)
        XCTAssertEqual(result.balanceDetails[0].granted, 10)
        XCTAssertEqual(result.balanceDetails[0].toppedUp, 100)
        XCTAssertEqual(result.remaining, 110)
    }

    func testEstimatesConsumptionOnlyWhenBalanceDrops() {
        let previous = [
            CurrencyBalance(currency: "CNY", total: 100, granted: 10, toppedUp: 90),
            CurrencyBalance(currency: "USD", total: 5, granted: 0, toppedUp: 5)
        ]
        let current = [
            CurrencyBalance(currency: "CNY", total: 96, granted: 10, toppedUp: 86),
            CurrencyBalance(currency: "USD", total: 8, granted: 0, toppedUp: 8)
        ]

        let estimated = DeepSeekBalanceLogic.addEstimatedConsumption(
            to: current,
            previous: previous
        )

        XCTAssertEqual(estimated[0].estimatedConsumption, 4)
        XCTAssertNil(estimated[1].estimatedConsumption)
    }

    func testUnavailableBalanceResponseIsTreatedAsZeroBalance() throws {
        let payload = """
        {
          "is_available": false,
          "balance_infos": []
        }
        """

        let result = try DeepSeekService.parseBalanceResponse(Data(payload.utf8))
        XCTAssertEqual(result.remaining, 0)
        XCTAssertTrue(result.balanceDetails.isEmpty)
    }
}
