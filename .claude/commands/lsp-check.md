---
description: Refresh SourceKit build server and typecheck changed Swift files without a full build
---

Catch Swift compile errors (type errors, concurrency/autoclosure issues, missing
symbols) faster than a full `build_run_sim`, and keep editor diagnostics accurate.

## Steps

1. **Refresh the build server** so SourceKit-LSP and any compile flags match the
   current scheme/build settings:
   ```
   xcode-build-server config -scheme BurgerNine -project BurgerNine.xcodeproj
   ```
   This rewrites `buildServer.json` (gitignored — machine-specific paths).

2. **Typecheck only** (no codegen, no link, no simulator). Much faster than a
   full build; surfaces the same frontend errors:
   ```
   xcodebuild -project BurgerNine.xcodeproj -scheme BurgerNine \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
     -derivedDataPath /tmp/BurgerNineDerivedData \
     OTHER_SWIFT_FLAGS='-typecheck' build 2>&1 \
     | grep -E 'error:|warning:' | sort -u
   ```
   If that prints nothing, the changed files typecheck clean.

3. **Report** only the `error:`/`warning:` lines, each as a clickable
   `file:line`. If clean, say so in one line — don't dump the build log.

## Notes
- Prefer this over `/build` while iterating on a single file's logic. Run `/build`
  (full build) before claiming a feature works end-to-end — typecheck does not
  catch link errors or runtime issues.
- The `LSP` tool (`documentSymbol`, `hover`, `goToDefinition`, `findReferences`)
  works build-free once `buildServer.json` exists — use it for navigation, but it
  does NOT return diagnostics, so this typecheck pass is how errors are found.
- `No such module 'UIKit'` from inline SourceKit is a known false positive only
  when `buildServer.json` is missing/stale — step 1 clears it.
