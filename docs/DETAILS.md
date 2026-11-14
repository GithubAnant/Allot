# Allot details

## Connect your tools

**T3 Code is not required.** Allot discovers existing Codex/Claude CLI sign-ins and the Cursor app’s local login (including its versioned macOS safeStorage encryption; access requires Keychain permission). Use **Accounts** in Allot to add independently signed-in Claude/Codex accounts, including 2–3 of each. Each quota window shows separate named account bars. The large provider percentage uses T3’s pooling rules; a missing account/window never becomes a measured zero.

The official provider CLIs are required for Claude/Codex authentication and quota queries. They are not bundled. If T3 is installed, its configured accounts and history are read as additional inputs. [Setup, language support and unsigned-build installation](INSTALL.md).

| Provider | Subscription limits | Cost and tokens |
| --- | --- | --- |
| Codex | Live CLI app-server quota query | Local session scans; optional T3 records |
| Claude | Live usage-only Claude Code SDK control request | Local project scans; optional T3 records |
| Cursor | Live current-period quota from the Cursor app or an existing T3 sign-in | T3’s saved account-usage cache |
| OpenCode Go | Experimental transport; not verified working | Available normalized T3 history |
| Other T3 providers | No implemented subscription-quota transport | Available normalized T3 history |

Gemini CLI, GitHub Copilot, Windsurf, Perplexity and standalone Grok subscription limits are **not implemented**. The app does not substitute developer API spending for subscription quota.

## What the numbers mean

- **Cost is an API-equivalent estimate, not your subscription bill.** An offline LiteLLM price snapshot is bundled ([source revision](MODEL-RATES-SOURCE.json)); optional T3 rates, aliases and overrides take precedence. Snapshot prices may become stale; missing models remain unpriced.
- Cursor limits refresh live. Cursor **cost/token history** updates when T3 syncs its account-usage cache; Allot does not fetch a new event ledger.
- Unavailable quota/reset data stays unavailable; it is never presented as a measured zero or an invented reset time.
- The OpenCode error banner is hidden. Its underlying connection error is still available in diagnostics.
- Add/remove Claude and Codex accounts directly in Allot. Extra Cursor accounts still require existing T3 account configurations. Refresh-interval settings and notification preferences are outside this minimal Usage-tab port.

Cursor’s local credential schema and quota endpoint can change between releases. The current `cursor-safe-storage:v1:` format is decoded with macOS Keychain permission; unsupported formats stay unavailable. This follows [Electron safeStorage](https://www.electronjs.org/docs/latest/api/safe-storage/) and its [macOS encryption format](https://chromium.googlesource.com/chromium/src/+/0267e3c2/components/os_crypt/os_crypt_mac.mm). Cursor cost/token history currently requires optional T3 records; local Cursor sign-in alone provides limits.

## Privacy

Usage stays local, apart from the quota requests sent to each provider. Existing credentials are read from their original CLI/Cursor/T3 stores, used in memory and never logged or copied into a second credential store. Added accounts authenticate using the official CLIs in isolated Allot config directories; new Codex accounts use Keychain. T3 settings, databases, caches and transcripts are read-only inputs. No model inference is requested to check usage.

The app is **not sandboxed** and reads local authentication and usage files. Review the source before running it. Diagnostic output contains usage aggregates, so redact it before posting publicly. See [Security](../SECURITY.md).

## How it works

T3 Code’s pure pooling, pricing, deduplication, aggregation and transcript-parsing modules execute in macOS **JavaScriptCore**. Swift handles filesystem access, network requests, background work and the native interface. No Node runtime or browser engine ships.

| Path | Purpose |
| --- | --- |
| `Sources/Quota/PanelView.swift` | Native Usage panel |
| `Sources/Quota/MetricPicker.swift` | Native segmented control and flat T3-style drawing |
| `Sources/Quota/CursorCredentials.swift` | Read-only Cursor token access and macOS Keychain decryption |
| `Sources/Quota/LocalAccounts.swift` | Standalone account metadata and official CLI sign-in |
| `Sources/Quota/Localization.swift` | Automatic macOS language selection and English fallback |
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
