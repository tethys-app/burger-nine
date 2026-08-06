import { useEffect, useRef } from 'react'
import { reopensAt, todayHours } from '../lib/hours'
import type { Store } from '../lib/types'

// Ported from the Neo app's mobile-hero.tsx. A tall hero that morphs into a
// compact sticky bar as you scroll: logo 72→44px, name 20→15px, address and
// service pills fade then collapse. Desktop uses the static banner instead.
export default function MobileHero({ store, logo }: { store: Store; logo: string }) {
  const heroRef = useRef<HTMLDivElement>(null)
  const logoWrapRef = useRef<HTMLDivElement>(null)
  const nameRef = useRef<HTMLSpanElement>(null)
  const detailsRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const hero = heroRef.current
    const logoWrap = logoWrapRef.current
    const nameEl = nameRef.current
    const detailsEl = detailsRef.current
    if (!hero) return

    let rafId = 0
    let lastP = -1
    // Measured once, while the hero is still at full height. Re-reading it each
    // frame feeds the collapsed height back into the ratio, so the hero latches
    // shut on the first scroll and never reopens.
    const heroH = hero.offsetHeight || 80

    const update = () => {
      const raw = Math.min(1, window.scrollY / heroH)
      // Clamp to 2 decimals to avoid micro-updates on every frame.
      const p = Math.round(raw * 100) / 100
      if (p === lastP) return
      lastP = p

      const logoSize = 44 + (1 - p) * 28
      if (logoWrap) {
        logoWrap.style.width = `${logoSize}px`
        logoWrap.style.height = `${logoSize}px`
      }
      if (nameEl) nameEl.style.fontSize = `${15 + (1 - p) * 5}px`
      if (detailsEl) {
        detailsEl.style.opacity = String(Math.max(0, 1 - p * 2.5))
        detailsEl.style.maxHeight = `${p > 0.85 ? 0 : 60}px`
      }
      hero.style.paddingTop = `${8 + (1 - p) * 8}px`
      hero.style.paddingBottom = `${8 + (1 - p) * 6}px`
    }

    const onScroll = () => {
      cancelAnimationFrame(rafId)
      rafId = requestAnimationFrame(update)
    }

    window.addEventListener('scroll', onScroll, { passive: true })
    update()
    return () => {
      window.removeEventListener('scroll', onScroll)
      cancelAnimationFrame(rafId)
    }
  }, [])

  const address = store.address?.street
    ? `${store.address.street}, ${store.address.zipcode} ${store.address.city}`
    : ''

  return (
    <div
      ref={heroRef}
      className="sticky top-0 z-40 border-b border-hairline bg-surface/90 backdrop-blur-xl lg:hidden"
      style={{ paddingTop: 16, paddingBottom: 14 }}
    >
      <div className="flex items-center gap-3 px-4">
        <div ref={logoWrapRef} className="relative shrink-0" style={{ width: 72, height: 72 }}>
          <a
            href="/"
            className="relative grid h-full w-full place-items-center overflow-hidden rounded-xl transition hover:opacity-80"
          >
            <img src={logo} alt={store.name} className="h-full w-full object-contain" />
          </a>
        </div>

        <div className="min-w-0 flex-1">
          <span ref={nameRef} className="block truncate font-black text-ink" style={{ fontSize: 20 }}>
            {store.name}
          </span>

          <div ref={detailsRef} style={{ opacity: 1, maxHeight: 60, overflow: 'hidden' }}>
            {address && (
              <span className="mt-0.5 block truncate text-[11px] font-semibold text-muted">{address}</span>
            )}
            {/* Open/closed, not the service pills — picking a service now
                happens at checkout, where it affects the total. */}
            <div className="mt-1.5 flex select-none flex-wrap items-center gap-1.5">
              <span
                className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-bold ${
                  store.isOpen ? 'bg-emerald/15 text-emerald' : 'bg-coral/15 text-coral'
                }`}
              >
                <span className={`h-1.5 w-1.5 rounded-full ${store.isOpen ? 'bg-emerald' : 'bg-coral'}`} />
                {store.isOpen ? 'Ouvert' : 'Fermé'}
              </span>
              {(store.isOpen ? todayHours(store) : reopensAt(store)) && (
                <span className="text-[10px] font-semibold text-muted">
                  {store.isOpen ? todayHours(store) : reopensAt(store)}
                </span>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
