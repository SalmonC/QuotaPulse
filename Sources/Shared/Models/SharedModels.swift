import Foundation
import AppKit

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }
}

enum APIProvider: String, Codable, CaseIterable, Identifiable {
    case miniMax = "miniMax"
    case glm = "glm"
    case tavily = "tavily"
    case openAI = "openAI"
    case chatGPT = "chatGPT"
    case kimi = "kimi"
    case deepSeek = "deepSeek"
    case codex = "codex"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .miniMax:
            return "MiniMax"
        case .glm:
            return "GLM (智谱AI)"
        case .tavily:
            return "Tavily"
        case .openAI:
            return "OpenAI API (Token)"
        case .chatGPT:
            return "ChatGPT (Subscription)"
        case .kimi:
            return "KIMI (Moonshot)"
        case .deepSeek:
            return "DeepSeek"
        case .codex:
            return "Codex (ChatGPT)"
        }
    }
    
    var icon: String {
        switch self {
        case .miniMax:
            return "brain"
        case .glm:
            return "cpu"
        case .tavily:
            return "magnifyingglass"
        case .openAI:
            return "sparkles"
        case .chatGPT:
            return "message.badge"
        case .kimi:
            return "moon.stars"
        case .deepSeek:
            return "drop.triangle"
        case .codex:
            return "terminal"
        }
    }

    var supportsRemainingQuotaQuery: Bool {
        Self.supportedMonitoringProviders.contains(self)
    }

    func remainingQuotaQueryUnsupportedReason(language: AppLanguage) -> String? {
        switch self {
        case .glm, .chatGPT:
            return language == .english
                ? "This monitoring method has been removed because it is not backed by a stable official API endpoint."
                : "该监控方案已删除，因为没有稳定的官方 API 接口支撑。"
        default:
            return nil
        }
    }

    func capabilityDescription(language: AppLanguage) -> String? {
        switch self {
        case .tavily:
            return language == .english
                ? "Remaining quota is available, but official API usually does not provide a stable reset timestamp."
                : "可查询额度余量；官方接口通常不返回稳定的周期重置时间。"
        case .kimi:
            return language == .english
                ? "Uses Moonshot's official balance endpoint and displays available balance."
                : "使用 Moonshot 官方余额接口，展示可用余额。"
        case .deepSeek:
            return language == .english
                ? "Shows every currency returned by DeepSeek, including topped-up and granted balances. Consumption is estimated from balance changes."
                : "展示 DeepSeek 实际返回的全部币种及充值/赠送余额；消耗量根据余额变化估算。"
        case .openAI:
            return language == .english
                ? "Uses the official organization Costs API; an OpenAI Admin Key is required."
                : "使用官方组织 Costs API；需要 OpenAI Admin Key。"
        case .codex:
            return language == .english
                ? "Reads your local Codex login and displays the 5-hour and weekly quota windows."
                : "读取本机 Codex 登录状态，显示 5 小时与每周额度周期。"
        default:
            return nil
        }
    }

    func restrictionHint(language: AppLanguage) -> String? {
        guard !supportsRemainingQuotaQuery else { return nil }
        return language == .english ? "Hidden from Add Provider list" : "新增列表中隐藏"
    }

    static var selectableForNewAccounts: [APIProvider] {
        supportedMonitoringProviders
    }

    var requiresCredential: Bool { self != .codex }

    static var supportedMonitoringProviders: [APIProvider] {
        [.miniMax, .tavily, .openAI, .kimi, .deepSeek, .codex]
    }

    static var unsupportedForRemainingQuotaQuery: [APIProvider] {
        allCases.filter { !$0.supportsRemainingQuotaQuery }
    }

    static var providersWithCapabilityDescription: [APIProvider] {
        supportedMonitoringProviders.filter { $0.capabilityDescription(language: .chinese) != nil }
    }
}

enum DashboardSortMode: String, Codable, CaseIterable, Identifiable {
    case manual
    case provider
    case name
    
    var id: String { rawValue }
    
    func displayName(language: AppLanguage) -> String {
        switch self {
        case .manual:
            return language == .english ? "Manual" : "手动排序"
        case .provider:
            return language == .english ? "By Provider" : "按平台"
        case .name:
            return language == .english ? "By Name" : "按名称"
        }
    }
}

