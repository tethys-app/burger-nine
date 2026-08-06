---
description: Run all relevant tests
allowed-tools: mcp__xcodebuildmcp__*
---

# /test — Run tests for "BurgerNine"

**Use these exact values first:**
Set Session Defaults:
- projectPath: "/Volumes/dev/Neo/api/burger-nine/BurgerNine.xcodeproj"
- scheme: "BurgerNine"
- simulatorName: "iPhone 17 Pro"
- persist: true

Call Set Session Defaults as the first action.

Then call the test tool for the simulator (the XcodeBuildMCP test equivalent).

Report pass/fail counts and any failing test names + messages.

No long preambles. Tool call first.
