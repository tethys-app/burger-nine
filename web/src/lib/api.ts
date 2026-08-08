import type {
  Catalog,
  CheckoutRequest,
  CheckoutResponse,
  Brand,
  Order,
  Quote,
  ServiceType,
  Store,
  CartLine,
  ApiError,
} from './types'

// No credentials in this repo — see CLAUDE.md. The brand slug identifies which
// site this is; it authorises nothing. Catalogs and prices are public data, and
// the Stripe publishable key now comes from GET /store so it can never disagree
// with the connected account it is paired with.
export const API_URL = import.meta.env.PUBLIC_NEO_API_URL
export const BRAND = import.meta.env.PUBLIC_BRAND_SLUG

const base = () => `${API_URL}/v1/brands/${encodeURIComponent(BRAND)}`

export class ApiFailure extends Error {
  constructor(
    readonly status: number,
    readonly body: ApiError,
  ) {
    super(body.message)
    this.name = 'ApiFailure'
  }
}

async function call<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${base()}${path}`, {
    ...init,
    headers: { 'Content-Type': 'application/json', ...init?.headers },
  })
  if (!response.ok) {
    const body = (await response.json().catch(() => null)) as ApiError | null
    throw new ApiFailure(response.status, body ?? { code: 'unknown', message: response.statusText })
  }
  return response.json() as Promise<T>
}

export const getBrand = () => call<Brand>('')
export const getStore = (slug: string, init?: RequestInit) =>
  call<Store>(`/stores/${slug}`, init)
export const getCatalog = (slug: string, init?: RequestInit) =>
  call<Catalog>(`/stores/${slug}/catalog`, init)

/** Authoritative. The only thing that decides whether a cart can be ordered. */
export const getQuote = (slug: string, lines: CartLine[], serviceType: ServiceType) =>
  call<Quote>(`/stores/${slug}/quote`, {
    method: 'POST',
    body: JSON.stringify({ lines, serviceType }),
  })

export const checkout = (slug: string, request: CheckoutRequest) =>
  call<CheckoutResponse>(`/stores/${slug}/checkout`, {
    method: 'POST',
    body: JSON.stringify(request),
  })

// ─── my orders ───────────────────────────────────────────────────────────────
// Identity is a phone number proved over SMS, carried as a bearer token.
//
// Deliberately not a cookie: the API is necessarily on another origin (this site
// has no server — invariant #1), and Safari's ITP drops cross-site cookies, so a
// cookie session would never work on an iPhone. The token only ever grants
// reading one phone number's own orders, so it is not a credential in the sense
// invariant #2 is about — and it is minted per customer, never shipped in the
// bundle.

const TOKEN_KEY = 'customerToken'

export const customerToken = () => localStorage.getItem(TOKEN_KEY)

export type CustomerOrder = Pick<
  Order, 'id' | 'status' | 'serviceType' | 'items' | 'totals' | 'createdAt' | 'store'
> & { token: string | null }

// Not brand-scoped in the path: one session spans the customer, and the brand
// is a query param on the read.
async function customer<T>(path: string, init?: RequestInit): Promise<T> {
  const token = customerToken()
  const response = await fetch(`${API_URL}/v1/customer${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...init?.headers,
    },
  })
  if (!response.ok) {
    const body = (await response.json().catch(() => null)) as ApiError | null
    throw new ApiFailure(response.status, body ?? { code: 'unknown', message: response.statusText })
  }
  return response.json() as Promise<T>
}

export const startLogin = (phone: string) =>
  customer<{ sent: true }>('/start', {
    method: 'POST',
    body: JSON.stringify({ phone }),
  })

export async function verifyLogin(phone: string, code: string) {
  const session = await customer<{ phone: string; token: string }>('/verify', {
    method: 'POST',
    body: JSON.stringify({ phone, code }),
  })
  localStorage.setItem(TOKEN_KEY, session.token)
  return session
}

/** Nothing server-side to revoke — the token simply stops being sent. */
export const logout = () => localStorage.removeItem(TOKEN_KEY)

export const myOrders = () =>
  customer<{ phone: string; orders: CustomerOrder[] }>(
    `/orders?brand=${encodeURIComponent(BRAND)}`,
  )

// Not brand-scoped: the order token is what guards it.
export const getOrder = (id: string, token: string) =>
  fetch(`${API_URL}/v1/orders/${id}?token=${encodeURIComponent(token)}`)
    .then(async (response) => {
      if (!response.ok) {
        const body = (await response.json().catch(() => null)) as ApiError | null
        throw new ApiFailure(response.status, body ?? { code: 'unknown', message: response.statusText })
      }
      return response.json() as Promise<Order>
    })
