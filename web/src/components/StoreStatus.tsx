import { useEffect, useState } from 'react'
import { getStore } from '../lib/api'
import { reopensAt, todayHours } from '../lib/hours'
import type { Store } from '../lib/types'

// Open/closed sits next to the address in the header. The build snapshot is
// days stale by design, so the flag is re-fetched on mount — a page built at
// noon must not tell a visitor at midnight that the shop is open.
export default function StoreStatus({ store: initial }: { store: Store }) {
  const [store, setStore] = useState(initial)

  useEffect(() => {
    getStore(initial.slug).then(setStore).catch(() => {})
  }, [initial.slug])

  const hours = todayHours(store)
  const reopen = reopensAt(store)

  return (
    <span className="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-1 text-[12px] font-semibold text-muted">
      {store.address?.street && (
        <span>
          {store.address.street}, {store.address.zipcode} {store.address.city}
        </span>
      )}

      <span
        className={`inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-[11px] font-bold ${
          store.isOpen ? 'bg-emerald/15 text-emerald' : 'bg-coral/15 text-coral'
        }`}
      >
        <span className={`h-1.5 w-1.5 rounded-full ${store.isOpen ? 'bg-emerald' : 'bg-coral'}`} />
        {store.isOpen ? 'Ouvert' : 'Fermé'}
      </span>

      {/* Open: today's hours. Closed: when it comes back. */}
      {store.isOpen
        ? hours && <span className="text-muted/80">{hours}</span>
        : reopen && <span className="text-muted/80">{reopen}</span>}
    </span>
  )
}
