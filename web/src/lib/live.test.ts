import { expect, test, describe } from 'bun:test'
import { LIVE_DEFAULT_MS, livePollMs } from './live'

// The value is attacker-controllable in production, so the clamp is the point:
// no URL may turn a customer's browser into a request flood.
describe('livePollMs', () => {
  test('off unless asked for', () => {
    expect(livePollMs('')).toBe(0)
    expect(livePollMs('?other=1')).toBe(0)
  })

  test('present but valueless means the default', () => {
    for (const search of ['?live', '?live=', '?live=on', '?live=true']) {
      expect(livePollMs(search)).toBe(LIVE_DEFAULT_MS)
    }
  })

  test('a number is seconds', () => {
    expect(livePollMs('?live=5')).toBe(5000)
    expect(livePollMs('?live=1')).toBe(1000)
  })

  test('never faster than 1s, never slower than 60s', () => {
    expect(livePollMs('?live=0.001')).toBe(1000)
    expect(livePollMs('?live=99999')).toBe(60000)
  })

  test('garbage falls back rather than producing NaN or a tight loop', () => {
    for (const search of ['?live=abc', '?live=NaN', '?live=Infinity', '?live=0', '?live=-5']) {
      const result = livePollMs(search)
      expect(Number.isFinite(result)).toBe(true)
      expect(result).toBeGreaterThanOrEqual(1000)
    }
  })
})
