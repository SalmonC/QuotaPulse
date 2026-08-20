import Foundation
import os.log

// Helper function to parse numbers from various formats
func parseNumber(_ value: Any?) -> Double? {
    guard let value = value else { return nil }
    if let d = value as? Double {
        return d
    } else if let i = value as? Int {
        return Double(i)
    } else if let s = value as? String, let d = Double(s) {
        return d
    } else if let n = value as? NSNumber {
        return n.doubleValue
    }
    return nil
}

final class Logger {
    private static let logger = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mactools.apiusagetracker",
        category: "app"
    )
    private static let criticalLogFileName = "quotapulse_critical.log"
    private static let criticalLogMaxBytes: UInt64 = 256 * 1024
    
    static func log(_ message: String) {
        #if DEBUG
        print("[QuotaPulse] \(message)")
        #endif
        os_log("%{public}@", log: logger, type: .default, message)
    }

    static func warning(_ message: String) {
        os_log("%{public}@", log: logger, type: .error, "WARNING: \(message)")
    }

    static func critical(_ message: String) {
        let line = "[\(Self.timestamp())] CRITICAL \(message)"
        os_log("%{public}@", log: logger, type: .fault, line)
        appendCriticalLog(line)
    }

    private static func appendCriticalLog(_ line: String) {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let fileURL = documentsURL.appendingPathComponent(criticalLogFileName)
        rotateCriticalLogIfNeeded(fileURL)

        guard let data = (line + "\n").data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                _ = try? handle.write(contentsOf: data)
            }
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func rotateCriticalLogIfNeeded(_ fileURL: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? UInt64,
              size > criticalLogMaxBytes else {
            return
        }

        let rotatedURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(fileURL.deletingPathExtension().lastPathComponent + ".1")
            .appendingPathExtension(fileURL.pathExtension)
        try? FileManager.default.removeItem(at: rotatedURL)
        try? FileManager.default.moveItem(at: fileURL, to: rotatedURL)
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case httpErrorWithMessage(Int, String)
    case decodingError(Error)
    case noAPIKey
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的URL"
        case .invalidResponse:
            return "无效的响应"
        case .httpError(let code):
            return "HTTP错误: \(code)"
        case .httpErrorWithMessage(let code, let message):
            return "HTTP \(code): \(message)"
        case .decodingError:
            return "数据解析失败"
        case .noAPIKey:
            return "未配置API Key"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        }
    }
}

struct UsageResult {
    var remaining: Double?
    var used: Double?
    var total: Double?
    var refreshTime: Date?
    var monthlyRemaining: Double?
    var monthlyTotal: Double?
    var monthlyUsed: Double?
    var monthlyRefreshTime: Date?
    var nextRefreshTime: Date?
    var subscriptionPlan: String? = nil
    var primaryCycleIsPercentage: Bool? = nil
    var secondaryCycleIsPercentage: Bool? = nil
    var balanceDetails: [CurrencyBalance] = []
}

protocol UsageService {
    var provider: APIProvider { get }
    func fetchUsage(apiKey: String) async throws -> UsageResult
}

enum DeepSeekBalanceLogic {
    static func addEstimatedConsumption(
        to current: [CurrencyBalance],
        previous: [CurrencyBalance]
    ) -> [CurrencyBalance] {
        let previousByCurrency = Dictionary(uniqueKeysWithValues: previous.map { ($0.currency, $0.total) })
        return current.map { balance in
            var updated = balance
            if let oldTotal = previousByCurrency[balance.currency] {
                let decrease = oldTotal - balance.total
                updated.estimatedConsumption = decrease > 0.000_001 ? decrease : nil
            }
            return updated
        }
    }
}

final class DeepSeekService: UsageService {
    let provider: APIProvider = .deepSeek

