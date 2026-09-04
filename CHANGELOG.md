# Changelog

## [Unreleased]

### Added

- First-run onboarding: a 720×520 window that walks through Quick Paste and area capture as live demos inside a MacBook Pro frame, then asks for Accessibility and (optionally) Screen Recording. Permission states update on their own while the window is open — no need to come back and press anything. Fully keyboard-navigable: Return continues, Escape skips setup, ⌘[ goes back.
- Re-authorize sheet: when an update makes macOS drop ClipStack's Accessibility grant, a compact sheet explains the off/on toggle and closes itself as soon as access returns.
- Screen Recording is requested through the system prompt first, which grants the running app, instead of sending you to System Settings — where turning the toggle on behind a running app makes macOS demand a restart. If the prompt is no longer available because the request was denied before, the step offers a one-click **Relaunch ClipStack** instead of leaving you to quit and reopen by hand.

### Changed

- New app icon and a single accent colour (system blue) used throughout the interface.

## [0.4.2] - 2026-09-03

### Fixed

- Resolve the quick-paste caret at any offset inside a line, not only at the start, end, or on an empty line. Native fields now derive the caret from the neighbouring character bounds and correct the zero-length bounds AppKit reports one line too high; browser-based fields (Codex, Chromium, Electron) that expose no per-character geometry now measure the caret inside the paragraph that contains it, so the panel opens after clicking in the middle of existing text.
- Reject caret candidates that describe a whole line, the whole field, another element, or non-finite coordinates instead of opening the panel at a misleading position.
- Close the quick-paste panel on any loss of focus: clicking, scrolling, or typing outside it, switching apps or Spaces, hiding or minimizing the target, screen changes, sleep, and keys the panel does not handle. The panel no longer follows the user to other Spaces.
- Show the newest clipboard items next to the caret when the panel opens below it, with arrow keys walking away from the caret in both directions.
- Log which accessibility path resolved the caret and why candidates were rejected, using geometry only, so caret problems can be diagnosed from the unified log.

## [0.4.1] - 2026-09-03

### Fixed

- Make quick paste use a bottom-origin scroll layout so the newest clipboard item is visible immediately and older items are revealed by scrolling upward.
- Preserve the release signature during installation so macOS receives the exact verified app identity from the published archive.
- Use only the installer-managed LaunchAgent for login startup and crash recovery instead of registering a second login item from inside the app.
- Explain how to recover Accessibility authorization when macOS retains a stale grant after an update.

## [0.4.0] - 2026-09-03

### Added

- Add a `Shift + Command + V` quick-paste panel that anchors to the exact text caret, chooses above or below based on available screen space, presents the 10 newest items with the latest at the bottom, loads earlier items on demand, and pastes the selection back into the originating app.

### Fixed

- Route global hot-key events by identifier so quick paste and area capture cannot swallow each other's shortcuts.

## [0.3.0] - 2026-09-02

### Added

- Register `Shift + Command + S` as a global shortcut for instant native area capture to the Desktop, clipboard, and ClipStack history without the floating thumbnail.
- Add animated multi-selection to Clipboard and Downloads, including type-preserving clipboard copy and native multi-item drag sessions.

### Changed

- Optimize release builds and omit Xcode debug and preview dylibs from distributed archives.

## [0.2.1] - 2026-08-05

### Fixed

- Prevent very large clipboard entries from crashing semantic indexing while keeping full-text literal search intact.
- Start ClipStack automatically at login and relaunch it if the process unexpectedly exits.

## [0.2.0] - 2026-05-01

### Added

- Add an ephemeral Downloads tray to the menu bar popover for dragging recent top-level Downloads files into other apps.
- Preserve older installer targets while making `0.2.0` the latest supported release.

### Changed

- Use the new Vector.png artwork for the macOS app icon.
- Smooth the popover tab transition between Clipboard and Downloads.

### Fixed

- Preserve high-resolution copied image payloads across restore, including JPEG/GIF/HEIC pasteboard data.

### Notes

- Downloads tray data is in memory only. Folders, packages, and Safari `.download` packages are intentionally ignored for v1 and can be supported later.

## [0.1.1] - 2026-04-25

### Changed

- Store image payloads outside history JSON and keep downsampled previews in memory.
- Use image content fingerprints for deduplication instead of repeated PNG re-encoding.
- Document that rerunning the installer updates ClipStack.
- Allow the installer to install a specific supported release version.

## [0.1.0] - 2026-04-20

### Added

- Initial public release
- Menu bar clipboard history manager
- Text and image clipboard monitoring
- Screenshot auto-copy support
- Local history persistence in Application Support
- curl-based installer for macOS 13+
