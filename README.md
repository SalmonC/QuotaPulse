# API Usage Tracker for Mac

A macOS menu bar application for tracking API usage quotas from various AI providers. Monitor your remaining credits, usage, and plan limits directly from the menu bar or desktop widget.

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014.0+-blue" alt="Platform">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/version-1.0.13-blue" alt="Version">
</p>

---

## 📖 Language / 语言

- [English](#english)
- [中文](#中文)

---

<a name="english"></a>
## 🇺🇸 English

### Features

#### Core Functionality
- **Menu Bar Interface** - Quick access to API usage from the menu bar
- **Desktop Widgets** - View usage on your desktop (small, medium, large sizes; source retained, temporarily disabled in distribution builds)
- **Auto Refresh** - Configurable automatic refresh interval (1-60 minutes)
- **Pinned Menu Bar Values** - Optionally show selected DeepSeek/Codex values next to the menu bar icon with custom labels
- **Global Hotkey** - Show/hide window with customizable keyboard shortcut
- **Test Connection** - Verify API keys before saving
- **Low Usage Alerts** - System notifications when usage exceeds the configured threshold
- **In-app Update Check** - Sparkle-based stable update check in Settings > General

#### Security
- **Keychain Storage** - API keys are securely stored in macOS Keychain

#### Supported Providers
| Provider | Type | Features |
|----------|------|----------|
| **MiniMax** | Token Plan | Official Token Plan remaining quota |
| **Tavily** | Credits | Search quota tracking |
| **OpenAI** | Organization Costs | Official Costs API via Admin Key |
| **KIMI** | Balance | Official Moonshot balance tracking |
| **DeepSeek** | Balance | Official account balance tracking |
| **Codex** | Local Login | Local Codex quota windows |

#### UI/UX
- **Collapsible Dashboard** - Expand/collapse accounts to see details
- **Usage Progress** - Visual progress bars showing usage percentage
- **DeepSeek Balance Trend** - Optional daily balance trend based on the last query of each day
- **Codex Reset Time** - Shows the next reset time point for 5-hour and weekly quota windows
- **Codex API Equivalent Value** - Shows verified paid Coding Plan text usage as a 3/7/14/30-day USD value chart using current official API prices; prices update daily from a validated remote catalog with cached and built-in fallback, while token details remain hidden
- **Color-coded Status** - Green/Orange/Red based on usage level
- **Error Handling** - Clear error messages with retry options

### Requirements

- macOS 14.0 (Sonoma) or later

### Installation

#### From Release
1. Download the latest `.dmg` from [Releases](https://github.com/SalmonC/ApiUsageTrackerForMac/releases)
2. Open the `.dmg` file
3. Drag `QuotaPulse.app` to Applications
4. Launch the app

#### From Source
```bash
# Clone repository
git clone https://github.com/SalmonC/ApiUsageTrackerForMac.git
cd ApiUsageTrackerForMac

# Generate Xcode project
xcodegen generate

# Build
xcodebuild -project ApiUsageTrackerForMac.xcodeproj -scheme ApiUsageTrackerForMac -configuration Release build

# Create DMG (optional)
APP_PATH=~/Library/Developer/Xcode/DerivedData/ApiUsageTrackerForMac-*/Build/Products/Release/QuotaPulse.app
hdiutil create -srcfolder "$APP_PATH" -volname "QuotaPulse" -fs HFS+ -format UDZO QuotaPulse.dmg
```

For Sparkle release/appcast workflow, see:
`scripts/release/README.md`

For a stable local signature and login Keychain access, use:

```bash
INSTALL=1 ./scripts/build-secure-local-release.sh
```

The script prefers a Developer ID Application identity when available, otherwise
uses the local Apple Development identity. A Developer ID plus notarization is still
required for normal public distribution without Gatekeeper warnings.

### Automated Verification (No Manual Install)

```bash
./scripts/auto-verify.sh
```

This script will automatically:
- build the app
- package `API-Tracker-latest.dmg`
- quit current running app instance
- mount DMG and launch app from DMG
- run startup/health/crash checks

Optional environment variables:
- `CONFIGURATION=Debug|Release`
- `HEALTH_CHECK_SECONDS=8`
- `LAUNCH_TIMEOUT_SECONDS=20`
- `PRINT_APP_LOG_TAIL=1` (disabled by default)

### Configuration

1. Click the menu bar icon
2. Click the **Settings** gear icon
3. Add API accounts:
   - Click **+** to add a new account
   - Select provider (MiniMax, Tavily, OpenAI, KIMI, DeepSeek, or Codex)
   - Enter your API key
   - Click **Test Connection** to verify
   - Configure display preferences (show/hide in menu bar)
4. Click **Save**

### Getting API Keys

- **MiniMax**: [MiniMax Platform](https://www.minimax.io/platform) → API Keys for a Token Plan account
- **Tavily**: [Tavily Dashboard](https://app.tavily.com) → API Keys
- **OpenAI**: [OpenAI Platform](https://platform.openai.com/settings/organization/admin-keys) → Organization Admin Keys
- **KIMI**: [Moonshot Platform](https://platform.moonshot.cn/console/api-keys) → API Keys
- **DeepSeek**: [DeepSeek Platform](https://platform.deepseek.com/api_keys) → API Keys
- **Codex**: Install Codex CLI, run `codex login`, then complete at least one Codex session. No credential is pasted into QuotaPulse.

### Usage

#### Menu Bar
- **Left-click**: Open usage dashboard
- **Right-click**: Context menu (Refresh, Settings, About, Quit)

#### Dashboard
- Expand/collapse rows by clicking the chevron icon
- View remaining credits, used amount, and total quota
- Progress bars show usage percentage

#### Desktop Widget
1. Right-click on desktop → "Edit Widgets"
2. Search for "API Usage"
3. Add preferred size widget

### Keyboard Shortcuts

- **Global Hotkey**: Default is `⌘⇧Space` (configurable in Settings)

---

<a name="中文"></a>
## 🇨🇳 中文

### 功能特性

#### 核心功能
- **菜单栏界面** - 从菜单栏快速查看 API 用量
- **桌面小组件** - 在桌面上查看用量（小、中、大三种尺寸；代码保留，分发构建中暂时关闭）
- **自动刷新** - 可配置的自动刷新间隔（1-60 分钟）
- **菜单栏固定数据** - 可将 DeepSeek/Codex 指定数据以自定义文本固定显示在菜单栏图标旁
- **全局快捷键** - 可自定义的快捷键显示/隐藏窗口
- **连接测试** - 保存前验证 API Key 是否有效
- **用量提醒** - 用量超过自定义阈值时发送系统通知
- **应用内检查更新** - 在设置 > 通用中使用 Sparkle 检查正式版更新

#### 安全性
- **钥匙串存储** - API Key 安全存储在 macOS 钥匙串中

#### 支持的提供商
| 提供商 | 类型 | 功能 |
|--------|------|------|
| **MiniMax** | Token Plan | 官方 Token Plan 余量查询 |
| **Tavily** | 额度 | 搜索配额追踪 |
| **OpenAI** | 组织 Costs | 通过 Admin Key 调用官方 Costs API |
| **KIMI** | 余额 | Moonshot 官方余额查询 |
| **DeepSeek** | 余额 | 官方账户余额查询 |
| **Codex** | 本机登录 | 本机 Codex 额度周期 |

#### 界面设计
- **可折叠仪表盘** - 展开/折叠账户查看详情
- **DeepSeek 余额趋势** - 可选展示每日余额趋势，每天采用当天最后一次查询结果
- **Codex 刷新时间点** - 5 小时额度与周额度展示下一次刷新的具体时间点
- **Codex API 等价价值** - 将可核验的付费 Coding Plan 文本用量按当前官方 API 美元单价折算，支持 3/7/14/30 天按日图表；价格每日自动检查，并提供缓存和内置兜底，且不展示 Token 明细
- **用量进度条** - 可视化显示用量百分比
- **颜色编码状态** - 根据用量级别显示绿/橙/红色
- **错误处理** - 清晰的错误信息和重试选项

### 系统要求

- macOS 14.0 (Sonoma) 或更高版本

### 安装方法

#### 从 Release 安装
1. 从 [Releases](https://github.com/SalmonC/ApiUsageTrackerForMac/releases) 下载最新的 `.dmg` 文件
2. 打开 `.dmg` 文件
3. 将 `QuotaPulse.app` 拖到应用程序文件夹
4. 启动应用

#### 从源码编译
```bash
# 克隆仓库
git clone https://github.com/SalmonC/ApiUsageTrackerForMac.git
cd ApiUsageTrackerForMac

# 生成 Xcode 项目
xcodegen generate

# 编译
xcodebuild -project ApiUsageTrackerForMac.xcodeproj -scheme ApiUsageTrackerForMac -configuration Release build

# 创建 DMG（可选）
APP_PATH=~/Library/Developer/Xcode/DerivedData/ApiUsageTrackerForMac-*/Build/Products/Release/QuotaPulse.app
hdiutil create -srcfolder "$APP_PATH" -volname "QuotaPulse" -fs HFS+ -format UDZO QuotaPulse.dmg
```

Sparkle 发布 / appcast 流程见：
`scripts/release/README.md`

需要稳定的本机签名与登录钥匙串访问时，使用：

```bash
INSTALL=1 ./scripts/build-secure-local-release.sh
```

脚本优先使用 Developer ID Application；若本机没有，则使用本机 Apple Development
身份。要实现面向公众且无 Gatekeeper 警告的正规分发，仍需 Developer ID 与公证。

### 自动验证（无需手动安装）

```bash
./scripts/auto-verify.sh
```

脚本会自动完成：
- 编译应用
- 打包 `API-Tracker-latest.dmg`
- 退出当前正在运行的应用
- 挂载 DMG 并从 DMG 启动应用
- 执行启动/健康度/崩溃检测

可选环境变量：
- `CONFIGURATION=Debug|Release`
- `HEALTH_CHECK_SECONDS=8`
- `LAUNCH_TIMEOUT_SECONDS=20`
- `PRINT_APP_LOG_TAIL=1`（默认关闭）

### 配置说明

1. 点击菜单栏图标
2. 点击**设置**齿轮图标
3. 添加 API 账户：
   - 点击 **+** 添加新账户
   - 选择提供商（MiniMax、Tavily、OpenAI、KIMI、DeepSeek 或 Codex）
   - 输入 API Key
   - 点击**测试连接**验证有效性
   - 配置显示偏好（在菜单栏中显示/隐藏）
4. 点击**保存**

### 获取 API Key

- **MiniMax**: [MiniMax 平台](https://www.minimax.io/platform) → 已开通 Token Plan 账号的 API Keys
- **Tavily**: [Tavily 控制台](https://app.tavily.com) → API Keys
- **OpenAI**: [OpenAI 平台](https://platform.openai.com/settings/organization/admin-keys) → 组织 Admin Keys
- **KIMI**: [Moonshot 平台](https://platform.moonshot.cn/console/api-keys) → API Keys
- **DeepSeek**: [DeepSeek 平台](https://platform.deepseek.com/api_keys) → API Keys
- **Codex**: 安装 Codex CLI，运行 `codex login` 并至少完成一次 Codex 会话；无需在 QuotaPulse 粘贴凭证。

### 使用说明

#### 菜单栏
- **左键点击**：打开用量仪表盘
- **右键点击**：上下文菜单（刷新、设置、关于、退出）

#### 仪表盘
- 点击箭头图标展开/折叠行
- 查看剩余额度、已用量和总额度
- 进度条显示用量百分比

#### 桌面小组件
1. 右键桌面 → "编辑小组件"
2. 搜索 "API Usage"
3. 添加喜欢的小组件尺寸

### 键盘快捷键

- **全局快捷键**：默认 `⌘⇧Space`（可在设置中配置）

---

## Changelog / 更新日志

### v1.0.13 (2026-08-20)

- **Fix / 修复**: Treat DeepSeek `is_available=false` as a valid exhausted-balance state and keep the account visible at zero instead of reporting an authentication failure / 将 DeepSeek `is_available=false` 按官方语义视为余额不足，余额为零时仍保留账号卡片，不再误报鉴权失败
- **Fix / 修复**: Repair stale launch-at-login registrations that still point to a DerivedData test build, so the installed app and its newer features reliably launch after sign-in / 自动修复仍指向 DerivedData 测试版的开机启动项，确保登录后启动已安装的正式版及新功能
- **UI / 界面**: Reorganize Settings into General, Display, and API Accounts with clearer grouping, progressive disclosure, and shorter descriptions / 将设置重组为“通用 / 显示 / API 账号”，优化分组、渐进展开与文案密度

### v1.0.12 (2026-08-14)

- **New / 新增**: Add optional daily Codex Coding Plan API-equivalent value for 3, 7, 14, or 30 days, showing only USD value rather than token details / 新增可选的 Codex Coding Plan 每日 API 等价价值，支持 3、7、14、30 天范围，仅显示美元价值而不展示 Token 明细
- **Accuracy / 准确性**: Count only records that explicitly identify a paid Coding Plan, calculate per-branch cumulative deltas, and skip replayed parent history in forked/sub-agent logs / 仅统计明确标识为付费 Coding Plan 的记录，按任务分支计算累计差值，并跳过 fork/子 agent 日志中回放的父任务历史
- **Safety / 安全口径**: Unknown models, unverifiable records, missing cache-write telemetry, deleted logs, and other-device usage are never guessed; affected values are shown as conservative lower bounds / 未知模型、无法核验记录、缺失的缓存写入遥测、已删除日志及其他设备用量均不猜测，受影响时以保守下界展示
- **Performance / 性能**: Stream the first local index with bounded memory, then read only appended JSONL bytes; the 10-second quota retry path does not rescan usage logs / 首次索引采用固定内存流式读取，后续仅读取 JSONL 新增字节，10 秒额度短重试不会重复扫描日志

### v1.0.11 (2026-08-11)

- **Compatibility / 兼容性**: Restore the established preferences domain so existing accounts, cached usage, history, menu bar pins, and settings remain available after upgrading / 恢复既有偏好域，升级后继续保留账号、缓存用量、历史、菜单栏固定项与设置
- **Security / 安全**: Use the macOS login Keychain with a stable signed identity and Hardened Runtime, avoiding unsupported Personal Team App Group/Data Protection entitlements that caused empty accounts and Keychain error `-34018` / 使用稳定签名身份、Hardened Runtime 与 macOS 登录钥匙串，避开个人团队无法正确授权、会导致账号为空及钥匙串 `-34018` 的 App Group/Data Protection entitlement

### v1.0.10 (2026-08-11)

- **Security / 安全**: Move API keys to the macOS Data Protection Keychain while retaining device-only, after-first-unlock background access / 将 API Key 迁移到 macOS Data Protection Keychain，同时保留仅限本机、首次解锁后可后台读取的策略
- **Migration / 迁移**: Legacy storage is read only when the v3 item is genuinely absent; authorization failures no longer cause a second fallback query, and the legacy snapshot is retained for v1.0.9 rollback / 仅在 v3 条目确实不存在时读取旧存储，授权失败不再触发第二次回查，并保留旧快照供 v1.0.9 回滚
- **Reliability / 可靠性**: Verify complete keyring writes, keep an empty v3 tombstone, fail closed on unreadable storage, and show settings-save failures instead of silently losing credentials / 校验完整 Keyring 写入、保留空 v3 墓碑、存储不可读时拒绝覆盖，并明确显示设置保存失败
- **Signing / 签名**: Add a stable local signing and packaging workflow with Hardened Runtime and explicit signature verification / 增加稳定的本机签名、Hardened Runtime、打包与签名校验流程

### v1.0.9 (2026-07-14)

- **Fix / 修复**: DeepSeek dashboard and menu bar pinned balance now fall back to the last cached balance when the latest query fails or older cache lacks detailed currency records / DeepSeek 查询失败或旧缓存缺少币种明细时，看板与菜单栏固定余额会回退显示上次缓存余额
- **Improve / 优化**: Query failure remains visible on the dashboard while cached DeepSeek balance is preserved / 保留 DeepSeek 缓存余额显示的同时，在看板继续标注查询失败

### v1.0.8 (2026-07-13)
- **Fix / 修复**: Codex quota parsing now classifies windows by duration, so weekly-only responses no longer appear as 5-hour remaining quota in the menu bar / Codex 额度解析改为按窗口时长分类，只有周额度时不再把周余量误显示为菜单栏 5 小时余量
- **Improve / 优化**: Unsupported pinned menu bar values are omitted until the provider returns that metric again / 不支持的菜单栏固定数据会默认隐藏，待供应商恢复对应指标后自动正常显示
- **Verify / 验证**: Passed unit tests, Release build, installer DMG creation, local replacement install, and launch verification / 已通过单元测试、Release 构建、安装器 DMG 生成、本地替换安装与启动验证

### v1.0.7 (2026-07-06)
- **Fix / 修复**: Prevent startup refresh from overwriting cached dashboard data and DeepSeek balance history when settings or Keychain credentials are temporarily unavailable / 当设置或钥匙串凭证临时不可用时，启动刷新不再用空结果覆盖看板缓存与 DeepSeek 余额历史
- **Improve / 优化**: Add rate-limited critical logs for App Group storage, settings decoding, Keychain loading, and cache-preservation guards without recording API keys / 为 App Group 存储、设置解码、钥匙串读取与缓存保护增加限量关键错误日志，且不记录 API Key
- **Verify / 验证**: Passed unit tests, Release build, installer DMG creation, local replacement install, and launch verification / 已通过单元测试、Release 构建、安装器 DMG 生成、本地替换安装与启动验证

### v1.0.6 (2026-07-03)
- **Fix / 修复**: Provider query failures now keep displaying the last successful data in the dashboard and menu bar, with a query-failed badge on the dashboard card / 供应商查询失败时，看板与菜单栏继续显示上一次成功数据，并在看板卡片上标注查询失败
- **Improve / 优化**: Failed providers enter a short 10-second retry cadence and return to the normal refresh schedule after success or three consecutive retry failures / 查询失败的供应商进入 10 秒短重试节奏，成功或连续 3 次重试失败后恢复原有刷新节奏
- **Change / 调整**: Removed the unfinished phone-sync implementation from the Mac app codebase / 移除未完成的手机同步实现
- **Verify / 验证**: Passed unit tests, Release build, installer DMG creation, local replacement install, and launch verification / 已通过单元测试、Release 构建、安装器 DMG 生成、本地替换安装与启动验证

### v1.0.5 (2026-07-02)
- **New / 新增**: Add optional menu bar pinned values for DeepSeek balance, Codex 5-hour remaining quota, and Codex weekly remaining quota, each with custom label text / 新增菜单栏固定数据展示，支持 DeepSeek 余额、Codex 5 小时余量与 Codex 周余量，并可自定义前缀文本
- **Change / 调整**: Codex dashboard reset rows now show the next refresh time point instead of a relative countdown, matching the Codex app display style / Codex 看板刷新行改为显示下一次刷新的具体时间点，不再显示相对倒计时，与 Codex 应用展示逻辑一致
- **Fix / 修复**: DeepSeek balance trend now uses the last query of each day and avoids clipping delta labels near chart boundaries / DeepSeek 余额趋势改为采用每天最后一次查询结果，并修复靠近图表边界时变化值被裁切的问题
- **Improve / 优化**: Settings adds a dedicated Menu Bar section and keeps pinned value updates based on existing refresh data without extra provider requests / 设置页新增“菜单栏”配置区，固定数据仅使用既有刷新结果，不增加供应商请求
- **Verify / 验证**: Passed unit tests, app/widget builds, and automated DMG startup verification / 已通过单元测试、应用与小组件构建、DMG 自动启动验证

### v1.0.2 (2026-03-12)
- **Fix / 修复**: Stabilized popover anchoring so the dashboard opens from the menu bar icon instead of occasionally drifting to an unrelated desktop position / 修复看板锚点定位，避免偶发从菜单栏图标脱离并出现在桌面错误位置
- **Verify / 验证**: Passed automated startup packaging check with `./scripts/auto-verify.sh` in addition to unit tests and Release build / 除单元测试与 Release 构建外，额外通过 `./scripts/auto-verify.sh` 自动启动打包验证

### v1.0.1 (2026-03-05)
- **Fix / 修复**: Stabilized account name editing in Settings with reliable commit on blur (inside/outside app) and enter / 修复设置页账号名称编辑，支持应用内外失焦与回车稳定提交
- **Fix / 修复**: Dashboard applies name changes only after clicking Save Settings while keeping immediate draft preview in Settings / 看板仅在点击“保存设置”后应用名称，设置页仍保持草稿即时预览
- **Fix / 修复**: Removed refresh-time scrollbar flicker by locking list indicators off and reducing popover height micro-jitter / 通过固定隐藏滚动条并收敛高度微抖，消除刷新时滚动条闪烁
- **Improve / 优化**: Unified sorting logic between app and widget to reduce inconsistent ordering / 抽取共享排序逻辑，减少应用与小组件排序不一致

### v1.0.0 (2026-03-04)
- **Release / 发布**: First stable release of QuotaPulse / QuotaPulse 首个稳定正式版
- **Update / 更新**: Settings adds GitHub stable release check and README quick access / 设置页新增 GitHub 正式版检查与 README 快速入口
- **Distribution / 分发**: Unsigned DMG + ZIP release artifacts with improved installer window / 提供未签名 DMG + ZIP，优化安装窗口引导
- **Note / 说明**: If first launch is blocked by macOS, allow from Privacy & Security / 若首次启动被系统拦截，请在“隐私与安全性”中放行

### v1.3.1 (2026-02-26)
- **Change / 调整**: Temporarily disable desktop widget embedding in app distribution builds / 临时关闭应用分发构建中的桌面小组件嵌入
  - Widget source code remains in repository for future re-enable / 仓库中保留小组件代码，后续可恢复
  - Reason: App Group access may fail under Personal Team signing in local distribution/debugging / 原因：个人团队签名下本地分发/调试时 App Group 访问可能失败

### v1.3.0 (2026-02-25)
- **New / 新增**: Add KIMI (Moonshot AI) support / 添加 KIMI (Moonshot) 支持
  - Monthly quota tracking / 月度额度追踪
  - Monthly usage statistics / 月度使用统计
  - Refresh time display / 刷新时间显示
- **Fix / 修复**: Improved GLM API data parsing with multiple fallback endpoints / 改进 GLM API 数据解析，添加多个备用端点
- **Improve / 优化**: Popover height now adjusts when expanding/collapsing items / 点击展开/折叠时看板高度动态调整
- **Improve / 优化**: Redesigned UsageService protocol with UsageResult struct / 重新设计 UsageService 协议，使用 UsageResult 结构体
- **Improve / 优化**: Added monthly quota display for all providers / 为所有提供商添加月度额度显示

### v1.2.1 (2026-02-25)
- **Fix / 修复**: GLM Token query returning 0 / GLM Token 余量查询返回 0 的问题
  - Added user info API as primary source / 添加 user info API 作为主要数据来源
  - Improved number parsing for various formats / 改进多种格式的数字解析
- **New / 新增**: Dynamic popover height adjustment / 看板高度根据内容实时调整
  - Height adapts to data count and content / 高度根据数据量和内容自适应
- **Improve / 优化**: Redesigned collapsed/expanded view / 重新设计折叠/展开视图
  - Collapsed: Compact with mini progress ring / 折叠：紧凑布局带迷你进度环
  - Expanded: Detailed stats grid with visual hierarchy / 展开：详细统计网格和视觉层级

### v1.2.0 (2026-02-25)
- **New / 新增**: Add OpenAI API support / 添加 OpenAI API 支持
- **New / 新增**: API Key storage migrated to Keychain / API Key 迁移到钥匙串存储
- **New / 新增**: Add "Test Connection" button / 添加"测试连接"按钮
- **New / 新增**: System notifications for high usage / 高用量时发送系统通知
- **Improve / 优化**: Optimized Logger with buffered writes / 优化 Logger 使用缓冲写入

### v1.1.1 (2026-02-25)
- **Fix / 修复**: Timer memory leak / 修复 Timer 内存泄漏
- **Fix / 修复**: Refresh interval not taking effect / 修复刷新间隔不生效问题
- **Fix / 修复**: Popover recreation memory leak / 修复 Popover 重复创建内存泄漏
- **Fix / 修复**: Widget refresh interval now follows settings / Widget 刷新间隔跟随设置

### v1.1.0 (2026-02-18)
- **New / 新增**: Add Tavily API support / 添加 Tavily API 支持
- **New / 新增**: Auto-detect MiniMax API type / 自动检测 MiniMax API 类型
- **New / 新增**: Auto-detect GLM platform / 自动检测 GLM 平台

---

## License / 许可证

MIT License - See [LICENSE](LICENSE) for details / 查看 [LICENSE](LICENSE) 了解详情

## Acknowledgments / 致谢

- [MiniMax](https://platform.minimaxi.com) - API usage data
- [Z.ai / BigModel](https://z.ai) - GLM API
- [Tavily](https://tavily.com) - Search API credits
- [OpenAI](https://openai.com) - GPT API

---

Built with SwiftUI and WidgetKit for macOS / 使用 SwiftUI 和 WidgetKit 为 macOS 构建
