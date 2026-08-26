# QuotaPulse Project Rules

These rules apply only when a task inspects, changes, builds, installs, or
releases this repository. For unrelated questions, do not load further project
documentation merely because this is the current directory.

## Development essentials

- Product: QuotaPulse, a Swift 5.9 / SwiftUI macOS 14+ menu-bar app with a
  WidgetKit extension.
- Generate the Xcode project from `project.yml` with XcodeGen; never hand-edit
  generated project settings.
- Preserve unrelated work in a dirty tree. Tests must use isolated state and
  must not access production credentials, App Group data, login items, or the
  installed app.
- Use the global rule router's minimal verification budget. The user's use of
  the delivered app is the primary acceptance check for visual and workflow
  behavior; do not claim that acceptance before it occurs.
- Read `README.md` or source files only when the task needs their details.

## Stable project identity

- Canonical app: `/Applications/QuotaPulse.app`
- Executable: `QuotaPulse`
- Main Bundle ID: `com.mactools.apiusagetracker`
- Widget Bundle ID: `com.mactools.apiusagetracker.widget`
- App Group/settings namespace: `group.com.mactools.apiusagetracker`
- Credentials: Keychain through `KeychainManager`
- Startup: `SMAppService.mainApp`; Debug/test builds must never register
- Version authority: `VERSION`; `project.yml` and generated settings must match
- Formal entry point: `INSTALL=1 ./scripts/build-secure-local-release.sh`
- Canonical artifacts: `Artifacts/v$VERSION/`; build numbers must increase for
  installed candidates and different bytes must not reuse one artifact identity

These identifiers and persistence/signing details are compatibility contracts.
Do not change them without an explicit migration and rollback plan.

## Delivery trigger

Before installing, replacing or cleaning app copies, changing persistence or
credentials, touching startup behavior, packaging, signing, or publishing,
read `/Users/salmonc/.codex/standards/DEVELOPMENT_DELIVERY_STANDARD.md`.

Standing authorization: after a requested QuotaPulse code change is complete,
package, replace the old canonical app, install, and launch the new build using
the formal entry point. Retain one known-good rollback artifact and remove only
identified disposable Debug/test copies. Never delete user data, unknown app
copies, or unrelated startup items.

Before and after replacement, verify the canonical path, version/build, bundle
and widget identifiers, stable signing identity, PID-to-executable mapping,
startup entry when enabled, and readability of existing accounts, credentials,
cache, and history. Stop and report ambiguity rather than guessing.
