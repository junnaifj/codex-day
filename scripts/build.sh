#!/bin/zsh
set -eu
cd "${0:A:h}/.."
STAGE=$(mktemp -d /private/tmp/codex-day-build.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Codex Day Helper.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$STAGE/module-cache"
swiftc -parse-as-library -O -module-cache-path "$STAGE/module-cache" -target "$(uname -m)-apple-macos14.0" codex-day/Sources/Models.swift codex-day/Sources/Helper.swift -o "$APP/Contents/MacOS/CodexDayHelper" -framework SwiftUI -framework EventKit -framework AppKit
cp codex-day/scripts/summarize.py "$APP/Contents/Resources/summarize.py"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CodexDayHelper</string>
<key>CFBundleIdentifier</key><string>local.codex.day.helper</string>
<key>CFBundleName</key><string>Codex Day Helper</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSCalendarsFullAccessUsageDescription</key><string>Display Apple Calendar events in the Codex Day sticky note. Calendar events are read-only.</string>
<key>NSRemindersFullAccessUsageDescription</key><string>Sync editable to-dos with a dedicated Codex Day list in Apple Reminders. Other lists are not changed.</string>
</dict></plist>
PLIST
xattr -cr "$APP"
codesign --force --sign - "$APP"
mkdir -p build
if [ -d 'build/Codex Day Helper.app' ]; then rm -rf 'build/Codex Day Helper.app'; fi
ditto --noextattr --norsrc "$APP" 'build/Codex Day Helper.app'
printf 'Built background helper (no window or Dock icon).\n'

LAUNCHER="$STAGE/Codex with Day.app"
mkdir -p "$LAUNCHER/Contents/MacOS"
swiftc -parse-as-library -O -module-cache-path "$STAGE/module-cache" -target "$(uname -m)-apple-macos14.0" codex-day/Sources/Launcher.swift -o "$LAUNCHER/Contents/MacOS/CodexDayLauncher" -framework AppKit
cat > "$LAUNCHER/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CodexDayLauncher</string>
<key>CFBundleIdentifier</key><string>local.codex.day.launcher</string>
<key>CFBundleName</key><string>Codex with Day</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
xattr -cr "$LAUNCHER"
codesign --force --sign - "$LAUNCHER"
if [ -d 'build/Codex with Day.app' ]; then rm -rf 'build/Codex with Day.app'; fi
ditto --noextattr --norsrc "$LAUNCHER" 'build/Codex with Day.app'
printf 'Built persistent Codex launcher.\n'
