// Commune centres for each store, from geo.api.gouv.fr (official French
// commune dataset), keyed by store slug and resolved from the store's zipcode.
//
// These live here because the API returns `latitude: null` for every store. As
// soon as it returns real coordinates, delete this file and read them from the
// address — `coordsFor` already prefers the API value.
export const STORE_COORDS: Record<string, { lat: number; lon: number }> = {
  'b9-beaurepaire': { lat: 45.3376, lon: 5.0439 },
  'b9-ferney-voltaire': { lat: 46.252, lon: 6.1061 },
  'b9-le-pont-de-beauvoisin': { lat: 45.5304, lon: 5.6622 },
  'b9-lyon-7': { lat: 45.758, lon: 4.8351 },
  'b9-mornant': { lat: 45.6162, lon: 4.6747 },
  'b9-nine-la-cote': { lat: 45.3844, lon: 5.2586 },
  'b9-saint-jean-de-bournay': { lat: 45.4964, lon: 5.145 },
  'b9-saint-vallier': { lat: 45.1794, lon: 4.8201 },
  'b9-sainte-colombe': { lat: 45.5247, lon: 4.8582 },
  'b9-tain-l-hermitage': { lat: 45.068, lon: 4.8488 },
  'b9-tassin': { lat: 45.7637, lon: 4.7521 },
  'b9-vaugneray': { lat: 45.73, lon: 4.6502 },
  'burger-nine-annonay': { lat: 45.2449, lon: 4.6419 },
  'burger-nine-condrieu': { lat: 45.4748, lon: 4.7516 },
  'burger-nine-gex': { lat: 46.3515, lon: 6.0488 },
  'burger-nine-roussillon': { lat: 45.3818, lon: 4.8133 },
}