enum TrendWindow: String, Codable, CaseIterable, Identifiable {
    case day
    case threeDays
    case week
    case twoWeeks
    case month

    var id: String { rawValue }

    static var dashboardSelectable: [TrendWindow] {
        [.threeDays, .week, .twoWeeks, .month]
    }

    var days: Int {
        switch self {
        case .day:
            return 1
        case .threeDays:
            return 3
        case .week:
            return 7
        case .twoWeeks:
            return 14
        case .month:
            return 30
        }
    }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .day:
            return language == .english ? "24h" : "24小时"
        case .threeDays:
            return language == .english ? "3d" : "3天"
        case .week:
            return language == .english ? "7d" : "7天"
        case .twoWeeks:
            return language == .english ? "14d" : "14天"
        case .month:
            return language == .english ? "30d" : "30天"
        }
    }
}

struct APIAccount: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var provider: APIProvider = .miniMax
    var apiKey: String = ""
    var isEnabled: Bool = true
    
}

struct HotkeySetting: Codable, Equatable {
    var keyCode: UInt16 = 0
    var modifiers: UInt32 = 0
    
    static let defaultHotkey = HotkeySetting(keyCode: 32, modifiers: UInt32(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue))
    
    static func validate(keyCode: UInt16, modifiers: UInt32, language: AppLanguage = .chinese) -> String? {
        let hasCommand = (modifiers & UInt32(NSEvent.ModifierFlags.command.rawValue)) != 0
        let hasShift = (modifiers & UInt32(NSEvent.ModifierFlags.shift.rawValue)) != 0
        let hasOption = (modifiers & UInt32(NSEvent.ModifierFlags.option.rawValue)) != 0
        let hasControl = (modifiers & UInt32(NSEvent.ModifierFlags.control.rawValue)) != 0
        
        if !hasCommand && !hasShift && !hasOption && !hasControl {
            return language == .english
                ? "Must include at least one modifier key (⌘⇧⌥⌃)"
                : "至少需要包含一个修饰键（⌘⇧⌥⌃）"
        }
        
        let invalidKeyCodes: [UInt16] = [48, 49, 51, 53, 36, 76]
        if invalidKeyCodes.contains(keyCode) {
            return language == .english
                ? "This key cannot be used as a hotkey (Tab, Caps Lock, Delete, Escape, Return, Enter)"
                : "该按键不能作为快捷键（Tab、Caps Lock、Delete、Escape、Return、Enter）"
        }
        
        return nil
    }
    
    var displayString: String {
        var parts: [String] = []
        
        if modifiers & UInt32(NSEvent.ModifierFlags.control.rawValue) != 0 {
            parts.append("⌃")
        }
        if modifiers & UInt32(NSEvent.ModifierFlags.option.rawValue) != 0 {
            parts.append("⌥")
        }
        if modifiers & UInt32(NSEvent.ModifierFlags.shift.rawValue) != 0 {
            parts.append("⇧")
        }
        if modifiers & UInt32(NSEvent.ModifierFlags.command.rawValue) != 0 {
            parts.append("⌘")
        }
        
        let keyName = keyCodeToString(keyCode)
        parts.append(keyName)
        
        return parts.joined()
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        let keyMap: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space",
            51: "⌫", 53: "⎋", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
            100: "F8", 101: "F9", 103: "F11", 105: "F13", 107: "F14",
            109: "F10", 111: "F12", 113: "F15", 118: "F4", 119: "F2",
            120: "F1", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return keyMap[keyCode] ?? "?"
    }
}

struct ThresholdAlertSettings: Codable, Equatable {
    var isEnabled: Bool = true
    var warningPercentage: Int = 80
    var criticalPercentage: Int = 90
    var cooldownMinutes: Int = 120

    static let `default` = ThresholdAlertSettings()

    var normalized: ThresholdAlertSettings {
        var next = self
        next.warningPercentage = min(max(next.warningPercentage, 5), 100)
        next.criticalPercentage = next.warningPercentage
        next.cooldownMinutes = min(max(next.cooldownMinutes, 5), 1_440)
        return next
    }
}

struct DeepSeekBalanceSettings: Codable, Equatable {
    var threshold: Double = 1

    static let `default` = DeepSeekBalanceSettings()

    var normalized: DeepSeekBalanceSettings {
        var next = self
        if !next.threshold.isFinite {
            next.threshold = 1
        }
        next.threshold = max(0, next.threshold)
        return next
    }
}

