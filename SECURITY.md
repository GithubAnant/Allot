# Security

Report a suspected vulnerability using the repository's **Security → Report a vulnerability** flow. Do not put credentials, private account data, transcripts, or exploit details in a public issue.

The app reads existing CLI/Cursor/T3 authentication and usage data. Added accounts use official CLI authentication in isolated Allot directories; Codex is configured for macOS Keychain. Allot stores account names and IDs locally with owner-only permissions. It does not create a second credential store, modify T3's files, or request model inference to check limits. Provider requests go to their respective services; no telemetry or third-party analytics service is included.

The app is not sandboxed. Review the source before granting it access to local authentication. Source-built/ad-hoc-signed binaries are not notarized distribution builds. Avoid running modified binaries from an untrusted source.
