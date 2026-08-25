# API Usage Tracker for Mac - Agent Guide

## Project Identity and Delivery Contract

This section is authoritative for build, install, startup, persistence, and
release work. Read the global delivery standard at
`/Users/salmonc/.codex/standards/DEVELOPMENT_DELIVERY_STANDARD.md` before any
such operation.

- **Product/display name**: QuotaPulse
- **Canonical installed app**: `/Applications/QuotaPulse.app`
- **Executable/process name**: `QuotaPulse`
- **Main Bundle ID**: `com.mactools.apiusagetracker`
- **Widget Bundle ID**: `com.mactools.apiusagetracker.widget`
- **App Group**: `group.com.mactools.apiusagetracker`
- **Authoritative version source**: `VERSION`; `project.yml` and the generated
  Xcode project must match it.
- **Build policy**: increment `BUILD` for every candidate installed over an
  earlier build, even when the marketing version is unchanged.
- **Project generator**: `project.yml` via XcodeGen. Do not hand-edit generated
  project settings.
- **Secure package/install entry point**:
  `INSTALL=1 ./scripts/build-secure-local-release.sh`
- **Artifact directory**: `Artifacts/v$VERSION/`; differing builds must not
  silently overwrite a formal artifact with the same name. Include the build
  number or archive the old artifact first.
- **Signing identity**: the secure release script must preserve the installed
  app's Team ID and designated requirement unless a migration is explicitly
  authorized.
- **Startup mechanism**: `SMAppService.mainApp`; only the canonical installed
  app may register. Debug/test bundles must never register.
- **Settings/cache namespace**: the App Group UserDefaults suite above.
- **Credential storage**: Keychain via `KeychainManager`; Keychain service,
  account format, signing identity, and migration markers are persistent
  identity contracts.
- **Standing project instruction**: after a requested code change is completed,
  package, replace the old canonical app, install, and launch the new build.
  Archive the previous known-good formal artifact for rollback and delete
  disposable Debug/test app bundles. This standing instruction does not permit
  deleting user data, unknown app copies, or unrelated startup items.

### Required pre/post-install evidence

Before replacement, inventory matching QuotaPulse processes, normal install
locations, project-owned startup items, installed version/build, signature, and
the rollback artifact. After installation verify:

- `/Applications/QuotaPulse.app` has the intended Bundle ID and version/build;
- the main app and widget versions/builds agree;
- signing Team ID and designated requirement are stable;
- exactly the expected QuotaPulse process maps to the canonical executable;
- the project-owned startup item, if enabled, points to the canonical app;
- existing accounts, credentials, cached data, and history remain readable; and
- no DerivedData/test app is running or registered for startup.

Do not identify the target through the display name alone. Unknown copies are
reported and left untouched until authorized.

## Project Overview

**QuotaPulse** is a macOS menu bar application that tracks balances and quota
windows from supported AI/API providers. It provides a menu bar dashboard,
pinned menu bar values, settings, notifications, and a widget target.

- **Bundle ID**: `com.mactools.apiusagetracker`
- **App Group**: `group.com.mactools.apiusagetracker`
- **Minimum macOS**: 14.0 (Sonoma)
- **Swift Version**: 5.9
- **Xcode Version**: 15.0+

## Project Structure

```
MacUsageTracker/
├── project.yml                  # XcodeGen project configuration
├── VERSION                      # Authoritative marketing version and build
├── README.md                    # User documentation (English/Chinese)
├── Sources/
│   ├── App/                     # Main application target
│   │   ├── MacUsageTrackerApp.swift      # App entry point & AppDelegate
│   │   ├── ViewModels/
│   │   │   └── AppViewModel.swift        # Main view model & business logic
│   │   ├── Views/
│   │   │   ├── MainView.swift            # Menu bar popover UI
│   │   │   └── SettingsView.swift        # Settings window UI
│   │   └── Resources/
│   │       ├── Info.plist                # App Info.plist
│   │       └── ApiUsageTrackerForMac.entitlements  # App sandbox entitlements
│   ├── Shared/                  # Shared code between app and widget
│   │   ├── Models/
│   │   │   └── SharedModels.swift        # Data models, storage, settings
│   │   ├── Services/
│   │   │   └── MiniMaxService.swift      # API service implementations
│   │   └── Security/
│   │       └── KeychainManager.swift     # API key secure storage wrapper
│   └── Widget/                  # Widget extension target
│       ├── UsageWidget.swift             # WidgetKit implementation
│       ├── Info.plist                    # Widget Info.plist
│       └── UsageWidget.entitlements      # Widget entitlements
└── ApiUsageTrackerForMac.xcodeproj/      # Generated Xcode project
```

