#!/usr/bin/env bash
# Generates the native shells (android/, ios/, web/) to match your Flutter
# version, then applies Tracka's changes: app name, permissions, icons.
#
# Why generate instead of committing android/ and ios/? They're thousands of
# lines of Flutter-version-specific boilerplate. Generating them keeps the repo
# small and always in step with the Flutter you build with (same as YesBut).
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f android/app/src/main/AndroidManifest.xml ]; then
  echo "▶ Generating native platform folders…"
  flutter create --org app.tracka --project-name tracka --platforms=android,ios,web . >/dev/null
fi

echo "▶ Android: name, permissions"
M=android/app/src/main/AndroidManifest.xml
perl -pi -e 's/android:label="[^"]*"/android:label="Tracka"/' "$M"
# Only what the app needs (Google Play's Data safety form lists every permission).
# No camera, microphone or media-library permission: image_picker uses the
# system photo picker and camera app, which need none. Google Play only allows
# READ_MEDIA_VIDEO for gallery-type apps (its Photo and Video Permissions policy).
for p in INTERNET POST_NOTIFICATIONS; do
  grep -q "permission.$p\"" "$M" || perl -0pi -e "s|<application|<uses-permission android:name=\"android.permission.$p\"/>\n    <application|" "$M"
done
# Plain http only in debug builds (your laptop at http://10.0.2.2:8000). Release
# builds talk https only, so nobody on the café Wi-Fi can read a player's data.
D=android/app/src/debug/AndroidManifest.xml
if [ -f "$D" ] && ! grep -q usesCleartextTraffic "$D"; then
  perl -0pi -e 's|</manifest>|    <application android:usesCleartextTraffic="true"/>\n</manifest>|' "$D"
fi
perl -pi -e 's/ android:usesCleartextTraffic="true"//' "$M"

echo "▶ iOS: name and privacy strings (required by Apple to pick or record video)"
P=ios/Runner/Info.plist
add_plist() {
  grep -q "<key>$1</key>" "$P" || perl -0pi -e "s|<dict>|<dict>\n\t<key>$1</key>\n\t<string>$2</string>|" "$P"
}
add_plist NSPhotoLibraryUsageDescription "Tracka needs your videos so Pep can coach you on them."
add_plist NSCameraUsageDescription "Record a clip or a drill for Pep to coach you on."
add_plist NSMicrophoneUsageDescription "Video recordings include sound."
perl -0pi -e 's|(<key>CFBundleDisplayName</key>\s*<string>)[^<]*|${1}Tracka|' "$P"

echo "▶ Icons and web shell"
cp -R platform_overlay/. .
# iOS icons: resize the 1024 px master into every size Xcode's icon set asks for.
ICONS=ios/Runner/Assets.xcassets/AppIcon.appiconset
if [ -d "$ICONS" ] && command -v convert >/dev/null; then
  for f in "$ICONS"/*.png; do
    size=$(identify -format "%w" "$f")
    convert tool/icon-ios-1024.png -resize "${size}x${size}" "$f"
  done
fi
perl -pi -e 's|<title>[^<]*</title>|<title>Tracka</title>|; s|content="#[0-9A-Fa-f]{6}"|content="#0A0B09"|g' web/index.html
[ -f web/manifest.json ] && perl -pi -e 's/"name": "[^"]*"/"name": "Tracka"/; s/"short_name": "[^"]*"/"short_name": "Tracka"/; s/"background_color": "[^"]*"/"background_color": "#0A0B09"/; s/"theme_color": "[^"]*"/"theme_color": "#E5FF00"/' web/manifest.json

flutter pub get
echo "✔ Platforms ready."
