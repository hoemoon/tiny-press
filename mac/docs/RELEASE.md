# Releasing tiny press for macOS

Two distribution stages, lowest friction first.

## Stage 0 — Ad-hoc unsigned `.dmg` (free)

What testers see: download → drag to Applications → first launch shows
"unidentified developer". They right-click the app, choose **Open**,
confirm once. Subsequent launches go directly.

### Locally

```bash
cd mac
./scripts/build-dmg.sh
# → dist/TinyPress-<version>.dmg (about 12 MB)
```

The `.app` is ad-hoc codesigned (no Developer ID). Gatekeeper rejects
silently launchable but tolerates a deliberate right-click → Open.

### Via GitHub Actions

`.github/workflows/release.yml` runs on every `v*` tag push:

```bash
git tag -a v0.1.0 -m "0.1.0 — first internal alpha"
git push origin v0.1.0
```

The workflow builds the `.dmg`, attaches it to the auto-created GitHub
Release, and publishes generated release notes from the commit log
since the previous tag.

> **Caveat about runners**: GitHub-hosted `macos-latest` typically lags
> the SDK we target. If the runner doesn't have an Xcode that ships
> SDK 26 yet, the workflow will fail. In that window, build locally and
> upload manually:
>
> ```bash
> ./scripts/build-dmg.sh
> gh release create v0.1.0 dist/*.dmg --generate-notes
> ```

### Help testers bypass quarantine

If they don't want to right-click:

```bash
xattr -d com.apple.quarantine /Applications/TinyPress.app
```

(Mention this in the release notes.)

---

## Stage 1 — Developer ID signed + notarized

What testers see: download → drag → double-click. Just works.

### One-time setup (manual)

1. **Apple Developer Program**: enroll (https://developer.apple.com/programs/) — $99/yr.
2. **Certificate**: in Xcode → Settings → Accounts → Manage Certificates,
   create *Developer ID Application*. Confirm it's in the login keychain
   (`security find-identity -v -p codesigning`).
3. **App-specific password**: at https://appleid.apple.com → Sign-In and
   Security → App-Specific Passwords, generate one for "tinypress notary".
4. **Store credentials in keychain** (no plaintext passwords on disk):

   ```bash
   xcrun notarytool store-credentials tinypress-notary \
       --apple-id you@example.com \
       --team-id YOURTEAMID \
       --password <app-specific-password>
   ```

   Find your team id in the Apple Developer member portal.

### Build a signed release

```bash
./scripts/build-dmg.sh --sign --notarize
```

The script:
1. Archives with automatic signing via your Developer ID cert.
2. Exports a Developer ID `.app`.
3. Submits to Apple notary, waits for the result.
4. Staples the ticket to the `.app`.
5. Builds a `.dmg`, signs it, notarizes it, staples it.

### Verify before publishing

```bash
spctl -a -vvv -t install dist/TinyPress-0.1.0.dmg
# expected: dist/TinyPress-0.1.0.dmg: accepted

stapler validate dist/TinyPress-0.1.0.dmg
# expected: The validate action worked!
```

### Publish

```bash
gh release upload v0.1.0 dist/TinyPress-0.1.0.dmg --clobber
```

`--clobber` replaces the unsigned dmg the CI workflow uploaded.

---

## Why not TestFlight?

- TestFlight Mac requires **App Sandbox** + Hardened Runtime + App Store
  Connect upload + (for external testers) App Review.
- The current build drops sandbox so it can shell out to the `tailscale`
  CLI for live preview sharing. Re-enabling sandbox means moving Tailscale
  invocation behind `NSUserUnixTask` (per-user helper script the user
  must install once) or an XPC privileged helper.
- Same $99/yr cost as Stage 1, more friction, slower iteration.

If you ever want TestFlight regardless:
1. Re-add `com.apple.security.app-sandbox` to `TinyPress.entitlements`.
2. Replace direct `Process` invocations of `tailscale` with
   `NSUserUnixTask` plus a setup wizard.
3. Add a `Distribution` provisioning profile and `app-store-connect`
   export method to a new `build-pkg.sh`.
4. `xcrun altool --upload-app` (or `xcrun notarytool` + Transporter).

---

## Tagging the core

The Swift package and the macOS app share a single repo, so they share a
single tag. The `v0.1.0` push that triggers the macOS dmg release also
pins the core for future bumps:

```bash
git tag -a v0.1.0 -m "0.1.0"
git push origin v0.1.0
```

CI runs `swift test` (core) and `xcodebuild test` (mac) on every push.