    func fetchUsage(apiKey: String) async throws -> UsageResult {
        guard !apiKey.isEmpty else { throw APIError.noAPIKey }
        guard let url = URL(string: "https://api.deepseek.com/user/balance") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            guard httpResponse.statusCode == 200 else {
                throw APIError.httpError(httpResponse.statusCode)
            }
            return try Self.parseBalanceResponse(data)
        } catch let error as APIError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as DecodingError {
            throw APIError.decodingError(error)
        } catch {
            throw APIError.networkError(error)
        }
    }

    static func parseBalanceResponse(_ data: Data) throws -> UsageResult {
        let response = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)
        guard response.isAvailable || !response.balanceInfos.isEmpty else {
            // DeepSeek defines is_available as "has enough balance for API calls".
            // A false value is therefore a valid zero-balance response, not an
            // authentication failure.
            return UsageResult(
                remaining: 0,
                used: nil,
                total: nil,
                refreshTime: nil,
                balanceDetails: []
            )
        }
        guard !response.balanceInfos.isEmpty else {
            throw APIError.invalidResponse
        }
        let balances = try response.balanceInfos.map { info in
            guard
                let total = Double(info.totalBalance),
                let granted = Double(info.grantedBalance),
                let toppedUp = Double(info.toppedUpBalance)
            else {
                throw APIError.invalidResponse
            }
            return CurrencyBalance(
                currency: info.currency.uppercased(),
                total: total,
                granted: granted,
                toppedUp: toppedUp
            )
        }
        return UsageResult(
            remaining: balances.first?.total,
            used: nil,
            total: nil,
            refreshTime: nil,
            balanceDetails: balances
        )
    }
}

private struct DeepSeekBalanceResponse: Decodable {
    let isAvailable: Bool
    let balanceInfos: [DeepSeekBalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

private struct DeepSeekBalanceInfo: Decodable {
    let currency: String
    let totalBalance: String
    let grantedBalance: String
    let toppedUpBalance: String

    enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance"
        case grantedBalance = "granted_balance"
        case toppedUpBalance = "topped_up_balance"
    }
}

final class MiniMaxService: UsageService {
    let provider: APIProvider = .miniMax

    func fetchUsage(apiKey: String) async throws -> UsageResult {
        guard !apiKey.isEmpty else { throw APIError.noAPIKey }
        try Task.checkCancellation()
        return try await fetchTokenPlanUsage(apiKey: apiKey)
    }

    private func fetchTokenPlanUsage(apiKey: String) async throws -> UsageResult {
        guard let url = URL(string: "https://www.minimax.io/v1/token_plan/remains") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            Logger.log("MiniMax Token Plan API: HTTP \(httpResponse.statusCode)")

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw APIError.httpErrorWithMessage(httpResponse.statusCode, "MiniMax API Key 无效或无 Token Plan 查询权限")
            }
            guard httpResponse.statusCode == 200 else {
                throw APIError.httpError(httpResponse.statusCode)
            }

            let decoded = try JSONDecoder().decode(MiniMaxTokenPlanResponse.self, from: data)
            guard let modelData = decoded.modelRemains.first else {
                throw APIError.httpErrorWithMessage(200, "MiniMax 官方 Token Plan 接口未返回额度数据")
            }

            let used = max(0, modelData.currentIntervalTotalCount - modelData.currentIntervalUsageCount)
            Logger.log("MiniMax Token Plan: remaining=\(modelData.currentIntervalUsageCount), used=\(used), total=\(modelData.currentIntervalTotalCount)")

            return UsageResult(
                remaining: Double(modelData.currentIntervalUsageCount),
                used: Double(used),
                total: Double(modelData.currentIntervalTotalCount),
                refreshTime: Date(timeIntervalSince1970: TimeInterval(modelData.endTime) / 1000)
            )
        } catch let error as APIError {
            throw error
        } catch {
            Logger.log("MiniMax Token Plan API failed: \(error.localizedDescription)")
            throw APIError.networkError(error)
        }
    }
}

struct MiniMaxTokenPlanResponse: Codable {
    let modelRemains: [MiniMaxTokenPlanData]
    let baseResp: BaseResp?

    enum CodingKeys: String, CodingKey {
        case modelRemains = "model_remains"
        case baseResp = "base_resp"
    }
}

struct MiniMaxTokenPlanData: Codable {
    let startTime: Int
    let endTime: Int
    let remainsTime: Int
    let currentIntervalTotalCount: Int
    let currentIntervalUsageCount: Int
    let modelName: String

    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
        case remainsTime = "remains_time"
        case currentIntervalTotalCount = "current_interval_total_count"
        case currentIntervalUsageCount = "current_interval_usage_count"
        case modelName = "model_name"
    }
}

struct BaseResp: Codable {
    let statusCode: Int
    let statusMsg: String

    enum CodingKeys: String, CodingKey {
        case statusCode = "status_code"
        case statusMsg = "status_msg"
    }
}
final class TavilyService: UsageService {
    let provider: APIProvider = .tavily
    
