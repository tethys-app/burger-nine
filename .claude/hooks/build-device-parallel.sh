#!/bin/bash
# Hook script to build+run on device when simulator build runs
# This is called by PostToolUse hook on mcp__XcodeBuildMCP__build_run_sim

set -e  # Exit on error

echo "🔨 Building and launching on device..." >&2

# Get device ID from session defaults
DEVICE_ID="${DEVICE_ID:-}"
PROJECT_DIR="/Volumes/dev/Neo/api/burger-nine"

if [ -z "$DEVICE_ID" ]; then
  echo "DEVICE_ID is required for a physical-device build; skipping device launch." >&2
  exit 0
fi

cd "$PROJECT_DIR"

# Build for device
echo "📦 Building..." >&2
xcodebuild \
  -project BurgerNine.xcodeproj \
  -scheme BurgerNine \
  -destination "id=$DEVICE_ID" \
  -allowProvisioningUpdates \
  build 2>&1 | grep -E '(BUILD|error|warning|note:)' || true

# Install on device
echo "📲 Installing..." >&2
xcrun devicectl device install app \
  --device "$DEVICE_ID" \
  "$(xcodebuild -project BurgerNine.xcodeproj -scheme BurgerNine -destination "id=$DEVICE_ID" -showBuildSettings 2>/dev/null | grep -m 1 'BUILT_PRODUCTS_DIR' | awk '{print $3}')/BurgerNine.app"

# Launch app
echo "🚀 Launching..." >&2
xcrun devicectl device process launch \
  --device "$DEVICE_ID" \
  BurgerNine

echo "✅ Done!" >&2
