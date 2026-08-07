import SwiftUI
import UIKit
import CryptoKit

// MARK: - Image loading

/// Decoded-image cache. URLSession's own URLCache handles the raw-bytes HTTP
/// layer (memory + disk); this keeps the *decoded* UIImages (the expensive part)
/// and dedups concurrent requests for the same URL.
@MainActor
final class ProductImageCache {
    static let shared = ProductImageCache()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let session: URLSession
    private let diskDirectory: URL

    private init() {
        cache.countLimit = 600
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 256 << 20)
        session = URLSession(configuration: config)
        diskDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BurgerNine/ProductImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
    }

    func cachedImage(for url: String) -> UIImage? {
        if let image = cache.object(forKey: url as NSString) { return image }
        let path = diskDirectory.appendingPathComponent(diskName(for: url))
        guard let data = try? Data(contentsOf: path), let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: url as NSString)
        return image
    }

    func image(for url: String) async -> UIImage? {
        if let cached = cachedImage(for: url) { return cached }
        if let task = inFlight[url] { return await task.value }

        let task = Task { () -> UIImage? in
            guard let endpoint = URL(string: url) else { return nil }
            guard let (data, _) = try? await session.data(from: endpoint),
                  let image = UIImage(data: data) else { return nil }
            try? data.write(to: self.diskDirectory.appendingPathComponent(self.diskName(for: url)), options: .atomic)
            return image
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { cache.setObject(image, forKey: url as NSString) }
        return image
    }

    private func diskName(for url: String) -> String {
        SHA256.hash(data: Data(url.utf8)).map { String(format: "%02x", $0) }.joined() + ".image"
    }

    /// Warm the cache for a set of URLs, bounded so we don't open every
    /// connection at once.
    func prefetch(_ urls: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            var active = 0
            for url in Set(urls) where !url.isEmpty {
                if active >= 6 { await group.next(); active -= 1 }
                group.addTask { _ = await self.image(for: url) }
                active += 1
            }
        }
    }
}

struct RemoteProductImage: View {
    let url: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity.combined(with: .scale(scale: 1.015)))
            } else {
                LinearGradient(colors: [TastyTheme.orange, TastyTheme.coral, TastyTheme.violet], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "photo")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            }
        }
        .animation(.smooth(duration: 0.18), value: image)
        .task(id: url) {
            if let cached = ProductImageCache.shared.cachedImage(for: url) {
                image = cached
            } else if !url.isEmpty {
                image = await ProductImageCache.shared.image(for: url)
            }
        }
    }
}

// MARK: - Product card

struct ProductCard: View {
    let item: MenuItem
    let quantity: Int
    var layout: RowLayout = .tapToAdd
    var hidePlus = false
    var plusFilled = true
    var clearIcon: ClearButtonIcon = .xmark
    var clearShape: ClearButtonShape = .roundedSquare
    var clearTone: ClearButtonTone = .coral
    var stepperAdd: (() -> Void)?
    let add: () -> Void
    let decrease: () -> Void
    var clear: (() -> Void)?

    @State private var isPressed = false
    @State private var decreasePressed = false
    @State private var justAdded = false
    @State private var addPulseID = 0

    // With the plus hidden, an empty row reserves no trailing slot — the whole
    // card is still tappable to add, the stepper only appears once in the cart.
    private var showsControl: Bool {
        switch layout {
        case .tapToAdd:
            quantity > 0
        default:
            quantity > 0 || !hidePlus
        }
    }