    func fetchUsage(apiKey: String) async throws -> UsageResult {
        guard !apiKey.isEmpty else {
            throw APIError.noAPIKey
        }
        
        guard let url = URL(string: "https://api.tavily.com/usage") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            let responseString = String(data: data, encoding: .utf8) ?? "nil"
            Logger.log("Tavily API: HTTP \(httpResponse.statusCode), Response: \(responseString)")
            
            if httpResponse.statusCode != 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let msg = json["message"] as? String ?? json["error"] as? String {
                    throw APIError.httpErrorWithMessage(httpResponse.statusCode, msg)
                }
                throw APIError.httpError(httpResponse.statusCode)
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var remaining: Double = 0
                var total: Double = 0
                var used: Double = 0
                let refreshTime = parseTavilyRefreshTime(in: json)
                
                if let keyObj = json["key"] as? [String: Any] {
                    if let limit = parseNumber(keyObj["limit"]), limit > 0 {
                        total = limit
                    }
                    if let usage = parseNumber(keyObj["usage"]) {
                        used = usage
                    }
                }
                
                if let accountObj = json["account"] as? [String: Any] {
                    if let planLimit = parseNumber(accountObj["plan_limit"]), planLimit > 0, total == 0 {
                        total = planLimit
                    }
                    if let planUsage = parseNumber(accountObj["plan_usage"]), used == 0 {
                        used = planUsage
                    }
                }
                
                remaining = max(0, total - used)
                
                Logger.log("Tavily API Success: remaining=\(remaining), used=\(used), total=\(total), refreshTime=\(String(describing: refreshTime))")
                return UsageResult(remaining: remaining, used: used, total: total, refreshTime: refreshTime)
            }
            
            throw APIError.decodingError(NSError(domain: "", code: 0))
        } catch let error as APIError {
            throw error
        } catch {
            Logger.log("Tavily API Error: \(error.localizedDescription)")
            throw APIError.networkError(error)
        }
    }

    private func parseTavilyRefreshTime(in json: [String: Any]) -> Date? {
        let candidateScopes: [[String: Any]] = [
            json,
            json["key"] as? [String: Any] ?? [:],
            json["account"] as? [String: Any] ?? [:]
        ]
        let dateKeys = [
            "next_reset",
            "next_reset_at",
            "reset_at",
            "renewal_at",
            "renews_at",
            "period_end",
            "period_end_at",
            "billing_cycle_end",
            "quota_reset_at",
            "nextRefreshTime",
            "refresh_time",
            "refreshTime"
        ]

        for scope in candidateScopes where !scope.isEmpty {
            for key in dateKeys {
                if let date = parseTavilyDate(scope[key]) {
                    return date
                }
            }
        }
        return nil
    }

    private func parseTavilyDate(_ raw: Any?) -> Date? {
        guard let raw else { return nil }

        if let number = parseNumber(raw), number > 0 {
            if number > 10_000_000_000 {
                return Date(timeIntervalSince1970: number / 1000)
            }
            return Date(timeIntervalSince1970: number)
        }

        guard let text = raw as? String, !text.isEmpty else { return nil }

        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFractional.date(from: text) {
            return date
        }

        let isoBasic = ISO8601DateFormatter()
        if let date = isoBasic.date(from: text) {
            return date
        }

        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.timeZone = TimeZone(secondsFromGMT: 0)
        fallback.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = fallback.date(from: text) {
            return date
        }

        let dateOnly = DateFormatter()
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.timeZone = TimeZone(secondsFromGMT: 0)
        dateOnly.dateFormat = "yyyy-MM-dd"
        return dateOnly.date(from: text)
    }
}

final class OpenAIService: UsageService {
    let provider: APIProvider = .openAI

