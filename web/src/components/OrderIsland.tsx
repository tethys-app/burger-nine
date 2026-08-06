import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { loadStripe } from '@stripe/stripe-js'
import { EmbeddedCheckoutProvider, EmbeddedCheckout } from '@stripe/react-stripe-js'
import { ApiFailure, checkout, getCatalog, getQuote, getStore } from '../lib/api'
import { livePollMs } from '../lib/live'
import { money, requirementLabel } from '../lib/format'
import { cart, toApiLines, useCartEntries, type Entry } from './menu/cart-store'
import { ProductCard } from './menu/ProductCard'
import { CategoryNav, CategoryRail } from './menu/CategoryRail'
import { CartPanel } from './menu/CartPanel'
import type { Blocker, CartLine, Catalog, PaymentMethod, Product, Quote, Section, ServiceType, Store } from '../lib/types'

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
        serviceType={serviceType}
        onServiceChange={setServiceType}
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
  store, catalog, serviceType, onServiceChange, entries, quote, stale, cartError,
  onConfigure, onAdd, onCheckout,
}: {
  store: Store
  catalog: Catalog
  serviceType: ServiceType
  onServiceChange: (next: ServiceType) => void
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
      <ServicePills store={store} value={serviceType} onChange={onServiceChange} />
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
                <h2 className="font-display text-xl font-black uppercase text-ink lg:text-2xl">
                  {section.title}
                </h2>
              </header>
              <div className="grid gap-3 grid-cols-[repeat(auto-fill,minmax(300px,1fr))]">
                {section.products.map((product) => (
                  <ProductCard
                    key={product.ref}
                    item={product}
                    sectionName={section.title}
                    currency={store.currency}
                    style="row"
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

// Service picker, styled as the Neo header's pills.
function ServicePills({
  store, value, onChange,
}: {
  store: Store; value: ServiceType; onChange: (next: ServiceType) => void
}) {
  if (store.services.length < 2) return null
  const label = (t: ServiceType) =>
    t === 'delivery' ? '🛵 Livraison' : t === 'collection' ? '🥡 À emporter' : '🪑 Sur place'
  return (
    <div className="mx-auto flex w-full max-w-[1500px] gap-2 px-4 pt-4 lg:px-6">
      {store.services.map((service) => (
        <button
          key={service.type}
          onClick={() => onChange(service.type)}
          className={`rounded-full px-4 py-2 text-[13px] font-semibold transition
            ${service.type === value
              ? 'bg-gradient-to-br from-pink-hot to-pink-deep text-white shadow-md'
              : 'border border-hairline bg-elevated/50 text-muted hover:text-ink'}`}
        >
          {label(service.type)}
        </button>
      ))}
    </div>
  )
}

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

  // Mirrors the server's rules so the button is only enabled for a line the
  // server will accept. The server still enforces it — this is UX, not trust.
  const satisfied = product.modifiers.every((modifier) => {
    const chosen = selected[modifier.ref] ?? []
    return chosen.length >= modifier.min && (modifier.max === null || chosen.length <= modifier.max)
  })

  const extra = product.modifiers.reduce((sum, modifier) => {
    const chosen = selected[modifier.ref] ?? []
    return sum + chosen.reduce((inner, ref) => {
      const choice = modifier.choices.find((entry) => entry.ref === ref)
      return inner + (choice?.price_cents ?? 0)
    }, 0)
  }, 0)

  return (
    <>
      <div className="sheet-backdrop" onClick={onCancel} />
      <div className="sheet" role="dialog" aria-modal="true" aria-label={product.title}>
      <header>
        <h3>{product.title}</h3>
        <button onClick={onCancel} aria-label="Fermer">×</button>
      </header>
      {product.description && <p className="description">{product.description}</p>}

      {product.modifiers.map((modifier) => (
        <fieldset key={modifier.ref}>
          <legend>
            {modifier.title}
            <span className="requirement">{requirementLabel(modifier.min, modifier.max)}</span>
          </legend>
          {modifier.choices.map((choice) => (
            <label key={choice.ref}>
              <input
                type={modifier.max === 1 ? 'radio' : 'checkbox'}
                name={modifier.ref}
                checked={(selected[modifier.ref] ?? []).includes(choice.ref)}
                onChange={() => toggle(modifier.ref, choice.ref, modifier.max)}
              />
              <span>{choice.title}</span>
              {choice.price_cents > 0 && <span className="price">+{money(choice.price_cents, currency)}</span>}
            </label>
          ))}
        </fieldset>
      ))}

      <footer>
        <button
          className="primary"
          disabled={!satisfied}
          onClick={() =>
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
        >
          Ajouter — {money(product.price_cents + extra, currency)}
        </button>
      </footer>
      </div>
    </>
  )
}

// Blockers arrive with both a `code` and a developer-facing English `message`.
// Localise on the code; fall back to the message only for codes we don't know.
function blockerLabel(blocker: Blocker, quote: Quote, store: Store, serviceType: ServiceType) {
  const currency = store.currency
  switch (blocker.code) {
    case 'below_minimum': {
      // Per service now, so read the one being ordered rather than a flat value.
      const minimum = store.services.find((service) => service.type === serviceType)?.minimumOrderCents ?? 0
      const missing = minimum - quote.totals.subtotalCents
      return missing > 0
        ? `Ajoutez ${money(missing, currency)} pour atteindre le minimum de ${money(minimum, currency)}.`
        : `Commande minimum de ${money(minimum, currency)} non atteinte.`
    }
    case 'store_closed':
      return 'Le restaurant est fermé pour le moment.'
    case 'accepting_paused':
      return `Le restaurant a suspendu les commandes${blocker.message ? ` — ${blocker.message}` : ''}.`
    case 'service_unavailable':
      return 'Ce mode de commande n’est pas proposé par ce restaurant.'
    case 'item_unavailable':
      return 'Un article de votre panier n’est plus disponible.'
    case 'payment_method_unavailable':
      return 'Ce mode de paiement n’est pas accepté par ce restaurant.'
    case 'no_brand':
      // Misconfiguration rather than drift, but the customer can only be told
      // that ordering is unavailable.
      return 'La commande en ligne n’est pas encore disponible pour ce restaurant.'
    default:
      return blocker.message
  }
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
  clientSecret,
  onCheckout,
  onClose,
}: {
  store: Store
  quote?: Quote
  serviceType: ServiceType
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
