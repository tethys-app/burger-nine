# Storefront

Static ordering site for one brand (one website, many locations). Talks to the Tethys `/v1` API. Deployed
to Cloudflare Workers static assets.

**You can rewrite almost everything in here freely.** Layout, copy, styling,
components, page structure, animations — all of it. The rules below are the
short list of things that must not change, and why.

## Invariants

`scripts/check-invariants.mjs` runs before every build and fails on violations.
Do not weaken it.

1. **No server-side code.** `output: 'static'`, no SSR adapter, no
   `prerender = false`, no files under `src/pages/` except `.astro`. If you need
   a backend behaviour, it belongs in the Tethys API, not here.
2. **No secrets.** Every env var must be `PUBLIC_`/`VITE_` prefixed. This repo
   holds no credentials at all: `PUBLIC_BRAND_SLUG` is an identifier, and the
   Stripe publishable key arrives from `GET /store` at runtime. A secret in this
   repo ships to every visitor in the JS bundle.
3. **Never compute a price you present as final, and never decide an order is
   paid.** Both come from the server. See below.

If you need a contact form, use a form service or an API endpoint — not an
Astro endpoint in this repo.

## Why the site has no authority

This repo is assumed to be continuously rewritten by an LLM, so it is given
none. It cannot price a cart, decide a cart is valid, or mark an order paid.
Those live in the API. A bug here produces a `422`, not a bad order.

That is what makes the rest of the code free to edit.

## Three layers of freshness

| Layer | Job | Stale? |
|---|---|---|
| Build snapshot (`getStaticPaths`) | crawler HTML, JSON-LD, instant first paint | days, fine |
| `GET /catalog` on hydration | greys out a dish 86'd at 12:40 | ~30s |
| `POST /quote` | **authoritative** — decides everything | never |

Do not try to make the build fresher. Correctness never comes from it. Prices
and availability change with no rebuild; only structural changes (a dish added,
removed or renamed) need one, and a nightly build covers that.

**`?live` opts into polling** while editing a menu: `OrderIsland` re-fetches
`/catalog` every 3s, so backoffice edits appear without a reload. `?live=5` sets
the seconds. Open the storefront beside the backoffice with `?live` and edit.

It compares `catalog.version` — `{snapshotId}:{store.updatedAt}`, which changes on any
store or catalog write — so state is set only when something actually changed. Off
unless the param is present: a normal customer never polls, and the single hydration
fetch is unchanged.

The interval is clamped to 1–60s (`lib/live.ts`) because the value comes from the URL
and must not be able to become a request flood. Keep the clamp.

## Ordering flow

```
add to cart ──> POST /quote (debounced 150ms) ──> totals + blockers
                                                        │
                                          valid ────────┘
                                            │
                          POST /checkout ───┴──> clientSecret ──> <EmbeddedCheckout/>
                                                                        │
                                                        Stripe ──webhook──> API marks paid
                                                                        │
                                            return_url ──> /order-status?id=…&token=…  (polls)
```

Notes that matter:

- **The add-to-cart sheet must enforce required modifiers before creating a
  line.** A line that violates `min`/`max` is treated by the server as a
  storefront bug and returns `422` — not something the customer can fix in the
  cart. `ProductSheet` does this; keep it if you rewrite the sheet.
- **`disabled={!quote?.valid}`** is the whole gate on the pay button. Don't
  reimplement the rules; read the flag.
- **Blockers vs 422.** `quote.blockers` (200) is drift — item 86'd, store
  closed, under the minimum. Show them and let the customer continue. A `422` is
  a bug in this code; surface it loudly.
- **Totals dim, never disappear**, while a quote is in flight
  (`.totals[data-stale]`). Binding straight to the response flashes on every tap.
- **The order status page polls.** The webhook is what marks an order paid; the
  return URL proves nothing.

## Env

```
PUBLIC_NEO_API_URL   https://<deployment>.convex.site
PUBLIC_BRAND_SLUG    which brand this site is — scopes every /v1/brands/… call
PUBLIC_SITE_URL      https://… canonical site URL, used for JSON-LD + return_url
```

The API is unauthenticated: catalogs, prices and opening hours are the same data
printed in the window. The brand slug identifies, it does not authorise. Placing
an order is gated server-side, not by anything this repo holds.

`store.stripePublishableKey` and `store.stripeAccountId` both come from
`GET /store`, deliberately as a pair — `loadStripe(key, { stripeAccount })`
fails if the two are from different Stripe modes.

## Types

`src/lib/types.ts` defines nothing. It re-exports `@tethys/api-types`, which
derives every type from the server implementation — `Quote` and `Blocker` from
the pricer, `Store`/`Brand`/`Order` from the queries that return them. There is
one source of truth, so renaming a field server-side breaks this build rather
than a customer's browser.

While the template lives in the API repo the dependency is
`file:../../packages/api-types`. When the template is copied into its own repo,
change that to a published version range — no source change, because the import
specifier is already the package name.

Do not hand-write a response type. If something is missing, export it from the
package.

## Naming

The API is domain-split on purpose:

- **Menu** (catalog, cart): `modifier` → `choices`, `choiceRef`
- **Order** (quote lines, orders): `options`, `optionRef`

`POST /quote` takes menu-shaped `choices` and returns order-shaped `options`.
That is not a bug — don't "fix" it.
