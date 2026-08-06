import { useSyncExternalStore } from 'react'
import type { CartLine, Product } from '../../lib/types'

// Ported from the Neo app's cart-store.ts, retyped onto the /v1 contract:
// `CartLine` here is the API's order-shaped line, so what the cart holds is
// exactly what POST /quote is sent. Display prices below are for the card and
// the drawer only — the total the customer pays always comes from the quote.
export type Entry = {
  key: string
  line: CartLine
  product: Product
  unitPriceCents: number
  qty: number
}

const choiceRefs = (line: CartLine) =>
  (line.choices ?? []).map((c) => `${c.modifierRef}:${c.choiceRef}`).sort().join(',')

export const lineKey = (line: CartLine) => `${line.productRef}#${choiceRefs(line)}`

class CartStore {
  private entries = new Map<string, Entry>()
  private listeners = new Set<() => void>()
  private snap: Entry[] = []

  subscribe = (cb: () => void) => {
    this.listeners.add(cb)
    return () => void this.listeners.delete(cb)
  }

  private emit() {
    this.snap = [...this.entries.values()]
    this.listeners.forEach((l) => l())
  }

  list = () => this.snap

  add(product: Product, line: CartLine, unitPriceCents: number, qty = 1) {
    const key = lineKey(line)
    const existing = this.entries.get(key)
    if (existing) existing.qty += qty
    else this.entries.set(key, { key, line, product, unitPriceCents, qty })
    this.emit()
  }

  increment(key: string) {
    const entry = this.entries.get(key)
    if (!entry) return
    entry.qty += 1
    this.emit()
  }

  decrement(key: string) {
    const entry = this.entries.get(key)
    if (!entry) return
    if (entry.qty <= 1) this.entries.delete(key)
    else entry.qty -= 1
    this.emit()
  }

  /** Step a product down by one, targeting its simplest line. */
  decrementProduct(productRef: string) {
    const entry = [...this.entries.values()]
      .filter((e) => e.line.productRef === productRef)
      .sort((a, b) => (a.line.choices?.length ?? 0) - (b.line.choices?.length ?? 0))[0]
    if (entry) this.decrement(entry.key)
  }

  /** Remove every line for a product — the bin button on a configurable row. */
  removeProduct(productRef: string) {
    for (const [k, e] of this.entries) if (e.line.productRef === productRef) this.entries.delete(k)
    this.emit()
  }

  clear() {
    this.entries.clear()
    this.emit()
  }
}

export const cart = new CartStore()

export function useCartEntries() {
  return useSyncExternalStore(cart.subscribe, cart.list, cart.list)
}

export function useProductQty(productRef: string) {
  return useCartEntries().reduce((a, e) => (e.line.productRef === productRef ? a + e.qty : a), 0)
}

export function cartTotals(entries: Entry[]) {
  return entries.reduce(
    (acc, e) => ({ count: acc.count + e.qty, totalCents: acc.totalCents + e.unitPriceCents * e.qty }),
    { count: 0, totalCents: 0 },
  )
}

/** What POST /quote and POST /checkout are sent. */
export const toApiLines = (entries: Entry[]): CartLine[] =>
  entries.map((e) => ({ ...e.line, quantity: e.qty }))
