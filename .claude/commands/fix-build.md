---
description: Diagnose and fix build errors
allowed-tools: mcp__xcodebuildmcp__*, Read, Write, Edit
---

# /fix-build — Diagnose and fix build errors for BurgerNine

**First:** Call Set Session Defaults with:
- projectPath: "/Volumes/dev/Neo/api/burger-nine/BurgerNine.xcodeproj"
- scheme: "BurgerNine"
- simulatorName: "iPhone 17 Pro"
- persist: true

**Then:** Clean, then do a fresh build (simulator) to surface current errors.

Analyze errors one by one.
Propose minimal fixes.
Edit source, then re-build to verify.
Repeat until clean build.

Call the MCP build/clean tools directly. Keep commentary short. Use the project facts above on every session-defaults call.
