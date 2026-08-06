---
description: Build and launch app on simulator
allowed-tools: mcp__xcodebuildmcp__*
---

# /run-app — Build and launch "BurgerNine" on simulator

**Project facts (use these exactly, every time):**
- projectPath: "/Volumes/dev/Neo/api/burger-nine/BurgerNine.xcodeproj"
- scheme: "BurgerNine"
- simulatorName: "iPhone 17 Pro"

**Mandatory first action — call this tool immediately with no preamble text:**
Set Session Defaults (or the mcp__xcodebuildmcp__ tool that configures the active project):
- projectPath: "/Volumes/dev/Neo/api/burger-nine/BurgerNine.xcodeproj"
- scheme: "BurgerNine"
- simulatorName: "iPhone 17 Pro"
- persist: true

**After the defaults call succeeds**, immediately proceed with the actual build + run flow using the available XcodeBuildMCP tools:
1. Build for simulator
2. Boot simulator (if not booted)
3. Install the built app
4. Launch the app
5. (Optional) capture logs

**Rules:**
- Do NOT output sentences like "Found scheme BurgerNine. Let me set up the session defaults..." or repeat plans.
- Call the Set Session Defaults tool as your very first action.
- Then chain the build/launch tools.
- Only speak after you have results from the tools.
- If you see repeated Set Session Defaults calls with no build, stop and call the actual build/launch tool next.

Use the tools. Get the app running on the simulator. Report status concisely at the end.
