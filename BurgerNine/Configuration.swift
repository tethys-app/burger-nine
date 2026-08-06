import Foundation

enum BurgerNineConfig {
    static let apiURL: URL = {
        guard let url = URL(string: value("PUBLIC_NEO_API_URL") ?? "http://127.0.0.1:3211") else {
            preconditionFailure("PUBLIC_NEO_API_URL must be a valid URL")
        }
        return url
    }()

    static let brandSlug = value("PUBLIC_BRAND_SLUG") ?? "burger-nine"

    static let siteURL: URL = {
        guard let url = URL(string: value("PUBLIC_SITE_URL") ?? "http://localhost:4321") else {
            preconditionFailure("PUBLIC_SITE_URL must be a valid URL")
        }
        return url
    }()

    private static func value(_ key: String) -> String? {
        if let processValue = ProcessInfo.processInfo.environment[key], !processValue.isEmpty {
            return processValue
        }
        if let bundleValue = Bundle.main.object(forInfoDictionaryKey: key) as? String, !bundleValue.isEmpty {
            return bundleValue
        }
        return nil
    }
}