    func fetchUsage(apiKey: String) async throws -> UsageResult {
        guard !apiKey.isEmpty else { throw APIError.noAPIKey }

        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
            throw APIError.invalidURL
        }
        let startTime = Int(startOfMonth.timeIntervalSince1970)
        let endTime = Int(now.timeIntervalSince1970)
        guard let url = URL(string: "https://api.openai.com/v1/organization/costs?start_time=\(startTime)&end_time=\(endTime)&bucket_width=1d&limit=180") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            Logger.log("OpenAI Costs API: HTTP \(httpResponse.statusCode)")

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw APIError.httpErrorWithMessage(httpResponse.statusCode, "OpenAI Costs API 需要组织 Admin Key")
            }
            guard httpResponse.statusCode == 200 else { throw APIError.httpError(httpResponse.statusCode) }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let parsed = Self.parseCostsResponse(json)
            guard let cost = parsed.totalCost else {
                throw APIError.decodingError(NSError(domain: "OpenAI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Costs API 未返回金额字段"]))
            }

            let currency = parsed.currency?.uppercased() ?? "USD"
            Logger.log("OpenAI Costs API Success: cost=\(cost), currency=\(currency)")
            return UsageResult(
                remaining: cost,
                used: nil,
                total: nil,
                refreshTime: nil,
                subscriptionPlan: currency,
                balanceDetails: [CurrencyBalance(currency: currency, total: cost, granted: 0, toppedUp: cost)]
            )
        } catch let error as APIError {
            throw error
        } catch {
            Logger.log("OpenAI Costs API Error: \(error.localizedDescription)")
            throw APIError.networkError(error)
        }
    }

    static func parseCostsResponse(_ json: [String: Any]?) -> (totalCost: Double?, currency: String?) {
        guard let buckets = json?["data"] as? [[String: Any]] else { return (nil, nil) }
        var total = 0.0
        var hasAmount = false
        var currency: String?

        for bucket in buckets {
            guard let results = bucket["results"] as? [[String: Any]] else { continue }
            for result in results {
                guard let amount = result["amount"] as? [String: Any] else { continue }
                if let value = parseNumber(amount["value"]) {
                    total += value
                    hasAmount = true
                }
                if currency == nil, let parsedCurrency = amount["currency"] as? String {
                    currency = parsedCurrency
                }
            }
        }

        return (hasAmount ? total : nil, currency)
    }
}
// MARK: - KIMI Service

final class KIMIService: UsageService {
    let provider: APIProvider = .kimi

    func fetchUsage(apiKey: String) async throws -> UsageResult {
        guard !apiKey.isEmpty else { throw APIError.noAPIKey }

        var lastError: APIError?
        for endpoint in ["https://api.moonshot.ai/v1/users/me/balance", "https://api.moonshot.cn/v1/users/me/balance"] {
            try Task.checkCancellation()
            do {
                return try await fetchBalance(apiKey: apiKey, endpoint: endpoint)
            } catch let error as APIError {
                lastError = error
                if Self.isAuthenticationError(error) { throw error }
                Logger.log("KIMI official balance endpoint failed (\(endpoint)): \(error.localizedDescription)")
            } catch {
                lastError = APIError.networkError(error)
                Logger.log("KIMI official balance endpoint failed (\(endpoint)): \(error.localizedDescription)")
            }
        }

        throw lastError ?? APIError.networkError(
            NSError(domain: "KIMI", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取 KIMI 官方余额信息"])
        )
    }

    private func fetchBalance(apiKey: String, endpoint: String) async throws -> UsageResult {
        guard let url = URL(string: endpoint) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        Logger.log("KIMI Balance API \(endpoint): HTTP \(httpResponse.statusCode)")

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw APIError.httpErrorWithMessage(httpResponse.statusCode, "KIMI API Key 无效或无余额查询权限")
        }
        guard httpResponse.statusCode == 200 else { throw APIError.httpError(httpResponse.statusCode) }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObject = json["data"] as? [String: Any] else {
            throw APIError.decodingError(NSError(domain: "KIMI", code: -1, userInfo: [NSLocalizedDescriptionKey: "余额接口返回结构异常"]))
        }

        let available = parseNumber(dataObject["available_balance"]) ?? parseNumber(dataObject["balance"])
        let voucher = parseNumber(dataObject["voucher_balance"]) ?? 0
        let cash = parseNumber(dataObject["cash_balance"]) ?? 0
        guard let remaining = available else {
            throw APIError.decodingError(NSError(domain: "KIMI", code: -1, userInfo: [NSLocalizedDescriptionKey: "余额接口未返回 available_balance"] ))
        }

        return UsageResult(
            remaining: remaining,
            used: nil,
            total: nil,
            refreshTime: nil,
            balanceDetails: [CurrencyBalance(currency: "CNY", total: remaining, granted: voucher, toppedUp: cash)]
        )
    }

