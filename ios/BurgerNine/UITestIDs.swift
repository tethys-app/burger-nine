import Foundation

/// Stable accessibility identifiers for Maestro / UI tests.
///
/// Prefix scheme (grep-friendly in `maestro hierarchy`):
/// - `category-pill-*`     sticky category bar pills
/// - `section-header-*`    in-scroll section titles
/// - `product-row-*`       tappable product cards
/// - `product-stepper-*`   in-row quantity controls
/// - `cart-bar`            checkout bar
enum UITestID {
    static func categoryPill(sectionID: String) -> String { "category-pill-\(sectionID)" }
    static func sectionHeader(sectionID: String) -> String { "section-header-\(sectionID)" }
    static func productRow(productID: String) -> String { "product-row-\(productID)" }
    static func productStepperPlus(productID: String) -> String { "product-stepper-plus-\(productID)" }
    static func productStepperMinus(productID: String) -> String { "product-stepper-minus-\(productID)" }
    static func productDecrease(productID: String) -> String { "product-decrease-\(productID)" }
    static let cartBar = "cart-bar"
}
