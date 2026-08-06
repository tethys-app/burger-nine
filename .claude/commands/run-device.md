---
description: Build and launch app on connected physical device
allowed-tools: mcp__xcodebuildmcp__*
---

# /run-device — Build and launch "BurgerNine" on connected iPhone

**Project facts (use these exactly, every time):**
- projectPath: "/Volumes/dev/Neo/api/burger-nine/BurgerNine.xcodeproj"
- scheme: "BurgerNine"

**Mandatory first action — call this tool immediately with no preamble text:**
Set Session Defaults (or the mcp__xcodebuildmcp__ tool that configures the active project):
- projectPath: "/Volumes/dev/Neo/api/burger-nine/BurgerNine.xcodeproj"
- scheme: "BurgerNine"
- deviceId: "A005D6B3-11DB-5294-9150-DEC3BF16EFAC"
- bundleId: "com.burgernine.app.debug"
- persist: true

**After the defaults call succeeds**, immediately proceed with the actual build + run flow for physical device:
1. List connected devices to select target
2. Build for device (with code signing)
3. Install the built app on device
4. Launch the app on device
5. (Optional) capture logs from device

**Rules:**
- Do NOT output sentences like "Found device..." or repeat plans.
- Call the Set Session Defaults tool as your very first action.
- Then chain the build/launch tools for device.
- Only speak after you have results from the tools.
- If multiple devices are connected, use the first available device or prompt user to select.

Use the tools. Get the app running on the connected device. Report status concisely at the end.
