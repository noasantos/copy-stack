# ClipStack — Contributor & Agent Guide

This file is the single source of truth for contributors and AI agents working on ClipStack. Read it before opening a PR or starting any significant change.

## What is ClipStack

ClipStack is a free, open-source, local-only clipboard manager for the macOS menu bar. Written entirely in Swift with no third-party dependencies. It runs as a background app (no Dock icon), monitors the system clipboard and screenshot folder, stores a local history, and provides a SwiftUI popover for browsing and restoring past items.

- **Platform:** macOS 13 (Ventura)+, universal binary (arm64 + x86_64)
- **Language:** Swift 5.9+, SwiftUI + AppKit
- **No external packages** — only system frameworks (AppKit, SwiftUI, Foundation, NaturalLanguage, Accelerate, CryptoKit, UserNotifications, ImageIO)
- **No network** — intentional, statically enforced by `scripts/lint-release.sh`
- **License:** MIT

## Architecture

```
ClipStack/
├── ClipStackApp.swift           — @main SwiftUI entry point
├── AppDelegate.swift            — NSApplicationDelegate, wires all components
├── ClipboardItem.swift          — Model: enum .text(String) / .image(Data)
├── ClipboardMonitor.swift       — NSPasteboard polling every 0.5s
├── ClipboardStore.swift         — @MainActor ObservableObject, core state
├── ClipboardHistoryPersistence.swift — JSON persistence to ~/Library/Application Support/ClipStack/
├── ScreenshotWatcher.swift      — kqueue/DispatchSource watcher on ~/Desktop
├── SemanticIndex.swift          — NLEmbedding-based semantic search (actor)
└── MenuBarView.swift            — SwiftUI popover UI
```

Data flows in one direction: `ClipboardMonitor` / `ScreenshotWatcher` → `ClipboardStore` → `MenuBarView`. `ClipboardHistoryPersistence` reads/writes to disk from `ClipboardStore`. `SemanticIndex` is fed text items by `ClipboardStore` and returns ranked results.

## Core Constraints

1. **No network access.** Do not add any import or API that touches the network. `scripts/lint-release.sh` will fail the build if it finds `URLSession`, `URLRequest`, `WKWebView`, `NWConnection`, `CFSocketCreate`, or `import Network`.
2. **No external dependencies.** Do not add Swift packages, Cocoapods, or Carthage dependencies.
3. **No telemetry, analytics, or crash reporting.** ClipStack is privacy-first by design.
4. **macOS 13 minimum.** Do not use APIs unavailable on macOS 13 without a `#available` guard.
5. **Universal binary only.** Both `arm64` and `x86_64` must build cleanly.

## Coding Standards

- Use Swift concurrency (`async/await`, `actor`) over GCD callbacks wherever possible.
- `ClipboardStore` is `@MainActor`. Mutations to shared state must happen there.
- `SemanticIndex` is a Swift `actor` — call its methods with `await`.
- Prefer value types (`struct`, `enum`) over classes. Use `@MainActor` classes only where UIKit/AppKit integration requires it.
- Do not add `// MARK:` comments unless they mark a distinct logical section with more than ~5 methods.
- Do not write comments that narrate what code does. Write comments only for non-obvious intent, trade-offs, or platform quirks.
- Keep files focused. If a file grows past ~300 lines, consider splitting concerns.
- Write unit tests in `Tests/` for any new logic. Mirror the source file name (e.g., `FooBar.swift` → `FooBarTests.swift`).

## Tests

```bash
./scripts/test.sh
```

This runs `scripts/lint-release.sh` (network API check) then `xcodebuild test`. All tests must pass before a PR is mergeable.

## Build & Run

```bash
# Debug run
./scripts/run.sh

# Release universal binary (produces build/ClipStack-x.y.z.zip)
./scripts/build.sh 0.x.0
```

## PR Guidelines

- **One concern per PR.** Don't bundle unrelated changes.
- **Title format:** `type: short description` — types: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`.
- **Update `CHANGELOG.md`** under `[Unreleased]` for any user-visible change.
- **Update `SECURITY.md`** if you change security-relevant behaviour (signing, sandboxing, encryption, network scope).
- **No breaking changes to install.sh or uninstall.sh** without a corresponding release and SHA-256 update per `RELEASING.md`.
- PRs must pass `./scripts/test.sh` locally before requesting review.

## Known MVP Gaps (do not paper over without a real fix)

The following are accepted limitations for the current release. See `SECURITY.md` for full details:

- Clipboard history is stored **unencrypted**
- App is **not sandboxed** (no App Sandbox entitlement)
- **No secret detection or redaction** before history capture
- **No pause / private mode**
- Installer uses `curl | bash`
- Builds are **ad-hoc signed**, not notarized

If your PR addresses one of these, mention it explicitly in the PR description and update `SECURITY.md`.

## What Good Contributions Look Like

- A focused fix with a test that previously failed
- A new feature behind a guard or preference that degrades gracefully on older OS
- A performance improvement with measurable before/after (even if just a comment)
- Documentation that fills a genuine gap (not restating what code already makes obvious)

## What to Avoid

- Adding external dependencies
- Adding any form of network call or remote logging
- Changing the data format of `history.json` without a migration path
- Adding frameworks that require capabilities not declared in `Info.plist`
- Committing `build/`, `DerivedData/`, or any generated artefact
