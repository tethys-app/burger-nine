import Foundation
import SwiftUI

/// Client for the public, unauthenticated storefront API.
///
/// The brand slug is part of every brand-scoped URL. There is intentionally no
/// endpoint here for listing all brands or all stores outside Burger Nine.
@MainActor
enum MenuAPI {
    static let brandSlug = BurgerNineConfig.brandSlug

    enum APIError: LocalizedError {
        case invalidURL
        case httpError(Int, String)
        case invalidResponse
        case invalidQuote
        case paymentConfigurationMissing

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Adresse API invalide"
            case let .httpError(status, message): return "Erreur API " + String(status) + " : " + message
            case .invalidResponse: return "Réponse API invalide"
            case .invalidQuote: return "Le panier n'est plus valide"
            case .paymentConfigurationMissing: return "Le paiement Stripe n'est pas configuré pour ce point de vente"
            }
        }
    }

    // MARK: Public storefront reads

    static func fetchSnapshot() async throws -> StorefrontSnapshot {
        let brand = try await fetchBrand()
        var locations: [LocationSnapshot] = []
        try await withThrowingTaskGroup(of: LocationSnapshot.self) { group in
            for store in brand.stores {
                group.addTask {
                    try await fetchLocationSnapshot(slug: store.slug)
                }
            }
            for try await location in group {
                locations.append(location)
            }
        }
        let order = brand.stores.map(\.slug)
        locations.sort {
            (order.firstIndex(of: $0.store.slug) ?? 0) < (order.firstIndex(of: $1.store.slug) ?? 0)
        }
        return StorefrontSnapshot(brand: brand, locations: locations)
    }

    static func fetchBrand() async throws -> BrandResponse {
        try await request(path: [])
    }

    static func fetchLocation(slug: String) async throws -> StoreLocation {
        let snapshot = try await fetchLocationSnapshot(slug: slug)
        return StoreLocation.from(store: snapshot.store, catalog: snapshot.catalog, brandName: nil)
    }

    static func fetchLocationSnapshot(slug: String) async throws -> LocationSnapshot {
        let store: StoreResponse = try await request(path: ["stores", slug])
        let catalog: CatalogResponse = try await request(path: ["stores", slug, "catalog"])
        return LocationSnapshot(store: store, catalog: catalog)
    }

    static func locations(from snapshot: StorefrontSnapshot) -> [StoreLocation] {
        let brand = StoreBrand(
            franchiseID: snapshot.brand.slug,
            appName: snapshot.brand.name,
            titleDescription: nil,
            newProductsDescription: nil,
            descriptionText: nil,
            primaryColor: Color(red: 0.08, green: 0.06, blue: 0.05),
            secondaryColor: Color(red: 0.96, green: 0.44, blue: 0.12),
            logoURL: nil,
            splashURL: nil,
            featuredItems: []
        )
        return snapshot.locations.map {
            StoreLocation.from(store: $0.store, catalog: $0.catalog, brandName: brand.appName).withBrand(brand)
        }
    }

    // MARK: Authoritative pricing and checkout

    static func quote(
        slug: String,
        lines: [CartLineRequest],
        serviceType: String,
        paymentMethod: String = "online"
    ) async throws -> QuoteResponse {
        try await request(
            path: ["stores", slug, "quote"],
            method: "POST",
            body: QuoteRequest(lines: lines, serviceType: serviceType, paymentMethod: paymentMethod)
        )
    }

    static func checkout(
        slug: String,
        lines: [CartLineRequest],
        serviceType: String,
        customer: CustomerRequest,
        deliveryAddress: DeliveryAddressRequest?,
        idempotencyKey: String
    ) async throws -> CheckoutResponse {
        try await request(
            path: ["stores", slug, "checkout"],
            method: "POST",
            body: CheckoutRequest(
                lines: lines,
                serviceType: serviceType,
                customer: customer,
                deliveryAddress: deliveryAddress,
                idempotencyKey: idempotencyKey,
                sessionId: nil,
                returnUrl: BurgerNineConfig.siteURL.absoluteString + "/order-status?id={ORDER_ID}",
                paymentFlow: "native_payment_sheet"
            )
        )
    }

    static func order(id: String, token: String) async throws -> OrderStatusResponse {
        guard var components = URLComponents(string: BurgerNineConfig.apiURL.absoluteString) else {
            throw APIError.invalidURL
        }
        components.path = ["v1", "orders", id].reduce(components.path) { path, component in
            path + (path.hasSuffix("/") ? "" : "/") + component
        }
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = components.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? JSONDecoder().decode(APIErrorResponse.self, from: data)
            throw APIError.httpError(http.statusCode, error?.message ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OrderStatusResponse.self, from: data)
    }

    static func cartLine(line: CartLine, quantity: Int) -> CartLineRequest {
        let modifierByOption = Dictionary(
            uniqueKeysWithValues: line.item.optionGroups.flatMap { group in
                group.items.map { ($0.id, group.id) }
            }
        )
        let choices = line.selectedOptions.compactMap { option -> ChoiceRequest? in
            guard let modifierRef = modifierByOption[option.id] else { return nil }
            return ChoiceRequest(modifierRef: modifierRef, choiceRef: option.id)
        }
        return CartLineRequest(productRef: line.item.id, quantity: quantity, choices: choices, note: nil)
    }

    // MARK: Transport

    private static func request<Response: Decodable>(
        path: [String],
        method: String = "GET"
    ) async throws -> Response {
        try await request(path: path, method: method, body: Optional<EmptyBody>.none)
    }

    private static func request<Response: Decodable, Body: Encodable>(
        path: [String],
        method: String = "GET",
        body: Body? = nil
    ) async throws -> Response {
        guard var url = URL(string: BurgerNineConfig.apiURL.absoluteString) else {
            throw APIError.invalidURL
        }
        let scopedPath = ["v1", "brands", brandSlug] + path
        url = scopedPath.reduce(url) { $0.appendingPathComponent($1) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? JSONDecoder().decode(APIErrorResponse.self, from: data)
            throw APIError.httpError(http.statusCode, error?.message ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.invalidResponse
        }
    }

    // MARK: Wire types

    struct StorefrontSnapshot: Codable {
        let brand: BrandResponse
        let locations: [LocationSnapshot]
    }

    struct LocationSnapshot: Codable {
        let store: StoreResponse
        let catalog: CatalogResponse
    }

    struct BrandResponse: Codable {
        let slug: String
        let name: String
        let siteUrl: String?
        let stores: [BrandStore]
    }

    struct BrandStore: Codable {
        let slug: String
        let name: String
        let address: WireAddress?
    }

    struct StoreResponse: Codable {
        let slug: String
        let name: String
        let phone: String?
        let address: WireAddress?
        let currency: String
        let isOpen: Bool
        let openingHours: [OpeningHoursDay]
        let services: [Service]
        let paymentMethods: [String]
        let stripeAccountId: String?
        let stripePublishableKey: String?
    }

    struct Service: Codable {
        let type: String
        let feeCents: Int
        let minimumOrderCents: Int?
        let preparationTimeMinutes: Int?
    }

    struct OpeningHoursDay: Codable {
        let day: String
        let slots: [OpeningSlot]
    }

    struct OpeningSlot: Codable {
        let from: String
        let to: String
    }

    struct WireAddress: Codable {
        let street: String?
        let zipcode: String?
        let city: String?
        let country: String?

        var display: String {
            [street, zipcode, city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        }
    }

    struct CatalogResponse: Codable {
        let version: String
        let sections: [CatalogSection]
    }

    struct CatalogSection: Codable {
        let id: String
        let title: String
        let products: [CatalogProduct]
    }

    struct CatalogProduct: Codable {
        let ref: String
        let title: String
        let description: String
        let ingredients: [String]
        let priceCents: Int
        let imageUri: String?
        let modifiers: [CatalogModifier]
    }

    struct CatalogModifier: Codable {
        let ref: String
        let title: String
        let min: Int
        let max: Int?
        let choices: [CatalogChoice]
    }

    struct CatalogChoice: Codable {
        let ref: String
        let title: String
        let priceCents: Int
    }

    struct CartLineRequest: Encodable {
        let productRef: String
        let quantity: Int
        let choices: [ChoiceRequest]
        let note: String?
    }

    struct ChoiceRequest: Encodable {
        let modifierRef: String
        let choiceRef: String
    }

    struct QuoteRequest: Encodable {
        let lines: [CartLineRequest]
        let serviceType: String
        let paymentMethod: String
    }

    struct QuoteResponse: Decodable {
        let catalogVersion: String
        let lines: [PricedLine]
        let totals: Totals
        let valid: Bool
        let blockers: [Blocker]
    }

    struct PricedLine: Decodable {
        let productRef: String
        let productName: String
        let quantity: Int
        let unitPriceCents: Int
        let subtotalCents: Int
        let options: [PricedOption]
    }

    struct PricedOption: Decodable {
        let modifierRef: String
        let modifierName: String
        let optionRef: String
        let optionName: String
        let priceCents: Int
    }

    struct Totals: Decodable {
        let subtotalCents: Int
        let commissionCents: Int
        let taxCents: Int
        let deliveryFeeCents: Int
        let totalCents: Int
    }

    struct Blocker: Decodable {
        let code: String
        let message: String
        let line: Int?
    }

    struct CustomerRequest: Encodable {
        let name: String
        let email: String?
        let phone: String
    }

    struct DeliveryAddressRequest: Encodable {
        let street: String
        let zipcode: String
        let city: String
        let country: String?
        let latitude: Double?
        let longitude: Double?
        let note: String?
    }

    struct CheckoutRequest: Encodable {
        let lines: [CartLineRequest]
        let serviceType: String
        let customer: CustomerRequest
        let deliveryAddress: DeliveryAddressRequest?
        let idempotencyKey: String
        let sessionId: String?
        let returnUrl: String
        let paymentFlow: String
    }

    struct CheckoutResponse: Decodable {
        let orderId: String
        let orderToken: String
        let paymentMethod: String
        let clientSecret: String?
    }

    enum OrderStatus: String, Decodable {
        case pendingPayment = "pending_payment"
        case paymentFailed = "payment_failed"
        case new
        case received
        case accepted
        case inPreparation = "in_preparation"
        case awaitingCollection = "awaiting_collection"
        case inDelivery = "in_delivery"
        case completed
        case rejected
        case cancelled
        case deliveryFailed = "delivery_failed"
    }

    struct OrderStatusResponse: Decodable {
        let id: String
        let status: OrderStatus
        let serviceType: String
        let customer: CustomerResponse
        let deliveryAddress: OrderAddress?
        let items: [PricedLine]
        let totals: Totals
        let createdAt: Double
        let store: OrderStore?
    }

    struct CustomerResponse: Decodable {
        let name: String?
        let email: String?
        let phone: String?
    }

    struct OrderAddress: Decodable {
        let street: String
        let zipcode: String
        let city: String
        let country: String?
        let note: String?
    }

    struct OrderStore: Decodable {
        let slug: String
        let name: String
    }

    private struct APIErrorResponse: Decodable {
        let code: String?
        let message: String
    }

    private struct EmptyBody: Encodable {}
}

private extension StoreLocation {
    static func from(
        store: MenuAPI.StoreResponse,
        catalog: MenuAPI.CatalogResponse,
        brandName: String?
    ) -> StoreLocation {
        let brand = StoreBrand(
            franchiseID: MenuAPI.brandSlug,
            appName: brandName ?? "Burger Nine",
            titleDescription: nil,
            newProductsDescription: nil,
            descriptionText: nil,
            primaryColor: Color(red: 0.08, green: 0.06, blue: 0.05),
            secondaryColor: Color(red: 0.96, green: 0.44, blue: 0.12),
            logoURL: nil,
            splashURL: nil,
            featuredItems: []
        )
        let sections = catalog.sections.enumerated().map { index, section in
            MenuSection(
                id: section.id,
                name: section.title,
                subtitle: String(section.products.count) + " produit" + (section.products.count == 1 ? "" : "s"),
                position: index,
                items: section.products.map { product in
                    MenuItem(
                        id: product.ref,
                        name: product.title,
                        description: product.description,
                        price: Double(product.priceCents) / 100,
                        image: product.imageUri ?? "",
                        tag: product.ingredients.first ?? "",
                        optionGroups: product.modifiers.enumerated().map { modifierIndex, modifier in
                            MenuOptionGroup(
                                id: modifier.ref,
                                name: modifier.title,
                                min: modifier.min,
                                max: modifier.max,
                                allowsMultiple: (modifier.max ?? 1) > 1,
                                position: modifierIndex,
                                items: modifier.choices.enumerated().map { choiceIndex, choice in
                                    MenuOptionItem(
                                        id: choice.ref,
                                        name: choice.title,
                                        price: Double(choice.priceCents) / 100,
                                        position: choiceIndex
                                    )
                                }
                            )
                        }
                    )
                }
            )
        }
        let orderTypes = store.services.map(\.type)
        let preparation = store.services.compactMap(\.preparationTimeMinutes).min() ?? 15
        let today = Calendar.current.component(.weekday, from: Date()) - 1
        let days = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        let todaySlots = store.openingHours.first(where: { $0.day == days[today] })?.slots.map { "\($0.from)-\($0.to)" } ?? []

        return StoreLocation(
            id: store.slug,
            displayName: store.name,
            addressLine: store.address?.display ?? "",
            city: store.address?.city,
            postalCode: store.address?.zipcode,
            brand: brand,
            sections: sections,
            featuredItem: sections.flatMap(\.items).first,
            preparationTime: preparation,
            isClosed: !store.isOpen,
            todaySlots: todaySlots,
            orderTypes: orderTypes,
            stripeAccountId: store.stripeAccountId,
            stripePublishableKey: store.stripePublishableKey
        )
    }
}

private extension StoreLocation {
    func withBrand(_ brand: StoreBrand) -> StoreLocation {
        StoreLocation(
            id: id,
            displayName: displayName,
            addressLine: addressLine,
            city: city,
            postalCode: postalCode,
            brand: brand,
            sections: sections,
            featuredItem: featuredItem,
            preparationTime: preparationTime,
            isClosed: isClosed,
            todaySlots: todaySlots,
            orderTypes: orderTypes,
            stripeAccountId: stripeAccountId,
            stripePublishableKey: stripePublishableKey
        )
    }
}