struct CodexEquivalentValueSettings: Codable, Equatable {
    var isEnabled: Bool = true
    var window: TrendWindow = .week

    static let `default` = CodexEquivalentValueSettings()

    var normalized: CodexEquivalentValueSettings {
        var next = self
        if !TrendWindow.dashboardSelectable.contains(next.window) {
            next.window = .week
        }
        return next
    }
}

enum MenuBarPinnedMetric: String, Codable, CaseIterable, Identifiable {
    case deepSeekBalance
    case codexFiveHourRemaining
    case codexWeeklyRemaining

    var id: String { rawValue }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .deepSeekBalance:
            return language == .english ? "DeepSeek balance" : "DeepSeek 余额"
        case .codexFiveHourRemaining:
            return language == .english ? "Codex 5h remaining" : "Codex 5小时余量"
        case .codexWeeklyRemaining:
            return language == .english ? "Codex weekly remaining" : "Codex 周余量"
        }
    }

    func defaultPrefix(language: AppLanguage) -> String {
        switch self {
        case .deepSeekBalance:
            return language == .english ? "DS " : "DS "
        case .codexFiveHourRemaining:
            return "5h "
        case .codexWeeklyRemaining:
            return language == .english ? "1w " : "1周 "
        }
    }
}

struct MenuBarPinnedItem: Codable, Equatable, Identifiable {
    var metric: MenuBarPinnedMetric
    var prefix: String
    var isEnabled: Bool

    var id: MenuBarPinnedMetric { metric }

    init(metric: MenuBarPinnedMetric, prefix: String? = nil, isEnabled: Bool = false, language: AppLanguage = .chinese) {
        self.metric = metric
        self.prefix = prefix ?? metric.defaultPrefix(language: language)
        self.isEnabled = isEnabled
    }

    static func defaults(language: AppLanguage = .chinese) -> [MenuBarPinnedItem] {
        MenuBarPinnedMetric.allCases.map { MenuBarPinnedItem(metric: $0, language: language) }
    }

    static func normalized(_ items: [MenuBarPinnedItem], language: AppLanguage) -> [MenuBarPinnedItem] {
        var byMetric = Dictionary(uniqueKeysWithValues: items.map { ($0.metric, $0) })
        return MenuBarPinnedMetric.allCases.map { metric in
            var item = byMetric.removeValue(forKey: metric) ?? MenuBarPinnedItem(metric: metric, language: language)
            item.prefix = String(item.prefix.prefix(12))
            return item
        }
    }
}

struct AppSettings: Codable {
    var accounts: [APIAccount] = []
    var refreshInterval: Int = 5
    var hotkey: HotkeySetting = HotkeySetting(keyCode: 32, modifiers: UInt32(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue))
    var language: AppLanguage = .chinese
    var alertSettings: ThresholdAlertSettings = .default
    var deepSeekBalanceSettings: DeepSeekBalanceSettings = .default
    var codexEquivalentValueSettings: CodexEquivalentValueSettings = .default
    var showTrendInDashboard: Bool = true
    var dashboardTrendWindow: TrendWindow = .week
    var launchAtLogin: Bool = false
    var menuBarPinnedItems: [MenuBarPinnedItem] = MenuBarPinnedItem.defaults()

    init(
        accounts: [APIAccount] = [],
        refreshInterval: Int = 5,
        hotkey: HotkeySetting = HotkeySetting(keyCode: 32, modifiers: UInt32(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)),
        language: AppLanguage = .chinese,
        alertSettings: ThresholdAlertSettings = .default,
        deepSeekBalanceSettings: DeepSeekBalanceSettings = .default,
        codexEquivalentValueSettings: CodexEquivalentValueSettings = .default,
        showTrendInDashboard: Bool = true,
        dashboardTrendWindow: TrendWindow = .week,
        launchAtLogin: Bool = false,
        menuBarPinnedItems: [MenuBarPinnedItem]? = nil
    ) {
        self.accounts = accounts.filter { $0.provider.supportsRemainingQuotaQuery }
        self.refreshInterval = refreshInterval
        self.hotkey = hotkey
        self.language = language
        self.alertSettings = alertSettings.normalized
        self.deepSeekBalanceSettings = deepSeekBalanceSettings.normalized
        self.codexEquivalentValueSettings = codexEquivalentValueSettings.normalized
        self.showTrendInDashboard = showTrendInDashboard
        self.dashboardTrendWindow = TrendWindow.dashboardSelectable.contains(dashboardTrendWindow) ? dashboardTrendWindow : .week
        self.launchAtLogin = launchAtLogin
        self.menuBarPinnedItems = MenuBarPinnedItem.normalized(menuBarPinnedItems ?? MenuBarPinnedItem.defaults(language: language), language: language)
    }

