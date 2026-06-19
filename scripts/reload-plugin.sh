#!/usr/bin/env bash
# Rebuild the C# plugin and hot-reload it in Logi Options+ without killing the service.
#
# IMPORTANT: never `kill` LogiPluginService to reload — a SIGKILL while the plugin runs is logged
# as a crash, which permanently disables the plugin ("disabled as it had crashed before"). This
# script clears any stale crash marker and uses the clean in-process reload URL instead.
set -euo pipefail
cd "$(dirname "$0")/.."

CRASH_MARKER="$HOME/Library/Application Support/Logi/LogiPluginService/Logs/plugin_crashes/FinalCutHaptics.dll"
LOG="$HOME/Library/Application Support/Logi/LogiPluginService/Logs/plugin_logs/FinalCutHaptics.log"

echo "→ building plugin…"
dotnet build plugin/FinalCutHaptics/FinalCutHaptics.csproj -c Release | grep -E "Build succeeded|error" || true

rm -f "$CRASH_MARKER" 2>/dev/null && echo "→ cleared stale crash marker" || true

echo "→ reloading via loupedeck:// URL scheme…"
open "loupedeck://plugin/FinalCutHaptics/reload"
sleep 2
echo "→ plugin log tail:"
tail -3 "$LOG" 2>/dev/null || echo "(no log yet)"
