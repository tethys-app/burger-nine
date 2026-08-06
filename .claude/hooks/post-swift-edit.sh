#!/bin/bash

# Read file path from stdin JSON
FILE=$(jq -r '.tool_input.file_path // empty' < /dev/stdin)

if [[ "$FILE" != *.swift ]]; then
    exit 0
fi

# Run SwiftLint on the edited file
if command -v swiftlint &> /dev/null && [ -f ".swiftlint.yml" ]; then
    swiftlint lint --path "$FILE" --quiet 2>&1 | head -5 >&2
fi

# Run swift-format check
if command -v swift-format &> /dev/null; then
    swift-format lint "$FILE" 2>&1 | head -3 >&2
fi
