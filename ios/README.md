# Burger Nine iOS

SwiftUI iOS app copied from the legacy Neo app and adapted to the storefront
public API described in `docs-v2/storefront-architecture.md`.

The active data path is scoped exclusively by the three public storefront
settings in `.env`:

```text
PUBLIC_NEO_API_URL=http://127.0.0.1:3211
PUBLIC_BRAND_SLUG=burger-nine
PUBLIC_SITE_URL=http://localhost:4321
```

The app uses Stripe PaymentSheet for online payments. The public Stripe key and
connected account are returned by the brand-scoped store endpoint; no Stripe
secret is stored in the app. Debug and Release both use the server's configured
payment flow; only the API URL/brand/site settings change by environment.

To refresh the build-time catalog seed before an archive:

```sh
./scripts/generate-burger-nine-snapshot.sh
```

The Xcode target mirrors these values in its build settings so they are
available to the simulator through `Info.plist`. `MenuAPI.swift` only calls
the brand-scoped `/v1/brands/{brand}` routes; the legacy SQLite and game files
remain in the project for compatibility but are not used as the app's catalog
source.

## Build and test

```sh
xcodebuild -project BurgerNine.xcodeproj -scheme BurgerNine \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -project BurgerNine.xcodeproj -scheme BurgerNine \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

The repo also includes the XcodeBuildMCP configuration and the copied Claude
iOS commands/skills under `.claude/`.