    private static func isAuthenticationError(_ error: APIError) -> Bool {
        switch error {
        case .httpError(let code), .httpErrorWithMessage(let code, _):
            return code == 401 || code == 403
        default:
            return false
        }
    }
}

// MARK: - Codex Service

final class CodexService: UsageService {
    let provider: APIProvider = .codex

    func fetchUsage(apiKey: String) async throws -> UsageResult {
        try Task.checkCancellation()
        return try await fetchLiveUsage()
    }

    private func fetchLiveUsage() async throws -> UsageResult {
        let accessToken = try readCodexAccessToken()
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("QuotaPulse/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            Logger.log("Codex usage API: HTTP \(httpResponse.statusCode)")

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw APIError.httpErrorWithMessage(httpResponse.statusCode, "Codex 登录已失效，请在终端重新运行 codex login")
            }
            guard httpResponse.statusCode == 200 else { throw APIError.httpError(httpResponse.statusCode) }

            return try Self.parseWhamUsageResponse(data)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    private func readCodexAccessToken() throws -> String {
        let authURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: authURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String,
              !accessToken.isEmpty else {
            throw APIError.httpErrorWithMessage(404, "未找到 Codex 登录凭证；请先在终端运行 codex login")
        }
        return accessToken
    }

    static func parseWhamUsageResponse(_ data: Data) throws -> UsageResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rateLimit = json["rate_limit"] as? [String: Any],
              let primaryWindow = rateLimit["primary_window"] as? [String: Any] else {
            throw APIError.decodingError(NSError(domain: "Codex", code: -1, userInfo: [NSLocalizedDescriptionKey: "Codex 用量接口返回结构异常"]))
        }

        let secondaryWindow = rateLimit["secondary_window"] as? [String: Any]
        guard let parsed = parseRateLimitWindows(
            primary: primaryWindow,
            secondary: secondaryWindow,
            planType: json["plan_type"] as? String
        ) else {
            throw APIError.decodingError(NSError(domain: "Codex", code: -1, userInfo: [NSLocalizedDescriptionKey: "Codex 用量接口未返回额度字段"]))
        }
        return parsed
    }

    static func parseResponses(_ output: String) throws -> UsageResult {
        var lastErrorMessage: String?

        for line in output.split(whereSeparator: \.isNewline).reversed() {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String {
                lastErrorMessage = message
                continue
            }

            if let rateLimits = findRateLimits(in: object),
               let parsed = parseSessionRateLimits(rateLimits) {
                return parsed
            }
        }

        if let lastErrorMessage {
            throw APIError.httpErrorWithMessage(502, lastErrorMessage)
        }

        throw APIError.httpErrorWithMessage(
            404,
            "未找到 Codex 本机用量记录；请先在终端运行 codex login，并至少完成一次 Codex 会话后再刷新。"
        )
    }

