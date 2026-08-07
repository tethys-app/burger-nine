import SwiftUI

/// Full-screen entry point shown after the opening splash. Roussillon is the
/// temporary nearest-store fallback until the API exposes store coordinates.
struct StoreEntryView: View {
    let store: StoreLocation
    let isLocating: Bool
    let locationEnabled: Bool
    let locationMessage: String?
    let chooseStore: () -> Void
    let requestLocation: () -> Void
    let startOrder: (FulfillmentMode) -> Void

    private var isOpen: Bool { !store.isClosed }
    private var storeName: String { (store.city ?? "Roussillon").uppercased() }
    private var statusText: String {
        let time = store.todaySlots.last.flatMap { $0.components(separatedBy: "-").last } ?? "23:59"
        return isOpen ? "Ouvert · \(time) · 1,2 km" : "Fermé · 1,2 km"
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                entryBackground

                VStack(spacing: 0) {
                    Spacer(minLength: max(30, proxy.size.height * 0.07))
                    brandLockup

                    Text("FAIT À LA COMMANDE")
                        .font(.caption.weight(.black))
                        .tracking(3.2)
                        .foregroundStyle(TastyTheme.muted.opacity(0.68))
                        .padding(.top, 18)

                    Spacer(minLength: 24)

                    VStack(spacing: 14) {
                        locationControls
                        orderActions
                    }
                    .padding(.bottom, max(22, proxy.safeAreaInsets.bottom + 12))
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("store-entry")
    }

    private var entryBackground: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.12, green: 0.06, blue: 0.16), TastyTheme.surface], startPoint: .top, endPoint: .bottom)
            Circle().fill(TastyTheme.violet.opacity(0.18)).blur(radius: 110).offset(x: 145, y: -230)
            Circle().fill(TastyTheme.neonViolet.opacity(0.10)).blur(radius: 130).offset(x: -150, y: 420)
        }
        .ignoresSafeArea()
    }

    private var brandLockup: some View {
        Image("BurgerNineLogo")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 330, maxHeight: 310)
            .accessibilityLabel("Burger Nine")
            .shadow(color: .black.opacity(0.38), radius: 26, y: 16)
    }

    private var locationControls: some View {
        HStack(spacing: 16) {
            Button(action: chooseStore) {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.title3.weight(.black))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(TastyTheme.brandGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        Text(storeName)
                            .font(.system(.headline, design: .rounded, weight: .black))
                            .foregroundStyle(TastyTheme.ink)
                        HStack(spacing: 7) {
                            Circle().fill(isOpen ? TastyTheme.cyan : TastyTheme.coral).frame(width: 8, height: 8)
                            Text(statusText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TastyTheme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.up")
                        .font(.footnote.weight(.black))
                        .foregroundStyle(TastyTheme.muted)
                }
                .padding(12)
                .background(TastyTheme.surfaceGradient, in: RoundedRectangle(cornerRadius: TastyTheme.sheetRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: TastyTheme.sheetRadius, style: .continuous).stroke(.white.opacity(0.13)))
            }
            .buttonStyle(.bouncy)
            .accessibilityHint("Ouvre la liste des restaurants Burger Nine")

            Button(action: requestLocation) {
                Image(systemName: isLocating ? "location.fill" : (locationEnabled ? "location.north.fill" : "scope"))
                    .font(.title2.weight(.black))
                    .foregroundStyle(TastyTheme.violet.opacity(0.78))
                    .frame(width: 84, height: 84)
                    .background(TastyTheme.surfaceGradient, in: RoundedRectangle(cornerRadius: TastyTheme.sheetRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: TastyTheme.sheetRadius, style: .continuous).stroke(.white.opacity(0.13)))
            }
            .buttonStyle(.bouncy)
            .disabled(isLocating)
            .accessibilityLabel("Utiliser ma position précise")
            .accessibilityHint("Demande l’autorisation d’utiliser votre position")
        }
    }

    private var orderActions: some View {
        HStack(spacing: 14) {
            orderButton(.pickup, title: "À EMPORTER", primary: true)
            orderButton(.delivery, title: "LIVRAISON", primary: false)
        }
    }

    private func orderButton(_ mode: FulfillmentMode, title: String, primary: Bool) -> some View {
        Button { startOrder(mode) } label: {
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .black))
                .tracking(1)
                .foregroundStyle(primary ? .white : TastyTheme.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background {
                    if primary {
                        TastyTheme.brandGradient
                    } else {
                        TastyTheme.surfaceGradient
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: TastyTheme.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: TastyTheme.cardRadius, style: .continuous).stroke(.white.opacity(primary ? 0.18 : 0.13)))
        }
        .buttonStyle(.bouncy)
        .accessibilityHint("Ouvre le menu pour une commande \(mode.rawValue.lowercased())")
    }
}

struct BrandSplashView: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.12, green: 0.06, blue: 0.16), TastyTheme.surface], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 24) {
                Image("BurgerNineLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 330, maxHeight: 290)
                    .accessibilityLabel("Burger Nine")
                Text("FAIT À LA COMMANDE")
                    .font(.caption.weight(.black))
                    .tracking(3.2)
                    .foregroundStyle(TastyTheme.muted.opacity(0.72))
            }
            .padding(.horizontal, 28)
        }
        .accessibilityIdentifier("brand-splash")
    }
}

/// A lightweight restaurant picker shared by the entry screen and the menu's
/// overflow control. It keeps selection explicit before proximity data exists.
struct StoreLocationPicker: View {
    let locations: [StoreLocation]
    let selectedID: String?
    let onSelect: (StoreLocation) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(locations) { location in
                Button {
                    onSelect(location)
                    dismiss()
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title2)
                            .foregroundStyle(location.id == selectedID ? TastyTheme.gold : TastyTheme.violet)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(location.displayName)
                                .font(.headline.weight(.black))
                                .foregroundStyle(TastyTheme.ink)
                            Text(location.addressLine.isEmpty ? (location.city ?? "Restaurant Burger Nine") : location.addressLine)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(TastyTheme.muted)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if location.id == selectedID {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(TastyTheme.gold)
                        }
                    }
                    .padding(.vertical, 5)
                }
                .listRowBackground(TastyTheme.elevated)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(TastyTheme.surface)
            .navigationTitle("Choisir un restaurant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .fontWeight(.bold)
                        .tint(TastyTheme.gold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(TastyTheme.sheetRadius)
        .preferredColorScheme(.dark)
    }
}
