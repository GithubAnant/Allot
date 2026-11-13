# Security

Report a suspected vulnerability using the repository's **Security → Report a vulnerability** flow. Do not put credentials, private account data, transcripts, or exploit details in a public issue.

The app reads existing CLI/T3 authentication and usage data. It does not create a second credential store, modify T3's files, or request model inference to check limits. Provider requests go to their respective services; no telemetry or third-party analytics service is included.

The app is not sandboxed. Review the source before granting it access to local authentication. Source-built/ad-hoc-signed binaries are not notarized distribution builds. Avoid running modified binaries from an untrusted source.
