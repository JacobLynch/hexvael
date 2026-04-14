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

# Client 1 — left half (adjust resolution for your screen)
$GODOT --path "$PROJECT" --resolution 960x720 --position 0,45 -- --server localhost --port 9050 --dev &

# Client 2 — right half
$GODOT --path "$PROJECT" --resolution 960x720 --position 960,45 -- --server localhost --port 9050 --dev &

wait
