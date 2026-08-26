# QuotaPulse v1.0.13 Release Notes

Release date: 2026-08-26

## Highlights

- Added Codex API-equivalent value tracking. QuotaPulse converts locally
  verifiable paid Coding Plan text usage into a daily USD value using current
  official API prices, without displaying token details.
- Reorganized Settings to make account, dashboard, trend, menu bar, refresh,
  startup, and alert options easier to find.
- Restored dashboard entries when a provider has no current quota or balance,
  so exhausted DeepSeek accounts remain visible instead of disappearing.

## Fixes

- DeepSeek balance trends now preserve and display negative balances instead of
  clamping them to zero.
- Improved chart scaling and labels for negative and edge-of-range values.
- Kept cached provider data visible when a refresh fails, while still showing
  the failure state.
- Codex menu bar pins omit unavailable quota windows instead of substituting a
  different window's percentage.

## Behavior and privacy notes

- Codex equivalent value is an estimate for comparison with pay-as-you-go API
  pricing; it is not a billing statement.
- Codex usage is derived locally from eligible session records. QuotaPulse does
  not upload session content and does not display raw token counts.
- DeepSeek trends remain based on the last successful balance query of each day.

## Distribution notes

- Version: 1.0.13 (Build 37)
- The app is signed with the project's stable Apple Development identity to
  preserve local Keychain access. It is not Developer ID notarized, so macOS on
  another device may require approval in System Settings > Privacy & Security.
