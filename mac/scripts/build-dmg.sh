#!/usr/bin/env bash
#
# Build TinyPress.app and package it as a .dmg.
#
#   ./scripts/build-dmg.sh                  # Stage 0 — ad-hoc signed, no notarization
#   ./scripts/build-dmg.sh --sign --notarize # Stage 1 — Developer ID + notarized
#
# Stage 1 setup (one-time, manual):
#   1. Enroll in the Apple Developer Program ($99/yr).
#   2. Download "Developer ID Application" cert into your login keychain.
#   3. xcrun notarytool store-credentials tinypress-notary \
#          --apple-id <you@example.com> \
#          --team-id <TEAMID> \
#          --password <app-specific-password>
#
# Output: dist/TinyPress-<version>.dmg
#
# Env knobs:
#   DEVELOPER_DIR             — path to Xcode (default: detected)
#   TINYPRESS_NOTARY_PROFILE  — keychain profile name (default: tinypress-notary)
#   TINYPRESS_SIGN_IDENTITY   — codesign identity (default: "Developer ID Application")

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE="$REPO_ROOT/TinyPress.xcworkspace"
SCHEME="TinyPress"
CONFIG="Release"
NOTARY_PROFILE="${TINYPRESS_NOTARY_PROFILE:-tinypress-notary}"
SIGN_IDENTITY="${TINYPRESS_SIGN_IDENTITY:-Developer ID Application}"

DO_SIGN=0
DO_NOTARIZE=0
for arg in "$@"; do
    case "$arg" in
        --sign) DO_SIGN=1 ;;
        --notarize) DO_NOTARIZE=1 ;;
        -h|--help)
            grep '^# ' "$0" | sed 's/^# //; s/^#//'
            exit 0
            ;;
        *) echo "unknown flag: $arg" >&2; exit 2 ;;
    esac
done

if (( DO_NOTARIZE && !DO_SIGN )); then
    echo "--notarize requires --sign" >&2
    exit 2
fi

cd "$REPO_ROOT"

# ---- Toolchain ---------------------------------------------------------

# Honour DEVELOPER_DIR if set; otherwise probe /Applications for Xcode.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    candidate=$(ls -d /Applications/Xcode*.app 2>/dev/null | sort -r | head -1 || true)
    if [[ -n "$candidate" ]]; then
        export DEVELOPER_DIR="$candidate/Contents/Developer"
    fi
fi
echo "==> Using Xcode at ${DEVELOPER_DIR:-(default xcode-select)}"

if ! command -v tuist >/dev/null; then
    echo "tuist not found — install with: brew install tuist" >&2
    exit 1
fi

# Pretty-print xcodebuild output if xcbeautify is available, else fall
# through unchanged.
xcfilter() {
    if command -v xcbeautify >/dev/null; then
        xcbeautify
    else
        cat
    fi
}

# ---- Generate ----------------------------------------------------------

echo "==> Generating Xcode project"
tuist install >/dev/null
tuist generate --no-open >/dev/null

BUILD_DIR="$REPO_ROOT/build/dmg"
DIST_DIR="$REPO_ROOT/dist"
mkdir -p "$BUILD_DIR" "$DIST_DIR"
rm -rf "$BUILD_DIR/Export" "$BUILD_DIR"/*.xcarchive 2>/dev/null || true

# ---- Build / sign ------------------------------------------------------

if (( DO_SIGN )); then
    ARCHIVE_PATH="$BUILD_DIR/TinyPress.xcarchive"
    APP_OUT="$BUILD_DIR/Export/TinyPress.app"

    # Derive the team id from the keychain unless the user pinned one.
    # Without DEVELOPMENT_TEAM, automatic signing falls back to "Sign to
    # Run Locally" and exportArchive errors with "No Team Found in Archive".
    if [[ -z "${TINYPRESS_TEAM_ID:-}" ]]; then
        TINYPRESS_TEAM_ID=$(security find-identity -v -p codesigning \
            | grep -m 1 "Developer ID Application" \
            | sed -E 's/.*\(([A-Z0-9]+)\)".*/\1/' || true)
    fi
    if [[ -z "${TINYPRESS_TEAM_ID:-}" ]]; then
        echo "No 'Developer ID Application' identity in keychain." >&2
        echo "Run: security find-identity -v -p codesigning" >&2
        exit 1
    fi
    echo "==> Signing as team $TINYPRESS_TEAM_ID"

    echo "==> Archiving (Developer ID)"
    # With Automatic signing, only DEVELOPMENT_TEAM is set — Xcode picks
    # the identity from the export `method` (developer-id in our plist).
    # Explicitly setting CODE_SIGN_IDENTITY here triggers a "conflicting
    # provisioning settings" lint failure for SPM-bundled framework
    # targets that have no concept of Developer ID.
    xcodebuild archive \
        -workspace "$WORKSPACE" \
        -scheme "$SCHEME" \
        -configuration "$CONFIG" \
        -destination 'generic/platform=macOS' \
        -archivePath "$ARCHIVE_PATH" \
        CODE_SIGN_STYLE=Automatic \
        CODE_SIGNING_REQUIRED=YES \
        DEVELOPMENT_TEAM="$TINYPRESS_TEAM_ID" \
        | xcfilter

    cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>signingStyle</key><string>automatic</string>
    <key>teamID</key><string>$TINYPRESS_TEAM_ID</string>
