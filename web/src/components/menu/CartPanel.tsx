import { useState } from 'react'
import { money } from '../../lib/format'
import { cart, cartTotals, type Entry } from './cart-store'
import type { Blocker, Quote } from '../../lib/types'

// Ported from the Neo app's cart-panel.tsx: docked sidebar on desktop, floating
// bar that expands into a drawer on mobile.
//
// One deliberate difference. The Neo panel sums its own lines and shows that as
// the total. Here the totals come from the server quote and the pay button is
// gated on `quote.valid` — this repo is not allowed to decide what a cart costs
// or whether it can be ordered (see CLAUDE.md). The local sum is only a
// placeholder while the first quote is in flight.

type Props = {
  entries: Entry[]
  currency: string
  quote?: Quote
  stale: boolean
  error?: string
  onCheckout: () => void
  variant: 'sidebar' | 'floating'
}

export function CartPanel({ entries, currency, quote, stale, error, onCheckout, variant }: Props) {
  const { count, totalCents } = cartTotals(entries)
  const [open, setOpen] = useState(false)

  const body = (
    <>
      <div className="min-h-0 flex-1 overflow-y-auto p-4">
        {count === 0 ? <Empty /> : <Lines entries={entries} currency={currency} />}
      </div>
      {count > 0 && (
        <Summary
          currency={currency}
          fallbackCents={totalCents}
          quote={quote}
          stale={stale}
          error={error}
          onCheckout={onCheckout}
          onClear={() => cart.clear()}
        />
      )}
    </>
  )

  if (variant === 'sidebar') {
    return (
      <aside className="sticky top-20 hidden h-[calc(100dvh-6rem)] w-[340px] shrink-0 flex-col
        rounded-[28px] border border-hairline theme-border theme-panel lg:flex">
        <div className="border-b border-hairline theme-border px-5 py-4">
          <h2 className="font-display text-lg font-black text-ink">Votre panier</h2>
          <p className="text-xs font-bold text-muted">{count} article{count > 1 ? 's' : ''}</p>
        </div>
        {body}
      </aside>
    )
  }

  return (
    <>
      {count > 0 && !open && (
        <div className="pointer-events-none fixed inset-x-0 bottom-0 z-40 p-4 pb-[max(1rem,env(safe-area-inset-bottom))]">
          <button
            onClick={() => setOpen(true)}
            className="pointer-events-auto mx-auto flex w-full max-w-md items-center gap-3.5 rounded-[26px]
              border border-pink/30 p-3.5 theme-floating-cart transition active:scale-[0.98] pop-in"
          >
            <span className="grid h-10 w-10 place-items-center rounded-full bg-yellow font-black text-surface">{count}</span>
            <span className="flex-1 text-left">
              <span className="block font-black text-white">Voir le panier</span>
              <span className="block text-xs font-bold text-white/55">
                {money(quote?.totals.totalCents ?? totalCents, currency)}
              </span>
            </span>
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" className="text-white"><path d="M9 6l6 6-6 6" /></svg>
          </button>
        </div>
      )}

      {open && (
        <div className="fixed inset-0 z-50 flex items-end justify-center sm:items-center sm:p-6">
          <div className="absolute inset-0 bg-black/55 backdrop-blur-sm" onClick={() => setOpen(false)} />
          <div className="relative flex max-h-[85dvh] w-full flex-col rounded-t-[32px] border border-hairline theme-border theme-surface-depth sm:max-w-md sm:rounded-[32px] pop-in">
            <div className="flex items-center justify-between border-b border-hairline theme-border px-5 py-4">
              <h2 className="font-display text-lg font-black text-ink">Votre panier</h2>
              <button onClick={() => setOpen(false)} aria-label="Fermer" className="grid h-9 w-9 place-items-center rounded-full theme-elevated text-muted">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round"><path d="M6 6l12 12M18 6L6 18" /></svg>
              </button>
            </div>
            {body}
          </div>
        </div>
      )}
    </>
  )
}

