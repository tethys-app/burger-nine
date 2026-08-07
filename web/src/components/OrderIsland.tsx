import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { loadStripe } from '@stripe/stripe-js'
import { EmbeddedCheckoutProvider, EmbeddedCheckout } from '@stripe/react-stripe-js'
import { ApiFailure, checkout, getCatalog, getQuote, getStore } from '../lib/api'
import { livePollMs } from '../lib/live'
import { money } from '../lib/format'
import { cart, toApiLines, useCartEntries, type Entry } from './menu/cart-store'
import { ProductCard } from './menu/ProductCard'
import { CategoryNav, CategoryRail } from './menu/CategoryRail'
import { CartPanel } from './menu/CartPanel'
import type { CartLine, Catalog, PaymentMethod, Product, Quote, ServiceType, Store } from '../lib/types'

type Props = { store: Store; catalog: Catalog; siteUrl: string }

// Read once at module scope, not per render. See lib/live.ts.
const pollMs = typeof window === 'undefined' ? 0 : livePollMs(window.location.search)

export default function OrderIsland({ store: buildStore, catalog: buildCatalog, siteUrl }: Props) {
  // Boots from the build-time snapshot, so there is no spinner on first paint.
  const [store, setStore] = useState(buildStore)
  const [catalog, setCatalog] = useState(buildCatalog)
  // The cart lives in a store (ported from the Neo app) so a product card deep
  // in the grid can read its own quantity without the whole menu re-rendering.
  const entries = useCartEntries()
  const lines = useMemo(() => toApiLines(entries), [entries])
  const [serviceType, setServiceType] = useState<ServiceType>(
    store.services[0]?.type ?? 'collection',
  )
  const [editing, setEditing] = useState<Product | null>(null)
  const [clientSecret, setClientSecret] = useState<string>()
  // The checkout modal owns customer details and, once paid for, the Stripe
  // form — so the right-hand panel stays a summary rather than a form.
  const [checkoutOpen, setCheckoutOpen] = useState(false)

  // The page ships a static, crawlable copy of the menu. Once this island is
  // live it owns the menu, so retire the static one — it stays in the HTML for
  // crawlers and for visitors without JS.
  useEffect(() => {
    document.querySelector('.static-menu')?.setAttribute('hidden', '')
  }, [])

  // Store settings are small and operational: always replace the build-time
  // copy so service availability, opening hours, and payment configuration are
  // current before a customer starts an order.
  useEffect(() => {
    getStore(buildStore.slug, { cache: 'no-store' })
      .then((live) => {
        setStore(live)
        setServiceType((current) =>
          live.services.some((service) => service.type === current)
            ? current
            : (live.services[0]?.type ?? 'collection'),
        )
      })
      .catch(() => {})
  }, [buildStore.slug])

  // The snapshot can be days old; this is what greys out a dish 86'd at 12:40.
  // With `?live=1` it repeats, so catalog edits show up without a reload — open
  // the storefront beside the backoffice while working on a menu.
  // `version` changes on every store or snapshot write, so state is only set
  // when something actually changed: polling costs a request, not a re-render.
  useEffect(() => {
    let current = buildCatalog.version
    const refresh = () =>
      getCatalog(buildStore.slug, { cache: 'no-store' })
        .then((live) => {
          if (live.version === current) return
          current = live.version
          setCatalog(live)
        })
        .catch(() => {})

    void refresh()
    if (!pollMs) return
    const timer = setInterval(refresh, pollMs)
    return () => clearInterval(timer)
  }, [buildStore.slug, buildCatalog.version])

  const { quote, stale, cartError } = useQuote(store.slug, lines, serviceType)

  return (
    <>
      <MenuLayout
        store={store}
        catalog={catalog}
        entries={entries}
        quote={quote}
        stale={stale}
        cartError={cartError}
        onConfigure={setEditing}
        onAdd={(product) =>
          cart.add(product, { productRef: product.ref, quantity: 1, choices: [] }, product.price_cents)
        }
        onCheckout={() => setCheckoutOpen(true)}
      />

      {editing && (
        <ProductSheet
          product={editing}
          currency={store.currency}
          onCancel={() => setEditing(null)}
          onAdd={(line, unitPriceCents) => {
            cart.add(editing, line, unitPriceCents)
            setEditing(null)
          }}
        />
      )}

      {checkoutOpen && (
        <CheckoutModal
          store={store}
          quote={quote}
          serviceType={serviceType}
          onServiceChange={setServiceType}
          clientSecret={clientSecret}
          onClose={() => {
            setCheckoutOpen(false)
            // Abandoning a started payment: drop the secret so reopening asks
            // for a fresh session rather than resuming a stale one.
            setClientSecret(undefined)
          }}
          onCheckout={async (customer, paymentMethod) => {
            const response = await checkout(store.slug, {
              lines,
              serviceType,
              customer,
              paymentMethod,
              idempotencyKey: crypto.randomUUID(),
              returnUrl: `${siteUrl}/order-status?id={ORDER_ID}`,
            })
            localStorage.setItem(
              'lastOrder',
              JSON.stringify({ id: response.orderId, token: response.orderToken }),
            )
            // Paying offline means the order is already placed — there is no
            // Stripe step, so go straight to the confirmation.
            if (response.paymentMethod === 'offline' || !response.clientSecret) {
              location.href = `/order-status?id=${response.orderId}&token=${response.orderToken}`
              return
            }
            setClientSecret(response.clientSecret)
          }}
        />
      )}
    </>
  )
}

