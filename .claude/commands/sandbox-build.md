---
description: Build and test without modifying code
allowed-tools: mcp__xcodebuildmcp__*, Read
---

# /sandbox-build — Read-only build + test for BurgerNine

**First action:** Set Session Defaults exactly:
projectPath="/Volumes/dev/Neo/api/burger-nine/BurgerNine.xcodeproj"
scheme="BurgerNine"
simulatorName="iPhone 17 Pro"
persist=true

Then, in order:
- Clean
- Build for simulator (using current session defaults)
- Run tests for simulator

Report results only. No code changes. No planning narration before the Set Session Defaults call.
