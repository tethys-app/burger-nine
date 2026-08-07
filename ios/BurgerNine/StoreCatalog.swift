import Foundation
import SQLite3
import SwiftUI
import Compression

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct StoreCatalog {
    let brand: StoreBrand
    let locations: [StoreLocation]

    static let defaultFranchiseID = "burger-nine"
    static let shared: StoreCatalog = load(franchiseID: defaultFranchiseID) ?? load() ?? .empty

    static let empty = StoreCatalog(
        brand: StoreBrand(
            franchiseID: defaultFranchiseID,
            appName: "Burger Nine",
            titleDescription: nil,
            newProductsDescription: nil,
            descriptionText: nil,
            primaryColor: Color(red: 0.10, green: 0.10, blue: 0.10),
            secondaryColor: Color(red: 0.44, green: 0.89, blue: 0.98),
            logoURL: nil,
            splashURL: nil,
            featuredItems: []
        ),
        locations: []
    )

    static func load(franchiseID requestedFranchiseID: String? = nil) -> StoreCatalog? {
        guard let database = StoreDatabase.openBundled() else { return nil }
        defer { database.close() }

        let franchiseID = requestedFranchiseID ?? database.firstFranchiseIDWithProducts() ?? defaultFranchiseID
        guard let brand = database.brand(franchiseID: franchiseID) else { return nil }

        let locations = database.locations(franchiseID: franchiseID, brand: brand)
        guard !locations.isEmpty else { return nil }

        return StoreCatalog(brand: brand, locations: locations)
    }

    static func availableFranchises() -> [FranchiseSummary] {
        guard let database = StoreDatabase.openBundled() else { return [] }
        defer { database.close() }
        return database.franchises()
    }

    // Returns (franchiseID, product) for a product ID, opening the DB briefly.
    static func findProduct(id: String) -> (franchiseID: String, item: MenuItem)? {
        guard let database = StoreDatabase.openBundled() else { return nil }
        defer { database.close() }
        guard let franchiseID = database.franchiseID(forProductID: id),
              let item = database.product(id: id) else { return nil }
        return (franchiseID, item)
    }

    func location(id: String?) -> StoreLocation? {
        guard let id else { return locations.first }
        return locations.first(where: { $0.id == id }) ?? locations.first
    }
}

private final class StoreDatabase {
    private var handle: OpaquePointer?

    private init(handle: OpaquePointer) {
        self.handle = handle
    }

    static func openBundled() -> StoreDatabase? {
        // Try compressed .lzfse first
        if let compressedURL = Bundle.main.url(forResource: "stores.sqlite", withExtension: "lzfse")
                ?? Bundle.main.url(forResource: "stores.sqlite", withExtension: "lzfse", subdirectory: "StoreData") {
            return openCompressed(compressedURL)
        }

        // Fallback to uncompressed .sqlite
        let databaseURL = Bundle.main.url(forResource: "stores", withExtension: "sqlite")
            ?? Bundle.main.url(forResource: "stores", withExtension: "sqlite", subdirectory: "StoreData")

        guard let url = databaseURL else { return nil }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            if let handle {
                sqlite3_close(handle)
            }
            return nil
        }

