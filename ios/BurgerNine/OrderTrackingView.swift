import SwiftUI
import MapKit

// MARK: - Tracking state machine

enum TrackingStep: Int, CaseIterable {
    case confirmed, preparing, onTheWay, arrived

    var label: String {
        switch self {
        case .confirmed:  return "Commande confirmée"
        case .preparing:  return "En préparation"
        case .onTheWay:   return "En route"
        case .arrived:    return "Livrée !"
        }
    }

    var icon: String {
        switch self {
        case .confirmed:  return "checkmark.seal.fill"
        case .preparing:  return "flame.fill"
        case .onTheWay:   return "scooter"
        case .arrived:    return "house.fill"
        }
    }

    var color: Color {
        switch self {
        case .confirmed:  return TastyTheme.violet
        case .preparing:  return TastyTheme.orange
        case .onTheWay:   return TastyTheme.coral
        case .arrived:    return Color(red: 0.18, green: 0.78, blue: 0.45)
        }
    }

    // Simulated auto-advance delays (seconds)
    var advanceAfter: Double? {
        switch self {
        case .confirmed:  return 3
        case .preparing:  return 8
        case .onTheWay:   return 14
        case .arrived:    return nil
        }
    }
}

// MARK: - Main view

struct OrderTrackingView: View {
    let mode: FulfillmentMode
    let storeName: String
    let address: String
    let grandTotal: Double
    let orderID: String?
    let orderToken: String?
    let onDismiss: () -> Void

