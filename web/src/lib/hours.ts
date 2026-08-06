import type { Store } from './types'

const DAYS = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'] as const

/**
 * Today's opening slots, formatted for display ("11:30 – 14:00, 18:00 – 22:30").
 * A slot covering the whole day is shown as "24h/24" rather than "00:00 – 23:59".
 */
export function todayHours(store: Store) {
  const today = DAYS[new Date().getDay()]
  const slots = store.openingHours?.find((d) => d.day === today)?.slots ?? []
  if (!slots.length) return null
  if (slots.length === 1 && slots[0].from === '00:00' && slots[0].to === '23:59') return '24h/24'
  return slots.map((s) => `${s.from} – ${s.to}`).join(', ')
}

/**
 * When the store reopens, as a short French phrase. `nextOpenAt` is an epoch
 * ms timestamp from the API; it is absent when the store never reopens.
 */
export function reopensAt(store: Store) {
  if (!store.nextOpenAt) return null
  const next = new Date(store.nextOpenAt)
  const time = next.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })
  const midnight = new Date()
  midnight.setHours(24, 0, 0, 0)
  if (next < midnight) return `ouvre à ${time}`
  const tomorrow = new Date(midnight)
  tomorrow.setDate(tomorrow.getDate() + 1)
  if (next < tomorrow) return `ouvre demain ${time}`
  return `ouvre ${next.toLocaleDateString('fr-FR', { weekday: 'long' })} ${time}`
}
