#!/bin/bash

# Block edits to sensitive files
FILE=$(jq -r '.tool_input.file_path // empty' < /dev/stdin)

PROTECTED_PATTERNS=(
    ".env"
    "Secrets.swift"
    "GoogleService-Info.plist"
    ".git/"
    "Podfile.lock"
)

for pattern in "${PROTECTED_PATTERNS[@]}"; do
    if [[ "$FILE" == *"$pattern"* ]]; then
        echo "🛡️ Protected file: $FILE" >&2
        exit 2  # Block the operation
    fi
done

exit 0  # Allow the operation
