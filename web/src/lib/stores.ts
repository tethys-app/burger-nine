import type { Brand } from './types'

// The POC hardcoded a département label per card. The API only gives us an
// address, so derive it: the first two digits of a French zipcode are the
// department number. Corsica (2A/2B) is not in scope for this brand.
const DEPT_NAMES: Record<string, string> = {
  '01': 'AIN',
  '07': 'ARDÈCHE',
  '26': 'DRÔME',
  '38': 'ISÈRE',
  '42': 'LOIRE',
  '69': 'RHÔNE',
  '73': 'SAVOIE',
  '74': 'HAUTE-SAVOIE',
}

export type BrandStore = Brand['stores'][number]

export function deptOf(store: BrandStore) {
  const code = store.address?.zipcode?.slice(0, 2)
  if (!code) return null
  return { code, name: DEPT_NAMES[code] ?? null }
}

/** `RHÔNE · 69`, or just the code when the name is unknown. */
export function deptLabel(store: BrandStore) {
  const dept = deptOf(store)
  if (!dept) return null
  return dept.name ? `${dept.name} · ${dept.code}` : dept.code
}

// Title-case: the API returns cities shouted ("ROUSSILLON"), and the card CSS
// already uppercases. Storing the shouted form would lose the accents' casing
// for anything that doesn't.
export function cityOf(store: BrandStore) {
  const city = store.address?.city
  if (!city) return store.name
  return city
    .toLocaleLowerCase('fr')
    .replace(/(^|[\s'’-])([\p{L}])/gu, (_, sep, ch) => sep + ch.toLocaleUpperCase('fr'))
}

/** Connected stores grouped by département, both sorted for a stable render. */
export function byDepartment(stores: BrandStore[]) {
  const groups = new Map<string, { code: string; name: string | null; stores: BrandStore[] }>()
  for (const store of stores) {
    const dept = deptOf(store)
    const code = dept?.code ?? '__'
    const group = groups.get(code) ?? { code, name: dept?.name ?? null, stores: [] }
    group.stores.push(store)
    groups.set(code, group)
  }
  for (const group of groups.values()) {
    group.stores.sort((a, b) => cityOf(a).localeCompare(cityOf(b), 'fr'))
  }
  return [...groups.values()].sort((a, b) => a.code.localeCompare(b.code))
}
