# Storefront template

Fork this per franchise. It is a 100% static Astro site that talks to the Tethys
`/v1` API and holds no secrets.

## Setup

```sh
cp .env.example .env
bun install
bun run dev
```

No key is needed. The `/v1` API is unauthenticated: catalogs, prices and opening
hours are the same data printed in the window, so `PUBLIC_BRAND_SLUG` identifies
the brand but authorises nothing. Set it in `.env` and you are done.

The Stripe publishable key is not held here either — it arrives at runtime from
`GET /stores/{slug}`, paired with `stripeAccountId`.

See `docs-v2/storefront-contract.md` in the API repo for the full contract.

## Deploy

Cloudflare Workers static assets — free and unmetered for asset requests.

```sh
bun run build          # runs the invariant checks first
bunx wrangler deploy
```

Then point the franchise domain at it. Adding their domain to the Cloudflare
account as a normal zone and using a `custom_domain` route is free; Cloudflare
for SaaS custom hostnames is only needed if they keep DNS elsewhere.

## Rebuild policy

**Git push + a nightly cron. Nothing else.**

Price and availability edits need no deploy — the island refetches the catalog
on hydration and `/quote` is authoritative at order time. Only structural
changes (dish added, removed, renamed) change which pages exist, and 24h is
fine for a crawler. Wire the backoffice "publish" button to the Cloudflare
deploy hook if a franchise wants it sooner.

## Layout

```
src/
  pages/
    index.astro          franchise home + store locator
    [store].astro        prerendered menu + JSON-LD + order island
    order-status.astro   reads ?id=&token= at runtime, polls the order
  components/
    OrderIsland.tsx      cart, quote, embedded Stripe checkout
    OrderStatus.tsx      post-payment polling
  lib/
    api.ts               typed client for /v1
    types.ts             the contract — regenerate from /openapi.json later
    jsonld.ts            schema.org Restaurant/Menu
scripts/
  check-invariants.mjs   static-only + no-secrets guard, runs before build
```

See [CLAUDE.md](./CLAUDE.md) for the rules that must hold when editing.
