import Foundation
import AppKit

struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
    }
}

enum ReleaseFetchError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "invalid response"
        case .httpStatus(let code):
            return "HTTP \(code)"
        }
    }
}

private enum UpdateComparisonResult {
    case updateAvailable(current: String, latest: String, releaseURL: URL)
    case upToDate(current: String, latest: String)
}

@MainActor
final class UpdateService: ObservableObject {
    @Published var isChecking = false
    @Published var statusMessage: String?
    @Published var lastCheckTime: Date?

    private let readmeURL: URL
    private let languageProvider: () -> AppLanguage
    private let urlOpener: (URL) -> Bool
    private let latestReleaseProvider: () async throws -> GitHubRelease?
    private let currentVersionProvider: () -> String

    init(
        readmeURL: URL = URL(string: "https://github.com/SalmonC/QuotaPulse/blob/main/README.md")!,
        languageProvider: @escaping () -> AppLanguage = { .chinese },
        urlOpener: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        latestReleaseProvider: @escaping () async throws -> GitHubRelease? = {
            try await UpdateService.fetchLatestStableRelease(
                owner: "SalmonC",
                repo: "QuotaPulse"
            )
        },
        currentVersionProvider: @escaping () -> String = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        }
    ) {
        self.readmeURL = readmeURL
        self.languageProvider = languageProvider
        self.urlOpener = urlOpener
        self.latestReleaseProvider = latestReleaseProvider
        self.currentVersionProvider = currentVersionProvider
    }

    func checkForUpdates() {
        guard !isChecking else { return }

        isChecking = true
        statusMessage = localized(
            zh: "正在检查更新（GitHub Release）…",
            en: "Checking for updates (GitHub Release)..."
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isChecking = false
                self.lastCheckTime = Date()
            }

            do {
                guard let release = try await self.latestReleaseProvider() else {
                    self.statusMessage = self.localized(
                        zh: "未找到可用的正式版 Release",
                        en: "No stable release found on GitHub"
                    )
                    return
                }

                let currentVersion = Self.normalizedVersion(self.currentVersionProvider())
                let latestVersion = Self.normalizedVersion(release.tagName)

                switch Self.compareVersion(current: currentVersion, latest: latestVersion, releaseURL: release.htmlURL) {
                case .upToDate:
                    self.statusMessage = self.localized(
                        zh: "当前已是最新版本（\(currentVersion)）",
                        en: "You're up to date (\(currentVersion))"
                    )
                case .updateAvailable(_, let latest, let releaseURL):
                    if self.urlOpener(releaseURL) {
                        self.statusMessage = self.localized(
                            zh: "发现新版本 \(latest)，已打开下载页面",
                            en: "New version \(latest) found. Opened download page"
                        )
                    } else {
                        self.statusMessage = self.localized(
                            zh: "发现新版本 \(latest)，但无法打开下载页面",
                            en: "New version \(latest) found, but failed to open download page"
                        )
                    }
                }
            } catch let error as ReleaseFetchError {
                switch error {
                case .httpStatus(let code):
                    self.statusMessage = self.localized(
                        zh: "检查更新失败：GitHub 返回 HTTP \(code)",
                        en: "Update check failed: GitHub returned HTTP \(code)"
                    )
                case .invalidResponse:
                    self.statusMessage = self.localized(
                        zh: "检查更新失败：GitHub 返回无效数据",
                        en: "Update check failed: invalid GitHub response"
                    )
                }
            } catch let urlError as URLError {
                self.statusMessage = self.localized(
                    zh: "检查更新失败：网络错误（\(urlError.code.rawValue)）",
                    en: "Update check failed: network error (\(urlError.code.rawValue))"
                )
            } catch {
                self.statusMessage = self.localized(
                    zh: "检查更新失败：\(error.localizedDescription)",
                    en: "Update check failed: \(error.localizedDescription)"
                )
            }
        }
    }

    func openGitHubReadme() {
        guard urlOpener(readmeURL) else {
            statusMessage = localized(
                zh: "无法打开 GitHub README 页面",
                en: "Failed to open GitHub README page"
            )
            return
        }
        statusMessage = localized(
            zh: "已打开 GitHub README",
            en: "Opened GitHub README"
        )
    }

    private static func fetchLatestStableRelease(owner: String, repo: String) async throws -> GitHubRelease? {
        let endpoint = "https://api.github.com/repos/\(owner)/\(repo)/releases?per_page=20"
        guard let url = URL(string: endpoint) else {
            throw ReleaseFetchError.invalidResponse
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 12)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ReleaseFetchError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw ReleaseFetchError.httpStatus(http.statusCode)
        }

        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        return releases.first(where: { !$0.draft && !$0.prerelease })
    }

    private static func normalizedVersion(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    private static func compareVersion(current: String, latest: String, releaseURL: URL) -> UpdateComparisonResult {
        let currentNumbers = parseVersion(current)
        let latestNumbers = parseVersion(latest)
        let maxLength = max(currentNumbers.count, latestNumbers.count)

        for idx in 0..<maxLength {
            let lhs = idx < currentNumbers.count ? currentNumbers[idx] : 0
            let rhs = idx < latestNumbers.count ? latestNumbers[idx] : 0
            if rhs > lhs {
                return .updateAvailable(current: current, latest: latest, releaseURL: releaseURL)
            }
            if rhs < lhs {
                return .upToDate(current: current, latest: latest)
            }
        }

        return .upToDate(current: current, latest: latest)
    }

    private static func parseVersion(_ version: String) -> [Int] {
        let segments = version.split(separator: ".")
        return segments.compactMap { segment in
            let numeric = segment.prefix { $0.isNumber }
            return Int(numeric)
        }
    }

    private func localized(zh: String, en: String) -> String {
        languageProvider() == .english ? en : zh
    }
}
