# Changelog

## [Unreleased]

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