    private static func findRateLimits(in value: Any) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            if let direct = dictionary["rate_limits"] as? [String: Any] {
                return direct
            }
            if let direct = dictionary["rateLimits"] as? [String: Any] {
                return direct
            }
            for nested in dictionary.values {
                if let found = findRateLimits(in: nested) {
                    return found
                }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let found = findRateLimits(in: nested) {
                    return found
                }
            }
        }
        return nil
    }

    private static func parseSessionRateLimits(_ rateLimits: [String: Any]) -> UsageResult? {
        guard let primary = rateLimits["primary"] as? [String: Any] else { return nil }
        let secondary = rateLimits["secondary"] as? [String: Any]

        return parseRateLimitWindows(
            primary: primary,
            secondary: secondary,
            planType: (rateLimits["plan_type"] as? String) ?? (rateLimits["planType"] as? String)
        )
    }

    private static func parseRateLimitWindows(
        primary: [String: Any],
        secondary: [String: Any]?,
        planType: String?
    ) -> UsageResult? {
        let primaryWindow = parseCodexWindow(primary)
        let secondaryWindow = secondary.map(parseCodexWindow)
        var fiveHourWindow: CodexQuotaWindow?
        var weeklyWindow: CodexQuotaWindow?

        assignCodexWindow(primaryWindow, fallbackKind: .fiveHour, fiveHour: &fiveHourWindow, weekly: &weeklyWindow)
        if let secondaryWindow {
            assignCodexWindow(secondaryWindow, fallbackKind: .weekly, fiveHour: &fiveHourWindow, weekly: &weeklyWindow)
        }

        guard fiveHourWindow?.hasData == true || weeklyWindow?.hasData == true else {
            return nil
        }

        return UsageResult(
            remaining: fiveHourWindow?.used.map { max(0, 100 - $0) },
            used: fiveHourWindow?.used,
            total: fiveHourWindow?.used == nil ? nil : 100,
            refreshTime: fiveHourWindow?.reset,
            monthlyRemaining: weeklyWindow?.used.map { max(0, 100 - $0) },
            monthlyTotal: weeklyWindow?.used == nil ? nil : 100,
            monthlyUsed: weeklyWindow?.used,
            monthlyRefreshTime: weeklyWindow?.reset,
            subscriptionPlan: planType,
            primaryCycleIsPercentage: fiveHourWindow?.used == nil ? nil : true,
            secondaryCycleIsPercentage: weeklyWindow?.used == nil ? nil : true
        )
    }

    private enum CodexQuotaWindowKind {
        case fiveHour
        case weekly
    }

    private struct CodexQuotaWindow {
        let used: Double?
        let reset: Date?
        let durationMinutes: Double?

        var hasData: Bool {
            used != nil || reset != nil
        }
    }

    private static func parseCodexWindow(_ window: [String: Any]) -> CodexQuotaWindow {
        let durationMinutes = parseCodexWindowDurationMinutes(window)
        return CodexQuotaWindow(
            used: parseNumber(window["used_percent"] ?? window["usedPercent"]),
            reset: parseResetDate(
                window["reset_at"] ?? window["resets_at"] ?? window["resetsAt"],
                resetAfter: window["reset_after_seconds"] ?? window["resetAfterSeconds"]
            ),
            durationMinutes: durationMinutes
        )
    }

    private static func parseCodexWindowDurationMinutes(_ window: [String: Any]) -> Double? {
        if let minutes = parseNumber(
            window["window_minutes"] ??
            window["windowDurationMins"] ??
            window["window_duration_mins"] ??
            window["windowDurationMinutes"] ??
            window["window_duration_minutes"]
        ) {
            return minutes
        }
        if let seconds = parseNumber(
            window["limit_window_seconds"] ??
            window["window_seconds"] ??
            window["windowDurationSeconds"] ??
            window["window_duration_seconds"]
        ) {
            return seconds / 60
        }
        return nil
    }

    private static func assignCodexWindow(
        _ window: CodexQuotaWindow,
        fallbackKind: CodexQuotaWindowKind,
        fiveHour: inout CodexQuotaWindow?,
        weekly: inout CodexQuotaWindow?
    ) {
        guard window.hasData else { return }
        switch codexWindowKind(for: window, fallback: fallbackKind) {
        case .fiveHour:
            if fiveHour == nil {
                fiveHour = window
            }
        case .weekly:
            if weekly == nil {
                weekly = window
            }
        case nil:
            break
        }
    }

    private static func codexWindowKind(
        for window: CodexQuotaWindow,
        fallback: CodexQuotaWindowKind
    ) -> CodexQuotaWindowKind? {
        guard let durationMinutes = window.durationMinutes else {
            return fallback
        }
        if abs(durationMinutes - 300) <= 5 {
            return .fiveHour
        }
        if abs(durationMinutes - 10_080) <= 60 {
            return .weekly
        }
        return nil
    }

    private static func parseResetDate(_ value: Any?, resetAfter: Any? = nil) -> Date? {
        if let timestamp = parseNumber(value), timestamp > 0 {
            return Date(timeIntervalSince1970: timestamp)
        }
        if let seconds = parseNumber(resetAfter), seconds > 0 {
            return Date().addingTimeInterval(seconds)
        }
        return nil
    }
}

struct UnsupportedUsageService: UsageService {
    let provider: APIProvider

    func fetchUsage(apiKey: String) async throws -> UsageResult {
        throw APIError.httpErrorWithMessage(410, "该监控方案已删除：没有稳定的官方 API 接口支撑")
    }
}

func getService(for provider: APIProvider) -> UsageService {
    switch provider {
    case .miniMax:
        return MiniMaxService()
    case .tavily:
        return TavilyService()
    case .openAI:
        return OpenAIService()
    case .kimi:
        return KIMIService()
    case .deepSeek:
        return DeepSeekService()
    case .codex:
        return CodexService()
    case .glm, .chatGPT:
        return UnsupportedUsageService(provider: provider)
    }
}
