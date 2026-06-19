#!/usr/bin/env bash
# Start the Final Cut Pro snap observer (sends UDP "snap" → the Logi plugin → MX Master 4 haptic).
# Usage: scripts/run-observer.sh [--console] [--debug]
#   --console : print detections instead of sending UDP (no haptics; for validation)
#   --debug   : also log timing/stall/crossing diagnostics
#
# Requires: Final Cut Pro running, and the terminal/IDE granted Accessibility permission
# (System Settings ▸ Privacy & Security ▸ Accessibility).
set -euo pipefail
cd "$(dirname "$0")/.."
pkill -f "interpret observer/SnapObserver" 2>/dev/null || true
exec swift observer/SnapObserver.swift "$@"