// Ported from the Neo app's menu-client.tsx: category rail + sticky left nav +
// card grid + docked cart, with the same IntersectionObserver scroll-spy.
function MenuLayout({
  store, catalog, entries, quote, stale, cartError,
  onConfigure, onAdd, onCheckout,
}: {
  store: Store
  catalog: Catalog
  entries: Entry[]
  quote?: Quote
  stale: boolean
  cartError?: string
  onConfigure: (product: Product) => void
  onAdd: (product: Product) => void
  onCheckout: () => void
}) {
  const sections = catalog.sections
  const [active, setActive] = useState(sections[0]?.id ?? '')
  const sectionRefs = useRef(new Map<string, HTMLElement>())
  const tapScrolling = useRef(false)

  useEffect(() => {
    const obs = new IntersectionObserver(
      (list) => {
        if (tapScrolling.current) return
        const visible = list
          .filter((e) => e.isIntersecting)
          .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top)
        if (visible[0]) setActive(visible[0].target.id)
      },
      { rootMargin: '-102px 0px -65% 0px', threshold: 0 },
    )
    sectionRefs.current.forEach((el) => obs.observe(el))
    return () => obs.disconnect()
  }, [sections])

  const scrollTo = useCallback((id: string) => {
    const el = sectionRefs.current.get(id)
    if (!el) return
    setActive(id)
    tapScrolling.current = true
    el.scrollIntoView({ behavior: 'smooth', block: 'start' })
    window.setTimeout(() => (tapScrolling.current = false), 650)
  }, [])

  const register = useCallback((id: string, el: HTMLElement | null) => {
    if (el) sectionRefs.current.set(id, el)
    else sectionRefs.current.delete(id)
  }, [])

  return (
    <>
      <CategoryRail sections={sections} active={active} onSelect={scrollTo} />

      <div className="mx-auto flex w-full max-w-[1500px] gap-6 px-4 lg:px-6">
        <CategoryNav sections={sections} active={active} onSelect={scrollTo} />

        <div className="min-w-0 flex-1 pb-32 pt-2 lg:pb-12">
          {sections.map((section) => (
            <section key={section.id} className="pt-8 first:pt-2">
              <header
                id={section.id}
                ref={(el) => register(section.id, el)}
                className="mb-4 flex scroll-mt-[101px] flex-col gap-1 border-b border-hairline pb-2.5
                  lg:scroll-mt-[52px] lg:flex-row lg:items-baseline lg:gap-3"
              >
                <h2 className="menu-section-title menu-title font-display text-xl font-black uppercase text-ink lg:text-2xl">
                  {section.title}
                </h2>
              </header>
              {/* Poster cards are squarer than row cards, so they pack more per
                  row — same breakpoints as the Neo app's `columns: auto`. */}
              <div className="grid gap-3 grid-cols-2 sm:grid-cols-3 2xl:grid-cols-4">
                {section.products.map((product) => (
                  <ProductCard
                    key={product.ref}
                    item={product}
                    sectionName={section.title}
                    currency={store.currency}
                    style="poster"
                    showImage
                    onConfigure={onConfigure}
                    onAdd={onAdd}
                  />
                ))}
              </div>
            </section>
          ))}
        </div>

        <CartPanel
          variant="sidebar"
          entries={entries}
          currency={store.currency}
          quote={quote}
          stale={stale}
          error={cartError}
          onCheckout={onCheckout}
        />
      </div>

      <div className="lg:hidden">
        <CartPanel
          variant="floating"
          entries={entries}
          currency={store.currency}
          quote={quote}
          stale={stale}
          error={cartError}
          onCheckout={onCheckout}
        />
      </div>
    </>
  )
}

