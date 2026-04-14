#!/bin/bash
# Dev launcher: server + two side-by-side clients
# Usage: ./dev.sh
# Requires: $GODOT env var or 'godot' in PATH

GODOT="${GODOT:-godot}"
PROJECT="$(cd "$(dirname "$0")" && pwd)/godot"

trap "kill 0" EXIT

# Server (headless)
$GODOT --headless --path "$PROJECT" res://server.tscn -- --port 9050 &

sleep 0.5  # Let server bind port

# Client 1 — left half
$GODOT --path "$PROJECT" --resolution 640x720 --position 0,25 -- --server localhost --port 9050 --dev &

# Client 2 — right half
$GODOT --path "$PROJECT" --resolution 640x720 --position 640,25 -- --server localhost --port 9050 --dev &

wait