</dict>
</plist>
PLIST

    echo "==> Exporting .app"
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
        -exportPath "$BUILD_DIR/Export" \
        | xcfilter
else
    echo "==> Building (unsigned, ad-hoc)"
    DERIVED="$BUILD_DIR/DerivedData"
    rm -rf "$DERIVED"
    xcodebuild \
        -workspace "$WORKSPACE" \
        -scheme "$SCHEME" \
        -configuration "$CONFIG" \
        -destination 'generic/platform=macOS' \
        -derivedDataPath "$DERIVED" \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        build \
        | xcfilter

    SRC_APP=$(find "$DERIVED/Build/Products/$CONFIG" -maxdepth 2 -name "TinyPress.app" -type d | head -1)
    if [[ -z "$SRC_APP" ]]; then
        echo "build succeeded but TinyPress.app not found under $DERIVED" >&2
        exit 1
    fi
    APP_OUT="$BUILD_DIR/Export/TinyPress.app"
    rm -rf "$BUILD_DIR/Export"
    mkdir -p "$BUILD_DIR/Export"
    cp -R "$SRC_APP" "$APP_OUT"

    echo "==> Ad-hoc signing"
    codesign --force --deep --sign - "$APP_OUT"
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "$APP_OUT/Contents/Info.plist")
echo "==> Built TinyPress.app version $VERSION"

# ---- Notarize ----------------------------------------------------------

if (( DO_NOTARIZE )); then
    echo "==> Submitting to notarization (this can take several minutes)"
    NOTARY_ZIP="$BUILD_DIR/TinyPress.zip"
    /usr/bin/ditto -c -k --keepParent "$APP_OUT" "$NOTARY_ZIP"
    xcrun notarytool submit "$NOTARY_ZIP" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait
    echo "==> Stapling notarization ticket"
    xcrun stapler staple "$APP_OUT"
fi

# ---- DMG ---------------------------------------------------------------

DMG_PATH="$DIST_DIR/TinyPress-$VERSION.dmg"
echo "==> Packaging $DMG_PATH"
rm -f "$DMG_PATH"
hdiutil create \
    -volname "tiny press $VERSION" \
    -srcfolder "$APP_OUT" \
    -ov -format UDZO \
    "$DMG_PATH" >/dev/null

if (( DO_SIGN )); then
    echo "==> Signing dmg"
    codesign --force --sign "$SIGN_IDENTITY" "$DMG_PATH"
    if (( DO_NOTARIZE )); then
        echo "==> Notarizing dmg"
        xcrun notarytool submit "$DMG_PATH" \
            --keychain-profile "$NOTARY_PROFILE" \
            --wait
        xcrun stapler staple "$DMG_PATH"
    fi
fi

echo
echo "✓ Done: $DMG_PATH"
echo "  Stage: $( ((DO_SIGN)) && echo "signed" || echo "ad-hoc unsigned")$( ((DO_NOTARIZE)) && echo " + notarized")"
echo
echo "Verify locally:"
echo "  spctl -a -vvv -t install \"$DMG_PATH\""
echo "  hdiutil verify \"$DMG_PATH\""