    @ViewBuilder
    private var control: some View {
        ZStack(alignment: .trailing) {
            if showsControl {
                if quantity > 0 {
                    if layout == .tapToAdd {
                        DecreaseBadge(
                            icon: clearIcon,
                            shape: clearShape,
                            tone: clearTone,
                            decreasePressed: $decreasePressed,
                            action: { (clear ?? decrease)() },
                            productID: item.id
                        )
                        .transition(.clearButtonArrival)
                    } else {
                        StepperCapsule(
                            quantity: quantity,
                            productID: item.id,
                            add: stepperAdd ?? add,
                            decrease: decrease
                        )
                        .transition(.scale(scale: 0.7, anchor: .trailing).combined(with: .opacity))
                    }
                } else {
                    plusBadge
                        .transition(.scale(scale: 0.7, anchor: .trailing).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.55), value: quantity)
    }

    private func textColumn(titleLines: Int, scale: CGFloat = 1) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !item.tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(item.tag.uppercased())
                    .font(.caption2.weight(.black))
                    .tracking(1.1)
                    .foregroundStyle(TastyTheme.orange)
            }
            Text(item.name.trimmingCharacters(in: .whitespaces).uppercased())
                .font(.system(.headline, design: .rounded, weight: .black))
                .foregroundStyle(TastyTheme.ink)
                .lineLimit(titleLines)
                .minimumScaleFactor(scale)
            Text(item.description)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TastyTheme.muted)
                .lineLimit(2)
            Text(item.price, format: .currency(code: "EUR"))
                .font(.system(.title3, design: .rounded, weight: .black))
                .foregroundStyle(TastyTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .committed:
            HStack(spacing: 14) {
                productImage
                textColumn(titleLines: 1)
                control.frame(width: 96, alignment: .trailing)
            }

        case .floatingCorner:
            HStack(spacing: 14) {
                productImage
                textColumn(titleLines: 1)
            }
            .overlay(alignment: .bottomTrailing) { control }

        case .wrapTwoLines:
            HStack(spacing: 14) {
                productImage
                textColumn(titleLines: 2, scale: 0.85)
                control.frame(width: 88, alignment: .trailing)
            }

        case .overlayTopRight:
            HStack(spacing: 14) {
                productImage
                textColumn(titleLines: 1)
            }
            .overlay(alignment: .topTrailing) { control }

        case .fullWidthControl:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    productImage
                    textColumn(titleLines: 2, scale: 0.85)
                }
                control.frame(maxWidth: .infinity, alignment: .trailing)
            }

        case .compactPlus:
            HStack(spacing: 10) {
                productImage
                textColumn(titleLines: 1)
                control.frame(width: 64, alignment: .trailing)
            }

        case .tapToAdd:
            HStack(spacing: 14) {
                productImage
                textColumn(titleLines: 2, scale: 0.86)
                if quantity > 0 {
                    control.frame(width: clearControlWidth, alignment: .trailing)
                } else {
                    plusBadge.frame(width: 52, alignment: .trailing)
                }
            }
        }
    }

    var body: some View {
        content
        .productCardSurface(pressed: isPressed, highlighted: justAdded)
        .scaleEffect(isPressed ? 0.965 : (justAdded ? 1.012 : 1))
        .animation(
            isPressed ? .easeOut(duration: 0.08) : .spring(response: 0.3, dampingFraction: 0.6),
            value: isPressed
        )
        .animation(.spring(response: 0.26, dampingFraction: 0.72), value: justAdded)
        .overlay {
            // Press surface skips the trailing slot so the stepper's own
            // buttons stay tappable once the product is in the cart.
            InstantPressGesture(
                onPressingChanged: { isPressed = $0 },
                action: add
            )
            .padding(.trailing, trailingPressExclusion)
            .padding(.bottom, quantity > 0 && layout == .fullWidthControl ? 60 : 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.name.trimmingCharacters(in: .whitespaces))
        .accessibilityIdentifier(UITestID.productRow(productID: item.id))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { add() }
        .accessibilityHint(
            quantity > 0
                ? (layout == .tapToAdd
                    ? "Touche la ligne pour en ajouter, ou le bouton de droite pour tout retirer"
                    : "Utilise les boutons plus et moins pour modifier la quantité")
                : (item.optionGroups.isEmpty ? "Ajoute ce produit au panier" : "Ouvre les options du produit")
        )
        .onChange(of: quantity) { oldValue, newValue in
            guard newValue > oldValue else { return }
            addPulseID += 1
            let pulseID = addPulseID
            justAdded = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                guard pulseID == addPulseID else { return }
                justAdded = false
            }
        }
    }

    private var productImage: some View {
        RemoteProductImage(url: item.image)
            .frame(width: 92, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(TastyTheme.hairline, lineWidth: 1)
            }
            .overlay(alignment: .topTrailing) {
                if quantity > 0 {
                    Text("×\(quantity)")
                        .font(.caption.weight(.black))
                        .foregroundStyle(TastyTheme.ink)
                        .padding(7)
                        .background(TastyTheme.gold, in: Circle())
                        .offset(x: 6, y: -6)
                        .transition(.scale)
                }
            }
    }

    private var trailingPressExclusion: CGFloat {
        guard quantity > 0 else { return 0 }
        switch layout {
        case .fullWidthControl:
            return 0
        case .tapToAdd:
            return clearControlWidth + 6
        default:
            return 94
        }
    }

    private var clearControlWidth: CGFloat {
        clearShape == .capsule ? 70 : 52
    }

    private var plusBadge: some View {
        Image(systemName: "plus")
            .font(.title3.weight(.black))
            .foregroundStyle(plusFilled ? TastyTheme.ink : TastyTheme.gold)
            .frame(width: 52, height: 52)
            .background(Circle().fill(plusFilled ? TastyTheme.gold : TastyTheme.gold.opacity(0.12)))
            .overlay(Circle().stroke(.white.opacity(plusFilled ? 0.7 : 0.18), lineWidth: 1))
    }

}

