import { useEffect, useMemo, useRef, useState } from 'react'
import { loadStripe } from '@stripe/stripe-js'
import { EmbeddedCheckoutProvider, EmbeddedCheckout } from '@stripe/react-stripe-js'
import { ApiFailure, checkout, getCatalog, getQuote, getStore } from '../lib/api'
import { livePollMs } from '../lib/live'
import { money, requirementLabel } from '../lib/format'
import type { Blocker, CartLine, Catalog, PaymentMethod, Product, Quote, ServiceType, Store } from '../lib/types'

type Props = { store: Store; catalog: Catalog; siteUrl: string }

// Read once at module scope, not per render. See lib/live.ts.
const pollMs = typeof window === 'undefined' ? 0 : livePollMs(window.location.search)

export default function OrderIsland({ store: buildStore, catalog: buildCatalog, siteUrl }: Props) {
  // Boots from the build-time snapshot, so there is no spinner on first paint.
  const [store, setStore] = useState(buildStore)
  const [catalog, setCatalog] = useState(buildCatalog)
  const [lines, setLines] = useState<CartLine[]>([])
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

  const add = (line: CartLine) => setLines((current) => [...current, line])
  const remove = (index: number) => setLines((current) => current.filter((_, i) => i !== index))

  return (
    <div className="order-app">
      <ServicePicker store={store} value={serviceType} onChange={setServiceType} />

      <div className="menu">
        {catalog.sections.map((section) => (
          <section key={section.id}>
            <h2>{section.title}</h2>
            {section.products.map((product) => (
              <button key={product.ref} className="product" onClick={() => openProduct(product, add, setEditing)}>
                <span className="title">{product.title}</span>
                <span className="price">{money(product.price_cents, store.currency)}</span>
              </button>
            ))}
          </section>
        ))}
      </div>

      {editing && (
        <ProductSheet
          product={editing}
          currency={store.currency}
          onCancel={() => setEditing(null)}
          onAdd={(line) => {
            add(line)
            setEditing(null)
          }}
        />
      )}

      <Cart
        lines={lines}
        quote={quote}
        stale={stale}
        cartError={cartError}
        store={store}
        serviceType={serviceType}
        onRemove={remove}
        onCheckout={() => setCheckoutOpen(true)}
      />

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
    </div>
  )
}

// A product with no required modifiers goes straight in; anything with choices
// opens the sheet. The sheet is what guarantees a malformed line never reaches
// the API — the server treats one as a bug and returns 422.
function openProduct(
  product: Product,
  add: (line: CartLine) => void,
  setEditing: (product: Product) => void,
) {
  if (product.modifiers.length === 0) {
    add({ productRef: product.ref, quantity: 1, choices: [] })
    return
  }
  setEditing(product)
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

function ServicePicker({
  store,
  value,
  onChange,
}: {
  store: Store
  value: ServiceType
  onChange: (next: ServiceType) => void
}) {
  // Already resolved server-side to what the brand sells — no filtering or
  // deduping needed, and no duplicates possible now that services are a record.
  if (store.services.length < 2) return null
  return (
    <div className="services">
      {store.services.map((service) => (
        <button
          key={service.type}
          data-active={service.type === value}
          onClick={() => onChange(service.type)}
        >
          {service.type === 'delivery' ? 'Livraison' : service.type === 'collection' ? 'À emporter' : 'Sur place'}
        </button>
      ))}
    </div>
  )
}

function ProductSheet({
  product,
  currency,
  onAdd,
  onCancel,
}: {
  product: Product
  currency: string
  onAdd: (line: CartLine) => void
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
            onAdd({
              productRef: product.ref,
              quantity: 1,
              choices: Object.entries(selected).flatMap(([modifierRef, refs]) =>
                refs.map((choiceRef) => ({ modifierRef, choiceRef })),
              ),
            })
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

function Cart({
  lines,
  quote,
  stale,
  cartError,
  store,
  serviceType,
  onRemove,
  onCheckout,
}: {
  lines: CartLine[]
  quote?: Quote
  stale: boolean
  cartError?: string
  store: Store
  serviceType: ServiceType
  onRemove: (index: number) => void
  onCheckout: () => void
}) {
  const currency = store.currency

  if (lines.length === 0) return <aside className="cart empty">Votre panier est vide.</aside>

  return (
    <aside className="cart">
      <ol>
        {(quote?.lines ?? []).map((item, index) => (
          <li key={index}>
            <span>{item.quantity}× {item.productName}</span>
            <span className="options">{item.options.map((option) => option.optionName).join(', ')}</span>
            <span className="price">{money(item.subtotalCents, currency)}</span>
            <button onClick={() => onRemove(index)} aria-label="Retirer">×</button>
          </li>
        ))}
      </ol>

      {quote?.blockers.map((blocker) => (
        <p key={blocker.code + blocker.line} className="blocker">{blockerLabel(blocker, quote, store, serviceType)}</p>
      ))}
      {cartError && <p className="error">Erreur de configuration du menu : {cartError}</p>}

      <dl className="totals" data-stale={stale}>
        <dt>Sous-total</dt>
        <dd>{money(quote?.totals.subtotalCents, currency)}</dd>
        {quote && quote.totals.deliveryFeeCents > 0 && (
          <>
            <dt>Livraison</dt>
            <dd>{money(quote.totals.deliveryFeeCents, currency)}</dd>
          </>
        )}
        <dt>Total</dt>
        <dd>{money(quote?.totals.totalCents, currency)}</dd>
      </dl>

      <button className="primary" type="button" disabled={!quote?.valid} onClick={onCheckout}>
        Commander — {money(quote?.totals.totalCents, currency)}
      </button>
    </aside>
  )
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
