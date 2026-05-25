#!/usr/bin/env zsh
set -euo pipefail

APP_PATH="${1:-}"
if [[ -z "$APP_PATH" ]]; then
  echo "Usage: Scripts/install-login-item.sh /absolute/path/to/CodexDockNotifier.app" >&2
  exit 2
fi

if [[ "$APP_PATH" != /* ]]; then
  APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

PLIST="$HOME/Library/LaunchAgents/com.local.CodexDockNotifier.plist"
mkdir -p "$HOME/Library/LaunchAgents"

/usr/bin/plutil -create xml1 "$PLIST"
/usr/bin/plutil -replace Label -string "com.local.CodexDockNotifier" "$PLIST"
/usr/bin/plutil -replace ProgramArguments -json "[\"/usr/bin/open\", \"$APP_PATH\"]" "$PLIST"
/usr/bin/plutil -replace RunAtLoad -bool true "$PLIST"
/usr/bin/plutil -replace KeepAlive -bool false "$PLIST"

/bin/launchctl bootout "gui/$UID" "$PLIST" >/dev/null 2>&1 || true
/bin/launchctl bootstrap "gui/$UID" "$PLIST"
/bin/launchctl enable "gui/$UID/com.local.CodexDockNotifier"

echo "Installed login item: $PLIST"
