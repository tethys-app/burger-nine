#!/bin/bash

PROJECT_NAME=$(basename "$(pwd)")
SWIFT_VERSION=$(swift --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
XCODE_VERSION=$(xcodebuild -version 2>/dev/null | head -1)

echo "🚀 Starting $PROJECT_NAME session" >&2
echo "📱 Swift $SWIFT_VERSION | $XCODE_VERSION" >&2

# Check for common issues
if ! command -v swiftlint &> /dev/null; then
    echo "⚠️  SwiftLint not installed" >&2
fi

# Check if simulator is booted
if ! xcrun simctl list devices booted | grep -q "Booted"; then
    echo "💡 No simulator running. Use /run-app to boot one." >&2
fi
