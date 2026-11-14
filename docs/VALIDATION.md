# Validation

## Automated checks

Run `swift test` on macOS. The correctness suite covers:

- Extracted T3 pooling, Cursor pool selection and reset-time units.
- Claude null sessions and model-specific weekly limits.
- Actual Claude/Codex transcript parsing, synthetic-record rejection and deduplication.
- Pricing availability, token accounting, provider filters and exact hourly cutoffs.
- Supported cache decoding and unsupported-version rejection.
- Account environment arrays and protected-reference handling.
- Cache reuse and preservation of newer locally parsed records.
- Unicode, invalid UTF-8, malformed JSON, chunk boundaries and partial writes.
- Native segmented-control action through to a redraw of the number region.
- Usage-curve silhouette and negative space, plus the 18-point native menu-bar template.

Documentation rendering is opt-in. `QUOTA_SCREENSHOT_DIRECTORY="$PWD/docs/screenshots" swift test --filter DocumentationScreenshots` produces all three panel screenshots using synthetic test records. No real accounts, usage files, credentials or provider requests are used by this renderer.

## Provider and platform scope

Development probes successfully read live Codex, Claude and Cursor quotas. Availability depends on the signed-in account, plan, CLI version and provider endpoint behavior. OpenCode Go has an implemented transport but is not verified working; its error banner is hidden and its diagnostic error remains.

Local release builds contain arm64 and x86_64 executables and pass `codesign --verify --strict` with an ad-hoc signature. Native views are rendered through NSHostingView. Apple Silicon runtime has been exercised; physical Intel runtime, notarization and sustained idle-energy use remain unverified.

Computer-use automation was unavailable during development. The in-process native control-to-render test passes, but it does not establish physical mouse behavior.

Cost remains an API-equivalent estimate. Cursor cost/token history uses T3’s saved event cache. See the README for coverage and limitations. No personal usage readings or account screenshots are included in this repository.


## Standalone accounts and localization, 2026-11-14

- 19 core/native tests passed; the documentation renderer and three live-provider tests are opt-in.
- Read-only live quota tests passed for local Claude Code, Codex and Cursor with the T3 directory absent. No sign-in tokens, account identifiers or usage totals are included in these logs or public screenshots.
- An isolated fixture used three Claude and three Codex CLI environments, returned six distinct account snapshots, and preserved each account’s quota in its provider pool. Fresh six-account browser authentication was not performed.
- Local transcript scanning and bundled model pricing were tested without a T3 installation. Account metadata permissions, corrupt-file preservation, removal without deleting sign-ins, Keychain configuration and Cursor decryption fixtures are covered.
- All seven translation tables have matching keys and format placeholders; regional language matching and English fallback are checked. Product/model names remain unchanged.
- Distribution builds remain ad-hoc signed and unnotarized. Intel compilation does not establish physical Intel runtime behavior.