    enum CodingKeys: String, CodingKey {
        case accounts
        case refreshInterval
        case hotkey
        case language
        case alertSettings
        case deepSeekBalanceSettings
        case codexEquivalentValueSettings
        case showTrendInDashboard
        case dashboardTrendWindow
        case launchAtLogin
        case menuBarPinnedItems
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accounts = (try container.decodeIfPresent([APIAccount].self, forKey: .accounts) ?? [])
            .filter { $0.provider.supportsRemainingQuotaQuery }
        refreshInterval = try container.decodeIfPresent(Int.self, forKey: .refreshInterval) ?? 5
        hotkey = try container.decodeIfPresent(HotkeySetting.self, forKey: .hotkey) ?? HotkeySetting(
            keyCode: 32,
            modifiers: UInt32(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)
        )
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .chinese
        alertSettings = (try container.decodeIfPresent(ThresholdAlertSettings.self, forKey: .alertSettings) ?? .default).normalized
        deepSeekBalanceSettings = (try container.decodeIfPresent(DeepSeekBalanceSettings.self, forKey: .deepSeekBalanceSettings) ?? .default).normalized
        codexEquivalentValueSettings = (try container.decodeIfPresent(CodexEquivalentValueSettings.self, forKey: .codexEquivalentValueSettings) ?? .default).normalized
        showTrendInDashboard = try container.decodeIfPresent(Bool.self, forKey: .showTrendInDashboard) ?? true
        let decodedTrendWindow = try container.decodeIfPresent(TrendWindow.self, forKey: .dashboardTrendWindow) ?? .week
        dashboardTrendWindow = TrendWindow.dashboardSelectable.contains(decodedTrendWindow) ? decodedTrendWindow : .week
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        let decodedMenuBarPinnedItems = try container.decodeIfPresent([MenuBarPinnedItem].self, forKey: .menuBarPinnedItems)
        menuBarPinnedItems = MenuBarPinnedItem.normalized(decodedMenuBarPinnedItems ?? MenuBarPinnedItem.defaults(language: language), language: language)
    }
    
    static let `default` = AppSettings()
}

struct CycleLearningState: Codable, Equatable {
    var observedResets: [Date] = []
    var learnedInterval: TimeInterval? = nil
    var confidence: Double = 0
    var lastObservedAt: Date? = nil
}

struct CurrencyBalance: Codable, Equatable, Identifiable {
    var currency: String
    var total: Double
    var granted: Double
    var toppedUp: Double
    var estimatedConsumption: Double? = nil

    var id: String { currency }
}

struct UsageData: Codable, Equatable {
    var accountId: UUID
    var accountName: String
    var provider: APIProvider
    var tokenRemaining: Double?
    var tokenUsed: Double?
    var tokenTotal: Double?
    var refreshTime: Date?
    var lastUpdated: Date
    var errorMessage: String?
    
    // Additional fields for monthly/limit data
    var monthlyRemaining: Double?      // Monthly remaining quota
    var monthlyTotal: Double?          // Monthly total quota
    var monthlyUsed: Double?           // Monthly used amount
    var monthlyRefreshTime: Date?      // Monthly quota refresh time
    var nextRefreshTime: Date?         // Next refresh time (for limited periods)
    var subscriptionPlan: String? = nil
    var primaryCycleIsPercentage: Bool? = nil
    var secondaryCycleIsPercentage: Bool? = nil
    var primaryRefreshIsEstimated: Bool = false
    var secondaryRefreshIsEstimated: Bool = false
    var balanceDetails: [CurrencyBalance]? = nil

    var currencyBalances: [CurrencyBalance] { balanceDetails ?? [] }
    var displayCurrencyBalances: [CurrencyBalance] {
        if let balanceDetails, !balanceDetails.isEmpty {
            return balanceDetails
        }
        if provider == .deepSeek, let tokenRemaining {
            return [
                CurrencyBalance(
                    currency: "CNY",
                    total: tokenRemaining,
                    granted: 0,
                    toppedUp: tokenRemaining
                )
            ]
        }
        return []
    }
    
