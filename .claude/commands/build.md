---
description: Build the iOS project intelligently
allowed-tools: mcp__xcodebuildmcp__*
---

# /build — Build "BurgerNine" for iOS Simulator

**Use these exact values:**
- projectPath: "/Volumes/dev/Neo/api/burger-nine/BurgerNine.xcodeproj"
- scheme: "BurgerNine"
- simulatorName: "iPhone 17 Pro"

**First tool call (no talking first):** Set Session Defaults with the three values above + persist: true.

**Then:** Call the simulator build tool (the one that builds for iOS Simulator using the session).

Report build success or the full error output.

Do not repeat "let me set up the session defaults" text. Call tools, then summarize results.