function Lines({ entries, currency }: { entries: Entry[]; currency: string }) {
  return (
    <ol className="space-y-2.5">
      {entries.map((e) => (
        <li key={e.key} className="flex gap-3 rounded-2xl border border-hairline theme-border theme-elevated p-3">
          <div className="min-w-0 flex-1">
            <span className="block truncate text-sm font-black text-ink">{e.product.title}</span>
            {!!e.line.choices?.length && (
              <span className="mt-0.5 block text-[11px] font-semibold leading-snug text-muted">
                {e.line.choices.map((c) => choiceLabel(e, c.choiceRef)).filter(Boolean).join(' · ')}
              </span>
            )}
            <span className="mt-1 block text-sm font-black text-ink">
              {money(e.unitPriceCents * e.qty, currency)}
            </span>
          </div>
          <div className="flex shrink-0 items-center gap-0.5 self-start rounded-full theme-surface-depth p-1">
            <button onClick={() => cart.decrement(e.key)} aria-label="Retirer un"
              className="grid h-7 w-7 place-items-center rounded-full text-muted transition hover:text-ink active:scale-90">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3.2" strokeLinecap="round"><path d="M5 12h14" /></svg>
            </button>
            <span className="min-w-4 text-center text-xs font-black tabular-nums text-ink">{e.qty}</span>
            <button onClick={() => cart.increment(e.key)} aria-label="Ajouter un"
              className="grid h-7 w-7 place-items-center rounded-full text-muted transition hover:text-ink active:scale-90">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3.2" strokeLinecap="round"><path d="M12 5v14M5 12h14" /></svg>
            </button>
          </div>
        </li>
      ))}
    </ol>
  )
}

const choiceLabel = (entry: Entry, choiceRef: string) =>
  entry.product.modifiers
    ?.flatMap((m) => m.choices)
    .find((c) => c.ref === choiceRef)?.title ?? ''

function Summary({
  currency, fallbackCents, quote, stale, error, onCheckout, onClear,
}: {
  currency: string
  fallbackCents: number
  quote?: Quote
  stale: boolean
  error?: string
  onCheckout: () => void
  onClear: () => void
}) {
  const totals = quote?.totals
  return (
    <div className="space-y-3 border-t border-hairline theme-border p-4 pb-[max(1rem,env(safe-area-inset-bottom))]">
      {/* Dims rather than disappears while a quote is in flight, so the panel
          never shifts under the pointer. */}
      <dl className="space-y-1 transition-opacity" style={{ opacity: stale ? 0.55 : 1 }}>
        <Row label="Sous-total" value={money(totals?.subtotalCents ?? fallbackCents, currency)} />
        {!!totals?.deliveryFeeCents && (
          <Row label="Livraison" value={money(totals.deliveryFeeCents, currency)} />
        )}
        <Row label="Total" value={money(totals?.totalCents ?? fallbackCents, currency)} strong />
      </dl>

      {quote?.blockers.map((b: Blocker, i: number) => (
        <p key={i} className="m-0 text-xs font-bold text-coral">{b.message}</p>
      ))}
      {error && <p className="m-0 text-xs font-bold text-coral">{error}</p>}

      <button
        onClick={onCheckout}
        disabled={!quote?.valid}
        className="w-full rounded-[22px] bg-gradient-to-br from-pink-hot to-pink-deep py-4 font-display
          font-black uppercase tracking-[0.06em] text-white shadow-lg transition
          active:scale-[0.98] disabled:opacity-40 disabled:active:scale-100"
      >
        Commander
      </button>
      <button onClick={onClear} className="w-full text-center text-xs font-bold text-muted transition hover:text-coral">
        Vider le panier
      </button>
    </div>
  )
}

function Row({ label, value, strong = false }: { label: string; value: string; strong?: boolean }) {
  return (
    <div className="flex items-center justify-between">
      <dt className={strong ? 'text-sm font-bold text-ink' : 'text-sm font-bold text-muted'}>{label}</dt>
      <dd className={`m-0 tabular-nums ${strong ? 'text-lg font-black text-ink' : 'text-sm font-bold text-muted'}`}>
        {value}
      </dd>
    </div>
  )
}

function Empty() {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-3 py-10 text-center">
      <div className="grid h-14 w-14 place-items-center rounded-2xl theme-elevated text-muted">
        <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="9" cy="20" r="1.5" /><circle cx="18" cy="20" r="1.5" /><path d="M2 3h3l2.6 13.4a2 2 0 0 0 2 1.6h7.7a2 2 0 0 0 2-1.6L23 7H6" /></svg>
      </div>
      <p className="text-sm font-bold text-muted">Votre panier est vide</p>
    </div>
  )
}
