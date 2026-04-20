# ClipStack

ClipStack is a free, local-only clipboard manager for the macOS menu bar.

## Install

```bash
# TODO: replace before public release
curl -fsSL https://raw.githubusercontent.com/FIXME_ORG/clipstack/main/install.sh | bash
```

Requirements: macOS 13 (Ventura) or later. Apple Silicon and Intel supported.

## What it does

- Monitors clipboard for text and images
- Auto-copies screenshots
- Stores local clipboard history
- Restore any previous clipboard item from the menu bar
- No network access. No cloud sync. No account. No telemetry.

## Privacy

ClipStack stores clipboard history exclusively in:

```text
~/Library/Application Support/ClipStack/
```

No data leaves your machine. No analytics. No crash reporting. History is stored unencrypted in this release (MVP). Do not store sensitive secrets in clipboard history if this concerns you.

## Uninstall

```bash
# TODO: replace before public release
curl -fsSL https://raw.githubusercontent.com/FIXME_ORG/clipstack/main/uninstall.sh | bash
```

Or manually:

```bash
rm -rf /Applications/ClipStack.app
rm -rf ~/Library/Application\ Support/ClipStack
rm -f ~/Library/Preferences/com.clipstack.app.plist
```

## Security note

ClipStack is not signed with an Apple Developer ID certificate. The installer removes the macOS quarantine flag and applies an ad-hoc signature. This is intentional and standard practice for free developer tools distributed outside the App Store. Review install.sh before running it if you have concerns.

## Build from source

Requires Xcode 15+ and macOS 13+.

```bash
# TODO: replace before public release
git clone https://github.com/FIXME_ORG/clipstack
cd clipstack
xcodebuild -scheme ClipStack -configuration Release \
  ONLY_ACTIVE_ARCH=NO ARCHS="arm64 x86_64" build
```

## License

MIT
