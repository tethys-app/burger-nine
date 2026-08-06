export function money(cents: number | undefined, currency = 'EUR') {
  if (cents === undefined) return ''
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency }).format(cents / 100)
}

export function requirementLabel(min: number, max: number | null) {
  if (min > 0 && max === min) return `Choisissez ${min}`
  if (min > 0) return `Choisissez au moins ${min}`
  if (max !== null) return `Jusqu'à ${max}`
  return 'Facultatif'
}
