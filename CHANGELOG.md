# Changelog

## [Unreleased]

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