private extension View {
    func productCardSurface(pressed: Bool = false, highlighted: Bool = false) -> some View {
        padding(13)
            .background(
                TastyTheme.surfaceGradient,
                in: RoundedRectangle(cornerRadius: TastyTheme.cardRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: TastyTheme.cardRadius)
                    .fill(TastyTheme.violet.opacity(highlighted ? 0.13 : 0))
            }
            .overlay {
                RoundedRectangle(cornerRadius: TastyTheme.cardRadius)
                    .stroke(
                        LinearGradient(
                            colors: [
                                highlighted ? TastyTheme.violet.opacity(0.52) : TastyTheme.hairline,
                                .white.opacity(highlighted ? 0.24 : 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: highlighted ? 1.5 : 1
                    )
            }
            .compositingGroup()
            .shadow(
                color: .black.opacity(pressed ? 0.28 : (highlighted ? 0.22 : 0.16)),
                radius: pressed ? 24 : (highlighted ? 18 : 14),
                y: pressed ? 12 : (highlighted ? 10 : 8)
            )
            .contentShape(RoundedRectangle(cornerRadius: TastyTheme.cardRadius))
    }
}

private extension AnyTransition {
    static var clearButtonArrival: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing)
                .combined(with: .scale(scale: 0.72, anchor: .trailing))
                .combined(with: .opacity),
            removal: .scale(scale: 0.84, anchor: .trailing)
                .combined(with: .opacity)
        )
    }
}

// MARK: - Decrease badge

private struct DecreaseBadge: View {
    let icon: ClearButtonIcon
    let shape: ClearButtonShape
    let tone: ClearButtonTone
    @Binding var decreasePressed: Bool
    let action: () -> Void
    let productID: String

    @State private var appeared = false

    private var buttonSize: CGSize {
        switch shape {
        case .roundedSquare, .circle:
            return CGSize(width: 52, height: 52)
        case .capsule:
            return CGSize(width: 68, height: 48)
        }
    }

    private var cornerRadius: CGFloat {
        switch shape {
        case .roundedSquare:
            return decreasePressed ? 17 : 19
        case .circle:
            return buttonSize.height / 2
        case .capsule:
            return buttonSize.height / 2
        }
    }

    private var accent: Color { tone.color }
    private var fillBase: Color {
        tone == .ink ? TastyTheme.ink : TastyTheme.elevatedSoft
    }
    private var iconColor: Color {
        if decreasePressed { return tone == .ink ? TastyTheme.ink : .white }
        return tone == .ink ? TastyTheme.elevated : accent
    }
    private var pressedFill: Color {
        tone == .ink ? TastyTheme.elevatedSoft : accent
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            (decreasePressed ? pressedFill : fillBase).opacity(tone == .ink ? 0.96 : 0.90),
                            accent.opacity(decreasePressed ? 0.30 : 0.11)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    accent.opacity(decreasePressed ? 0.72 : 0.42),
                                    TastyTheme.violet.opacity(0.16)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: decreasePressed ? 1.7 : 1.2
                        )
                }

            Image(systemName: icon.systemName)
                .font(.headline.weight(.black))
                .foregroundStyle(iconColor)
                .symbolEffect(.bounce, value: decreasePressed)
        }
            .frame(width: buttonSize.width, height: buttonSize.height)
            .shadow(color: accent.opacity(decreasePressed ? 0.20 : 0.11), radius: decreasePressed ? 10 : 14, y: decreasePressed ? 4 : 7)
            .scaleEffect(appeared ? (decreasePressed ? 0.90 : 1) : 0.72, anchor: .trailing)
            .rotationEffect(.degrees(decreasePressed ? -5 : 0))
            .animation(
                decreasePressed
                    ? .easeOut(duration: 0.08)
                    : .spring(response: 0.32, dampingFraction: 0.70),
                value: decreasePressed
            )
            .animation(.spring(response: 0.42, dampingFraction: 0.64), value: appeared)
            .overlay {
                // Hit zone extends well beyond the 52pt visual so the small
                // minus button is comfortable to tap.
                InstantPressGesture(
                    onPressingChanged: { decreasePressed = $0 },
                    action: action
                )
                .padding(.vertical, -18)
                .padding(.trailing, -18)
                .padding(.leading, -4)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Retirer du panier")
            .accessibilityIdentifier(UITestID.productDecrease(productID: productID))
            .onAppear { appeared = true }
            .onDisappear { appeared = false }
    }
}

