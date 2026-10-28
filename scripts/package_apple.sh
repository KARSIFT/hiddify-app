#!/bin/bash
set -euo pipefail
platform=$1
version=$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml)
mkdir -p out
if [ "$platform" = macos ]; then
  app='build/macos/Build/Products/Release/Hiddify Karsift.app'
  test -d "$app"
  # Supply a classic icon for macOS/Xcode versions without Icon Composer support.
  bash scripts/set_macos_icon.sh "$app"
  # Ad-hoc signing permits local testing; this is not Developer ID notarization.
  codesign --force --deep --sign - --entitlements macos/Runner/Release.entitlements "$app"
  codesign --verify --deep --strict "$app"
  staging=$(mktemp -d)
  trap 'rm -rf "$staging"' EXIT
  ditto "$app" "$staging/Hiddify Karsift.app"
  ln -s /Applications "$staging/Applications"
  hdiutil create -volname 'Hiddify Karsift' -srcfolder "$staging" -ov -format UDZO "out/Hiddify-Karsift-$version-macOS.dmg"
  (cd out && shasum -a 256 *.dmg > SHA256SUMS-macOS.txt)
  printf 'Source commit: %s\nNative core: v5.0.3\nSigning: ad-hoc; not notarized\n' "$GITHUB_SHA" > out/BUILD-INFO-macOS.txt
elif [ "$platform" = ios ]; then
  app=build/ios/iphoneos/Runner.app
  test -d "$app/PlugIns/HiddifyPacketTunnel.appex"
  staging=$(mktemp -d)
  trap 'rm -rf "$staging"' EXIT
  mkdir "$staging/Payload"
  ditto "$app" "$staging/Payload/Runner.app"
  ditto -c -k --keepParent "$staging/Payload" "out/Hiddify-Karsift-$version-iOS-unsigned.ipa"
  cp docs/IOS-SIGNING.txt out/IOS-SIGNING.txt
  (cd out && shasum -a 256 *.ipa > SHA256SUMS-iOS.txt)
  printf 'Source commit: %s\nNative core: v5.0.3\nSigning: unsigned; cannot install before signing\n' "$GITHUB_SHA" > out/BUILD-INFO-iOS.txt
else
  echo "Unsupported platform: $platform" >&2
  exit 1
fi
