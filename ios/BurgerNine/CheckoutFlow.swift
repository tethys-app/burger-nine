import SwiftUI
import MapKit
import StripePaymentSheet

// MARK: - Shared model

enum FulfillmentMode: String, CaseIterable, Identifiable {
    case delivery = "Livraison"
    case pickup = "Sur place / à emporter"

    var id: String { rawValue }

    /// Compact label for the segmented control.
    var shortLabel: String {
        switch self {
        case .delivery: return "Livraison"
        case .pickup: return "Sur place"
        }
    }

    var accent: Color {
        switch self {
        case .delivery: return TastyTheme.orange
        case .pickup: return TastyTheme.violet
        }
    }

    var icon: String {
        switch self {
        case .delivery: return "scooter"
        case .pickup: return "bag.fill"
        }
    }

    /// Step 1 CTA — verb only, color carries the mode.
    var confirmTitle: String {
        switch self {
        case .delivery: return "Livrer à cette adresse"
        case .pickup: return "Valider le retrait"
        }
    }

    /// Step 2 pay CTA suffix.
    var paySuffix: String {
        switch self {
        case .delivery: return "en livraison"
        case .pickup: return "à emporter"
        }
    }

    var etaTitle: String {
        switch self {
        case .delivery: return "Livraison estimée"
        case .pickup: return "Prêt à récupérer"
        }
    }

    var etaRange: String {
        switch self {
        case .delivery: return "25–35 min"
        case .pickup: return "15–20 min"
        }
    }
}

/// Drives the two-step flow. Lives above both screens so the confirmed
/// address survives the morph from half-sheet to full checkout.
@MainActor
@Observable
final class CheckoutModel {
    var mode = FulfillmentMode.delivery
    var confirmedAddress: String?
    /// Code porte, étage, instructions… (optional second line).
    var addressDetail = ""
    var step = Step.fulfillment

    enum Step { case fulfillment, payment }

    init(mode: FulfillmentMode = .delivery) {
        self.mode = mode
    }

    var canPay: Bool {
        mode == .pickup || confirmedAddress != nil
    }
}

// MARK: - Flow container

struct CheckoutFlow: View {
    let cart: [CartLine: Int]
    let store: StoreLocation
    let total: Double
    var onOrderPlaced: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var model = CheckoutModel()
    @State private var detent = PresentationDetent.fraction(0.58)

    var body: some View {
        ZStack {
            switch model.step {
            case .fulfillment:
                FulfillmentSheet(store: store, model: model, detent: $detent) { advance(to: .payment) }
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            case .payment:
                CheckoutDetailView(cart: cart, store: store, total: total, model: model, onOrderPlaced: onOrderPlaced) { advance(to: .fulfillment) }
                    .transition(.opacity.animation(.easeInOut(duration: 0.25)))
            }
        }
        .presentationDetents([.fraction(0.58), .large], selection: $detent)
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(TastyTheme.sheetRadius)
        .presentationContentInteraction(.scrolls)
        .interactiveDismissDisabled(model.step == .payment)
    }

    func advance(to step: CheckoutModel.Step) {
        // One transaction: the sheet height (detent) and the content swap animate
        // together on the same curve, so the morph reads as a single continuous motion.
        withAnimation(.snappy(duration: 0.4, extraBounce: 0)) {
            detent = step == .payment ? .large : .fraction(0.58)
            model.step = step
        }
    }
}

// MARK: - Step 1 — fulfillment

private struct FulfillmentSheet: View {
    let store: StoreLocation
    @Bindable var model: CheckoutModel
    @Binding var detent: PresentationDetent
    let onConfirm: () -> Void

