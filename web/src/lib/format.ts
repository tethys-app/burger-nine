import type { Order } from './types'

export const STATUS_LABELS: Record<Order['status'], string> = {
  pending_payment: 'Confirmation du paiement…',
  payment_failed: 'Le paiement n’a pas abouti.',
  new: 'Commande reçue',
  received: 'Commande reçue',
  accepted: 'Commande acceptée',
  in_preparation: 'En préparation',
  awaiting_collection: 'Prête — à récupérer',
  in_delivery: 'En livraison',
  completed: 'Terminée',
  rejected: 'Refusée par le restaurant',
  cancelled: 'Annulée',
  delivery_failed: 'Échec de la livraison',
}

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
