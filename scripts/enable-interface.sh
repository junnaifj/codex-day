#!/bin/zsh
set -eu
APP=/Applications/ChatGPT.app
[[ -d "$APP" ]] || APP=/Applications/Codex.app
IDENTIFIER=$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$APP/Contents/Info.plist")
[[ "$IDENTIFIER" == com.openai.codex ]] || { print 'Official Codex app not found.'; exit 1; }
/usr/bin/codesign --verify --strict --test-requirement '=anchor apple generic and certificate leaf[subject.OU] = "2DC432GLL2"' "$APP"
EXE=$(/usr/bin/plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")
if /bin/ps -axo comm= | /usr/bin/grep -Fxq "$APP/Contents/MacOS/$EXE"; then
  print 'Close Codex normally first, then run this launcher. This script never terminates Codex.'
  exit 2
fi
/usr/bin/open -na "$APP" --args --remote-debugging-address=127.0.0.1 --remote-debugging-port=9341