    var displayRemaining: String {
        guard let remaining = tokenRemaining else { return "--" }
        if remaining >= 1000 {
            return String(format: "%.1fK", remaining / 1000)
        }
        return String(format: "%.0f", remaining)
    }
    
    var displayUsed: String {
        guard let used = tokenUsed else { return "--" }
        if used >= 1000 {
            return String(format: "%.1fK", used / 1000)
        }
        return String(format: "%.0f", used)
    }
    
    var displayTotal: String {
        guard let total = tokenTotal else { return "--" }
        if total >= 1000 {
            return String(format: "%.1fK", total / 1000)
        }
        return String(format: "%.0f", total)
    }
    
    var displayMonthlyRemaining: String {
        guard let remaining = monthlyRemaining else { return "--" }
        if remaining >= 1000 {
            return String(format: "%.1fK", remaining / 1000)
        }
        return String(format: "%.0f", remaining)
    }
    
    var displayMonthlyTotal: String {
        guard let total = monthlyTotal else { return "--" }
        if total >= 1000 {
            return String(format: "%.1fK", total / 1000)
        }
        return String(format: "%.0f", total)
    }
    
    var displayMonthlyUsed: String {
        guard let used = monthlyUsed else { return "--" }
        if used >= 1000 {
            return String(format: "%.1fK", used / 1000)
        }
        return String(format: "%.0f", used)
    }
    
    var usagePercentage: Double {
        guard let used = tokenUsed, let total = tokenTotal, total > 0 else { return 0 }
        return min(used / total * 100, 100)
    }
    
    var monthlyUsagePercentage: Double {
        guard let used = monthlyUsed, let total = monthlyTotal, total > 0 else { return 0 }
        return min(used / total * 100, 100)
    }
    
    var displaySubscriptionPlan: String? {
        guard let subscriptionPlan, !subscriptionPlan.isEmpty else { return nil }
        let normalized = subscriptionPlan
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch normalized {
        case "plus":
            return "Plus"
        case "chatgptplusplan":
            return "Plus"
        case "chatgpt_plus_plan":
            return "Plus"
        case "pro":
            return "Pro"
        case "chatgptproplan":
            return "Pro"
        case "chatgpt_pro_plan":
            return "Pro"
        case "free":
            return "Free"
        case "chatgptfreeplan":
            return "Free"
        case "chatgpt_free_plan":
            return "Free"
        case "team":
            return "Team"
        case "business":
            return "Business"
        case "enterprise":
            return "Enterprise"
        case "active":
            return "Subscribed"
        default:
            return subscriptionPlan
        }
    }
}

struct UsageSnapshot: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var accountId: UUID
    var provider: APIProvider
    var capturedAt: Date
    var tokenUsed: Double?
    var tokenTotal: Double?
    var monthlyUsed: Double?
    var monthlyTotal: Double?
    var usagePercentage: Double?
    var monthlyUsagePercentage: Double?
    var balanceTotal: Double? = nil
    var balanceCurrency: String? = nil
}

enum SettingsPersistenceError: LocalizedError {
    case defaultsUnavailable
    case encodeFailed(Error)
    case keychainFailed(Error)
    case defaultsVerificationFailed

    var errorDescription: String? {
        switch self {
        case .defaultsUnavailable:
            return "无法访问应用设置存储。"
        case .encodeFailed:
            return "设置数据编码失败。"
        case .keychainFailed(let error):
            return "API Key 未能安全保存：\(error.localizedDescription)"
        case .defaultsVerificationFailed:
            return "设置写入后校验失败，API Key 已尝试恢复到修改前状态。"
        }
    }
}

final class Storage {
    static let shared = Storage()
    
    private let suiteName = "group.com.mactools.apiusagetracker"
    private let usageKey = "usageData"
    private let usageSnapshotsKey = "usageSnapshots"
    private let settingsKey = "appSettings"
    private let refreshIntervalKey = "widgetRefreshInterval"
    private let dashboardSortModeKey = "dashboardSortMode"
    private let dashboardManualOrderKey = "dashboardManualOrder"
    private let cycleLearningKey = "cycleLearningState"
    private let alertNotificationStateKey = "alertNotificationState"
    private var emittedCriticalLogKeys: Set<String> = []
    
