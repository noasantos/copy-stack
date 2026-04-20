# ClipStack Release Checklist

## For every new version release:

### 1. Update version

- [ ] Set `MARKETING_VERSION` in Xcode to the new version (e.g. 0.2.0)
- [ ] Update `CHANGELOG.md` with new version entry
- [ ] Update `VERSION` variable in `install.sh`

### 2. Build

```bash
chmod +x scripts/build.sh
./scripts/build.sh 0.2.0
```

### 3. Tag and release on GitHub

```bash
git add -A
git commit -m "chore: release v0.2.0"
git tag v0.2.0
git push origin main --tags
```

- Create GitHub Release for `v0.2.0`
- Upload `build/ClipStack-0.2.0.zip` as release asset
- Paste the SHA-256 printed by build.sh into the release notes

### 4. Update install.sh SHA-256

- [ ] Replace `EXPECTED_SHA256` in `install.sh` with the SHA-256 from build.sh output
- [ ] Commit: `git commit -am "chore: update installer sha256 for v0.2.0"`
- [ ] Push: `git push origin main`

### 5. Verify install

```bash
# TODO: replace before public release
curl -fsSL https://raw.githubusercontent.com/FIXME_ORG/clipstack/main/install.sh | bash
```

- [ ] App launches from /Applications
- [ ] Menu bar icon appears
- [ ] Clipboard history works
- [ ] Uninstall works

## What does NOT require an Apple Developer account

- Building the app
- Ad-hoc signing
- Quarantine removal
- GitHub Releases hosting
- curl-based distribution

## What WOULD require an Apple Developer account ($99/yr)

- Developer ID signing (trusted by all users without xattr removal)
- Notarization (Apple scans the binary)
- Stapling (offline notarization ticket)
- Submission to Homebrew/homebrew-cask main repo
- Mac App Store distribution
