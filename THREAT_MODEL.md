# ClipStack Threat Model

## Assets

- Clipboard history stored in `history.json`
- Screenshot images copied into clipboard history
- Semantic index data derived from clipboard text

## Trust Boundary

ClipStack operates inside the local user session only. It has no accounts, cloud sync, telemetry, or intended network communication.

The primary trust boundary is between the current macOS user account and other local processes or users on the same machine.

## Threats Considered

- Local file exposure of clipboard history from `~/Library/Application Support/ClipStack/history.json`
- Clipboard interception by other local processes with pasteboard access
- Installer supply-chain risk from GitHub Releases and the `curl | bash` install path
- Malformed or oversized filesystem input from screenshot files

## Accepted MVP Risks

- Clipboard history is stored unencrypted.
- The app is ad-hoc signed.
- The app is not sandboxed.
- The release is not notarized.
- The installer uses `curl | bash`.

## Deferred Mitigations

- Encryption at rest for clipboard history and images
- App Sandbox with scoped access decisions for screenshots
- Developer ID signing and notarization
- Secret redaction or blocking before history capture
- Stronger installer attestation and distribution controls
