# Security Policy

## Reporting Vulnerabilities

Open a GitHub issue and tag it `security`. Include enough detail to reproduce the issue, the affected version, and whether clipboard history, screenshots, installer integrity, or local files are involved.

Do not include private clipboard contents, screenshots, passwords, tokens, or other secrets in public reports.

## Known Limitations

ClipStack is an MVP local-only clipboard manager. The following limitations are accepted for the current release:

- Clipboard history is stored unencrypted at `~/Library/Application Support/ClipStack/`, with metadata in `history.json` and image payloads in `Images/`.
- The app does not use the App Sandbox.
- Release builds are ad-hoc signed and do not use Hardened Runtime.
- Builds are not notarized with Apple Developer ID.
- The installer uses a `curl | bash` flow.

## No Network Scope

ClipStack is intended to make no network requests. Clipboard history, screenshots, and search index data stay on the local Mac.

The current check is static: `scripts/lint-release.sh` scans app Swift sources for common network APIs such as `URLSession`, `URLRequest`, `WKWebView`, `NWConnection`, `CFSocketCreate`, and `import Network`. This does not prove runtime network silence, but it protects the current source tree from accidental network API use.

## Threat Model

**Assets**

- Clipboard history metadata stored in `history.json`
- Clipboard image payloads stored under `Images/`
- Screenshot images copied into clipboard history
- Semantic index data derived from clipboard text

**Trust Boundary**

ClipStack operates inside the local user session only. The primary trust boundary is between the current macOS user account and other local processes or users on the same machine.

**Threats Considered**

- Local file exposure of clipboard history from `~/Library/Application Support/ClipStack/`
- Clipboard interception by other local processes with pasteboard access
- Installer supply-chain risk from GitHub Releases and the `curl | bash` install path
- Malformed or oversized filesystem input from screenshot files

**Deferred Mitigations**

- Encryption at rest for clipboard history and images
- App Sandbox with scoped access decisions for screenshots
- Developer ID signing and notarization
- Secret redaction or blocking before history capture
- Stronger installer attestation and distribution controls
