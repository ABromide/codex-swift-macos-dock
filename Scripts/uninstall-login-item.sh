#!/usr/bin/env zsh
set -euo pipefail

PLIST="$HOME/Library/LaunchAgents/com.local.CodexDockNotifier.plist"
/bin/launchctl bootout "gui/$UID" "$PLIST" >/dev/null 2>&1 || true
rm -f "$PLIST"
echo "Removed login item: $PLIST"