        return StoreDatabase(handle: handle)
    }

    private static func openCompressed(_ compressedURL: URL) -> StoreDatabase? {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let decompressedURL = cacheDir.appendingPathComponent("stores.sqlite")

        // Decompress to cache on first run
        if !FileManager.default.fileExists(atPath: decompressedURL.path) {
            guard let compressed = try? Data(contentsOf: compressedURL) else { return nil }

            let decompressed = compressed.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> Data? in
                let maxSize = 2_000_000_000 // 2GB max decompressed size
                var output = Data(count: maxSize)
                let written = output.withUnsafeMutableBytes { outPtr -> Int in
                    compression_decode_buffer(
                        outPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        maxSize,
                        ptr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        ptr.count,
                        UnsafeMutableRawPointer?.none,
                        COMPRESSION_LZFSE)
                }
                guard written > 0 else { return nil }
                return output.prefix(written)
            }

            guard let decompressed else { return nil }
            try? decompressed.write(to: decompressedURL)
        }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(decompressedURL.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            if let handle {
                sqlite3_close(handle)
            }
            return nil
        }

        return StoreDatabase(handle: handle)
    }

    func close() {
        guard let handle else { return }
        sqlite3_close(handle)
        self.handle = nil
    }

    func firstFranchiseIDWithProducts() -> String? {
        let franchiseID = queryOne(
            """
            SELECT franchises.id
            FROM franchises
            WHERE EXISTS (
                SELECT 1
                FROM stores
                JOIN products ON products.store_id = stores.id
                WHERE stores.franchise_id = franchises.id
                LIMIT 1
            )
            ORDER BY CASE WHEN franchises.id = ? THEN 0 ELSE 1 END, franchises.app_name
            LIMIT 1
            """,
            bindings: [.text(StoreCatalog.defaultFranchiseID)]
        ) { statement in
            text(statement, 0) ?? ""
        }
        return franchiseID?.isEmpty == false ? franchiseID : nil
    }

    func franchises() -> [FranchiseSummary] {
        query(
            """
            SELECT franchises.id, franchises.app_name, COUNT(DISTINCT stores.id) AS store_count
            FROM franchises
            JOIN stores ON stores.franchise_id = franchises.id
            WHERE EXISTS (
                SELECT 1
                FROM products
                WHERE products.store_id = stores.id
                LIMIT 1
            )
            GROUP BY franchises.id, franchises.app_name
            ORDER BY CASE WHEN franchises.id = ? THEN 0 ELSE 1 END, franchises.app_name
            """,
            bindings: [.text(StoreCatalog.defaultFranchiseID)]
        ) { statement in
            FranchiseSummary(
                id: text(statement, 0) ?? "",
                name: text(statement, 1) ?? "Franchise",
                storeCount: int(statement, 2)
            )
        }
        .filter { !$0.id.isEmpty }
    }

    func brand(franchiseID: String) -> StoreBrand? {
        queryOne(
            """
            SELECT id, app_name, description_text, primary_color, secondary_color, logo_url, splash_url, mobile_app_json, raw_json
            FROM franchises
            WHERE id = ?
            LIMIT 1
            """,
            bindings: [.text(franchiseID)]
        ) { statement in
            let mobileApp = jsonObject(text(statement, 7))
            let rawConfig = jsonObject(text(statement, 8))

            return StoreBrand(
                franchiseID: text(statement, 0) ?? franchiseID,
                appName: text(statement, 1) ?? franchiseID,
                titleDescription: string(in: mobileApp, key: "titleDescription"),
                newProductsDescription: string(in: mobileApp, key: "newProductsDescription"),
                descriptionText: trimmed(text(statement, 2)),
                primaryColor: Color(hex: text(statement, 3) ?? "") ?? Color(red: 0.10, green: 0.10, blue: 0.10),
                secondaryColor: Color(hex: text(statement, 4) ?? "") ?? Color(red: 0.44, green: 0.89, blue: 0.98),
                logoURL: text(statement, 5),
                splashURL: text(statement, 6),
                featuredItems: featuredItems(from: rawConfig)
            )
        }
    }

    func locations(franchiseID: String, brand: StoreBrand) -> [StoreLocation] {
        query(
            """
            SELECT id, name, city, postal_code, street_number, street,
                   preparation_time_minutes, is_closed, hours_json, order_types_json
            FROM stores
            WHERE franchise_id = ?
              AND EXISTS (
                  SELECT 1
                  FROM products
                  WHERE products.store_id = stores.id
                  LIMIT 1
              )
            ORDER BY is_closed ASC, name
            """,
            bindings: [.text(franchiseID)]
        ) { statement in
            let id = text(statement, 0) ?? ""
            let city = trimmed(text(statement, 2))
            let postalCode = trimmed(text(statement, 3))
            let addressParts = [
                trimmed(text(statement, 4)),
                trimmed(text(statement, 5)),
                postalCode,
                city
            ].compactMap { $0 }

            let sections = sections(storeID: id)
            let todaySlots = todaySlotsFrom(hoursJSON: text(statement, 8))
            let orderTypes = jsonStringArray(text(statement, 9))

            return StoreLocation(
                id: id,
                displayName: text(statement, 1) ?? brand.appName,
                addressLine: addressParts.joined(separator: " "),
                city: city,
                postalCode: postalCode,
                brand: brand,
                sections: sections,
                featuredItem: sections.first?.items.first,
                preparationTime: int(statement, 6),
                isClosed: int(statement, 7) != 0,
                todaySlots: todaySlots,
                orderTypes: orderTypes
            )
        }
        .filter { !$0.id.isEmpty && !$0.sections.isEmpty }
    }

    private func todaySlotsFrom(hoursJSON: String?) -> [String] {
        let json = jsonObject(hoursJSON)
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let weekday = Calendar.current.component(.weekday, from: Date()) - 1
        let dayKey = days[weekday]
        guard let day = json[dayKey] as? [String: Any],
              let slots = day["slots"] as? [String] else { return [] }
        return slots
    }

    private func jsonStringArray(_ text: String?) -> [String] {
        guard let data = text?.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
        return array
    }

    private func sections(storeID: String) -> [MenuSection] {
        query(
            """
            SELECT id, name, description, position
            FROM sections
            WHERE store_id = ?
              AND hidden = 0
            ORDER BY position, name
            """,
            bindings: [.text(storeID)]
        ) { statement in
            let id = text(statement, 0) ?? ""
            let name = trimmed(text(statement, 1)) ?? "Section"
            let items = products(sectionID: id, sectionName: name)

            return MenuSection(
                id: id,
                name: name,
                subtitle: "\(items.count) produit\(items.count == 1 ? "" : "s")",
                position: int(statement, 3),
                items: items
            )
        }
        .filter { section in
            !section.items.isEmpty && !isIngredientSection(section.name)
        }
    }

    private func products(sectionID: String, sectionName: String) -> [MenuItem] {
        query(
            """
            SELECT id, name, description, price, image_url, image_compressed_url, position
            FROM products
            WHERE section_id = ?
              AND disabled = 0
            ORDER BY position, name
            """,
            bindings: [.text(sectionID)]
        ) { statement in
            let imageURL = trimmed(text(statement, 5)) ?? trimmed(text(statement, 4)) ?? ""

            let productID = text(statement, 0) ?? UUID().uuidString
            let groups = optionGroups(productID: productID)
            let subGroups = subcategoryGroups(for: groups)
            return MenuItem(
                id: productID,
                name: trimmed(text(statement, 1)) ?? "Produit",
                description: trimmed(text(statement, 2)) ?? "",
                price: double(statement, 3),
                image: imageURL,
                tag: shortTag(from: sectionName),
                optionGroups: groups,
                subcategoryGroups: subGroups
            )
        }
        .filter { item in
            !item.name.isEmpty && (item.price > 0 || !item.description.isEmpty)
        }
    }

    private func optionGroups(productID: String) -> [MenuOptionGroup] {
        query(
            """
            SELECT option_groups.id,
                   option_groups.name,
                   option_groups.min,
                   option_groups.max,
                   option_groups.multiple,
                   product_option_groups.position
            FROM product_option_groups
            JOIN option_groups ON option_groups.id = product_option_groups.option_group_id
            WHERE product_option_groups.product_id = ?
            ORDER BY product_option_groups.position, option_groups.position, option_groups.name
            """,
            bindings: [.text(productID)]
        ) { statement in
            let id = text(statement, 0) ?? ""
            return MenuOptionGroup(
                id: id,
                name: trimmed(text(statement, 1)) ?? "Options",
                min: int(statement, 2),
                max: sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : int(statement, 3),
                allowsMultiple: int(statement, 4) == 1,
                position: int(statement, 5),
                items: optionItems(groupID: id)
            )
        }
        .filter { !$0.id.isEmpty && !$0.items.isEmpty }
    }

    private func optionItems(groupID: String) -> [MenuOptionItem] {
        var seenIDs = Set<String>()
        let items = query(
            """
            SELECT id, name, price, position
            FROM option_items
            WHERE option_group_id = ?
            ORDER BY position, name
            """,
            bindings: [.text(groupID)]
        ) { statement in
            MenuOptionItem(
                id: text(statement, 0) ?? "",
                name: trimmed(text(statement, 1)) ?? "Option",
                price: double(statement, 2),
                position: int(statement, 3)
            )
        }
        .filter { item in
            guard !item.id.isEmpty, !seenIDs.contains(item.id) else { return false }
            seenIDs.insert(item.id)
            return true
        }

        return items.map { item in
            let subs = itemSubcategoryGroupIDs(itemID: item.id)
            guard !subs.isEmpty else { return item }
            return MenuOptionItem(id: item.id, name: item.name, price: item.price,
                                  position: item.position, subcategoryGroupIDs: subs)
        }
    }

    private func itemSubcategoryGroupIDs(itemID: String) -> [String] {
        query(
            """
            SELECT option_group_id FROM option_item_subcategories
            WHERE option_item_id = ? ORDER BY position
            """,
            bindings: [.text(itemID)]
        ) { statement in
            text(statement, 0) ?? ""
        }
        .filter { !$0.isEmpty }
    }

    private func subcategoryGroups(for groups: [MenuOptionGroup]) -> [String: MenuOptionGroup] {
        var result: [String: MenuOptionGroup] = [:]
        var pending = groups.flatMap(\.items).flatMap(\.subcategoryGroupIDs)
        var visited = Set<String>()
        while let id = pending.popLast() {
            guard visited.insert(id).inserted else { continue }
            guard let group = optionGroup(id: id) else { continue }
            result[id] = group
            pending.append(contentsOf: group.items.flatMap(\.subcategoryGroupIDs))
        }
        return result
    }

    func product(id: String) -> MenuItem? {
        queryOne(
            """
            SELECT p.id, p.name, p.description, p.price, p.image_url, p.image_compressed_url, s.name
            FROM products p
            JOIN sections s ON s.id = p.section_id
            WHERE p.id = ?
            """,
            bindings: [.text(id)]
        ) { statement in
            let pid = text(statement, 0) ?? id
            let sectionName = trimmed(text(statement, 6)) ?? ""
            let imageURL = trimmed(text(statement, 5)) ?? trimmed(text(statement, 4)) ?? ""
            let groups = optionGroups(productID: pid)
            let subGroups = subcategoryGroups(for: groups)
            return MenuItem(
                id: pid,
                name: trimmed(text(statement, 1)) ?? "Produit",
                description: trimmed(text(statement, 2)) ?? "",
                price: double(statement, 3),
                image: imageURL,
                tag: shortTag(from: sectionName),
                optionGroups: groups,
                subcategoryGroups: subGroups
            )
        }
    }

    func franchiseID(forProductID productID: String) -> String? {
        queryOne(
            """
            SELECT s.store_id FROM products p
            JOIN sections s ON s.id = p.section_id
            WHERE p.id = ?
            """,
            bindings: [.text(productID)]
        ) { statement in
            // store_id format: "franchiseID:storeSlug"
            let storeID = text(statement, 0) ?? ""
            return storeID.components(separatedBy: ":").first ?? ""
        }
    }

    func optionGroup(id: String) -> MenuOptionGroup? {
        queryOne(
            """
            SELECT id, name, min, max, multiple, position
            FROM option_groups
            WHERE id = ?
            """,
            bindings: [.text(id)]
        ) { statement in
            let gid = text(statement, 0) ?? ""
            return MenuOptionGroup(
                id: gid,
                name: trimmed(text(statement, 1)) ?? "Options",
                min: int(statement, 2),
                max: sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : int(statement, 3),
                allowsMultiple: int(statement, 4) == 1,
                position: int(statement, 5),
                items: optionItems(groupID: gid)
            )
        }
    }

    private enum Binding {
        case text(String)
    }

    private func query<Result>(
        _ sql: String,
        bindings: [Binding] = [],
        map: (OpaquePointer) -> Result
    ) -> [Result] {
        guard let statement = prepare(sql, bindings: bindings) else { return [] }
        defer { sqlite3_finalize(statement) }

        var rows: [Result] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(map(statement))
        }
        return rows
    }

    private func queryOne<Result>(
        _ sql: String,
        bindings: [Binding] = [],
        map: (OpaquePointer) -> Result
    ) -> Result? {
        guard let statement = prepare(sql, bindings: bindings) else { return nil }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return map(statement)
    }

    private func prepare(_ sql: String, bindings: [Binding]) -> OpaquePointer? {
        guard let handle else { return nil }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return nil
        }

        for (index, binding) in bindings.enumerated() {
            let position = Int32(index + 1)
            switch binding {
            case .text(let value):
                sqlite3_bind_text(statement, position, value, -1, sqliteTransient)
            }
        }

        return statement
    }

    private func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        guard let pointer = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: pointer)
    }

    private func int(_ statement: OpaquePointer, _ column: Int32) -> Int {
        Int(sqlite3_column_int(statement, column))
    }

    private func double(_ statement: OpaquePointer, _ column: Int32) -> Double {
        sqlite3_column_double(statement, column)
    }

    private func jsonObject(_ raw: String?) -> [String: Any] {
        guard let raw, let data = raw.data(using: .utf8) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private func string(in dictionary: [String: Any], key: String) -> String? {
        if let string = dictionary[key] as? String {
            return trimmed(string)
        }
        if let number = dictionary[key] as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private func featuredItems(from rawConfig: [String: Any]) -> [MenuItem] {
        let rawProducts: [[String: Any]]
        if let array = rawConfig["newProducts"] as? [[String: Any]] {
            rawProducts = array
        } else if let dictionary = rawConfig["newProducts"] as? [String: Any] {
            rawProducts = dictionary.values.compactMap { $0 as? [String: Any] }
        } else {
            rawProducts = []
        }

        return rawProducts
            .sorted { int(in: $0, key: "position") < int(in: $1, key: "position") }
            .compactMap { product in
                let image = trimmed(string(in: product, key: "imageCompressed")) ?? trimmed(string(in: product, key: "image"))
                guard let image else { return nil }

                return MenuItem(
                    id: string(in: product, key: "id") ?? string(in: product, key: "key") ?? UUID().uuidString,
                    name: trimmed(string(in: product, key: "name")) ?? "Produit",
                    description: trimmed(string(in: product, key: "description")) ?? "",
                price: double(in: product, key: "price"),
                image: image,
                tag: "NOUVEAU",
                optionGroups: []
            )
        }
    }

    private func int(in dictionary: [String: Any], key: String) -> Int {
        if let int = dictionary[key] as? Int {
            return int
        }
        if let number = dictionary[key] as? NSNumber {
            return number.intValue
        }
        if let string = dictionary[key] as? String {
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }
        return 0
    }

    private func double(in dictionary: [String: Any], key: String) -> Double {
        if let double = dictionary[key] as? Double {
            return double
        }
        if let number = dictionary[key] as? NSNumber {
            return number.doubleValue
        }
        if let string = dictionary[key] as? String {
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }
        return 0
    }

    private func trimmed(_ string: String?) -> String? {
        let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func isIngredientSection(_ sectionName: String) -> Bool {
        let lowercased = sectionName.lowercased()
        return lowercased.contains("ingrédient") || lowercased.contains("ingredient")
    }

    private func shortTag(from sectionName: String) -> String {
        let cleaned = sectionName
            .replacingOccurrences(of: "🍚", with: "")
            .replacingOccurrences(of: "🍗", with: "")
            .replacingOccurrences(of: "🥢", with: "")
            .replacingOccurrences(of: "🧊", with: "")
            .replacingOccurrences(of: "🍰", with: "")
            .replacingOccurrences(of: "⭐", with: "")
            .replacingOccurrences(of: "😈", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.components(separatedBy: .whitespacesAndNewlines).first.map { $0.uppercased() } ?? "MENU"
    }
}

struct FranchiseSummary: Identifiable, Hashable {
    let id: String
    let name: String
    let storeCount: Int
}

struct StoreBrand {
    let franchiseID: String
    let appName: String
    let titleDescription: String?
    let newProductsDescription: String?
    let descriptionText: String?
    let primaryColor: Color
    let secondaryColor: Color
    let logoURL: String?
    let splashURL: String?
    let featuredItems: [MenuItem]
}

struct StoreLocation: Identifiable {
    let id: String
    let displayName: String
    let addressLine: String
    let city: String?
    let postalCode: String?
    let brand: StoreBrand
    let sections: [MenuSection]
    let featuredItem: MenuItem?
    let preparationTime: Int
    let isClosed: Bool
    let todaySlots: [String]
    let orderTypes: [String]
    let stripeAccountId: String?
    let stripePublishableKey: String?

    init(
        id: String,
        displayName: String,
        addressLine: String,
        city: String?,
        postalCode: String?,
        brand: StoreBrand,
        sections: [MenuSection],
        featuredItem: MenuItem?,
        preparationTime: Int,
        isClosed: Bool,
        todaySlots: [String],
        orderTypes: [String],
        stripeAccountId: String? = nil,
        stripePublishableKey: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.addressLine = addressLine
        self.city = city
        self.postalCode = postalCode
        self.brand = brand
        self.sections = sections
        self.featuredItem = featuredItem
        self.preparationTime = preparationTime
        self.isClosed = isClosed
        self.todaySlots = todaySlots
        self.orderTypes = orderTypes
        self.stripeAccountId = stripeAccountId
        self.stripePublishableKey = stripePublishableKey
    }
}

extension StoreLocation {
    var actionableSections: [MenuSection] {
        let existingProductIDs = Set(sections.flatMap { section in
            section.items.map(\.id)
        })
        let featuredProducts = brand.featuredItems
            .map(enrichedFeaturedItem)
            .filter { item in
                item.price > 0 && !existingProductIDs.contains(item.id)
            }

        guard !featuredProducts.isEmpty else { return sections }

        let featuredSection = MenuSection(
            id: "\(id)-featured-products",
            name: brand.newProductsDescription ?? "En ce moment",
            subtitle: "\(featuredProducts.count) produit\(featuredProducts.count == 1 ? "" : "s")",
            position: Int.min,
            items: featuredProducts
        )

        return [featuredSection] + sections
    }

    private func enrichedFeaturedItem(_ item: MenuItem) -> MenuItem {
        guard item.optionGroups.isEmpty else { return item }

        let allProducts = sections.flatMap(\.items)
        if let idMatch = allProducts.first(where: { $0.id == item.id }) {
            return idMatch.withFeaturedPresentation(from: item)
        }

        if let nameMatch = allProducts.first(where: { $0.name.normalizedMenuKey == item.name.normalizedMenuKey }) {
            return nameMatch.withFeaturedPresentation(from: item)
        }

        if let fuzzyMatch = allProducts
            .filter({ !$0.optionGroups.isEmpty && abs($0.price - item.price) < 0.01 })
            .max(by: { fuzzyScore(item, $0) < fuzzyScore(item, $1) }),
           fuzzyScore(item, fuzzyMatch) >= 2 {
            return fuzzyMatch.withFeaturedPresentation(from: item)
        }

        return item
    }

    private func fuzzyScore(_ featuredItem: MenuItem, _ product: MenuItem) -> Int {
        let featuredTokens = Set((featuredItem.name + " " + featuredItem.description).menuTokens)
        let productTokens = Set((product.name + " " + product.description).menuTokens)
        return featuredTokens.intersection(productTokens).count
    }
}

struct MenuSection: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let position: Int
    let items: [MenuItem]
}

struct MenuItem: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let price: Double
    let image: String
    let tag: String
    let optionGroups: [MenuOptionGroup]
    let subcategoryGroups: [String: MenuOptionGroup]

    init(id: String, name: String, description: String, price: Double, image: String, tag: String,
         optionGroups: [MenuOptionGroup], subcategoryGroups: [String: MenuOptionGroup] = [:]) {
        self.id = id; self.name = name; self.description = description; self.price = price
        self.image = image; self.tag = tag; self.optionGroups = optionGroups
        self.subcategoryGroups = subcategoryGroups
    }

    func withFeaturedPresentation(from featuredItem: MenuItem) -> MenuItem {
        MenuItem(
            id: featuredItem.id,
            name: featuredItem.name,
            description: featuredItem.description.isEmpty ? description : featuredItem.description,
            price: featuredItem.price > 0 ? featuredItem.price : price,
            image: featuredItem.image.isEmpty ? image : featuredItem.image,
            tag: featuredItem.tag,
            optionGroups: optionGroups,
            subcategoryGroups: subcategoryGroups
        )
    }
}

struct MenuOptionGroup: Identifiable, Hashable {
    let id: String
    let name: String
    let min: Int
    let max: Int?
    let allowsMultiple: Bool
    let position: Int
    let items: [MenuOptionItem]
}

struct MenuOptionItem: Identifiable, Hashable {
    let id: String
    let name: String
    let price: Double
    let position: Int
    let subcategoryGroupIDs: [String]

    init(id: String, name: String, price: Double, position: Int, subcategoryGroupIDs: [String] = []) {
        self.id = id; self.name = name; self.price = price
        self.position = position; self.subcategoryGroupIDs = subcategoryGroupIDs
    }
}

private extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6 || cleaned.count == 8 else { return nil }

        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else { return nil }

        let red, green, blue, alpha: Double
        if cleaned.count == 6 {
            red = Double((value & 0xFF0000) >> 16) / 255
            green = Double((value & 0x00FF00) >> 8) / 255
            blue = Double(value & 0x0000FF) / 255
            alpha = 1
        } else {
            red = Double((value & 0xFF000000) >> 24) / 255
            green = Double((value & 0x00FF0000) >> 16) / 255
            blue = Double((value & 0x0000FF00) >> 8) / 255
            alpha = Double(value & 0x000000FF) / 255
        }

        self.init(red: red, green: green, blue: blue, opacity: alpha)
    }
}

private extension String {
    var normalizedMenuKey: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }

    var menuTokens: [String] {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 }
    }
}