## Technology Stack

- **Language**: Swift 5.9
- **UI Framework**: SwiftUI
- **Platform**: macOS 14.0+
- **Project Generation**: XcodeGen (configured via `project.yml`)
- **Data Persistence**: UserDefaults with App Groups
- **Architecture**: MVVM (Model-View-ViewModel)

## Build System

The project uses **XcodeGen** for project file generation. Do not manually edit `.xcodeproj` files.

### Build Commands

```bash
# Generate Xcode project from project.yml
xcodegen generate

# Build Debug version
xcodebuild -project ApiUsageTrackerForMac.xcodeproj \
  -scheme ApiUsageTrackerForMac \
  -configuration Debug build

# Build Release version
xcodebuild -project ApiUsageTrackerForMac.xcodeproj \
  -scheme ApiUsageTrackerForMac \
  -configuration Release build

# Create DMG (after building)
APP_PATH=~/Library/Developer/Xcode/DerivedData/ApiUsageTrackerForMac-*/Build/Products/Debug/API\ Tracker.app
hdiutil create -srcfolder "$APP_PATH" -volname "ApiUsageTrackerForMac" -fs HFS+ -format UDZO ApiUsageTrackerForMac.dmg
```

### Key Build Settings

- **App Target**: `ApiUsageTrackerForMac` (type: application)
- **Widget Target**: `UsageWidget` (type: app-extension)
- **Code Signing**: unsigned/ad-hoc for isolated development builds; formal
  local packages are signed by `build-secure-local-release.sh` with a stable
  identity and identity-drift checks.
- **Sandbox**: Enabled with network client and app group capabilities

## Architecture Details

### Targets

1. **ApiUsageTrackerForMac** (Main App)
   - Menu bar only app (`LSUIElement: YES` - no dock icon)
   - Popover interface from status bar
   - Settings window for configuration
   - Global hotkey support (default: ⌘⇧Space)

2. **UsageWidget** (App Extension)
   - WidgetKit-based desktop widgets
   - Supports small, medium, and large sizes
   - Shares data via App Group UserDefaults

### Core Components

| Component | Purpose |
|-----------|---------|
| `AppDelegate` | Menu bar setup, global hotkeys, window management |
| `AppViewModel` | Business logic, API fetching, data caching |
| `MainView` | Menu bar popover UI |
| `SettingsView` | Account management and app preferences |
| `Storage` | UserDefaults wrapper with JSON encoding |
| `UsageService` | Protocol for API provider implementations |

### Data Flow

```
SettingsView → AppViewModel → Storage (UserDefaults)
                    ↓
              [API Services] → WidgetCenter.reloadAllTimelines()
                    ↓
               MainView ← UsageData[]
```

## Supported API Providers

| Provider | Endpoint Pattern | Features |
|----------|-----------------|----------|
| **MiniMax** | Official MiniMax endpoints | Coding Plan / supported quota data |
| **Tavily** | Official Tavily endpoint | Credit quota tracking |
| **OpenAI API** | Official OpenAI organization usage/cost endpoints | API usage/cost tracking |
| **Kimi** | Official Moonshot balance endpoints | Balance tracking |
| **DeepSeek** | Official DeepSeek balance endpoint | Currency balance and local daily trend |
| **Codex** | Local Codex account/session data | Quota windows and conservative API-equivalent value |

## Code Style Guidelines

### Swift Conventions

- Use `@MainActor` for UI-related classes
- Prefer `async/await` for asynchronous operations
- Use `ObservableObject` with `@Published` for state management
- Follow Swift naming conventions (camelCase for variables/functions, PascalCase for types)

### Error Handling

- Custom `APIError` enum for API-related errors
- Error messages in Chinese for user-facing errors
- Logging via `Logger.log()` (writes to `~/Documents/api_tracker.log`)

