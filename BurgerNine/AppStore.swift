import Foundation
import SwiftUI

/// The app's only data source. Every location and catalog request is scoped by
/// `PUBLIC_BRAND_SLUG` inside MenuAPI. A bundled/build-time snapshot or the
/// last successful disk snapshot renders immediately, then the API rehydrates it.
@MainActor
@Observable
final class AppStore {
    private(set) var locations: [StoreLocation] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var brand = StoreBrand(
        franchiseID: BurgerNineConfig.brandSlug,
        appName: "Burger Nine",
        titleDescription: nil,
        newProductsDescription: nil,
        descriptionText: nil,
        primaryColor: Color(red: 0.08, green: 0.06, blue: 0.05),
        secondaryColor: Color(red: 0.96, green: 0.44, blue: 0.12),
        logoURL: nil,
        splashURL: nil,
        featuredItems: []
    )

    func location(id: String?) -> StoreLocation? {
        guard let id else { return locations.first }
        return locations.first(where: { $0.id == id }) ?? locations.first
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        if let cached = StorefrontCache.load() {
            apply(cached)
        }

        do {
            let snapshot = try await MenuAPI.fetchSnapshot()
            apply(snapshot)
            StorefrontCache.save(snapshot)
            error = nil
        } catch {
            if locations.isEmpty {
                self.error = error.localizedDescription
            } else {
                MenuDiag.record("catalog refresh failed; using cached snapshot: \(error.localizedDescription)")
            }
        }
    }

    private func apply(_ snapshot: MenuAPI.StorefrontSnapshot) {
        guard snapshot.brand.slug == BurgerNineConfig.brandSlug else { return }
        brand = StoreBrand(
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
        locations = MenuAPI.locations(from: snapshot)
    }
}

enum StorefrontCache {
    private static let snapshotName = "burger-nine.snapshot"

    static func load() -> MenuAPI.StorefrontSnapshot? {
        let decoder = JSONDecoder()
        let urls = [
            diskURL,
            Bundle.main.url(forResource: snapshotName, withExtension: "json")
        ].compactMap { $0 }
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let snapshot = try? decoder.decode(MenuAPI.StorefrontSnapshot.self, from: data),
                  snapshot.brand.slug == BurgerNineConfig.brandSlug else { continue }
            return snapshot
        }
        return nil
    }

    static func save(_ snapshot: MenuAPI.StorefrontSnapshot) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        do {
            let directory = diskURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: diskURL, options: .atomic)
        } catch {
            MenuDiag.record("catalog snapshot cache write failed: \(error.localizedDescription)")
        }
    }

    private static var diskURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("BurgerNine", isDirectory: true)
            .appendingPathComponent("\(BurgerNineConfig.brandSlug).snapshot.json")
    }
}
