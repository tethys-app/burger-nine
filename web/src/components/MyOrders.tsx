import { useEffect, useState } from 'react'
import {
  customerToken, logout, myOrders, startLogin, verifyLogin, type CustomerOrder,
} from '../lib/api'
import { money, STATUS_LABELS } from '../lib/format'

export default function MyOrders() {
  const [session, setSession] = useState<{ phone?: string; orders: CustomerOrder[] }>()
  const [phone, setPhone] = useState('')
  const [code, setCode] = useState('')
  const [sent, setSent] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string>()

  // A stored token may still have expired, so a load is also a check.
  useEffect(() => {
    if (!customerToken()) return setSession({ orders: [] })
    myOrders().then(setSession).catch(() => { logout(); setSession({ orders: [] }) })
  }, [])

  const submit = async (event: React.FormEvent) => {
    event.preventDefault()
    setBusy(true)
    setError(undefined)
    try {
      if (!sent) {
        await startLogin(phone)
        setSent(true)
      } else {
        await verifyLogin(phone, code)
        setSession(await myOrders())
      }
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'Une erreur est survenue.')
    } finally {
      setBusy(false)
    }
  }

  if (!session) return <p className="muted">Chargement…</p>

  if (!session.phone) {
    return (
      <form className="login" onSubmit={submit}>
        <h1>Mes commandes</h1>
        <p className="muted">
          {sent
            ? `Code envoyé au ${phone}.`
            : 'Recevez un code par SMS pour retrouver vos commandes.'}
        </p>
        {!sent ? (
          <input
            type="tel" name="phone" autoComplete="tel" inputMode="tel"
            placeholder="06 12 34 56 78" required autoFocus
            value={phone} onChange={(e) => setPhone(e.target.value)}
          />
        ) : (
          <input
            type="text" name="code" autoComplete="one-time-code" inputMode="numeric"
            placeholder="123456" required autoFocus
            value={code} onChange={(e) => setCode(e.target.value)}
          />
        )}
        {error && <p className="error">{error}</p>}
        <button className="btn btn-solid" type="submit" disabled={busy}>
          {busy ? '…' : sent ? 'Se connecter' : 'Recevoir le code'}
        </button>
        {sent && (
          <button
            type="button" className="linky"
            onClick={() => { setSent(false); setCode(''); setError(undefined) }}
          >
            Changer de numéro
          </button>
        )}
      </form>
    )
  }

  return (
    <section className="history">
      <header>
        <h1>Mes commandes</h1>
        <button
          type="button" className="linky"
          onClick={() => { logout(); setSession({ orders: [] }); setSent(false); setPhone('') }}
        >
          Se déconnecter
        </button>
      </header>

      {session.orders.length === 0 && (
        <p className="muted">Aucune commande pour ce numéro.</p>
      )}

      <ol>
        {session.orders.map((order) => (
          <li key={order.id}>
            <a href={order.token ? `/order-status?id=${order.id}&token=${order.token}` : undefined}>
              <span className="when">
                {new Date(order.createdAt).toLocaleDateString('fr-FR', {
                  day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit',
                })}
              </span>
              <span className="what">
                {order.items.map((item) => `${item.quantity}× ${item.productName}`).join(', ')}
              </span>
              <span className="where">{order.store?.name}</span>
              <span className="state">{STATUS_LABELS[order.status]}</span>
              <span className="sum">{money(order.totals.totalCents)}</span>
            </a>
          </li>
        ))}
      </ol>
    </section>
  )
}
