// The /v1 contract, from the API package. Nothing is defined here — every type
// is derived from the server implementation, so there is one source of truth and
// a renamed field breaks this build instead of a customer's browser.
//
// When this template is copied into its own repo, change the dependency in
// package.json from `file:../../packages/api-types` to a published version. No
// source change is needed: the import specifier is already the package name.

export type {
  ServiceType,
  CartLine,
  PricedItem,
  Totals,
  Blocker,
  Quote,
  Store,
  Brand,
  Order,
  Address,
  OrderStatus,
  Section,
  Product,
  Modifier,
  Choice,
  Catalog,
  PaymentMethod,
  CheckoutRequest,
  CheckoutResponse,
  ApiError,
} from '@tethys/api-types'
