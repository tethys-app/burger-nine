import { useEffect, useState } from 'react'
import { getOrder } from '../lib/api'
import { money, STATUS_LABELS as LABELS } from '../lib/format'
import type { Order } from '../lib/types'

export default function OrderStatus() {
  const [order, setOrder] = useState<Order>()
  const [error, setError] = useState<string>()

  useEffect(() => {
    const params = new URLSearchParams(location.search)
    const stored = safeParse(localStorage.getItem('lastOrder'))
    const id = params.get('id') ?? stored?.id
    const token = params.get('token') ?? stored?.token
    if (!id || !token) {
      setError('Lien de commande incomplet.')
      return
    }

    let cancelled = false
    let timer: ReturnType<typeof setTimeout>

    // The webhook is what marks an order paid, so poll until it lands — usually
    // under a second. The return_url itself proves nothing.
    const poll = async () => {
      try {
        const next = await getOrder(id, token)
        if (cancelled) return
        setOrder(next)
        if (next.status === 'pending_payment') timer = setTimeout(poll, 1000)
      } catch {
        if (!cancelled) setError('Commande introuvable.')
      }
    }
    poll()

    return () => {
      cancelled = true
      clearTimeout(timer)
    }
  }, [])

  if (error) return <p className="error">{error}</p>
  if (!order) return <p>Chargement…</p>

  return (
    <section className="status">
      <h1>{LABELS[order.status]}</h1>
      {order.store && <p className="store">{order.store.name}</p>}
      <ol>
        {order.items.map((item, index) => (
          <li key={index}>
            <span>{item.quantity}× {item.productName}</span>
            <span className="options">{item.options.map((option) => option.optionName).join(', ')}</span>
            <span className="price">{money(item.subtotalCents)}</span>
          </li>
        ))}
      </ol>
      <p className="total">Total {money(order.totals.totalCents)}</p>
    </section>
  )
}

function safeParse(value: string | null): { id: string; token: string } | null {
  if (!value) return null
  try {
    return JSON.parse(value)
  } catch {
    return null
  }
}