// MARK: - Stepper

struct StepperCapsule: View {
    let quantity: Int
    var productID: String?
    var canAdd = true
    let add: () -> Void
    let decrease: () -> Void

    @State private var minusPressed = false
    @State private var plusPressed = false

    private var isPressed: Bool { minusPressed || plusPressed }

    @ViewBuilder
    private func stepperIcon(_ name: String, label: String, testID: String?) -> some View {
        let icon = Image(systemName: name)
            .font(.caption.weight(.black))
            .frame(width: 30, height: 34)
            .contentShape(Rectangle())
            .accessibilityLabel(label)
        if let testID {
            icon.accessibilityIdentifier(testID)
        } else {
            icon
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            stepperIcon(
                "minus",
                label: "Retirer un article",
                testID: productID.map { UITestID.productStepperMinus(productID: $0) }
            )

            Text("\(quantity)")
                .font(.callout.weight(.black))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(quantity)))
                .foregroundStyle(TastyTheme.ink)
                .frame(minWidth: 20)

            stepperIcon(
                "plus",
                label: "Ajouter un article",
                testID: productID.map { UITestID.productStepperPlus(productID: $0) }
            )
            .foregroundStyle(canAdd ? TastyTheme.ink : TastyTheme.muted.opacity(0.45))
        }
        .foregroundStyle(TastyTheme.ink)
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .background(TastyTheme.gold.opacity(isPressed ? 0.88 : 0.96), in: Capsule())
        .overlay(Capsule().stroke(TastyTheme.elevated.opacity(0.95), lineWidth: 1.5))
        .scaleEffect(isPressed ? 0.94 : 1)
        .animation(
            isPressed ? .easeOut(duration: 0.08) : .spring(response: 0.28, dampingFraction: 0.65),
            value: isPressed
        )
        .overlay(alignment: .leading) {
            InstantPressGesture(
                onPressingChanged: { minusPressed = $0 },
                action: decrease
            )
            .frame(width: 36, height: 42)
        }
        .overlay(alignment: .trailing) {
            InstantPressGesture(
                onPressingChanged: { pressed in
                    guard canAdd else { return }
                    plusPressed = pressed
                },
                action: {
                    guard canAdd else { return }
                    add()
                }
            )
            .frame(width: 36, height: 42)
            .allowsHitTesting(canAdd)
        }
    }
}

// MARK: - Trash pop transition

private struct ScaleOnlyModifier: ViewModifier {
    var scale: CGFloat
    var anchor: UnitPoint

    func body(content: Content) -> some View {
        content.scaleEffect(scale, anchor: anchor)
    }
}

// MARK: - Instant press gesture

@MainActor
final class ScrollVelocityMonitor {
    static let shared = ScrollVelocityMonitor()
    private var samples: [(t: TimeInterval, y: CGFloat)] = []

    func record(_ y: CGFloat) {
        guard y.isFinite else { return }
        samples.append((CACurrentMediaTime(), y))
        if samples.count > 6 { samples.removeFirst() }
    }

    /// Points per second over the last ~120ms; 0 when the content is idle.
    var velocity: CGFloat {
        let cutoff = CACurrentMediaTime() - 0.12
        let recent = samples.filter { $0.t > cutoff }
        guard let first = recent.first, let last = recent.last, last.t > first.t else { return 0 }
        return (last.y - first.y) / (last.t - first.t)
    }
}

/// UIKit-backed instant press: SwiftUI buttons inside a ScrollView get their
/// `isPressed` delayed by scroll disambiguation. This recognizer presses in
/// on touch-down, unconditionally; whether it was a scroll or a tap is only
/// decided at press-out (moved > 10pt = scroll, no action). Exception: a
/// touch landing while content is still moving fast is a scroll-stop tap —
/// no press visual, no action.
struct InstantPressGesture: UIViewRepresentable {
    static let stopTapVelocity: CGFloat = 350

