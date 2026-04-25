# Changelog

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
