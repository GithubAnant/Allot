# Install Allot

Requires macOS 14 or newer. The same build supports Apple Silicon and Intel.

## From a shared app build

1. Get `Allot.zip` from a source you trust and unzip it.
2. Move `Allot.app` into Applications and open it once.
3. If macOS blocks it because the developer cannot be verified, open **System Settings → Privacy & Security → Open Anyway**, then confirm **Open**. Only do this for the genuine build you intended to install. See [Apple’s instructions](https://support.apple.com/en-us/102445).

The current build is **ad-hoc signed, not Developer ID signed or notarized**. macOS may require that first-launch approval. You do not need to disable Gatekeeper. A managed Mac may prohibit opening it. If macOS reports damage or malware, do not bypass that warning; verify the download with the sender.

## Connect accounts

Click the menu-bar icon, then the **Accounts** button.

- Existing Codex and Claude Code CLI sign-ins are discovered automatically.
- For another Claude or Codex account, enter a name, select the provider, and choose **Add account**. Complete the official sign-in in your browser. Repeat for your other accounts, then refresh.
- Install the official [Codex CLI](https://developers.openai.com/codex/cli/) or [Claude Code](https://code.claude.com/docs/en/setup) if needed; Accounts includes both links. Allot does not install or bundle those CLIs.
- Cursor uses the installed Cursor app’s local sign-in. Sign in within Cursor first. Only its current local account is discovered. For encrypted credentials, choose **Sign in** beside Cursor in Allot’s Accounts window to approve macOS Keychain access. Background refresh never requests interactive Keychain access.

**T3 Code is not required.** If it is already installed, Allot can also read its existing accounts and usage history. It does not change T3’s files.

Each added Claude/Codex account has an isolated config directory. Names and IDs live in `~/Library/Application Support/Allot/accounts.json`; the official CLIs manage authentication. New Codex accounts explicitly use macOS Keychain; Claude Code uses its own macOS credential handling. Removing an account stops tracking it and preserves its sign-in and local history. It does not cancel your subscription or sign out the provider CLI.

## Language

Allot follows macOS’s preferred language at launch: English, Spanish, French, German, Hindi, Japanese, or Simplified Chinese. Unsupported languages fall back to English. There is no language picker. Quit and reopen after changing macOS language settings.

Provider/model names and raw provider diagnostics retain their original text. Number and date formatting follows macOS regional settings; API estimates remain denominated in USD.

## Share your own build

```sh
./scripts/build-app.sh
```

Share `dist/Allot.zip` together with `dist/Allot.zip.sha256`. No Xcode or Swift installation is needed to run a shared build. Source builds still require Swift 6 and the Xcode command-line tools. Developer ID signing and Apple notarization are not included.