export const serviceLabel = (t: ServiceType) =>
  t === 'delivery' ? '🛵 Livraison' : t === 'collection' ? '🥡 À emporter' : '🪑 Sur place'

function useQuote(slug: string, lines: CartLine[], serviceType: ServiceType) {
  const [quote, setQuote] = useState<Quote>()
  const [cartError, setCartError] = useState<string>()
  const last = useRef<Quote>(undefined)
  const key = useMemo(() => JSON.stringify({ lines, serviceType }), [lines, serviceType])

  useEffect(() => {
    if (lines.length === 0) {
      setQuote(undefined)
      last.current = undefined
      return
    }
    setQuote(undefined)
    const timer = setTimeout(() => {
      getQuote(slug, lines, serviceType)
        .then((result) => {
          setQuote(result)
          setCartError(undefined)
        })
        .catch((error) => {
          // 422 means this storefront built an impossible line. Surface it
          // loudly rather than pretending the cart is fine.
          if (error instanceof ApiFailure && error.status === 422) setCartError(error.body.message)
        })
    }, 150)
    return () => clearTimeout(timer)
  }, [slug, key])

  if (quote) last.current = quote
  return { quote: quote ?? last.current, stale: quote === undefined, cartError }
}


function ProductSheet({
  product,
  currency,
  onAdd,
  onCancel,
}: {
  product: Product
  currency: string
  onAdd: (line: CartLine, unitPriceCents: number) => void
  onCancel: () => void
}) {
  const [selected, setSelected] = useState<Record<string, string[]>>({})
  const [step, setStep] = useState(0)
  const advanceTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(() => () => {
    if (advanceTimer.current) clearTimeout(advanceTimer.current)
  }, [])

  const toggle = (modifierRef: string, choiceRef: string, max: number | null) => {
    setSelected((current) => {
      const chosen = current[modifierRef] ?? []
      if (chosen.includes(choiceRef)) {
        return { ...current, [modifierRef]: chosen.filter((ref) => ref !== choiceRef) }
      }
      if (max === 1) return { ...current, [modifierRef]: [choiceRef] }
      if (max !== null && chosen.length >= max) return current
      return { ...current, [modifierRef]: [...chosen, choiceRef] }
    })
  }

  const validModifier = (modifier: Product['modifiers'][number]) => {
    const chosen = selected[modifier.ref] ?? []
    return chosen.length >= modifier.min && (modifier.max === null || chosen.length <= modifier.max)
  }

  // Mirrors the server's rules so the final add action only builds an accepted
  // v1 line. The API remains authoritative when the cart is quoted.
  const satisfied = product.modifiers.every(validModifier)
  const current = product.modifiers[step]
  const isLast = step === product.modifiers.length - 1
  const currentValid = current ? validModifier(current) : true

  const extra = product.modifiers.reduce((sum, modifier) => {
    const chosen = selected[modifier.ref] ?? []
    return sum + chosen.reduce((inner, ref) => {
      const choice = modifier.choices.find((entry) => entry.ref === ref)
      return inner + (choice?.price_cents ?? 0)
    }, 0)
  }, 0)

  const selectedTitles = product.modifiers.flatMap((modifier) => {
    const selectedRefs = selected[modifier.ref] ?? []
    return modifier.choices
      .filter((choice) => selectedRefs.includes(choice.ref))
      .map((choice) => choice.title)
  })

  const add = () => {
    if (!satisfied) return
    onAdd(
      {
        productRef: product.ref,
        quantity: 1,
        choices: Object.entries(selected).flatMap(([modifierRef, refs]) =>
          refs.map((choiceRef) => ({ modifierRef, choiceRef })),
        ),
      },
      product.price_cents + extra,
    )
  }

  const continueFunnel = () => {
    if (!currentValid) return
    if (isLast) add()
    else setStep((value) => value + 1)
  }

  const selectChoice = (choiceRef: string) => {
    if (!current) return
    const wasSelected = (selected[current.ref] ?? []).includes(choiceRef)
    toggle(current.ref, choiceRef, current.max)

    // Preserve the legacy funnel's quick path: required single-choice steps
    // briefly acknowledge the pick, then reveal the next modifier.
    if (!wasSelected && current.max === 1 && current.min > 0 && !isLast) {
      if (advanceTimer.current) clearTimeout(advanceTimer.current)
      advanceTimer.current = setTimeout(
        () => setStep((value) => Math.min(value + 1, product.modifiers.length - 1)),
        180,
      )
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center sm:items-center">
      <div className="absolute inset-0 bg-black/55 backdrop-blur-sm" onClick={onCancel} />
      <div
        className="funnel-sheet relative flex max-h-[88dvh] w-full flex-col rounded-t-[32px] border pop-in sm:max-w-lg sm:rounded-[32px]"
        role="dialog"
        aria-modal="true"
        aria-label={product.title}
      >
        <header className="flex items-start gap-3 border-b p-5">
          {product.image_uri && (
            <img src={product.image_uri} alt="" className="h-16 w-16 rounded-2xl object-cover" />
          )}
          <div className="min-w-0 flex-1">
            <h3 className="text-xl font-black">{product.title}</h3>
            {selectedTitles.length > 0 ? (
              <p className="line-clamp-2 text-xs font-semibold funnel-muted">{selectedTitles.join(', ')}</p>
            ) : product.description ? (
              <p className="line-clamp-2 text-xs font-semibold funnel-muted">{product.description}</p>
            ) : null}
          </div>
          <button
            type="button"
            aria-label="Fermer"
            onClick={onCancel}
            className="funnel-close grid h-9 w-9 shrink-0 place-items-center rounded-full transition"
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round"><path d="M6 6l12 12M18 6 6 18" /></svg>
          </button>
        </header>

        {product.modifiers.length > 1 && (
          <div className="flex items-center gap-2 px-5 pt-4" aria-label={`Étape ${step + 1} sur ${product.modifiers.length}`}>
            {product.modifiers.map((modifier, index) => (
              <span
                key={modifier.ref}
                className={`funnel-progress h-1.5 flex-1 rounded-full transition ${index <= step ? 'funnel-progress-active' : ''}`}
              />
            ))}
            <span className="funnel-step-count funnel-muted ml-1 shrink-0 text-[11px] font-black">{step + 1}/{product.modifiers.length}</span>
          </div>
        )}

        <div className="min-h-0 flex-1 overflow-y-auto p-5">
          {current && (
            <fieldset className="m-0 border-0 p-0">
              <legend className="mb-2.5 flex w-full items-baseline justify-between gap-3">
                <span className="text-sm font-black">{current.title}</span>
                <span className="funnel-requirement funnel-muted shrink-0 text-[11px] font-bold uppercase tracking-wide">
                  {current.min > 0 ? 'Obligatoire' : 'Optionnel'}
                  {current.max !== null && current.max !== 1 ? ` · max ${current.max}` : ''}
                </span>
              </legend>
              <div className="space-y-2">
                {current.choices.map((choice) => {
                  const isSelected = (selected[current.ref] ?? []).includes(choice.ref)
                  return (
                    <button
                      key={choice.ref}
                      type="button"
                      aria-pressed={isSelected}
                      onClick={() => selectChoice(choice.ref)}
                      className={`funnel-choice flex w-full items-center gap-3 rounded-2xl border p-3 text-left transition ${
                        isSelected ? 'funnel-choice-selected' : ''
                      }`}
                    >
                      <span className={`grid h-5 w-5 shrink-0 place-items-center border-2 ${current.max === 1 ? 'rounded-full' : 'rounded-md'} ${
                        isSelected ? 'funnel-choice-mark-selected' : 'funnel-choice-mark'
                      }`}>
                        {isSelected && <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="4" strokeLinecap="round" strokeLinejoin="round"><path d="M5 13l4 4L19 7" /></svg>}
                      </span>
                      <span className="flex-1 text-sm font-bold">{choice.title}</span>
                      {choice.price_cents > 0 && <span className="funnel-gold text-sm font-black">+{money(choice.price_cents, currency)}</span>}
                    </button>
                  )
                })}
              </div>
            </fieldset>
          )}
        </div>

        <footer className="flex items-center gap-2 border-t p-4 pb-[max(1rem,env(safe-area-inset-bottom))]">
          {step > 0 && (
            <button
              type="button"
              onClick={() => setStep((value) => value - 1)}
              aria-label="Étape précédente"
              className="funnel-back grid h-[52px] w-[52px] shrink-0 place-items-center rounded-[18px] border transition active:scale-95"
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"><path d="M15 18l-6-6 6-6" /></svg>
            </button>
          )}
          <button
            type="button"
            disabled={!currentValid}
            onClick={continueFunnel}
            className="funnel-primary flex flex-1 items-center justify-between rounded-[22px] bg-gradient-to-br px-5 py-4 font-black shadow-lg transition active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-40 disabled:active:scale-100"
          >
            <span>{isLast ? 'Ajouter au panier' : 'Continuer'}</span>
            <span>{money(product.price_cents + extra, currency)}</span>
          </button>
        </footer>
      </div>
    </div>
  )
}

function checkoutFailureLabel(error: unknown) {
  if (!(error instanceof ApiFailure)) return 'Le paiement n’a pas pu démarrer. Réessayez.'
  switch (error.body.code) {
    case 'payments_unconfigured':
      return 'Ce restaurant ne peut pas encore encaisser de paiement en ligne.'
    case 'not_orderable':
      return 'Votre panier n’est plus commandable — vérifiez les articles ci-dessus.'
    case 'store_not_found':
      return 'Ce restaurant n’est plus disponible.'
    default:
      // 422s here are storefront bugs; show them rather than hiding them.
      return error.status === 422
        ? `Erreur de configuration du menu : ${error.body.message}`
        : 'Le paiement n’a pas pu démarrer. Réessayez.'
  }
}


/**
 * Customer details, then Stripe, in one dialog. Payment stays inline rather than
 * replacing the page: the cart stays visible behind it, and closing returns to a
 * cart that is still intact.
 */
function CheckoutModal({
  store,
  quote,
  serviceType,
  onServiceChange,
  clientSecret,
  onCheckout,
  onClose,
}: {
  store: Store
  quote?: Quote
  serviceType: ServiceType
  onServiceChange: (next: ServiceType) => void
  clientSecret?: string
  onCheckout: (
    customer: { name: string; email: string; phone: string },
    paymentMethod: PaymentMethod,
  ) => Promise<void>
  onClose: () => void
}) {
  const [customer, setCustomer] = useState({ name: '', email: '', phone: '' })
  const [submitting, setSubmitting] = useState(false)
  const [failure, setFailure] = useState<string>()
  const [offline, setOffline] = useState(false)
  const currency = store.currency
  // Where the money changes hands is decided by the service, so the server does
  // not model it — one 'offline' method, labelled per service here.
  const offlineLabel = serviceType === 'delivery'
    ? 'Payer à la livraison'
    : serviceType === 'eat_in' ? 'Payer sur place' : 'Payer au retrait'

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key === 'Escape') onClose() }
    document.addEventListener('keydown', onKey)
    // The page behind must not scroll while the dialog is up.
    const previous = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => {
      document.removeEventListener('keydown', onKey)
      document.body.style.overflow = previous
    }
  }, [onClose])

  const paying = Boolean(clientSecret && store.stripePublishableKey)

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div
        className="modal"
        role="dialog"
        aria-modal="true"
        aria-label="Finaliser la commande"
        onClick={(event) => event.stopPropagation()}
      >
        <header>
          <h2>{paying ? 'Paiement' : 'Vos coordonnées'}</h2>
          <button type="button" className="close" onClick={onClose} aria-label="Fermer">×</button>
        </header>

        {paying ? (
          <EmbeddedCheckoutProvider
            // Direct charges: payment happens on the brand's connected account.
            // Both values come from GET /store, so the key and the account match.
            stripe={loadStripe(store.stripePublishableKey!, {
              stripeAccount: store.stripeAccountId ?? undefined,
            })}
            options={{ clientSecret: clientSecret! }}
          >
            <EmbeddedCheckout />
          </EmbeddedCheckoutProvider>
        ) : (
          <form
            onSubmit={async (event) => {
              event.preventDefault()
              setSubmitting(true)
              setFailure(undefined)
              try {
                await onCheckout(customer, offline ? 'offline' : 'online')
              } catch (error) {
                setFailure(checkoutFailureLabel(error))
              } finally {
                setSubmitting(false)
              }
            }}
          >
            {/* How you get the order is decided here, not in the header: it
                changes the delivery fee and the minimum, so it belongs with
                the other order details. Re-quotes on change. */}
            {store.services.length > 1 && (
              <fieldset className="service-choice">
                <legend>Comment récupérer votre commande&nbsp;?</legend>
                <div>
                  {store.services.map((service) => (
                    <label key={service.type} data-on={service.type === serviceType}>
                      <input
                        type="radio"
                        name="service"
                        value={service.type}
                        checked={service.type === serviceType}
                        onChange={() => onServiceChange(service.type)}
                      />
                      <span className="label">{serviceLabel(service.type)}</span>
                      <span className="hint">
                        {service.preparationTimeMinutes
                          ? `≈ ${service.preparationTimeMinutes} min`
                          : 'Dès que prêt'}
                        {service.feeCents ? ` · ${money(service.feeCents, currency)}` : ' · offert'}
                      </span>
                    </label>
                  ))}
                </div>
              </fieldset>
            )}

            <input
              required
              autoFocus
              placeholder="Nom"
              value={customer.name}
              onChange={(event) => setCustomer({ ...customer, name: event.target.value })}
            />
            <input
              required
              type="tel"
              placeholder="Téléphone"
              value={customer.phone}
              onChange={(event) => setCustomer({ ...customer, phone: event.target.value })}
            />
            <input
              type="email"
              placeholder="Email (facultatif)"
              value={customer.email}
              onChange={(event) => setCustomer({ ...customer, email: event.target.value })}
            />
            {store.paymentMethods.includes('offline') && (
              <label className="on-site">
                <input type="checkbox" checked={offline} onChange={(event) => setOffline(event.target.checked)} />
                <span>{offlineLabel}</span>
              </label>
            )}
            {failure && <p className="error">{failure}</p>}
            <button className="primary" type="submit" disabled={!quote?.valid || submitting}>
              {submitting
                ? offline ? 'Envoi de la commande…' : 'Ouverture du paiement…'
                : offline
                  ? `Commander — ${money(quote?.totals.totalCents, currency)}`
                  : `Payer ${money(quote?.totals.totalCents, currency)}`}
            </button>
          </form>
        )}
      </div>
    </div>
  )
}
