import { useEffect, useRef, useState } from 'react'
import { money } from '../../lib/format'
import { cart, useProductQty } from './cart-store'
import type { Product } from '../../lib/types'

const stripHtml = (s: string) => s.replace(/<[^>]*>/g, '').trim()

// Ported from the Neo app's product-card.tsx. Its poster/row split, thumb,
// stepper and add button are kept as-is; the settings store that switched
// between them is not — this site has one look, so the layout is a prop.
export type CardStyle = 'row' | 'poster'

type Props = {
  item: Product
  sectionName: string
  currency: string
  style: CardStyle
  showImage: boolean
  unavailable?: boolean
  onConfigure: (item: Product) => void
  onAdd: (item: Product) => void
}

export function ProductCard(props: Props) {
  const { item, onAdd, onConfigure, unavailable } = props
  const qty = useProductQty(item.ref)
  const hasOptions = (item.modifiers?.length ?? 0) > 0
  const [pulse, setPulse] = useState(false)

  // Pulse the border briefly whenever the quantity grows.
  const prev = useRef(qty)
  useEffect(() => {
    const grew = qty > prev.current
    prev.current = qty
    if (!grew) return
    setPulse(true)
    const t = setTimeout(() => setPulse(false), 240)
    return () => clearTimeout(t)
  }, [qty])

  const add = () => (hasOptions ? onConfigure(item) : onAdd(item))
  const shared = { ...props, qty, hasOptions, add, pulse }
  if (unavailable) return <Unavailable {...shared} />
  return props.style === 'poster' ? <PosterCard {...shared} /> : <RowCard {...shared} />
}

type CardProps = Props & { qty: number; hasOptions: boolean; add: () => void; pulse: boolean }

/* ── Row layout: image left, text right ─────────────────────────────────── */
function RowCard({ item, sectionName, currency, showImage, qty, hasOptions, add, pulse }: CardProps) {
  return (
    <div
      data-qty={qty}
      className={`group relative flex flex-col rounded-[28px] border p-3.5 theme-card
        transition-[border-color,box-shadow] duration-200
        ${qty > 0 ? 'border-pink/60' : 'border-hairline theme-border hover:border-pink/40'}
        ${pulse ? 'shadow-[0_0_0_4px_rgb(255_45_158/0.18)]' : 'shadow-[0_8px_24px_-16px_rgb(0_0_0/0.8)]'}`}
    >
      <div className="flex w-full flex-1 gap-3.5">
        {showImage && (
          <button
            type="button"
            onClick={add}
            aria-label={hasOptions ? `Choisir les options de ${item.title}` : `Ajouter ${item.title}`}
            className="shrink-0 text-left outline-none transition-transform duration-150 active:scale-[0.98]"
          >
            <Thumb item={item} qty={qty} />
          </button>
        )}

        <button
          type="button"
          onClick={add}
          aria-label={hasOptions ? `Choisir les options de ${item.title}` : `Ajouter ${item.title}`}
          className="flex min-w-0 flex-1 flex-col text-left outline-none transition-transform duration-150 active:scale-[0.98]"
        >
          <span className="block text-[10px] font-black uppercase tracking-[0.12em] text-pink">
            {sectionName}
          </span>
          <span className="block truncate font-black text-ink text-[15px]">{item.title}</span>
          {item.description && (
            <span className="line-clamp-2 block text-xs font-semibold text-muted">
              {stripHtml(item.description)}
            </span>
          )}
          <span className="mt-1 block pr-[52px] text-lg font-black text-ink">
            {money(item.price_cents, currency)}
          </span>
        </button>
      </div>

      <div className="absolute bottom-3.5 right-3.5 flex items-center gap-1.5">
        {qty === 0 ? (
          <AddButton onClick={add} />
        ) : (
          <Stepper item={item} qty={qty} hasOptions={hasOptions} onAdd={add} />
        )}
      </div>
    </div>
  )
}

/* ── Poster layout: flat card, image top, text below ────────────────────── */
function PosterCard({ item, sectionName, currency, showImage, qty, hasOptions, add, pulse }: CardProps) {
  return (
    <div
      data-qty={qty}
      className={`group relative flex h-full flex-col overflow-hidden rounded-[22px] border bg-surface-depth
        transition-[border-color,box-shadow,transform] duration-200 hover:-translate-y-[5px] hover:border-pink
        ${qty > 0 ? '!translate-y-0 border-pink/60' : 'border-hairline'}
        ${pulse ? 'shadow-[0_0_0_4px_rgb(255_45_158/0.18)]' : ''}`}
    >
      {showImage && (
        <button
          type="button"
          onClick={add}
          aria-label={hasOptions ? `Choisir les options de ${item.title}` : `Ajouter ${item.title}`}
          className="relative block w-full outline-none"
        >
          <Thumb item={item} qty={qty} fill />
        </button>
      )}

      <div className="flex flex-1 flex-col gap-1 p-[18px]">
        <button
          type="button"
          onClick={add}
          aria-label={hasOptions ? `Choisir les options de ${item.title}` : `Ajouter ${item.title}`}
          className="flex min-w-0 flex-1 flex-col text-left outline-none"
        >
          <span className="mb-1 block text-[10px] font-black uppercase tracking-[0.12em] text-pink">
            {sectionName}
          </span>
          <span className="block min-h-[42px] text-[17px] font-bold leading-tight text-ink">
            {item.title}
          </span>
          {item.description && (
            <span className="line-clamp-2 block text-xs font-semibold text-muted">
              {stripHtml(item.description)}
            </span>
          )}
        </button>
        <div className="mt-[14px] flex items-center justify-between gap-2">
          <span className="text-[22px] font-black text-ink">{money(item.price_cents, currency)}</span>
          {qty === 0 ? (
            <PosterAddButton onClick={add} />
          ) : (
            <Stepper item={item} qty={qty} hasOptions={hasOptions} onAdd={add} poster />
          )}
        </div>
      </div>
    </div>
  )
}

