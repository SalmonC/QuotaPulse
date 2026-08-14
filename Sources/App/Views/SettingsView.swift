import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var updateService: UpdateService
    @State private var accounts: [APIAccount] = []
    @State private var autoNamedAccountIDs: Set<UUID> = []
    @State private var expandedStates: [UUID: Bool] = [:]
    @State private var refreshInterval: Int = 5
    @State private var hotkey: HotkeySetting = HotkeySetting(keyCode: 32, modifiers: UInt32(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue))
    @State private var isRecordingHotkey: Bool = false
    @State private var hotkeyBeforeRecording: HotkeySetting?
    @State private var hotkeyError: String?
    @State private var saveButtonState: SaveButtonState = .normal
    @State private var saveErrorMessage: String?
    @State private var savedDraftSignature: String = ""
    @State private var pendingDeleteAccount: APIAccount?
    @State private var isCapabilityNoticeExpanded: Bool = false
    @State private var language: AppLanguage = .chinese
    @State private var alertsEnabled: Bool = true
    @State private var warningThreshold: Int = 80
    @State private var criticalThreshold: Int = 90
    @State private var alertCooldownMinutes: Int = 120
    @State private var deepSeekBalanceThreshold: Double = 1
    @State private var showTrendInDashboard: Bool = true
    @State private var showCodexEquivalentValue: Bool = true
    @State private var codexEquivalentValueWindow: TrendWindow = .week
    @State private var dashboardSortMode: DashboardSortMode = .manual
    @State private var dashboardTrendWindow: TrendWindow = .week
    @State private var launchAtLogin: Bool = false
    @State private var menuBarPinnedItems: [MenuBarPinnedItem] = MenuBarPinnedItem.defaults()
    @State private var editingAccountID: UUID?
    @State private var nameDraftByAccountID: [UUID: String] = [:]
    @State private var nameAtEditStartByAccountID: [UUID: String] = [:]
    @State private var defocusObserverTokens: [NSObjectProtocol] = []
    @State private var localClickMonitor: Any?
    @State private var selectedSettingsTab: SettingsTab = .general
    
    enum SaveButtonState {
        case normal
        case saved
    }

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case general
        case accounts

        var id: String { rawValue }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            settingsTabBar

            Group {
                switch selectedSettingsTab {
                case .general:
                    generalSettingsView
                case .accounts:
                    accountsSettingsView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadSettings()
            installDefocusObserversIfNeeded()
            installLocalClickMonitorIfNeeded()
        }
        .onDisappear {
            removeDefocusObservers()
            removeLocalClickMonitor()
        }
        .alert(language == .english ? "Delete Account?" : "删除账号？", isPresented: pendingDeleteBinding) {
            Button(language == .english ? "Delete" : "删除", role: .destructive) {
                if let account = pendingDeleteAccount {
                    deleteAccount(account)
                }
                pendingDeleteAccount = nil
            }
            Button(language == .english ? "Cancel" : "取消", role: .cancel) {
                pendingDeleteAccount = nil
            }
        } message: {
            Text(language == .english
                 ? "This removes account config and deletes stored API key from Keychain."
                 : "将删除该账号配置，并移除钥匙串中已保存的 API Key。")
        }
        .alert(
            language == .english ? "Save Failed" : "保存失败",
            isPresented: saveErrorBinding
        ) {
            Button(language == .english ? "OK" : "确定", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    private var settingsTabBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    QuotaPulseMark(size: 18, ringColor: .primary)
                    Text("QuotaPulse")
                        .font(.headline)
                        .lineLimit(1)
                }
                .frame(width: 132, alignment: .leading)

                Spacer(minLength: 0)

                Picker("", selection: $selectedSettingsTab) {
                    Text(language == .english ? "General" : "通用").tag(SettingsTab.general)
                    Text(language == .english ? "API Accounts" : "API 账号").tag(SettingsTab.accounts)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: language == .english ? 260 : 220)

                Spacer(minLength: 0)

                Text("v\(currentAppVersion)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .frame(width: 132, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()
        }
    }
    
    private var generalSettingsView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if hasUnsavedChanges {
                        Label(language == .english ? "Unsaved changes" : "有未保存改动", systemImage: "circle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    generalCard(
                        title: language == .english ? "Appearance" : "外观",
                        icon: "textformat"
                    ) {
                        VStack(alignment: .leading, spacing: 7) {
                            settingLabel(language == .english ? "Language" : "语言")
                            Picker("", selection: $language) {
                                Text(language == .english ? "Chinese" : "中文").tag(AppLanguage.chinese)
                                Text(language == .english ? "English" : "英文").tag(AppLanguage.english)
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 260, alignment: .leading)
                        }
                    }

                    generalCard(
                        title: language == .english ? "Menu Bar" : "菜单栏",
                        icon: "menubar.rectangle"
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(language == .english
                                 ? "Pin selected live values next to the menu bar icon. Values use the latest refreshed data and do not trigger extra requests."
                                 : "将选定数据固定显示在菜单栏图标旁。数据来自最近一次刷新，不会产生额外请求。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(MenuBarPinnedMetric.allCases) { metric in
                                    menuBarPinnedMetricRow(metric)
                                }
                            }
                        }
                    }

                    generalCard(
                        title: language == .english ? "Refresh & Startup" : "刷新与启动",
                        icon: "arrow.clockwise"
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 7) {
                                settingLabel(language == .english ? "Auto refresh" : "自动刷新")
                                Picker("", selection: $refreshInterval) {
                                    Text(language == .english ? "1m" : "1 分钟").tag(1)
                                    Text(language == .english ? "5m" : "5 分钟").tag(5)
                                    Text(language == .english ? "15m" : "15 分钟").tag(15)
                                    Text(language == .english ? "30m" : "30 分钟").tag(30)
                                    Text(language == .english ? "1h" : "1 小时").tag(60)
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 560, alignment: .leading)
                            }

                            Divider()

                            Toggle(isOn: $launchAtLogin) {
                                Text(language == .english ? "Launch at login" : "开机自启动")
                            }
                            .toggleStyle(.switch)

                            if let launchError = viewModel.launchAtLoginErrorMessage {
                                Label(
                                    language == .english
                                    ? "Failed to update launch item: \(launchError)"
                                    : "更新开机自启动失败：\(launchError)",
                                    systemImage: "exclamationmark.triangle.fill"
                                )
                                .font(.caption2)
                                .foregroundColor(.red)
                            }
                        }
                    }

                    generalCard(
                        title: language == .english ? "Dashboard" : "看板",
                        icon: "rectangle.grid.1x2"
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 7) {
                                settingLabel(language == .english ? "Card order" : "卡片排序")
                                Picker("", selection: $dashboardSortMode) {
                                    ForEach(DashboardSortMode.allCases) { mode in
                                        Label(mode.displayName(language: language), systemImage: dashboardSortModeIconName(mode))
                                            .tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 430, alignment: .leading)
                            }

                            Divider()

                            Toggle(isOn: $showTrendInDashboard) {
                                Text(language == .english ? "Show DeepSeek balance trend" : "显示 DeepSeek 余额趋势")
                            }
                            .toggleStyle(.switch)
                            .help(language == .english ? "Only applies to DeepSeek cards" : "仅适用于 DeepSeek 卡片")

                            if showTrendInDashboard {
                                VStack(alignment: .leading, spacing: 7) {
                                    settingLabel(language == .english ? "Trend range" : "趋势范围")
                                    Picker("", selection: $dashboardTrendWindow) {
                                        ForEach(TrendWindow.dashboardSelectable) { window in
                                            Text(window.displayName(language: language)).tag(window)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(maxWidth: 430, alignment: .leading)
                                }
                                .padding(10)
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }

                            Divider()

                            Toggle(isOn: $showCodexEquivalentValue) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(language == .english ? "Show Codex API equivalent value" : "显示 Codex API 等价价值")
                                    Text(language == .english
                                         ? "Verified paid Coding Plan text usage only; token details stay hidden."
                                         : "仅统计可核验的付费 Coding Plan 文本用量，不显示 Token 明细。")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .toggleStyle(.switch)

                            if showCodexEquivalentValue {
                                VStack(alignment: .leading, spacing: 7) {
                                    settingLabel(language == .english ? "Value range" : "价值范围")
                                    Picker("", selection: $codexEquivalentValueWindow) {
                                        ForEach(TrendWindow.dashboardSelectable) { window in
                                            Text(window.displayName(language: language)).tag(window)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(maxWidth: 430, alignment: .leading)

                                    Text(language == .english
                                         ? "Uses current official API prices (USD, priced \(CodexEquivalentValuePricing.referenceDate))."
                                         : "按当前官方 API 美元单价折算（价格基准 \(CodexEquivalentValuePricing.referenceDate)）。")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(10)
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }

                    generalCard(
                        title: language == .english ? "Alerts & Thresholds" : "提醒与阈值",
                        icon: "bell.badge"
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(isOn: $alertsEnabled) {
                                Text(language == .english ? "Enable low-quota notifications" : "开启低余量通知")
                            }
                            .toggleStyle(.switch)

                            if alertsEnabled {
                                VStack(alignment: .leading, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            settingLabel(language == .english ? "Notify when usage reaches" : "用量达到时通知")
                                            Spacer()
                                            Text("\(warningThreshold)%")
                                                .font(.headline)
                                                .fontDesign(.rounded)
                                                .monospacedDigit()
                                        }

                                        Slider(
                                            value: Binding(
                                                get: { Double(warningThreshold) },
                                                set: { newValue in
                                                    let stepped = Int((newValue / 5).rounded() * 5)
                                                    warningThreshold = min(max(stepped, 50), 100)
                                                    criticalThreshold = warningThreshold
                                                }
                                            ),
                                            in: 50...100,
                                            step: 5
                                        )

                                        HStack {
                                            Text("50%")
                                            Spacer()
                                            Text("75%")
                                            Spacer()
                                            Text("100%")
                                        }
                                        .font(.caption2)
                                        .foregroundColor(.secondary)

                                    }

                                    compactThresholdPicker(
                                        title: language == .english ? "Cooldown" : "冷却",
                                        valueText: cooldownLabel(alertCooldownMinutes)
                                    ) {
                                        Picker("", selection: $alertCooldownMinutes) {
                                            Text(language == .english ? "30m" : "30分").tag(30)
                                            Text(language == .english ? "1h" : "1时").tag(60)
                                            Text(language == .english ? "2h" : "2时").tag(120)
                                            Text(language == .english ? "4h" : "4时").tag(240)
                                            Text(language == .english ? "24h" : "24时").tag(1440)
                                        }
                                        .pickerStyle(.segmented)
                                    }
                                }
                                .padding(10)
                                .background(Color.gray.opacity(0.08))
                                .cornerRadius(10)
                            }

                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(language == .english ? "DeepSeek low balance color threshold" : "DeepSeek 低余额颜色阈值")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(String(format: "%.2f", max(0, deepSeekBalanceThreshold)))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .monospacedDigit()
                                }

                                HStack(spacing: 8) {
                                    TextField(
                                        language == .english ? "Threshold" : "阈值",
                                        value: $deepSeekBalanceThreshold,
                                        format: .number.precision(.fractionLength(0...2))
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 120)
                                    .onChange(of: deepSeekBalanceThreshold) { _, newValue in
                                        if !newValue.isFinite || newValue < 0 {
                                            deepSeekBalanceThreshold = 0
                                        }
                                    }

                                    Text(language == .english ? "Dashboard color only" : "仅影响看板颜色")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    generalCard(
                        title: language == .english ? "Hotkey" : "快捷键",
                        icon: "keyboard"
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Button(action: {
                                    hotkeyError = nil
                                    hotkeyBeforeRecording = hotkey
                                    isRecordingHotkey = true
                                }) {
                                    HStack {
                                        if isRecordingHotkey {
                                            Text(language == .english ? "Press keys..." : "请按下组合键...")
                                                .foregroundColor(.red)
                                        } else {
                                            Text(hotkey.displayString)
                                                .fontWeight(.medium)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                .background(
                                    HotkeyRecorderView(
                                        isRecording: $isRecordingHotkey,
                                        hotkey: $hotkey,
                                        language: language,
                                        onValidationError: { error in
                                            hotkeyError = error
                                            hotkeyBeforeRecording = nil
                                        },
                                        onRecordingCancelled: {
                                            cancelHotkeyRecording()
                                        },
                                        onRecordingCompleted: {
                                            hotkeyBeforeRecording = nil
                                        }
                                    )
                                )

                                Button(action: {
                                    hotkey = HotkeySetting.defaultHotkey
                                    hotkeyError = nil
                                }) {
                                    Text(language == .english ? "Default" : "默认")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)

                                if isRecordingHotkey {
                                    Button(language == .english ? "Cancel" : "取消") {
                                        cancelHotkeyRecording()
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }

                            if let error = hotkeyError {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }

                    generalCard(
                        title: language == .english ? "Updates & Project" : "更新与项目",
                        icon: "arrow.triangle.2.circlepath"
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            let buttonHeight: CGFloat = 32
                            HStack(spacing: 8) {
                                Button(action: {
                                    updateService.checkForUpdates()
                                }) {
                                    HStack(spacing: 6) {
                                        ZStack {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.system(size: 12, weight: .semibold))
                                                .opacity(updateService.isChecking ? 0 : 1)
                                            ProgressView()
                                                .controlSize(.small)
                                                .opacity(updateService.isChecking ? 1 : 0)
                                        }
                                        .frame(width: 14, height: 14)
                                        Text(language == .english ? "Check for Updates" : "检查更新")
                                    }
                                    .frame(maxWidth: .infinity, minHeight: buttonHeight, maxHeight: buttonHeight)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.regular)
                                .disabled(updateService.isChecking)
                                .animation(.none, value: updateService.isChecking)

                                Button(action: {
                                    updateService.openGitHubReadme()
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "book")
                                        Text(language == .english ? "GitHub README" : "GitHub 文档")
                                    }
                                    .frame(maxWidth: .infinity, minHeight: buttonHeight, maxHeight: buttonHeight)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                            }

                            if let statusMessage = updateService.statusMessage {
                                Text(statusMessage)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let lastCheckTime = updateService.lastCheckTime {
                                Text(
                                    language == .english
                                    ? "Last checked: \(formattedUpdateCheckTime(lastCheckTime))"
                                    : "上次检查：\(formattedUpdateCheckTime(lastCheckTime))"
                                )
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }
                        }
                    }

                }
                .padding(16)
                .padding(.bottom, 8)
            }

            stickySaveBar(primary: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func generalCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.14))
                        .frame(width: 26, height: 26)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                }
                Spacer(minLength: 0)
            }

            content()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func settingLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.secondary)
    }
    
    private var accountsSettingsView: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    Spacer()
                    if hasUnsavedChanges {
                        Text(language == .english ? "Unsaved" : "未保存")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.16))
                            .foregroundColor(.orange)
                            .clipShape(Capsule())
                    }
                    Button(action: addAccount) {
                        Label(language == .english ? "Add" : "新增", systemImage: "plus")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                if accounts.isEmpty {
                    VStack {
                        Text(language == .english ? "No API accounts configured" : "当前没有配置 API 账号")
                            .foregroundColor(.secondary)
                        Text(language == .english ? "Click + to add an account" : "点击 + 新增账号")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    if !APIProvider.providersWithCapabilityDescription.isEmpty {
                        providerCapabilityNoticeSection
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach($accounts) { $account in
                                AccountRowView(
                                    account: $account,
                                    isExpanded: Binding(
                                        get: { expandedStates[account.id] ?? false },
                                        set: { expandedStates[account.id] = $0 }
                                    ),
                                    isEditingName: editingAccountID == account.id,
                                    nameDraft: nameDraftByAccountID[account.id] ?? account.name,
                                    onDelete: {
                                        forceCommitCurrentEditor()
                                        pendingDeleteAccount = account
                                    },
                                    onNameLabelTapped: {
                                        beginNameEditing(for: account.id)
                                    },
                                    onNameDraftChanged: { draft in
                                        updateNameDraft(for: account.id, draft: draft)
                                    },
                                    onNameEditCommitted: {
                                        commitNameEdit(for: account.id)
                                    },
                                    onProviderChanged: { _, newProvider in
                                        let shouldFollowProvider = autoNamedAccountIDs.contains(account.id)
                                        if shouldFollowProvider {
                                            account.name = newProvider.displayName
                                            autoNamedAccountIDs.insert(account.id)
                                            nameDraftByAccountID[account.id] = newProvider.displayName
                                        }
                                    },
                                    language: language
                                )
                            }

                            if !APIProvider.providersWithCapabilityDescription.isEmpty {
                                providerCapabilityNoticeSection
                                    .padding(.top, 2)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            stickySaveBar(primary: false)
        }
    }

    private func stickySaveBar(primary: Bool) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button(action: {
                    commitEditsThenSave()
                }) {
                    HStack {
                        if saveButtonState == .saved {
                            Image(systemName: "checkmark.circle.fill")
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Text(saveButtonTitle(primary: primary))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(saveButtonTintColor)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!hasUnsavedChanges && saveButtonState != .saved)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    private var providerCapabilityNoticeSection: some View {
        DisclosureGroup(isExpanded: $isCapabilityNoticeExpanded) {
            providerCapabilityNoticeCard
                .padding(.top, 8)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text(language == .english ? "Provider Capabilities" : "供应商能力说明")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(language == .english ? "\(APIProvider.providersWithCapabilityDescription.count) items" : "\(APIProvider.providersWithCapabilityDescription.count)项")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)
        }
        .padding(.top, 4)
    }

    private var providerCapabilityNoticeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                language == .english
                ? "Known provider-specific behavior."
                : "各供应商的特殊展示规则"
            )
            .font(.caption)
            .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                ForEach(APIProvider.providersWithCapabilityDescription) { provider in
                    HStack(alignment: .top, spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.10))
                                .frame(width: 28, height: 28)
                            Image(systemName: provider.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.blue)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(provider.displayName)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                if let hint = provider.restrictionHint(language: language) {
                                    Text(hint)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Text(provider.capabilityDescription(language: language) ?? (language == .english ? "No extra notes" : "暂无说明"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.blue.opacity(0.14), lineWidth: 1)
                    )
                    .cornerRadius(10)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.06),
                            Color.blue.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.16), lineWidth: 1)
        )
    }
    
    private func loadSettings() {
        // Reuse the in-memory settings from the shared view model to avoid an extra
        // Keychain read prompt every time the settings window is opened.
        let settings = viewModel.settings
        accounts = settings.accounts
        autoNamedAccountIDs = []
        refreshInterval = settings.refreshInterval
        hotkey = settings.hotkey
        language = settings.language
        alertsEnabled = settings.alertSettings.isEnabled
        warningThreshold = settings.alertSettings.warningPercentage
        criticalThreshold = settings.alertSettings.criticalPercentage
        alertCooldownMinutes = settings.alertSettings.cooldownMinutes
        deepSeekBalanceThreshold = settings.deepSeekBalanceSettings.threshold
        showTrendInDashboard = settings.showTrendInDashboard
        dashboardTrendWindow = settings.dashboardTrendWindow
        showCodexEquivalentValue = settings.codexEquivalentValueSettings.isEnabled
        codexEquivalentValueWindow = settings.codexEquivalentValueSettings.window
        menuBarPinnedItems = MenuBarPinnedItem.normalized(settings.menuBarPinnedItems, language: language)
        dashboardSortMode = viewModel.dashboardSortMode
        viewModel.refreshLaunchAtLoginStatus()
        launchAtLogin = viewModel.launchAtLoginEnabled
        isRecordingHotkey = false
        hotkeyBeforeRecording = nil
        hotkeyError = nil
        saveButtonState = .normal
        isCapabilityNoticeExpanded = false
        editingAccountID = nil
        nameDraftByAccountID = [:]
        nameAtEditStartByAccountID = [:]
        collapseAllAccounts()
        savedDraftSignature = currentDraftSignature()
    }
    
    private func saveSettings() {
        accounts = accounts.map { account in
            var normalized = account
            normalized.name = normalized.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized.name.isEmpty {
                normalized.name = normalized.provider.displayName
            }
            return normalized
        }

        let settings = AppSettings(
            accounts: accounts,
            refreshInterval: refreshInterval,
            hotkey: hotkey,
            language: language,
            alertSettings: normalizedAlertSettings(),
            deepSeekBalanceSettings: normalizedDeepSeekBalanceSettings(),
            codexEquivalentValueSettings: CodexEquivalentValueSettings(
                isEnabled: showCodexEquivalentValue,
                window: codexEquivalentValueWindow
            ),
            showTrendInDashboard: showTrendInDashboard,
            dashboardTrendWindow: dashboardTrendWindow,
            launchAtLogin: launchAtLogin,
            menuBarPinnedItems: normalizedMenuBarPinnedItems()
        )
        do {
            try viewModel.saveSettings(settings)
        } catch {
            saveErrorMessage = localizedSaveError(error)
            return
        }
        viewModel.setDashboardSortMode(dashboardSortMode)
        launchAtLogin = viewModel.launchAtLoginEnabled
        savedDraftSignature = currentDraftSignature()
        
        withAnimation {
            saveButtonState = .saved
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                saveButtonState = .normal
            }
        }
    }

    private var saveErrorBinding: Binding<Bool> {
        Binding(
            get: { saveErrorMessage != nil },
            set: { isPresented in
                if !isPresented { saveErrorMessage = nil }
            }
        )
    }

    private func localizedSaveError(_ error: Error) -> String {
        guard language == .english else { return error.localizedDescription }
        switch error {
        case SettingsPersistenceError.defaultsUnavailable:
            return "App settings storage is unavailable. No changes were saved."
        case SettingsPersistenceError.encodeFailed:
            return "Settings could not be encoded. No changes were saved."
        case SettingsPersistenceError.keychainFailed(let underlying):
            return "API keys could not be saved securely: \(underlying.localizedDescription)"
        case SettingsPersistenceError.defaultsVerificationFailed:
            return "Settings verification failed. API keys were restored to their previous state where possible."
        default:
            return error.localizedDescription
        }
    }

    private func commitEditsThenSave() {
        forceCommitCurrentEditor()
        NSApp.keyWindow?.makeFirstResponder(nil)
        DispatchQueue.main.async {
            saveSettings()
        }
    }

    private func installDefocusObserversIfNeeded() {
        guard defocusObserverTokens.isEmpty else { return }
        let center = NotificationCenter.default
        let windowToken = center.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { _ in
            forceCommitCurrentEditor()
        }
        let appToken = center.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            forceCommitCurrentEditor()
        }
        defocusObserverTokens = [windowToken, appToken]
    }

    private func removeDefocusObservers() {
        let center = NotificationCenter.default
        defocusObserverTokens.forEach { center.removeObserver($0) }
        defocusObserverTokens.removeAll()
    }

    private func installLocalClickMonitorIfNeeded() {
        guard localClickMonitor == nil else { return }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            DispatchQueue.main.async {
                guard editingAccountID != nil else { return }
                if NSApp.keyWindow?.firstResponder is NSTextView {
                    return
                }
                // Some control clicks transition focus asynchronously; verify once more
                // on the next runloop turn before committing the edit.
                if NSApp.keyWindow?.firstResponder == nil {
                    DispatchQueue.main.async {
                        guard editingAccountID != nil else { return }
                        if NSApp.keyWindow?.firstResponder is NSTextView {
                            return
                        }
                        forceCommitCurrentEditor()
                    }
                    return
                }
                forceCommitCurrentEditor()
            }
            return event
        }
    }

    private func removeLocalClickMonitor() {
        guard let monitor = localClickMonitor else { return }
        NSEvent.removeMonitor(monitor)
        localClickMonitor = nil
    }

    private func beginNameEditing(for accountID: UUID) {
        if editingAccountID != accountID {
            forceCommitCurrentEditor()
        }
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        editingAccountID = accountID
        nameDraftByAccountID[accountID] = accounts[index].name
        nameAtEditStartByAccountID[accountID] = accounts[index].name
    }

    private func updateNameDraft(for accountID: UUID, draft: String) {
        nameDraftByAccountID[accountID] = draft
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[index].name = draft
    }

    private func commitNameEdit(for accountID: UUID) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else {
            editingAccountID = nil
            nameDraftByAccountID.removeValue(forKey: accountID)
            nameAtEditStartByAccountID.removeValue(forKey: accountID)
            return
        }

        let originalName = nameAtEditStartByAccountID[accountID] ?? accounts[index].name
        var committedName = (nameDraftByAccountID[accountID] ?? accounts[index].name)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if committedName.isEmpty {
            committedName = accounts[index].provider.displayName
            autoNamedAccountIDs.insert(accountID)
        } else if committedName != originalName {
            autoNamedAccountIDs.remove(accountID)
        }

        accounts[index].name = committedName
        nameDraftByAccountID[accountID] = committedName
        nameAtEditStartByAccountID.removeValue(forKey: accountID)
        if editingAccountID == accountID {
            editingAccountID = nil
        }
    }

    private func forceCommitCurrentEditor() {
        guard let accountID = editingAccountID else { return }
        commitNameEdit(for: accountID)
    }
    
    private func addAccount() {
        let defaultProvider: APIProvider = .miniMax
        let newAccount = APIAccount(name: defaultProvider.displayName, provider: defaultProvider, apiKey: "", isEnabled: true)
        accounts.insert(newAccount, at: 0)
        autoNamedAccountIDs.insert(newAccount.id)
        
        for i in accounts.indices {
            if accounts[i].id != newAccount.id {
                expandedStates[accounts[i].id] = false
            }
        }
        expandedStates[newAccount.id] = true
    }

    private func cancelHotkeyRecording() {
        guard isRecordingHotkey else { return }
        if let original = hotkeyBeforeRecording {
            hotkey = original
        }
        isRecordingHotkey = false
        hotkeyBeforeRecording = nil
    }
    
    private func deleteAccount(_ account: APIAccount) {
        if editingAccountID == account.id {
            editingAccountID = nil
        }
        nameDraftByAccountID.removeValue(forKey: account.id)
        nameAtEditStartByAccountID.removeValue(forKey: account.id)
        accounts.removeAll { $0.id == account.id }
        autoNamedAccountIDs.remove(account.id)
        expandedStates.removeValue(forKey: account.id)
        // Keychain deletion is handled on save via Storage.saveSettings(_:), so draft edits
        // (add/remove before save) do not trigger extra Keychain authorization prompts.
    }
    
    private func collapseAllAccounts() {
        for i in accounts.indices {
            expandedStates[accounts[i].id] = false
        }
    }

    private var hasUnsavedChanges: Bool {
        currentDraftSignature() != savedDraftSignature
    }

    private var pendingDeleteBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteAccount != nil },
            set: { newValue in
                if !newValue { pendingDeleteAccount = nil }
            }
        )
    }

    private func saveButtonTitle(primary: Bool) -> String {
        if saveButtonState == .saved {
            return language == .english ? "Saved!" : "已保存"
        }
        if !hasUnsavedChanges {
            return language == .english ? "No Changes" : "无改动"
        }
        return primary
            ? (language == .english ? "Save Settings" : "保存设置")
            : (language == .english ? "Save" : "保存")
    }

    private var saveButtonTintColor: Color {
        if saveButtonState == .saved {
            return .green
        }
        if hasUnsavedChanges {
            return .blue
        }
        return .gray
    }

    private func currentDraftSignature() -> String {
        let draft = AppSettings(
            accounts: accounts,
            refreshInterval: refreshInterval,
            hotkey: hotkey,
            language: language,
            alertSettings: normalizedAlertSettings(),
            deepSeekBalanceSettings: normalizedDeepSeekBalanceSettings(),
            codexEquivalentValueSettings: CodexEquivalentValueSettings(
                isEnabled: showCodexEquivalentValue,
                window: codexEquivalentValueWindow
            ),
            showTrendInDashboard: showTrendInDashboard,
            dashboardTrendWindow: dashboardTrendWindow,
            launchAtLogin: launchAtLogin,
            menuBarPinnedItems: normalizedMenuBarPinnedItems()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(draft) else { return "" }
        return "\(String(decoding: data, as: UTF8.self))|dashboardSortMode=\(dashboardSortMode.rawValue)"
    }

    private func dashboardSortModeIconName(_ mode: DashboardSortMode) -> String {
        switch mode {
        case .manual:
            return "line.3.horizontal.circle"
        case .provider:
            return "square.grid.2x2"
        case .name:
            return "textformat.abc"
        }
    }

    private func menuBarPinnedMetricRow(_ metric: MenuBarPinnedMetric) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Toggle(isOn: menuBarPinnedEnabledBinding(for: metric)) {
                Text(metric.displayName(language: language))
                    .font(.subheadline)
            }
            .toggleStyle(.checkbox)
            .frame(width: language == .english ? 190 : 150, alignment: .leading)

            TextField(
                language == .english ? "Custom text" : "自定义文本",
                text: menuBarPinnedPrefixBinding(for: metric)
            )
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 180)
            .disabled(!menuBarPinnedEnabledBinding(for: metric).wrappedValue)

            Text(menuBarPinnedPreviewText(for: metric))
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func menuBarPinnedEnabledBinding(for metric: MenuBarPinnedMetric) -> Binding<Bool> {
        Binding(
            get: { menuBarPinnedItem(for: metric).isEnabled },
            set: { newValue in
                updateMenuBarPinnedItem(metric) { item in
                    item.isEnabled = newValue
                }
            }
        )
    }

    private func menuBarPinnedPrefixBinding(for metric: MenuBarPinnedMetric) -> Binding<String> {
        Binding(
            get: { menuBarPinnedItem(for: metric).prefix },
            set: { newValue in
                updateMenuBarPinnedItem(metric) { item in
                    item.prefix = String(newValue.prefix(12))
                }
            }
        )
    }

    private func menuBarPinnedItem(for metric: MenuBarPinnedMetric) -> MenuBarPinnedItem {
        let normalized = MenuBarPinnedItem.normalized(menuBarPinnedItems, language: language)
        return normalized.first(where: { $0.metric == metric }) ?? MenuBarPinnedItem(metric: metric, language: language)
    }

    private func updateMenuBarPinnedItem(_ metric: MenuBarPinnedMetric, mutate: (inout MenuBarPinnedItem) -> Void) {
        var normalized = MenuBarPinnedItem.normalized(menuBarPinnedItems, language: language)
        guard let index = normalized.firstIndex(where: { $0.metric == metric }) else {
            return
        }
        mutate(&normalized[index])
        menuBarPinnedItems = normalized
    }

    private func menuBarPinnedPreviewText(for metric: MenuBarPinnedMetric) -> String {
        let prefix = menuBarPinnedItem(for: metric).prefix
        switch metric {
        case .deepSeekBalance:
            return "\(prefix)¥12"
        case .codexFiveHourRemaining:
            return "\(prefix)73%"
        case .codexWeeklyRemaining:
            return "\(prefix)97%"
        }
    }

    private func normalizedMenuBarPinnedItems() -> [MenuBarPinnedItem] {
        MenuBarPinnedItem.normalized(menuBarPinnedItems, language: language)
    }

    @ViewBuilder
    private func compactThresholdPicker<Content: View>(
        title: String,
        valueText: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text(valueText)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            content()
        }
    }

    private func normalizedAlertSettings() -> ThresholdAlertSettings {
        ThresholdAlertSettings(
            isEnabled: alertsEnabled,
            warningPercentage: warningThreshold,
            criticalPercentage: warningThreshold,
            cooldownMinutes: alertCooldownMinutes
        ).normalized
    }

    private func normalizedDeepSeekBalanceSettings() -> DeepSeekBalanceSettings {
        DeepSeekBalanceSettings(
            threshold: deepSeekBalanceThreshold
        ).normalized
    }

    private func cooldownLabel(_ minutes: Int) -> String {
        if minutes % 60 == 0 {
            let hour = minutes / 60
            return language == .english ? "\(hour)h" : "\(hour)小时"
        }
        return language == .english ? "\(minutes)m" : "\(minutes)分钟"
    }

    private func formattedUpdateCheckTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language == .english ? Locale(identifier: "en_US_POSIX") : Locale(identifier: "zh_CN")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

}

