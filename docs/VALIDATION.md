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
- Token-mark cutout geometry and the 18-point native menu-bar template.

Documentation rendering is opt-in. `QUOTA_SCREENSHOT_DIRECTORY="$PWD/docs/screenshots" swift test --filter DocumentationScreenshots` produces all three panel screenshots using synthetic test records. No real accounts, usage files, credentials or provider requests are used by this renderer.

## Provider and platform scope

Development probes successfully read live Codex, Claude and Cursor quotas. Availability depends on the signed-in account, plan, CLI version and provider endpoint behavior. OpenCode Go has an implemented transport but is not verified working; its error banner is hidden and its diagnostic error remains.

Local release builds contain arm64 and x86_64 executables and pass `codesign --verify --strict` with an ad-hoc signature. Native views are rendered through NSHostingView. Apple Silicon runtime has been exercised; physical Intel runtime, notarization and sustained idle-energy use remain unverified.

Computer-use automation was unavailable during development. The in-process native control-to-render test passes, but it does not establish physical mouse behavior.

Cost remains an API-equivalent estimate. Cursor cost/token history uses T3’s saved event cache. See the README for coverage and limitations. No personal usage readings or account screenshots are included in this repository.
