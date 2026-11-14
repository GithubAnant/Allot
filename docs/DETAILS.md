# Allot details

## Connect your tools

Sign in to the **Codex** and **Claude Code** CLIs normally. Allot discovers their default accounts. It also reads enabled provider instances and existing credentials from T3 Code’s default `~/.t3/userdata` directory. Set up custom accounts in T3, then refresh Allot.

| Provider | Subscription limits | Cost and tokens |
| --- | --- | --- |
| Codex | Live CLI app-server quota query | T3 records plus fresh local session scans |
| Claude | Live usage-only Claude Code SDK control request | T3 records plus fresh local project scans |
| Cursor | Live current-period quota using an existing T3 sign-in | T3’s saved account-usage cache |
| OpenCode Go | Experimental transport; not verified working | Available normalized T3 history |
| Other T3 providers | No implemented subscription-quota transport | Available normalized T3 history |

Gemini CLI, GitHub Copilot, Windsurf, Perplexity and standalone Grok subscription limits are **not implemented**. The app does not substitute developer API spending for subscription quota.

## What the numbers mean

- **Cost is an API-equivalent estimate, not your subscription bill.** Prices, aliases, filters and overrides come from T3’s local rate/settings files. Missing rates remain unpriced.
- Cursor limits refresh live. Cursor **cost/token history** updates when T3 syncs its account-usage cache; Allot does not fetch a new event ledger.
- Unavailable quota/reset data stays unavailable; it is never presented as a measured zero or an invented reset time.
- The OpenCode error banner is hidden. Its underlying connection error is still available in diagnostics.
- Account management remains in the CLI/T3. Refresh-interval settings and notification preferences are outside this minimal Usage-tab port.

## Privacy

Usage stays local, apart from the quota requests sent to each provider. Existing credentials are read from their original CLI/T3 stores, used in memory and never logged or copied into a second credential store. T3 settings, databases, caches and transcripts are read-only inputs. No model inference is requested to check usage.

The app is **not sandboxed** and reads local authentication and usage files. Review the source before running it. Diagnostic output contains usage aggregates, so redact it before posting publicly. See [Security](../SECURITY.md).

## How it works

T3 Code’s pure pooling, pricing, deduplication, aggregation and transcript-parsing modules execute in macOS **JavaScriptCore**. Swift handles filesystem access, network requests, background work and the native interface. No Node runtime or browser engine ships.

| Path | Purpose |
| --- | --- |
| `Sources/Quota/PanelView.swift` | Native Usage panel |
| `Sources/Quota/MetricPicker.swift` | Native segmented control and flat T3-style drawing |
| `Sources/Quota/T3Source.swift` | Account discovery and provider quota transports |
| `Sources/Quota/T3History.swift` | Byte-based history reader and actor-owned engine |
| `tools/t3-source/` | Pinned upstream copies, adapted modules and source hashes |
| `Tests/QuotaTests/` | Usage correctness, native rendering and synthetic screenshot fixtures |

Source pin: [`60f70d98cdeb2c692db649b9ade3adf74dd62bf9`](https://github.com/pingdotgg/t3code/commit/60f70d98cdeb2c692db649b9ade3adf74dd62bf9). Supported T3 scan-cache versions: 4–15. Newer incompatible formats require an update.

The checked-in JavaScript bundle is sufficient to build. To regenerate it:

```sh
git clone https://github.com/pingdotgg/t3code .reference/t3code
git -C .reference/t3code checkout 60f70d98cdeb2c692db649b9ade3adf74dd62bf9
pnpm --dir tools install --frozen-lockfile
pnpm --dir tools run extract
```

For local diagnostics, run the built executable with `--probe`, or `--render /tmp/quota.png` with optional `--cost` / `--tokens`. These read real usage and issue real quota requests. Do not publish their output without redaction.