    @State private var step: TrackingStep = .confirmed
    @State private var liveOrder: MenuAPI.OrderStatusResponse?
    @State private var pollingError: String?
    @State private var etaMinutes: Int = 28
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 45.6881, longitude: 4.8156), // Roussillon
        span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
    )
    // Simulated courier coordinate drifts toward delivery address
    @State private var courierCoord = CLLocationCoordinate2D(latitude: 45.6920, longitude: 4.8090)
    @State private var pulseScale: CGFloat = 1

    init(
        mode: FulfillmentMode,
        storeName: String,
        address: String,
        grandTotal: Double,
        orderID: String? = nil,
        orderToken: String? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.mode = mode
        self.storeName = storeName
        self.address = address
        self.grandTotal = grandTotal
        self.orderID = orderID
        self.orderToken = orderToken
        self.onDismiss = onDismiss
    }

    private var isPickup: Bool { mode == .pickup }
    private var currentColor: Color { step.color }

    var body: some View {
        ZStack(alignment: .top) {
            // MARK: Map background
            Map(position: .constant(.region(region))) {
                ForEach(mapAnnotations) { pin in
                    Annotation("", coordinate: pin.coord) { pin.view }
                }
            }
            .ignoresSafeArea()

            // MARK: Status bar overlay (top)
            VStack(spacing: 0) {
                statusBar
                Spacer()
                bottomCard
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if orderID == nil { startSimulation() }
        }
        .task { await pollLiveOrder() }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        VStack(spacing: 0) {
            // Colored top strip
            currentColor
                .frame(height: 4)
                .animation(.easeInOut(duration: 0.5), value: step)

            HStack(spacing: 14) {
                // Step icon with pulse
                ZStack {
                    Circle()
                        .fill(currentColor.opacity(0.18))
                        .frame(width: 48, height: 48)
                        .scaleEffect(pulseScale)
                    Image(systemName: step.icon)
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(currentColor)
                }
                .animation(.easeInOut(duration: 0.4), value: step)

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusLabel)
                        .font(.system(.headline, design: .rounded, weight: .black))
                        .foregroundStyle(TastyTheme.ink)
                        .animation(.none, value: step)
                    Text(liveOrder == nil ? etaLine : liveStatusDetail)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TastyTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if step != .arrived {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(etaMinutes)")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(currentColor)
                            .contentTransition(.numericText())
                        Text("min")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(TastyTheme.muted)
                    }
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32, weight: .black))
                        .foregroundStyle(currentColor)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)

            // Progress steps strip
            stepsStrip
                .background(.ultraThinMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 0))
        .shadow(color: .black.opacity(0.1), radius: 12, y: 6)
    }

    private var etaLine: String {
        switch step {
        case .confirmed:  return "Votre commande a été acceptée"
        case .preparing:  return isPickup ? "Prêt dans ~\(etaMinutes) min" : "Le restaurant prépare votre commande"
        case .onTheWay:   return "Votre livreur arrive dans ~\(etaMinutes) min"
        case .arrived:    return isPickup ? "Vous pouvez récupérer votre commande" : "Votre commande est arrivée 🎉"
        }
    }

    private var stepsStrip: some View {
        HStack(spacing: 0) {
            ForEach(isPickup ? pickupSteps : deliverySteps, id: \.self) { s in
                let done = s.rawValue <= step.rawValue
                let active = s == step
                HStack(spacing: 0) {
                    VStack(spacing: 4) {
                        Circle()
                            .fill(done ? s.color : TastyTheme.hairline)
                            .frame(width: active ? 10 : 7, height: active ? 10 : 7)
                            .overlay(active ? Circle().stroke(s.color.opacity(0.4), lineWidth: 3) : nil)
                        Text(s.label)
                            .font(.system(size: 9, weight: active ? .black : .semibold))
                            .foregroundStyle(done ? s.color : TastyTheme.muted)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)

                    if s != (isPickup ? pickupSteps : deliverySteps).last {
                        Rectangle()
                            .fill(s.rawValue < step.rawValue ? currentColor.opacity(0.4) : TastyTheme.hairline)
                            .frame(height: 1.5)
                            .frame(maxWidth: 32)
                            .offset(y: -8)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var deliverySteps: [TrackingStep] { TrackingStep.allCases }
    private var pickupSteps: [TrackingStep] { [.confirmed, .preparing, .arrived] }

    private var displayStoreName: String { liveOrder?.store?.name ?? storeName }

    private var displayAddress: String {
        guard let address = liveOrder?.deliveryAddress else { return self.address }
        return [address.street, address.zipcode, address.city].joined(separator: ", ")
    }

    private var displayTotal: Double {
        Double(liveOrder?.totals.totalCents ?? Int((grandTotal * 100).rounded())) / 100
    }

    private var statusLabel: String {
        guard let status = liveOrder?.status else { return step.label }
        switch status {
        case .pendingPayment: return "Confirmation du paiement…"
        case .paymentFailed: return "Le paiement n’a pas abouti"
        case .new, .received: return "Commande reçue"
        case .accepted: return "Commande acceptée"
        case .inPreparation: return "En préparation"
        case .awaitingCollection: return "Prête — à récupérer"
        case .inDelivery: return "En livraison"
        case .completed: return "Commande terminée"
        case .rejected: return "Commande refusée"
        case .cancelled: return "Commande annulée"
        case .deliveryFailed: return "Échec de la livraison"
        }
    }

    private var liveStatusDetail: String {
        if let pollingError { return pollingError }
        switch liveOrder?.status {
        case .pendingPayment: return "Nous confirmons votre paiement…"
        case .paymentFailed: return "Vous pouvez fermer cette commande et réessayer."
        case .new, .received, .accepted: return "Votre commande a bien été transmise au restaurant."
        case .inPreparation: return "Le restaurant prépare votre commande."
        case .awaitingCollection: return "Vous pouvez récupérer votre commande."
        case .inDelivery: return "Votre commande est en livraison."
        case .completed: return "Merci pour votre commande !"
        case .rejected: return "Le restaurant n’a pas pu accepter cette commande."
        case .cancelled: return "Cette commande a été annulée."
        case .deliveryFailed: return "La livraison n’a pas abouti."
        case nil: return "Chargement de la commande…"
        }
    }

    private func pollLiveOrder() async {
        guard let orderID, let orderToken else { return }
        while !Task.isCancelled {
            do {
                let next = try await MenuAPI.order(id: orderID, token: orderToken)
                guard !Task.isCancelled else { return }
                liveOrder = next
                step = trackingStep(for: next.status)
                pollingError = nil
                if isTerminal(next.status) { return }
                try await Task.sleep(for: .seconds(1))
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled { pollingError = error.localizedDescription }
                return
            }
        }
    }

    private func trackingStep(for status: MenuAPI.OrderStatus) -> TrackingStep {
        switch status {
        case .inDelivery: return .onTheWay
        case .inPreparation, .awaitingCollection: return .preparing
        case .completed, .rejected, .cancelled, .deliveryFailed: return .arrived
        case .pendingPayment, .paymentFailed, .new, .received, .accepted: return .confirmed
        }
    }

    private func isTerminal(_ status: MenuAPI.OrderStatus) -> Bool {
        switch status {
        case .paymentFailed, .completed, .rejected, .cancelled, .deliveryFailed: return true
        default: return false
        }
    }

    // MARK: - Bottom card

    private var bottomCard: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(TastyTheme.hairline)
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 6)

            VStack(spacing: 12) {
                // Store + address row
                HStack(spacing: 12) {
                    Image(systemName: isPickup ? "takeoutbag.and.cup.and.straw.fill" : "storefront.fill")
                        .font(.headline.weight(.black))
                        .foregroundStyle(currentColor)
                        .frame(width: 38, height: 38)
                        .background(currentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayStoreName)
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(TastyTheme.ink)
                            .lineLimit(1)
                        Text(isPickup ? "Retrait sur place" : displayAddress)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TastyTheme.muted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(displayTotal, format: .currency(code: "EUR"))
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(TastyTheme.ink)
                }

                Divider().overlay(TastyTheme.hairline)

                // Courier row (delivery only, once on the way)
                if !isPickup && step == .onTheWay {
                    HStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(TastyTheme.muted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Votre livreur")
                                .font(.caption.weight(.black))
                                .foregroundStyle(TastyTheme.muted)
                            Text("Lucas")
                                .font(.subheadline.weight(.black))
                                .foregroundStyle(TastyTheme.ink)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill").foregroundStyle(TastyTheme.gold)
                            Text("4.9").font(.subheadline.weight(.black)).foregroundStyle(TastyTheme.ink)
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))

                    Divider().overlay(TastyTheme.hairline)
                }

                // Dismiss button
                Button(action: onDismiss) {
                    Text(step == .arrived ? "Fermer" : "Retour au menu")
                        .font(.headline.weight(.black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(currentColor, in: RoundedRectangle(cornerRadius: 18))
                        .shadow(color: currentColor.opacity(0.25), radius: 10, y: 5)
                }
                .buttonStyle(.bouncy)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(TastyTheme.hairline))
        .shadow(color: .black.opacity(0.12), radius: 24, y: -8)
        .padding(.horizontal, 0)
        .animation(.snappy(duration: 0.3), value: step)
    }

    // MARK: - Map annotations

    private var mapAnnotations: [MapPin] {
        var pins: [MapPin] = [
            MapPin(id: "store", coord: region.center, view: AnyView(StoreMapPin(color: currentColor)))
        ]
        if orderID == nil && !isPickup && step == .onTheWay {
            pins.append(MapPin(id: "courier", coord: courierCoord, view: AnyView(CourierMapPin())))
        }
        return pins
    }

    // MARK: - Simulation

    private func startSimulation() {
        // Pulse animation loop
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            pulseScale = 1.18
        }
        advanceStep()
    }

    private func advanceStep() {
        guard let delay = step.advanceAfter else { return }
        // Tick down ETA while waiting
        startETACountdown(totalSeconds: delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.snappy(duration: 0.4)) {
                if let next = TrackingStep(rawValue: step.rawValue + 1) {
                    step = next
                    if step == .onTheWay { etaMinutes = 12 }
                    if step == .arrived { etaMinutes = 0 }
                }
            }
            HapticFeedback.select()
            advanceStep()
            // Drift courier toward center
            if step == .onTheWay {
                animateCourier()
            }
        }
    }

    private func startETACountdown(totalSeconds: Double) {
        let startMinutes = etaMinutes
        let tickInterval = totalSeconds / Double(max(startMinutes, 1))
        var ticks = 0
        Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { timer in
            ticks += 1
            withAnimation(.easeInOut(duration: 0.3)) {
                etaMinutes = max(0, startMinutes - ticks)
            }
            if ticks >= startMinutes { timer.invalidate() }
        }
    }

    private func animateCourier() {
        let target = region.center
        let steps = 20
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.6) {
                let t = Double(i) / Double(steps)
                courierCoord = CLLocationCoordinate2D(
                    latitude: courierCoord.latitude + (target.latitude - courierCoord.latitude) * t * 0.15,
                    longitude: courierCoord.longitude + (target.longitude - courierCoord.longitude) * t * 0.15
                )
            }
        }
    }
}

// MARK: - Map pin types

private struct MapPin: Identifiable {
    let id: String
    let coord: CLLocationCoordinate2D
    let view: AnyView
}

private struct StoreMapPin: View {
    let color: Color
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(color).frame(width: 44, height: 44)
                    .shadow(color: color.opacity(0.4), radius: 8, y: 4)
                Image(systemName: "bag.fill")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.white)
            }
            Triangle().fill(color).frame(width: 12, height: 7)
        }
    }
}

private struct CourierMapPin: View {
    var body: some View {
        ZStack {
            Circle().fill(TastyTheme.ink).frame(width: 36, height: 36)
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
            Image(systemName: "scooter")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(.white)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

#Preview {
    OrderTrackingView(
        mode: .delivery,
        storeName: "Burger Nine Roussillon",
        address: "22 Rue de la Déserte, 69800 Saint-Priest",
        grandTotal: 12.35,
        onDismiss: {}
    )
}