struct AccountRowView: View {
    private static let deepSeekKeysURL = URL(string: "https://platform.deepseek.com/api_keys")!
    private static let codexLoginURL = URL(string: "https://developers.openai.com/codex/cli/")!
    @Binding var account: APIAccount
    @Binding var isExpanded: Bool
    var isEditingName: Bool
    var nameDraft: String
    var onDelete: () -> Void
    var onNameLabelTapped: () -> Void
    var onNameDraftChanged: (String) -> Void
    var onNameEditCommitted: () -> Void
    var onProviderChanged: ((APIProvider, APIProvider) -> Void)?
    var language: AppLanguage = .chinese
    @State private var isCredentialGuideExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 14 : 0) {
            HStack(alignment: .center, spacing: 8) {
                Button(action: toggleExpanded) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
                .help(language == .english ? "Expand/collapse account" : "展开/合上账号")

                if isExpanded {
                    nameEditorOrLabel
                } else {
                    Button(action: toggleExpanded) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(account.name.isEmpty ? account.provider.displayName : account.name)
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(1)
                            Text(account.provider.displayName)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    Text(language == .english ? "Show" : "显示")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Toggle("", isOn: $account.isEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                }
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .frame(width: 20, height: 20)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(language == .english ? "Provider" : "供应商")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Menu {
                            ForEach(providerOptions) { provider in
                                Button {
                                    selectProvider(provider)
                                } label: {
                                    if provider == account.provider {
                                        Label(providerOptionLabel(provider), systemImage: "checkmark")
                                    } else {
                                        Text(providerOptionLabel(provider))
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Label(account.provider.displayName, systemImage: account.provider.icon)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .menuStyle(.borderlessButton)
                        .frame(maxWidth: .infinity)
                    }

                    if account.provider.requiresCredential {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(apiKeyPlaceholder)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            SecureField(apiKeyPlaceholder, text: $account.apiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                    } else {
                        Label(
                            language == .english ? "Uses local Codex login" : "使用本机 Codex 登录状态",
                            systemImage: "checkmark.shield"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }

                    credentialGuide
                    
                    Divider()
                    TestConnectionButton(account: $account, language: language)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, isExpanded ? 12 : 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isExpanded ? Color.accentColor.opacity(0.30) : Color.gray.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
    }

    @ViewBuilder
    private var nameEditorOrLabel: some View {
        if isEditingName {
            AccountNameEditor(
                text: Binding(
                    get: { nameDraft },
                    set: onNameDraftChanged
                ),
                isFocused: isEditingName,
                onBeginEditing: {},
                onEndEditing: {
                    onNameEditCommitted()
                }
            )
            .frame(width: 200)
        } else {
            Button(action: onNameLabelTapped) {
                HStack(spacing: 4) {
                    Text(account.name.isEmpty ? account.provider.displayName : account.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "pencil")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .opacity(0.75)
                }
            }
            .buttonStyle(.plain)
            .help(language == .english ? "Click name to edit" : "点击名称可改名")
        }
    }

    private func toggleExpanded() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded.toggle()
        }
        if !isExpanded {
            onNameEditCommitted()
        }
    }
    
    private var apiKeyPlaceholder: String {
        switch account.provider {
        case .openAI:
            return language == .english
                ? "OpenAI Admin Key"
                : "OpenAI Admin Key"
        default:
            return "API Key"
        }
    }

    private var providerOptions: [APIProvider] {
        if APIProvider.selectableForNewAccounts.contains(account.provider) {
            return APIProvider.selectableForNewAccounts
        }
        return APIProvider.selectableForNewAccounts + [account.provider]
    }

    private func selectProvider(_ provider: APIProvider) {
        guard provider != account.provider else { return }
        let oldProvider = account.provider
        onNameEditCommitted()
        account.provider = provider
        account.apiKey = ""
        if provider == .deepSeek || provider == .codex {
            isCredentialGuideExpanded = true
        }
        onProviderChanged?(oldProvider, provider)
    }

    @ViewBuilder
    private var credentialGuide: some View {
        if account.provider == .deepSeek || account.provider == .openAI || account.provider == .miniMax || account.provider == .tavily || account.provider == .kimi || account.provider == .codex {
            DisclosureGroup(isExpanded: $isCredentialGuideExpanded) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(credentialGuideText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let url = credentialGuideURL {
                        Link(destination: url) {
                            Label(credentialGuideLinkText, systemImage: "arrow.up.right.square")
                                .font(.caption)
                        }
                    }
                }
                .padding(.top, 7)
            } label: {
                Label(language == .english ? "How to connect" : "如何连接", systemImage: "key.horizontal")
                    .font(.caption.weight(.semibold))
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var credentialGuideText: String {
        switch account.provider {
        case .deepSeek:
            return language == .english
                ? "Sign in to DeepSeek, create an API key on the API Keys page, copy the complete key, and paste it into the API Key field above."
                : "登录 DeepSeek，在 API Keys 页面创建密钥，复制完整 API Key，并粘贴到上方 API Key 输入框。"
        case .openAI:
            return language == .english
                ? "Create an organization Admin Key in OpenAI platform settings. The standard project API key is not enough for the official Costs API."
                : "在 OpenAI 平台组织设置中创建 Admin Key。普通项目 API Key 不能调用官方 Costs API。"
        case .miniMax:
            return language == .english
                ? "Use the API key for the MiniMax account that has an active Token Plan subscription. QuotaPulse calls MiniMax's official Token Plan remains endpoint."
                : "填写已开通 MiniMax Token Plan 的账号 API Key；QuotaPulse 调用官方 Token Plan 余量接口。"
        case .tavily:
            return language == .english
                ? "Copy your Tavily API key from the Tavily dashboard and paste the complete key above."
                : "从 Tavily 控制台复制完整 API Key，并粘贴到上方输入框。"
        case .kimi:
            return language == .english
                ? "Copy your Moonshot/Kimi API key from the Moonshot platform. QuotaPulse uses the official balance endpoint."
                : "从 Moonshot/Kimi 平台复制完整 API Key；QuotaPulse 使用官方余额接口查询。"
        case .codex:
            return language == .english
                ? "Install Codex CLI, run “codex login” in Terminal, and complete sign-in. QuotaPulse reads the local Codex usage record; nothing needs to be pasted here."
                : "安装 Codex CLI 后，在终端运行“codex login”并完成登录；QuotaPulse 读取本机 Codex 用量记录，这里无需粘贴任何内容。"
        case .glm, .chatGPT:
            return language == .english
                ? "This monitoring method has been removed because it is not backed by a stable official API."
                : "该监控方案已删除，因为没有稳定的官方 API 接口支撑。"
        }
    }

    private var credentialGuideURL: URL? {
        switch account.provider {
        case .deepSeek:
            return Self.deepSeekKeysURL
        case .openAI:
            return URL(string: "https://platform.openai.com/settings/organization/admin-keys")
        case .miniMax:
            return URL(string: "https://www.minimax.io/platform")
        case .tavily:
            return URL(string: "https://app.tavily.com/home")
        case .kimi:
            return URL(string: "https://platform.moonshot.cn/console/api-keys")
        case .codex:
            return Self.codexLoginURL
        case .glm, .chatGPT:
            return nil
        }
    }

    private var credentialGuideLinkText: String {
        switch account.provider {
        case .deepSeek:
            return language == .english ? "Open DeepSeek API Keys" : "打开 DeepSeek API Keys"
        case .openAI:
            return language == .english ? "Open OpenAI Admin Keys" : "打开 OpenAI Admin Keys"
        case .miniMax:
            return language == .english ? "Open MiniMax platform" : "打开 MiniMax 平台"
        case .tavily:
            return language == .english ? "Open Tavily dashboard" : "打开 Tavily 控制台"
        case .kimi:
            return language == .english ? "Open Moonshot API Keys" : "打开 Moonshot API Keys"
        case .codex:
            return language == .english ? "Open Codex CLI guide" : "打开 Codex CLI 指南"
        case .glm, .chatGPT:
            return language == .english ? "Unsupported" : "不支持"
        }
    }

    private func providerOptionLabel(_ provider: APIProvider) -> String {
        if provider.supportsRemainingQuotaQuery {
            return provider.displayName
        }
        return language == .english
            ? "\(provider.displayName) (remaining quota unsupported)"
            : "\(provider.displayName)（暂不支持余量查询）"
    }
}

private struct AccountNameEditor: NSViewRepresentable {
    @Binding var text: String
    var isFocused: Bool
    var onBeginEditing: () -> Void
    var onEndEditing: () -> Void

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AccountNameEditor
        var isProgrammaticTextUpdate = false

        init(parent: AccountNameEditor) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.onBeginEditing()
        }

        func controlTextDidChange(_ notification: Notification) {
            guard !isProgrammaticTextUpdate else { return }
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onEndEditing()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(string: text)
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .default
        textField.delegate = context.coordinator
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self

        if nsView.stringValue != text {
            context.coordinator.isProgrammaticTextUpdate = true
            nsView.stringValue = text
            context.coordinator.isProgrammaticTextUpdate = false
        }

        guard let window = nsView.window else { return }
        if isFocused {
            if window.firstResponder !== nsView.currentEditor() {
                window.makeFirstResponder(nsView)
            }
        }
    }
}

struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var hotkey: HotkeySetting
    var language: AppLanguage = .chinese
    var onValidationError: ((String) -> Void)?
    var onRecordingCancelled: (() -> Void)?
    var onRecordingCompleted: (() -> Void)?
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyRecorderNSView()
        view.onKeyRecorded = { keyCode, modifiers in
            let validationError = HotkeySetting.validate(keyCode: keyCode, modifiers: modifiers, language: language)
            if let error = validationError {
                onValidationError?(error)
                isRecording = false
            } else {
                hotkey = HotkeySetting(keyCode: keyCode, modifiers: modifiers)
                isRecording = false
                onRecordingCompleted?()
            }
        }
        view.onRecordingCancelled = {
            onRecordingCancelled?()
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let recorderView = nsView as? KeyRecorderNSView {
            recorderView.isRecording = isRecording
        }
    }
}

class KeyRecorderNSView: NSView {
    var isRecording: Bool = false {
        didSet {
            if isRecording {
                window?.makeFirstResponder(self)
            }
        }
    }
    var onKeyRecorded: ((UInt16, UInt32) -> Void)?
    var onRecordingCancelled: (() -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }

        if event.keyCode == 53 { // Esc
            isRecording = false
            onRecordingCancelled?()
            return
        }
        
        let modifiers = event.modifierFlags.rawValue & (NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue | NSEvent.ModifierFlags.option.rawValue | NSEvent.ModifierFlags.control.rawValue)
        
        guard modifiers != 0 else { return }
        
        onKeyRecorded?(UInt16(event.keyCode), UInt32(modifiers))
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign && isRecording {
            isRecording = false
            onRecordingCancelled?()
        }
        return didResign
    }
}

struct TestConnectionButton: View {
    @Binding var account: APIAccount
    var language: AppLanguage = .chinese
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var showDetails = false
    
    enum TestResult {
        case success(summary: String, details: String?)
        case failure(summary: String, details: String?)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(action: testConnection) {
                    HStack(spacing: 6) {
                        if isTesting {
                            ProgressView()
                                .scaleEffect(0.65)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "network")
                                .font(.caption)
                        }
                        Text(buttonText)
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isTesting)

                if let result = testResult {
                    Label(messageForResult(result), systemImage: iconForResult(result))
                        .font(.caption)
                        .foregroundColor(colorForResult(result))
                        .lineLimit(1)
                }
            }

            if let result = testResult,
               let details = detailsForResult(result),
               !details.isEmpty {
                Button(showDetails ? (language == .english ? "Hide details" : "收起详情") : (language == .english ? "Show details" : "展开详情")) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showDetails.toggle()
                    }
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundColor(.secondary)

                if showDetails {
                    Text(details)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .onChange(of: account.apiKey) { _, _ in
            testResult = nil
            showDetails = false
        }
        .onChange(of: account.provider) { _, _ in
            testResult = nil
            showDetails = false
        }
    }
    
    private var buttonText: String {
        if isTesting {
            return language == .english ? "Testing..." : "测试中..."
        } else if testResult != nil {
            return language == .english ? "Test Again" : "重新测试"
        }
        return language == .english ? "Test Connection" : "测试连接"
    }
    
    private func testConnection() {
        // Force commit editing so SecureField value is synchronized before test.
        NSApp.keyWindow?.makeFirstResponder(nil)

        let credential = account.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.provider.requiresCredential || !credential.isEmpty else {
            testResult = .failure(
                summary: language == .english ? "Please enter credential first" : "请先输入凭证",
                details: nil
            )
            return
        }
        
        isTesting = true
        testResult = nil
        showDetails = false
        
        // Capture current state before entering async context
        let currentAccount = account
        let currentLanguage = language
        
        Task {
            let service = getService(for: currentAccount.provider)
            do {
                let result = try await service.fetchUsage(apiKey: credential)
                try Task.checkCancellation()
                await MainActor.run {
                    if result.remaining != nil ||
                        result.used != nil ||
                        result.total != nil ||
                        result.monthlyRemaining != nil ||
                        result.monthlyUsed != nil ||
                        result.monthlyTotal != nil ||
                        result.subscriptionPlan != nil ||
                        result.refreshTime != nil ||
                        result.monthlyRefreshTime != nil ||
                        result.nextRefreshTime != nil {
                        testResult = .success(
                            summary: currentLanguage == .english ? "Connection successful" : "连接成功",
                            details: currentLanguage == .english
                            ? "Provider: \(currentAccount.provider.displayName)"
                            : "供应商：\(currentAccount.provider.displayName)"
                        )
                    } else {
                        testResult = .failure(
                            summary: currentLanguage == .english ? "Connected but no usable fields" : "连接成功但无可用字段",
                            details: currentLanguage == .english
                            ? "Provider endpoint returned success without known usage/subscription fields."
                            : "接口返回成功，但没有识别到可用的用量/订阅字段。"
                        )
                    }
                    isTesting = false
                }
            } catch is CancellationError {
                // Task was cancelled, ignore
                await MainActor.run {
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = .failure(
                        summary: currentLanguage == .english ? "Connection failed" : "连接失败",
                        details: classifiedFailureDetail(error, language: currentLanguage)
                    )
                    isTesting = false
                }
            }
        }
    }

    
    private func iconForResult(_ result: TestResult) -> String {
        switch result {
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "xmark.circle.fill"
        }
    }
    
    private func colorForResult(_ result: TestResult) -> Color {
        switch result {
        case .success:
            return .green
        case .failure:
            return .red
        }
    }
    
    private func messageForResult(_ result: TestResult) -> String {
        switch result {
        case .success(let msg, _):
            return msg
        case .failure(let msg, _):
            return msg
        }
    }

    private func detailsForResult(_ result: TestResult) -> String? {
        switch result {
        case .success(_, let details):
            return details
        case .failure(_, let details):
            return details
        }
    }

    private func classifiedFailureDetail(_ error: Error, language: AppLanguage? = nil) -> String {
        let lang = language ?? self.language
        if let apiError = error as? APIError {
            switch apiError {
            case .noAPIKey:
                return lang == .english
                    ? "Type: Missing credential\nPlease input API key/token and retry."
                    : "类型：缺少凭证\n请先输入 API Key/Token 后重试。"
            case .httpErrorWithMessage(let code, let message):
                if code < 0 {
                    return lang == .english
                        ? "Type: Provider/API failure\n\(message)"
                        : "类型：供应商接口失败\n\(message)"
                }
                if code == 401 || code == 403 {
                    return lang == .english
                        ? "Type: Authentication failed (HTTP \(code))\nCredential is invalid, expired, or has insufficient permissions."
                        : "类型：鉴权失败（HTTP \(code)）\n凭证无效、已过期或权限不足。"
                }
                if code == 429 {
                    return lang == .english
                        ? "Type: Rate limited (HTTP 429)\nPlease retry later."
                        : "类型：触发频率限制（HTTP 429）\n请稍后重试。"
                }
                if code >= 500 {
                    return lang == .english
                        ? "Type: Provider service error (HTTP \(code))\nThis is usually temporary."
                        : "类型：供应商服务异常（HTTP \(code)）\n通常为临时问题。"
                }
                return lang == .english
                    ? "Type: API request failed (HTTP \(code))\n\(error.localizedDescription)"
                    : "类型：接口请求失败（HTTP \(code)）\n\(error.localizedDescription)"
            case .httpError(let code):
                if code == 401 || code == 403 {
                    return lang == .english
                        ? "Type: Authentication failed (HTTP \(code))\nCredential is invalid, expired, or has insufficient permissions."
                        : "类型：鉴权失败（HTTP \(code)）\n凭证无效、已过期或权限不足。"
                }
                if code == 429 {
                    return lang == .english
                        ? "Type: Rate limited (HTTP 429)\nPlease retry later."
                        : "类型：触发频率限制（HTTP 429）\n请稍后重试。"
                }
                if code >= 500 {
                    return lang == .english
                        ? "Type: Provider service error (HTTP \(code))\nThis is usually temporary."
                        : "类型：供应商服务异常（HTTP \(code)）\n通常为临时问题。"
                }
                return lang == .english
                    ? "Type: API request failed (HTTP \(code))\n\(error.localizedDescription)"
                    : "类型：接口请求失败（HTTP \(code)）\n\(error.localizedDescription)"
            case .decodingError:
                return lang == .english
                    ? "Type: Response parse failure\nProvider response schema may have changed."
                    : "类型：响应解析失败\n可能是供应商返回结构发生变化。"
            case .networkError(let wrapped):
                return classifyWrappedError(wrapped, language: lang)
            case .invalidURL, .invalidResponse:
                return lang == .english
                    ? "Type: Invalid response\nProvider endpoint returned unexpected payload."
                    : "类型：响应无效\n供应商接口返回了异常数据。"
            }
        }

        let lowered = error.localizedDescription.lowercased()
        if lowered.contains("401") || lowered.contains("403") || lowered.contains("unauthorized") || lowered.contains("forbidden") {
            return lang == .english
                ? "Type: Authentication failed\nCredential is invalid, expired, or unauthorized."
                : "类型：鉴权失败\n凭证无效、过期或权限不足。"
        }
        if lowered.contains("429") || lowered.contains("rate") {
            return lang == .english
                ? "Type: Rate limited\nPlease retry later."
                : "类型：触发频率限制\n请稍后重试。"
        }
        if lowered.contains("decode") || lowered.contains("json") || lowered.contains("parse") {
            return lang == .english
                ? "Type: Response parse failure\nProvider response schema may have changed."
                : "类型：响应解析失败\n可能是供应商返回结构发生变化。"
        }
        if lowered.contains("timed out") || lowered.contains("timeout") {
            return lang == .english
                ? "Type: Request timeout\nNetwork is slow or provider endpoint is overloaded."
                : "类型：请求超时\n可能是网络较慢或供应商接口拥塞。"
        }
        return lang == .english
            ? "Type: Unknown failure\n\(error.localizedDescription)"
            : "类型：未知错误\n\(error.localizedDescription)"
    }

    private func classifyWrappedError(_ wrapped: Error, language: AppLanguage? = nil) -> String {
        let lang = language ?? self.language
        if let urlError = wrapped as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return lang == .english
                    ? "Type: Network unavailable\nPlease check internet connection."
                    : "类型：网络不可用\n请检查网络连接。"
            case .timedOut:
                return lang == .english
                    ? "Type: Request timeout\nProvider did not respond in time."
                    : "类型：请求超时\n供应商接口响应超时。"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return lang == .english
                    ? "Type: Endpoint unreachable\nPlease check network/proxy/DNS."
                    : "类型：接口不可达\n请检查网络、代理或 DNS。"
            default:
                return lang == .english
                    ? "Type: Network error\n\(wrapped.localizedDescription)"
                    : "类型：网络错误\n\(wrapped.localizedDescription)"
            }
        }

        let nsError = wrapped as NSError
        if nsError.domain == NSURLErrorDomain {
            return lang == .english
                ? "Type: Network error\n\(wrapped.localizedDescription)"
                : "类型：网络错误\n\(wrapped.localizedDescription)"
        }

        // Many providers wrap auth/schema/business failures into a custom NSError
        // (domain != NSURLErrorDomain), so classify them as provider/API failures.
        let lowered = wrapped.localizedDescription.lowercased()
        if lowered.contains("auth") || lowered.contains("token") || lowered.contains("key") || lowered.contains("permission") {
            return lang == .english
                ? "Type: Authentication/permission failure\n\(wrapped.localizedDescription)"
                : "类型：鉴权或权限失败\n\(wrapped.localizedDescription)"
        }
        return lang == .english
            ? "Type: Provider/API failure\n\(wrapped.localizedDescription)"
            : "类型：供应商接口失败\n\(wrapped.localizedDescription)"
    }
}