    var onPressingChanged: (Bool) -> Void
    var action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handle(_:)))
        press.minimumPressDuration = 0
        press.cancelsTouchesInView = false
        press.delegate = context.coordinator
        view.addGestureRecognizer(press)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: InstantPressGesture
        private var startLocation = CGPoint.zero
        private var moved = false
        private var isStopTap = false

        init(_ parent: InstantPressGesture) { self.parent = parent }

        @objc func handle(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began:
                moved = false
                isStopTap = abs(ScrollVelocityMonitor.shared.velocity) > InstantPressGesture.stopTapVelocity
                guard !isStopTap else { return }
                startLocation = recognizer.location(in: recognizer.view)
                parent.onPressingChanged(true)
            case .changed:
                guard !isStopTap else { return }
                let location = recognizer.location(in: recognizer.view)
                if hypot(location.x - startLocation.x, location.y - startLocation.y) > 10 {
                    moved = true
                }
            case .ended:
                guard !isStopTap else { return }
                parent.onPressingChanged(false)
                if !moved { parent.action() }
            case .cancelled, .failed:
                guard !isStopTap else { return }
                parent.onPressingChanged(false)
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { true }
    }
}

// MARK: - Previews

#if DEBUG
private enum CardPreview {
    static let sample = MenuItem(
        id: "demo",
        name: "Crousty Royale Bacon",
        description: "Double steak, cheddar fondu, bacon croustillant et sauce maison.",
        price: 12.9,
        image: "",
        tag: "Bestseller",
        optionGroups: []
    )

    static let short = MenuItem(
        id: "demo2",
        name: "Coca-Cola",
        description: "33cl bien frais.",
        price: 2.5,
        image: "",
        tag: "Boisson",
        optionGroups: []
    )

    @ViewBuilder
    static func row(_ label: String, layout: RowLayout, quantity: Int, hidePlus: Bool = false, plusFilled: Bool = true, item: MenuItem = sample) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(label) · qty \(quantity)\(hidePlus ? " · hidePlus" : "")\(plusFilled ? "" : " · outlined")")
                .font(.caption2.weight(.bold))
                .foregroundStyle(TastyTheme.muted)
            ProductCard(
                item: item,
                quantity: quantity,
                layout: layout,
                hidePlus: hidePlus,
                plusFilled: plusFilled,
                add: {}, decrease: {}, clear: {}
            )
        }
    }

    static var background: some View {
        LinearGradient(colors: [TastyTheme.surface, TastyTheme.surfaceDepth], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

/// Every layout side-by-side at its empty and in-cart state.
#Preview("Layouts") {
    ScrollView {
        VStack(spacing: 18) {
            ForEach(RowLayout.allCases, id: \.rawValue) { layout in
                CardPreview.row(layout.label, layout: layout, quantity: 0)
                CardPreview.row(layout.label, layout: layout, quantity: 2)
            }
        }
        .padding(18)
    }
    .background(CardPreview.background)
}

/// Plus-button styling knobs.
#Preview("Plus variants") {
    ScrollView {
        VStack(spacing: 18) {
            CardPreview.row("filled plus", layout: .committed, quantity: 0, plusFilled: true)
            CardPreview.row("outlined plus", layout: .committed, quantity: 0, plusFilled: false)
            CardPreview.row("hidden plus (empty)", layout: .committed, quantity: 0, hidePlus: true)
            CardPreview.row("hidden plus (in cart)", layout: .committed, quantity: 1, hidePlus: true)
            CardPreview.row("short item", layout: .compactPlus, quantity: 0, item: CardPreview.short)
        }
        .padding(18)
    }
    .background(CardPreview.background)
}

#Preview("Dark") {
    ScrollView {
        VStack(spacing: 18) {
            CardPreview.row("committed", layout: .committed, quantity: 0)
            CardPreview.row("tapToAdd", layout: .tapToAdd, quantity: 3)
            CardPreview.row("fullWidthControl", layout: .fullWidthControl, quantity: 1)
        }
        .padding(18)
    }
    .background(CardPreview.background)
    .preferredColorScheme(.dark)
}

#Preview("Stepper") {
    VStack(spacing: 20) {
        StepperCapsule(quantity: 1, add: {}, decrease: {})
        StepperCapsule(quantity: 12, add: {}, decrease: {})
        StepperCapsule(quantity: 3, canAdd: false, add: {}, decrease: {})
    }
    .padding(40)
    .background(CardPreview.background)
}
#endif