    private var userDefaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }
    
    private init() {}

    private func logCriticalOnce(_ key: String, _ message: String) {
        guard !emittedCriticalLogKeys.contains(key) else { return }
        emittedCriticalLogKeys.insert(key)
        Logger.critical(message)
    }
    
    func saveUsageData(_ data: [UsageData]) {
        guard let defaults = userDefaults else {
            logCriticalOnce("saveUsageData.defaultsUnavailable", "App Group UserDefaults unavailable while saving usage data")
            return
        }
        do {
            let encoded = try JSONEncoder().encode(data)
            defaults.set(encoded, forKey: usageKey)
        } catch {
            logCriticalOnce("saveUsageData.encodeFailed", "Failed to encode usage data: count=\(data.count), error=\(error.localizedDescription)")
        }
    }
    
    func loadUsageData() -> [UsageData] {
        guard let defaults = userDefaults else {
            logCriticalOnce("loadUsageData.defaultsUnavailable", "App Group UserDefaults unavailable while loading usage data")
            return []
        }
        guard let data = defaults.data(forKey: usageKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([UsageData].self, from: data)
        } catch {
            logCriticalOnce("loadUsageData.decodeFailed", "Failed to decode usage data: bytes=\(data.count), error=\(error.localizedDescription)")
            return []
        }
    }

    func saveUsageSnapshots(_ snapshots: [UsageSnapshot]) {
        guard let defaults = userDefaults else {
            logCriticalOnce("saveUsageSnapshots.defaultsUnavailable", "App Group UserDefaults unavailable while saving usage snapshots")
            return
        }
        do {
            let encoded = try JSONEncoder().encode(snapshots)
            defaults.set(encoded, forKey: usageSnapshotsKey)
        } catch {
            logCriticalOnce("saveUsageSnapshots.encodeFailed", "Failed to encode usage snapshots: count=\(snapshots.count), error=\(error.localizedDescription)")
        }
    }

    func loadUsageSnapshots() -> [UsageSnapshot] {
        guard let defaults = userDefaults else {
            logCriticalOnce("loadUsageSnapshots.defaultsUnavailable", "App Group UserDefaults unavailable while loading usage snapshots")
            return []
        }
        guard let data = defaults.data(forKey: usageSnapshotsKey) else {
            return []
        }
        do {
            let decoded = try JSONDecoder().decode([UsageSnapshot].self, from: data)
            return decoded.sorted { $0.capturedAt < $1.capturedAt }
        } catch {
            logCriticalOnce("loadUsageSnapshots.decodeFailed", "Failed to decode usage snapshots: bytes=\(data.count), error=\(error.localizedDescription)")
            return []
        }
    }

    func saveCycleLearningState(_ state: [String: CycleLearningState]) {
        guard let defaults = userDefaults else { return }
        if let encoded = try? JSONEncoder().encode(state) {
            defaults.set(encoded, forKey: cycleLearningKey)
        }
    }

    func loadCycleLearningState() -> [String: CycleLearningState] {
        guard let defaults = userDefaults,
              let data = defaults.data(forKey: cycleLearningKey),
              let decoded = try? JSONDecoder().decode([String: CycleLearningState].self, from: data) else {
            return [:]
        }
        return decoded
    }
    
    func saveSettings(_ settings: AppSettings) throws {
        guard let defaults = userDefaults else {
            logCriticalOnce("saveSettings.defaultsUnavailable", "App Group UserDefaults unavailable while saving settings")
            throw SettingsPersistenceError.defaultsUnavailable
        }

        // Encode first so an encoding error cannot leave Keychain ahead of settings.
        var settingsWithoutKeys = settings
        for i in settingsWithoutKeys.accounts.indices {
            settingsWithoutKeys.accounts[i].apiKey = ""
        }

        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(settingsWithoutKeys)
        } catch {
            logCriticalOnce("saveSettings.encodeFailed", "Failed to encode app settings: accounts=\(settings.accounts.count)")
            throw SettingsPersistenceError.encodeFailed(error)
        }

        let targetKeys = Dictionary(uniqueKeysWithValues: settings.accounts.compactMap { account in
            account.apiKey.isEmpty ? nil : (account.id, account.apiKey)
        })
        let previousKeys: [UUID: String]
        do {
            previousKeys = try KeychainManager.shared.replaceAPIKeys(targetKeys)
        } catch {
            Logger.critical("Failed to atomically save API keyring: \(error)")
            throw SettingsPersistenceError.keychainFailed(error)
        }

        let previousSettingsData = defaults.data(forKey: settingsKey)
        defaults.set(encoded, forKey: settingsKey)
        guard defaults.data(forKey: settingsKey) == encoded else {
            if let previousSettingsData {
                defaults.set(previousSettingsData, forKey: settingsKey)
            } else {
                defaults.removeObject(forKey: settingsKey)
            }
            do {
                try KeychainManager.shared.replaceAPIKeys(previousKeys)
            } catch {
                Logger.critical("Settings verification and Keychain rollback both failed: \(error)")
            }
            Logger.critical("Settings write verification failed after Keychain commit")
            throw SettingsPersistenceError.defaultsVerificationFailed
        }
    }
    
    func loadSettings(includeAPIKeys: Bool = true) -> AppSettings {
        guard let defaults = userDefaults else {
            logCriticalOnce("loadSettings.defaultsUnavailable", "App Group UserDefaults unavailable while loading settings")
            return .default
        }
        guard let data = defaults.data(forKey: settingsKey) else {
            return .default
        }
        let decodedSettings: AppSettings
        do {
            decodedSettings = try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            logCriticalOnce("loadSettings.decodeFailed", "Failed to decode app settings: bytes=\(data.count), error=\(error.localizedDescription)")
            return .default
        }
        var decoded = decodedSettings
        
        guard includeAPIKeys else { return decoded }
        
        let keyMap = KeychainManager.shared.loadAPIKeys(for: decoded.accounts.map(\.id))
        let credentialAccountCount = decoded.accounts.filter { $0.provider.requiresCredential }.count
        if credentialAccountCount > 0 && keyMap.isEmpty {
            let statusText = KeychainManager.shared.lastKeyringLoadStatus.map(String.init) ?? "nil"
            logCriticalOnce(
                "loadSettings.emptyKeyMap",
                "No API keys loaded from Keychain for configured credential accounts: accounts=\(credentialAccountCount), keyringStatus=\(statusText)"
            )
        }
        for i in decoded.accounts.indices {
            if let keychainKey = keyMap[decoded.accounts[i].id] {
                decoded.accounts[i].apiKey = keychainKey
            }
        }
        
        return decoded
    }
    
    // Save refresh interval separately for widget access
    func saveRefreshInterval(_ minutes: Int) {
        userDefaults?.set(minutes, forKey: refreshIntervalKey)
    }
    
    func loadRefreshInterval() -> Int {
        let interval = userDefaults?.integer(forKey: refreshIntervalKey) ?? 5
        return interval > 0 ? interval : 5
    }
    
    func saveDashboardSortMode(_ mode: DashboardSortMode) {
        userDefaults?.set(mode.rawValue, forKey: dashboardSortModeKey)
    }
    
    func loadDashboardSortMode() -> DashboardSortMode {
        guard
            let rawValue = userDefaults?.string(forKey: dashboardSortModeKey),
            let mode = DashboardSortMode(rawValue: rawValue)
        else {
            return .manual
        }
        return mode
    }
    
    func saveDashboardManualOrder(_ ids: [UUID]) {
        let rawIDs = ids.map(\.uuidString)
        userDefaults?.set(rawIDs, forKey: dashboardManualOrderKey)
    }
    
    func loadDashboardManualOrder() -> [UUID] {
        guard let rawIDs = userDefaults?.stringArray(forKey: dashboardManualOrderKey) else {
            return []
        }
        return rawIDs.compactMap(UUID.init(uuidString:))
    }

    func saveAlertNotificationState(_ state: [String: Date]) {
        guard let defaults = userDefaults else { return }
        if let encoded = try? JSONEncoder().encode(state) {
            defaults.set(encoded, forKey: alertNotificationStateKey)
        }
    }

    func loadAlertNotificationState() -> [String: Date] {
        guard let defaults = userDefaults,
              let data = defaults.data(forKey: alertNotificationStateKey),
              let decoded = try? JSONDecoder().decode([String: Date].self, from: data) else {
            return [:]
        }
        return decoded
    }
}
