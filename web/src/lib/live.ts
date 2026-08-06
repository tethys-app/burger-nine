/**
 * `?live` re-fetches the catalog on an interval, so a menu being edited in the
 * backoffice updates without a reload. `?live=5` sets the interval in seconds;
 * `?live=1` is the fastest allowed.
 *
 * Clamped to 1–60s: the value comes from the URL, so it must not be able to
 * become a request flood. Returns 0 (off) unless asked for — a normal customer
 * never polls.
 */
export const LIVE_DEFAULT_MS = 3000

export function livePollMs(search: string) {
  const value = new URLSearchParams(search).get('live')
  if (value === null) return 0
  // Present but not a usable interval: `?live`, `?live=on`, `?live=true`.
  if (value === '' || value === 'on' || value === 'true') return LIVE_DEFAULT_MS
  const seconds = Number(value)
  if (!Number.isFinite(seconds) || seconds <= 0) return LIVE_DEFAULT_MS
  return Math.min(Math.max(seconds, 1), 60) * 1000
}
