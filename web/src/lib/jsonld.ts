import type { Catalog, Store } from './types'

// schema.org Restaurant/Menu is the actual SEO payoff for a food site — it is
// what produces rich results and the menu panel. Generated from the catalog so
// no franchise has to think about it.
export function restaurantJsonLd(store: Store, catalog: Catalog, siteUrl?: string) {
  return {
    '@context': 'https://schema.org',
    '@type': 'Restaurant',
    name: store.name,
    url: siteUrl,
    telephone: store.phone ?? undefined,
    priceRange: '€€',
    address: store.address
      ? {
          '@type': 'PostalAddress',
          streetAddress: store.address.street ?? undefined,
          postalCode: store.address.zipcode ?? undefined,
          addressLocality: store.address.city ?? undefined,
          addressCountry: store.address.country ?? undefined,
        }
      : undefined,
    geo:
      store.address?.latitude != null && store.address?.longitude != null
        ? { '@type': 'GeoCoordinates', latitude: store.address.latitude, longitude: store.address.longitude }
        : undefined,
    openingHoursSpecification: store.openingHours.flatMap((entry) =>
      entry.slots.map((slot) => ({
        '@type': 'OpeningHoursSpecification',
        dayOfWeek: `https://schema.org/${entry.day[0].toUpperCase()}${entry.day.slice(1)}`,
        opens: slot.from,
        closes: slot.to,
      })),
    ),
    hasMenu: {
      '@type': 'Menu',
      hasMenuSection: catalog.sections.map((section) => ({
        '@type': 'MenuSection',
        name: section.title,
        hasMenuItem: section.products.map((product) => ({
          '@type': 'MenuItem',
          name: product.title,
          description: product.description || undefined,
          offers: {
            '@type': 'Offer',
            price: (product.price_cents / 100).toFixed(2),
            priceCurrency: store.currency,
          },
        })),
      })),
    },
  }
}