// An 86'd dish stays visible but inert: it is information, not a dead end.
function Unavailable({ item, sectionName, currency, style, showImage }: CardProps) {
  const poster = style === 'poster'
  return (
    <div
      aria-disabled="true"
      className={`relative flex ${poster ? 'h-full flex-col overflow-hidden rounded-[22px]' : 'flex-col rounded-[28px] p-3.5'}
        border border-hairline theme-card opacity-45 saturate-50`}
    >
      <div className={poster ? '' : 'flex w-full flex-1 gap-3.5'}>
        {showImage && <Thumb item={item} qty={0} fill={poster} />}
        <div className={poster ? 'flex flex-1 flex-col gap-1 p-[18px]' : 'flex min-w-0 flex-1 flex-col'}>
          <span className="block text-[10px] font-black uppercase tracking-[0.12em] text-muted">
            {sectionName}
          </span>
          <span className={`block font-black text-ink ${poster ? 'text-[17px]' : 'truncate text-[15px]'}`}>
            {item.title}
          </span>
          <span className="mt-1 block text-lg font-black text-muted line-through">
            {money(item.price_cents, currency)}
          </span>
          <span className="mt-1 text-[11px] font-black uppercase tracking-[0.1em] text-coral">
            Épuisé
          </span>
        </div>
      </div>
    </div>
  )
}

function AddButton({ onClick }: { onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label="Ajouter au panier"
      className="grid h-11 w-11 place-items-center rounded-full bg-gradient-to-br from-pink-hot to-pink-deep
        text-white shadow-md transition active:scale-90"
    >
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3.2" strokeLinecap="round"><path d="M12 5v14M5 12h14" /></svg>
    </button>
  )
}

function PosterAddButton({ onClick }: { onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label="Ajouter au panier"
      className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-gradient-to-br from-pink-hot to-pink-deep
        text-white shadow-[0_6px_18px_-4px_rgb(255_45_158/0.5)] transition active:scale-90"
    >
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round"><path d="M12 5v14M5 12h14" /></svg>
    </button>
  )
}

function Stepper({
  item, qty, hasOptions, onAdd, poster = false,
}: {
  item: Product; qty: number; hasOptions: boolean; onAdd: () => void; poster?: boolean
}) {
  // A configurable product has no single line to step down, so the minus
  // becomes "remove all" — same rule as the Neo app.
  const dec = () => (hasOptions ? cart.removeProduct(item.ref) : cart.decrementProduct(item.ref))
  const btn = poster ? 'h-8 w-8' : 'h-9 w-9'
  const ico = poster ? 16 : 18

  return (
    <div className="flex select-none items-center gap-0.5 rounded-full bg-gradient-to-br from-pink-hot to-pink-deep p-1 text-white shadow-md">
      <button type="button" onClick={dec} aria-label={hasOptions ? 'Retirer du panier' : 'Retirer un'}
        className={`grid ${btn} place-items-center rounded-full transition hover:bg-black/10 active:scale-90`}>
        {hasOptions ? (
          <svg width={ico} height={ico} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round"><path d="M3 6h18M8 6V4h8v2M6 6l1 14h10l1-14" /></svg>
        ) : (
          <svg width={ico} height={ico} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3.2" strokeLinecap="round"><path d="M5 12h14" /></svg>
        )}
      </button>
      <span className="min-w-5 text-center text-sm font-black tabular-nums">{qty}</span>
      <button type="button" onClick={onAdd} aria-label="Ajouter un"
        className={`grid ${btn} place-items-center rounded-full transition hover:bg-black/10 active:scale-90`}>
        <svg width={ico} height={ico} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3.2" strokeLinecap="round"><path d="M12 5v14M5 12h14" /></svg>
      </button>
    </div>
  )
}

function Thumb({ item, qty, fill = false }: { item: Product; qty: number; fill?: boolean }) {
  const src = item.image_uri
  const box = fill ? 'aspect-square w-full' : 'h-[100px] w-[100px]'
  return (
    <div className={`relative overflow-hidden ${fill ? '' : 'rounded-[20px]'} ${box} bg-elevated`}>
      {src ? (
        <img
          src={src}
          alt=""
          loading="lazy"
          decoding="async"
          className="h-full w-full object-cover transition-transform duration-300 group-hover:scale-[1.04]"
        />
      ) : (
        <div className="grid h-full w-full place-items-center text-muted/40">
          <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"><path d="M3 5h18v14H3zM3 15l5-5 4 4 3-3 6 6" /></svg>
        </div>
      )}
      {qty > 0 && (
        <span className="absolute left-2 top-2 grid h-6 min-w-6 place-items-center rounded-full bg-pink px-1.5 text-[11px] font-black text-white">
          {qty}
        </span>
      )}
    </div>
  )
}
