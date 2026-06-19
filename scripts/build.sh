#!/usr/bin/env bash
# Build FinalCutHaptics from source: the universal Swift observer, the C# plugin, and the .pkg installer.
#
# Requirements: macOS, Xcode/Swift toolchain, .NET SDK 8+, and Logi Options+ installed
# (the plugin links against its PluginApi.dll).
#
# Optional code-signing / notarization (omit to build unsigned):
#   FCH_SIGN_APP="Developer ID Application: NAME (TEAMID)"       # sign the observer binary
#   FCH_SIGN_INSTALLER="Developer ID Installer: NAME (TEAMID)"   # sign the .pkg
#   FCH_NOTARY_PROFILE="notary-profile-name"                     # notarytool profile → notarize + staple
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="1.0.1"
mkdir -p dist

echo "→ [1/3] Building universal Swift observer (arm64 + x86_64)…"
swiftc -O -target arm64-apple-macosx11.0  observer/SnapObserver.swift -o /tmp/fch-arm
swiftc -O -target x86_64-apple-macosx11.0 observer/SnapObserver.swift -o /tmp/fch-x64
lipo -create /tmp/fch-arm /tmp/fch-x64 -output plugin/FinalCutHaptics/SnapObserver
if [ -n "${FCH_SIGN_APP:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$FCH_SIGN_APP" plugin/FinalCutHaptics/SnapObserver
  echo "   signed observer with: $FCH_SIGN_APP"
fi

echo "→ [2/3] Building C# plugin (.NET Release)…"
# Need a .NET *SDK*, not just a runtime. Fail loudly if one isn't resolvable.
if ! dotnet --list-sdks >/dev/null 2>&1 || [ -z "$(dotnet --list-sdks 2>/dev/null)" ]; then
  echo "ERROR: no .NET SDK found for '$(command -v dotnet)'. Install one (e.g. 'brew install dotnet') and ensure it's first on PATH." >&2
  exit 1
fi
dotnet build plugin/FinalCutHaptics/FinalCutHaptics.csproj -c Release -v minimal

echo "→ [3/3] Packaging installer .pkg…"
SRC="plugin/bin/Release"
rm -rf packaging/pkgroot && mkdir -p packaging/pkgroot
ditto "$SRC/metadata" packaging/pkgroot/metadata
ditto "$SRC/events"   packaging/pkgroot/events
ditto "$SRC/bin"      packaging/pkgroot/bin
pkgbuild --root packaging/pkgroot --scripts packaging/scripts \
  --identifier com.finalcuthaptics.plugin --version "$VERSION" \
  --install-location /usr/local/share/FinalCutHaptics/staging \
  /tmp/FinalCutHaptics-component.pkg
productbuild --distribution packaging/distribution.xml --package-path /tmp /tmp/FinalCutHaptics-unsigned.pkg

OUT="dist/FinalCutHaptics-$VERSION.pkg"
if [ -n "${FCH_SIGN_INSTALLER:-}" ]; then
  productsign --sign "$FCH_SIGN_INSTALLER" --timestamp /tmp/FinalCutHaptics-unsigned.pkg "$OUT"
  echo "   signed .pkg with: $FCH_SIGN_INSTALLER"
  if [ -n "${FCH_NOTARY_PROFILE:-}" ]; then
    echo "   notarizing (this can take a few minutes)…"
    xcrun notarytool submit "$OUT" --keychain-profile "$FCH_NOTARY_PROFILE" --wait
    xcrun stapler staple "$OUT"
  fi
else
  cp /tmp/FinalCutHaptics-unsigned.pkg "$OUT"
  echo "   built UNSIGNED (set FCH_SIGN_INSTALLER + FCH_NOTARY_PROFILE to sign/notarize)"
fi
echo "✅ Built $OUT"

echo "→ [bonus] Packaging Marketplace .lplug4…"
# A .lplug4 is just a zip of the plugin tree (metadata/ + events/ + bin/, with the signed observer).
LPLUG="$(pwd)/dist/FinalCutHaptics_${VERSION//./_}.lplug4"
rm -f "$LPLUG"
( cd "$SRC" && zip -r -X "$LPLUG" metadata events bin >/dev/null )
echo "✅ Built $LPLUG"
