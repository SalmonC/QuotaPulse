import XCTest
@testable import QuotaPulse

@MainActor
final class UpdateServiceTests: XCTestCase {
    private func waitUntil(
        timeout: TimeInterval = 1.0,
        condition: @escaping () -> Bool
    ) {
        let expectation = XCTestExpectation(description: "Wait for condition")
        let deadline = Date().addingTimeInterval(timeout)
        
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            if condition() || Date() > deadline {
                timer.invalidate()
                expectation.fulfill()
            }
        }
        
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout + 0.1)
        if result != .completed || !condition() {
            XCTFail("Timed out waiting for condition")
        }
    }

    func testCheckForUpdatesTransitionsToUpToDate() {
        let service = UpdateService(
            languageProvider: { .english },
            urlOpener: { _ in true },
            latestReleaseProvider: {
                GitHubRelease(
                    tagName: "v0.9.3",
                    htmlURL: URL(string: "https://github.com/SalmonC/QuotaPulse/releases/tag/v0.9.3")!,
                    draft: false,
                    prerelease: false
                )
            },
            currentVersionProvider: { "0.9.3" }
        )

        service.checkForUpdates()
        waitUntil { !service.isChecking }
        XCTAssertEqual(service.statusMessage, "You're up to date (0.9.3)")
        XCTAssertNotNil(service.lastCheckTime)
    }

    func testUpdateAvailableOpensReleasePage() {
        var openedURL: URL?
        let service = UpdateService(
            languageProvider: { .chinese },
            urlOpener: { url in
                openedURL = url
                return true
            },
            latestReleaseProvider: {
                GitHubRelease(
                    tagName: "v0.9.4",
                    htmlURL: URL(string: "https://github.com/SalmonC/QuotaPulse/releases/tag/v0.9.4")!,
                    draft: false,
                    prerelease: false
                )
            },
            currentVersionProvider: { "0.9.3" }
        )

        service.checkForUpdates()
        waitUntil { !service.isChecking }
        XCTAssertEqual(openedURL?.absoluteString, "https://github.com/SalmonC/QuotaPulse/releases/tag/v0.9.4")
        XCTAssertTrue((service.statusMessage ?? "").contains("已打开下载页面"))
    }

    func testNetworkErrorRespectsSelectedLanguage() {
        let service = UpdateService(
            languageProvider: { .chinese },
            urlOpener: { _ in true },
            latestReleaseProvider: {
                throw URLError(.notConnectedToInternet)
            },
            currentVersionProvider: { "0.9.3" }
        )

        service.checkForUpdates()
        waitUntil { !service.isChecking }
        XCTAssertTrue((service.statusMessage ?? "").contains("网络错误"))
    }

    func testGitHubReadmeOpenFailureShowsMessage() {
        let service = UpdateService(
            languageProvider: { .english },
            urlOpener: { _ in false },
            latestReleaseProvider: { nil },
            currentVersionProvider: { "0.9.3" }
        )

        service.openGitHubReadme()
        XCTAssertEqual(service.statusMessage, "Failed to open GitHub README page")
    }
}