### Example Pattern

```swift
// Service protocol
protocol UsageService {
    var provider: APIProvider { get }
    func fetchUsage(apiKey: String) async throws -> (remaining: Double?, used: Double?, total: Double?, refreshTime: Date?)
}

// ViewModel pattern
@MainActor
final class AppViewModel: ObservableObject {
    @Published var usageData: [UsageData] = []
    @Published var isLoading = false
    
    func refreshAll() async {
        isLoading = true
        // ... fetch logic
        isLoading = false
    }
}
```

## Data Models

### Core Types

```swift
APIProvider: Enum  // miniMax, glm, tavily
APIAccount: Struct // id, name, provider, apiKey, isEnabled
AppSettings: Struct // accounts, refreshInterval, hotkey
UsageData: Struct   // account info + usage statistics
HotkeySetting: Struct // keyCode, modifiers
```

### Storage

- **App Group**: `group.com.mactools.apiusagetracker`
- **Non-secret state**: App Group UserDefaults, JSON-encoded where applicable.
- **API keys/credentials**: Keychain through `KeychainManager`; never describe
  them as plain UserDefaults storage.
- Persistent suite names, keys, Keychain service/account/access group, and
  migration markers are compatibility contracts. Changes require the global
  L3 migration workflow.

## Development Notes

### Adding a New API Provider

1. Add case to `APIProvider` enum in `Sources/Shared/Models/SharedModels.swift`
2. Implement `UsageService` protocol in `Sources/Shared/Services/MiniMaxService.swift`
3. Add provider icon mapping
4. Update `getService(for:)` factory function

### Key Configuration Files

- `project.yml`: XcodeGen configuration (targets, settings, schemes)
- `Sources/App/Resources/Info.plist`: App metadata (LSUIElement enabled)
- `*.entitlements`: Sandbox and app group capabilities
- `VERSION`: Build version tracking (format: `VERSION=x.x.x\nBUILD=x`)

### UI Patterns

- Collapsible rows with chevron icons
- Color-coded usage status (green < 50%, orange 50-80%, red > 80%)
- Progress bars for visual usage indication
- "K" suffix for numbers >= 1000 (e.g., "1.5K")

## Verification Strategy

Use the global risk-based, minimal-sufficient workflow. This is a personal
utility; do not grow or run a broad suite by default.

- Pure UI/layout/text changes: build and inspect the canonical installed app;
  do not add automated tests by default.
- Local logic changes: run at most one directly relevant test case/target, then
  inspect the real installed behavior.
- Shared core changes: run only the related test group unless broad impact is
  demonstrated.
- Keychain, persistence, signing, login items, install/update, cleanup, and
  release changes: use targeted backups, identity/readback/rollback checks;
  high risk does not imply a general full suite.
- Tests must use isolated state and must not register the test app, access real
  credentials, or write production App Group data.
- The user's use of the canonical installed build is the primary acceptance
  test for visual quality, interaction, wording, and workflow semantics.

## Security Considerations

- API keys are stored in Keychain through `KeychainManager`.
- App Sandbox enabled with minimal entitlements
- Network client capability required for API calls
- No hardcoded API keys in source code

## Localization

- User-facing text is primarily in **Chinese** (e.g., "刷新" for Refresh, "设置" for Settings)
- Error messages from API services are also in Chinese

## Deployment

1. Update the authoritative `VERSION` and monotonic `BUILD`; make `project.yml`
   match and regenerate the Xcode project.
2. Commit the intended source state before a formal publication build.
3. Use `scripts/build-secure-local-release.sh`; do not invent a second package
   path or sign with a drifting identity.
4. For the standing local-install workflow, use `INSTALL=1` so the canonical
   app is replaced and relaunched, then perform the identity/data postflight.
5. Archive the previous known-good artifact and remove disposable Debug apps;
   never clean user data as part of artifact cleanup.
6. For GitHub publication, tag the exact source commit and upload the already
   verified artifact. Record its SHA-256 and verify the remote attachment before
   reporting the release.

## Dependencies

No external dependencies. Uses only Apple frameworks:
- SwiftUI
- WidgetKit
- ServiceManagement (for launch at login)
- Carbon (for global hotkeys)
- AppKit