    @State private var search = AddressSearch()
    @FocusState private var addressFocused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Comment souhaitez-vous recevoir votre commande ?")
                        .font(.system(.title3, design: .rounded, weight: .black))
                        .foregroundStyle(TastyTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    modePicker
                        .animation(.snappy(duration: 0.22, extraBounce: 0), value: model.mode)

                    if model.mode == .delivery {
                        addressArea
                    } else {
                        pickupRecap
                    }

                    // Spacer so the last suggestion can scroll clear of the pinned CTA.
                    Color.clear.frame(height: 84)
                }
                .padding(20)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)

            confirmCTA
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(TastyTheme.surface.ignoresSafeArea(edges: .bottom))
        }
        .background(TastyTheme.surface.ignoresSafeArea())
        // ONE keyboard-ignore over the whole composed view (scroll + pinned CTA),
        // so nothing applies keyboard avoidance twice. The CTA never jumps; the
        // sheet grows to .large on focus to lift everything above the keyboard.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: addressFocused) { _, focused in
            detent = focused ? .large : .fraction(0.58)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(FulfillmentMode.allCases) { mode in
                let selected = model.mode == mode
                Button { model.mode = mode } label: {
                    HStack(spacing: 7) {
                        Image(systemName: mode.icon)
                        Text(mode.shortLabel).lineLimit(1)
                    }
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(selected ? .white : TastyTheme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(selected ? mode.accent : TastyTheme.elevatedSoft, in: RoundedRectangle(cornerRadius: TastyTheme.controlRadius))
                    .overlay(RoundedRectangle(cornerRadius: TastyTheme.controlRadius).stroke(selected ? .white.opacity(0.5) : TastyTheme.hairline))
                }
                .buttonStyle(.bouncy)
            }
        }
    }

    @ViewBuilder
    private var addressArea: some View {
        if let address = model.confirmedAddress {
            VStack(spacing: 10) {
                addressRecap(address)
                detailField
            }
            .transition(.opacity)
        } else {
            VStack(spacing: 10) {
                addressField
                if !search.results.isEmpty {
                    suggestions
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: search.results)
        }
    }

    private func addressRecap(_ address: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "location.fill")
                .font(.headline.weight(.black))
                .foregroundStyle(model.mode.accent)
                .frame(width: 36, height: 36)
                .background(model.mode.accent.opacity(0.16), in: Circle())
            Text(address)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(TastyTheme.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Modifier") {
                search.query = ""
                model.confirmedAddress = nil
            }
                .font(.caption.weight(.black))
                .foregroundStyle(model.mode.accent)
                .padding(.vertical, 6)
                .padding(.leading, 6)
                .contentShape(Rectangle())
        }
        .padding(14)
        .background(TastyTheme.elevatedSoft, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(TastyTheme.hairline))
    }

    private var detailField: some View {
        HStack(spacing: 10) {
            Image(systemName: "number")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(TastyTheme.muted)
            TextField("Code, étage, instructions (facultatif)", text: $model.addressDetail)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TastyTheme.ink)
        }
        .padding(14)
        .background(TastyTheme.elevatedSoft, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(TastyTheme.hairline))
    }

    private var addressField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(TastyTheme.muted)
            TextField("Adresse de livraison", text: $search.query)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TastyTheme.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($addressFocused)
        }
        .padding(16)
        .background(TastyTheme.elevatedSoft, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(addressFocused ? model.mode.accent.opacity(0.6) : TastyTheme.hairline, lineWidth: addressFocused ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture { addressFocused = true }
    }

    private var suggestions: some View {
        VStack(spacing: 0) {
            ForEach(Array(search.results.enumerated()), id: \.element) { index, result in
                Button {
                    addressFocused = false
                    search.query = ""
                    model.confirmedAddress = [result.title, result.subtitle]
                        .filter { !$0.isEmpty }.joined(separator: ", ")
                    HapticFeedback.select()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title3)
                            .foregroundStyle(TastyTheme.muted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(TastyTheme.ink)
                            if !result.subtitle.isEmpty {
                                Text(result.subtitle)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(TastyTheme.muted)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 15)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index != search.results.count - 1 {
                    Divider().overlay(TastyTheme.hairline).padding(.leading, 48)
                }
            }
        }
        .background(TastyTheme.elevatedSoft, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(TastyTheme.hairline))
    }

    private var pickupRecap: some View {
        HStack(spacing: 12) {
            Image(systemName: "takeoutbag.and.cup.and.straw.fill")
                .font(.headline.weight(.black))
                .foregroundStyle(model.mode.accent)
                .frame(width: 36, height: 36)
                .background(model.mode.accent.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(store.displayName)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(TastyTheme.ink)
                    .lineLimit(1)
                Text(store.addressLine.isEmpty ? "Retrait sur place" : store.addressLine)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TastyTheme.muted)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(TastyTheme.elevatedSoft, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(TastyTheme.hairline))
    }

    private var confirmCTA: some View {
        Button {
            addressFocused = false
            if model.mode == .pickup { model.confirmedAddress = nil }
            HapticFeedback.add()
            onConfirm()
        } label: {
            Text(model.mode.confirmTitle)
                .font(.headline.weight(.black))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(17)
                .background(model.canPay ? model.mode.accent : TastyTheme.muted.opacity(0.4),
                           in: RoundedRectangle(cornerRadius: TastyTheme.cardRadius))
                .shadow(color: model.mode.accent.opacity(model.canPay ? 0.28 : 0), radius: 16, y: 8)
        }
        .buttonStyle(.bouncy)
        .disabled(!model.canPay)
        .animation(.snappy(duration: 0.2), value: model.canPay)
    }
}

// MARK: - Step 2 — full checkout

private struct CheckoutDetailView: View {
    let cart: [CartLine: Int]
    let store: StoreLocation
    let total: Double
    @Bindable var model: CheckoutModel
    var onOrderPlaced: (() -> Void)? = nil
    let onChangeAddress: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var expanded = false
    @State private var orderPlaced = false
    @State private var placing = false
    @State private var showPlacementError = false
    @State private var placementError = ""
    @State private var paymentSheet: PaymentSheet?
    @State private var showPaymentSheet = false
    @State private var showGame = false
    @State private var prize: GamePrize?

    private let collapsedRows = 1

    private var freeMeal: Bool { prize?.isWin == true }
    private var discountRate: Double {
        if case .discount(let p)? = prize { return Double(p) / 100 } else { return 0 }
    }
    private var subtotalAfter: Double { freeMeal ? 0 : total * (1 - discountRate) }
    private var deliveryFee: Double { (model.mode == .delivery && !freeMeal) ? 1.90 : 0 }
    private var serviceFee: Double { (total > 0 && !freeMeal) ? 0.45 : 0 }
    private var grandTotal: Double { subtotalAfter + deliveryFee + serviceFee }

    private var sortedLines: [CartLine] {
        cart.keys.sorted { $0.item.name.localizedCaseInsensitiveCompare($1.item.name) == .orderedAscending }
    }
    private var visibleLines: [CartLine] {
        expanded ? sortedLines : Array(sortedLines.prefix(collapsedRows))
    }
    private var hiddenCount: Int { max(0, sortedLines.count - collapsedRows) }

    var body: some View {
        checkoutSurface
            .preferredColorScheme(.dark)
            .animation(.snappy(duration: 0.24), value: orderPlaced)
            .animation(.snappy(duration: 0.3), value: prize)
            .background { paymentSheetHost }
            .fullScreenCover(isPresented: $showGame) {
                ViceStripGame { won in prize = won }
            }
            .alert("Commande impossible", isPresented: $showPlacementError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(placementError)
            }
    }

    private var checkoutSurface: some View {
        ZStack {
            TastyTheme.surface.ignoresSafeArea()
            if orderPlaced {
                completionView.transition(.scale(scale: 0.96).combined(with: .opacity))
            } else {
                content.transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var paymentSheetHost: some View {
        if let paymentSheet {
            Color.clear
                .paymentSheet(isPresented: $showPaymentSheet, paymentSheet: paymentSheet) { result in
                    handlePaymentSheetResult(result)
                }
        }
    }

    private func makePaymentSheet(clientSecret: String) throws -> PaymentSheet {
        guard let publishableKey = store.stripePublishableKey, !publishableKey.isEmpty else {
            throw MenuAPI.APIError.paymentConfigurationMissing
        }

        let apiClient = STPAPIClient(publishableKey: publishableKey)
        apiClient.stripeAccount = store.stripeAccountId

        var configuration = PaymentSheet.Configuration()
        configuration.apiClient = apiClient
        configuration.merchantDisplayName = "Burger Nine"
        configuration.primaryButtonLabel = "Payer et commander"
        configuration.returnURL = "burgernine://stripe-redirect"
        configuration.paymentMethodOrder = ["card"]
        return PaymentSheet(paymentIntentClientSecret: clientSecret, configuration: configuration)
    }

    /// Burger Nine hook into the game — only shown until the player has played once.
    private var gameTeaser: some View {
        Button { HapticFeedback.select(); showGame = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "gamecontroller.fill")
                    .font(.title2.weight(.black))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text("REPAS OFFERT ?")
                        .font(.system(.subheadline, design: .rounded, weight: .black))
                        .foregroundStyle(.white)
                    Text("Tente ta chance sur le Vice Strip — 1 essai")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(14)
            .background(
                LinearGradient(colors: [Color(red: 1.0, green: 0.27, blue: 0.67), TastyTheme.neonViolet, TastyTheme.cyan],
                               startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 18)
            )
            .shadow(color: Color(red: 1.0, green: 0.27, blue: 0.67).opacity(0.4), radius: 14, y: 6)
        }
        .buttonStyle(.bouncy)
    }

    private func winRow(_ title: String, _ value: Double) -> some View {
        HStack {
            Text(title).font(.subheadline.weight(.black)).foregroundStyle(TastyTheme.coral)
            Spacer()
            Text(value, format: .currency(code: "EUR"))
                .font(.subheadline.weight(.black))
                .foregroundStyle(TastyTheme.coral)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    if prize == nil { gameTeaser }
                    orderRecap
                    addressRecap
                    etaRow
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 18)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { payBar }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.black))
                    .foregroundStyle(TastyTheme.ink)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(TastyTheme.hairline))
            }
            .buttonStyle(.bouncy)
            VStack(alignment: .leading, spacing: 2) {
                Text("Paiement")
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .foregroundStyle(TastyTheme.ink)
                Text(store.displayName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TastyTheme.muted)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Rectangle().fill(TastyTheme.hairline).frame(height: 1) }
    }

    private var orderRecap: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionTitle("Récapitulatif")
                Spacer()
                if hiddenCount > 0 || expanded {
                    Button {
                        withAnimation(.snappy(duration: 0.24)) { expanded.toggle() }
                    } label: {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.black))
                            .foregroundStyle(TastyTheme.muted)
                    }
                }
            }

            VStack(spacing: 10) {
                ForEach(visibleLines, id: \.self) { line in
                    productRow(line)
                }
                if !expanded && hiddenCount > 0 {
                    Button {
                        withAnimation(.snappy(duration: 0.24)) { expanded = true }
                    } label: {
                        Text("+ \(hiddenCount) autre\(hiddenCount == 1 ? "" : "s") article\(hiddenCount == 1 ? "" : "s")")
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(model.mode.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(spacing: 9) {
                Divider().overlay(TastyTheme.hairline)
                priceRow("Sous-total", total)
                if freeMeal {
                    winRow("Repas offert 🌴", -total)
                } else if discountRate > 0 {
                    winRow("Réduction Vice", -(total * discountRate))
                }
                if model.mode == .delivery { priceRow("Livraison", deliveryFee) }
                priceRow("Frais de service", serviceFee)
                Divider().overlay(TastyTheme.hairline)
                HStack {
                    Text("Total").font(.headline.weight(.black)).foregroundStyle(TastyTheme.ink)
                    Spacer()
                    Text(grandTotal, format: .currency(code: "EUR"))
                        .font(.headline.weight(.black))
                        .foregroundStyle(model.mode.accent)
                }
            }
        }
        .checkoutPanel()
    }

    private func productRow(_ line: CartLine) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(cart[line, default: 0])")
                .font(.subheadline.weight(.black))
                .foregroundStyle(TastyTheme.ink)
                .frame(width: 28, height: 28)
                .background(TastyTheme.gold.opacity(0.9), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(line.item.name.trimmingCharacters(in: .whitespaces))
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(TastyTheme.ink)
                    .lineLimit(1)
                if !line.selectedOptions.isEmpty {
                    Text(line.selectedOptions.map(\.name).joined(separator: ", "))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TastyTheme.muted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Double(cart[line, default: 0]) * line.totalPrice, format: .currency(code: "EUR"))
                .font(.subheadline.weight(.black))
                .foregroundStyle(TastyTheme.ink)
        }
    }

    private var addressRecap: some View {
        HStack(spacing: 12) {
            Image(systemName: model.mode == .delivery ? "location.fill" : "takeoutbag.and.cup.and.straw.fill")
                .font(.headline.weight(.black))
                .foregroundStyle(model.mode.accent)
                .frame(width: 36, height: 36)
                .background(model.mode.accent.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(model.mode.rawValue)
                    .font(.caption.weight(.black))
                    .foregroundStyle(TastyTheme.muted)
                Text(model.mode == .delivery ? (model.confirmedAddress ?? "") : store.displayName)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(TastyTheme.ink)
                    .lineLimit(2)
                if model.mode == .delivery, !model.addressDetail.isEmpty {
                    Text(model.addressDetail)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TastyTheme.muted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Changer") { onChangeAddress() }
                .font(.caption.weight(.black))
                .foregroundStyle(model.mode.accent)
                .padding(.vertical, 6)
                .padding(.leading, 6)
                .contentShape(Rectangle())
        }
        .padding(14)
        .background(TastyTheme.elevatedSoft, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(TastyTheme.hairline))
    }

    private var etaRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.badge.checkmark.fill")
                .font(.headline.weight(.black))
                .foregroundStyle(model.mode.accent)
                .frame(width: 36, height: 36)
                .background(model.mode.accent.opacity(0.16), in: Circle())
            Text(model.mode.etaTitle)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(TastyTheme.muted)
            Spacer()
            Text(model.mode.etaRange)
                .font(.system(.subheadline, design: .rounded, weight: .black))
                .foregroundStyle(TastyTheme.ink)
        }
        .checkoutPanel()
    }

    private var payBar: some View {
        Button {
            guard !placing else { return }
            Task {
                placing = true
                defer { placing = false }
                do {
                    let lines = sortedLines.map { line in
                        MenuAPI.cartLine(line: line, quantity: cart[line, default: 0])
                    }
                    let serviceType = model.mode == .delivery ? "delivery" : "collection"
                    let paymentMethod = "online"
                    let quote = try await MenuAPI.quote(
                        slug: store.id,
                        lines: lines,
                        serviceType: serviceType,
                        paymentMethod: paymentMethod
                    )
                    guard quote.valid else {
                        throw MenuAPI.APIError.httpError(422, quote.blockers.map(\.message).joined(separator: "\n"))
                    }
                    let deliveryAddress = model.mode == .delivery
                        ? MenuAPI.DeliveryAddressRequest(
                            street: model.confirmedAddress ?? "",
                            zipcode: "",
                            city: "",
                            country: "FR",
                            note: model.addressDetail.isEmpty ? nil : model.addressDetail
                        )
                        : nil
                    let order = try await MenuAPI.checkout(
                        slug: store.id,
                        lines: lines,
                        serviceType: serviceType,
                        customer: MenuAPI.CustomerRequest(name: "Burger Nine customer", email: nil, phone: nil),
                        deliveryAddress: deliveryAddress,
                        idempotencyKey: UUID().uuidString,
                        paymentMethod: paymentMethod
                    )
                    MenuDiag.record("checkout created order \(order.orderId) for brand \(BurgerNineConfig.brandSlug)")
                    if order.paymentMethod == "offline" {
                        HapticFeedback.add()
                        onOrderPlaced?()
                        withAnimation(.snappy(duration: 0.24)) { orderPlaced = true }
                    } else if let clientSecret = order.clientSecret {
                        let sheet = try makePaymentSheet(clientSecret: clientSecret)
                        showPaymentSheet = false
                        paymentSheet = sheet
                        MenuDiag.record("Stripe payment sheet prepared for order \(order.orderId)")
                        // PaymentSheet presents on a false -> true transition. Let
                        // SwiftUI mount the configured sheet before opening it.
                        Task { @MainActor in
                            await Task.yield()
                            showPaymentSheet = true
                        }
                    } else {
                        throw MenuAPI.APIError.paymentConfigurationMissing
                    }
                } catch {
                    placementError = error.localizedDescription
                    showPlacementError = true
                    MenuDiag.record("checkout failed: \(error.localizedDescription)", isError: true)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Text("Payer et commander \(model.mode.paySuffix)")
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer()
                Text(grandTotal, format: .currency(code: "EUR"))
            }
            .font(.headline.weight(.black))
            .foregroundStyle(.white)
            .padding(17)
            .background(model.mode.accent, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: model.mode.accent.opacity(0.28), radius: 16, y: 8)
        }
        .buttonStyle(.bouncy)
        .disabled(placing)
        .opacity(placing ? 0.6 : 1)
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background {
            Rectangle().fill(.ultraThinMaterial)
                .overlay(alignment: .top) { Rectangle().fill(TastyTheme.hairline).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func handlePaymentSheetResult(_ result: PaymentSheetResult) {
        showPaymentSheet = false
        switch result {
        case .completed:
            MenuDiag.record("Stripe payment completed")
            HapticFeedback.add()
            onOrderPlaced?()
            withAnimation(.snappy(duration: 0.24)) { orderPlaced = true }
        case .canceled:
            MenuDiag.record("Stripe payment canceled")
        case .failed(let error):
            placementError = error.localizedDescription
            showPlacementError = true
            MenuDiag.record("Stripe payment failed: \(error.localizedDescription)", isError: true)
        }
    }

    private var completionView: some View {
        OrderTrackingView(
            mode: model.mode,
            storeName: store.displayName,
            address: model.confirmedAddress ?? store.addressLine,
            grandTotal: grandTotal,
            onDismiss: { dismiss() }
        )
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.headline.weight(.black)).foregroundStyle(TastyTheme.ink)
    }

    private func priceRow(_ title: String, _ value: Double) -> some View {
        HStack {
            Text(title).font(.subheadline.weight(.bold)).foregroundStyle(TastyTheme.muted)
            Spacer()
            Text(value, format: .currency(code: "EUR"))
                .font(.subheadline.weight(.black))
                .foregroundStyle(TastyTheme.ink)
        }
    }
}

// MARK: - MapKit address autocomplete

@MainActor
@Observable
final class AddressSearch: NSObject, MKLocalSearchCompleterDelegate {
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            if query.isEmpty {
                results = []
            } else {
                completer.queryFragment = query
            }
        }
    }
    private(set) var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let updated = completer.results
        Task { @MainActor in self.results = Array(updated.prefix(4)) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }
}

// MARK: - Shared panel style

private extension View {
    func checkoutPanel() -> some View {
        padding(16)
            .background(TastyTheme.elevatedSoft, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(TastyTheme.hairline))
            .shadow(color: TastyTheme.violet.opacity(0.045), radius: 10, y: 5)
    }
}
