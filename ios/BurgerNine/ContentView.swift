import SwiftUI
import UIKit

/// Scroll-sync state. Section-header geometry (read-only) drives which pill is
/// selected and whether the sticky bar shows. Tapping a pill scrolls
/// imperatively via ScrollViewReader — there is no persisted scrollPosition
/// write-binding, so re-renders (taps, sheets, cart bar) never re-anchor the
/// content. `scrollRequest` is a one-shot token the view observes and clears.
@MainActor
@Observable
final class MenuScrollSync {
    var selectedSection: MenuSection.ID?
    var isPinned = false
    var railTarget: String?
    /// One-shot: set on tap, the view scrolls to it then clears it.
    var scrollRequest: MenuSection.ID?

    static func pillID(_ id: MenuSection.ID) -> String { "pill-\(id)" }

    @ObservationIgnored private var sectionIDs: [MenuSection.ID] = []
    @ObservationIgnored private var headerY: [MenuSection.ID: CGFloat] = [:]
    // While a tap-scroll is in flight, ignore the geometry spy so it can't
    // fight the imperative scroll mid-animation.
    @ObservationIgnored private var spyMutedUntil = ContinuousClock.now

    init(sections: [MenuSection]) { reset(to: sections) }

    func reset(to sections: [MenuSection]) {
        sectionIDs = sections.map(\.id)
        headerY = [:]
        selectedSection = sectionIDs.first
        railTarget = selectedSection.map(Self.pillID)
        isPinned = false
    }

    func headerMoved(_ id: MenuSection.ID, minY: CGFloat, activationY: CGFloat) {
        headerY[id] = minY
        guard ContinuousClock.now >= spyMutedUntil else { return }
        // Topmost header still above the activation line is the active section;
        // if none are above, it's the predecessor of the topmost visible one.
        var best: (id: MenuSection.ID, y: CGFloat)?
        var topmost: (id: MenuSection.ID, y: CGFloat)?
        for (id, y) in headerY {
            if y <= activationY, best == nil || y > best!.y { best = (id, y) }
            if topmost == nil || y < topmost!.y { topmost = (id, y) }
        }
        let current: MenuSection.ID?
        if let best {
            current = best.id
        } else if let topmost, let idx = sectionIDs.firstIndex(of: topmost.id) {
            current = sectionIDs[max(idx - 1, 0)]
        } else {
            current = selectedSection
        }
        guard let current, current != selectedSection else { return }
        selectedSection = current
        railTarget = Self.pillID(current)
    }

    func headerGone(_ id: MenuSection.ID) { headerY[id] = nil }

    /// Reveal the sticky category bar once the first section header nears the top.
    func updateCategoryBarVisibility(firstHeaderMinY: CGFloat, showAt: CGFloat, hideAt: CGFloat) {
        guard ContinuousClock.now >= spyMutedUntil else { return }
        let shouldShow = isPinned ? firstHeaderMinY <= hideAt : firstHeaderMinY <= showAt
        guard shouldShow != isPinned else { return }
        withAnimation(.snappy(duration: 0.22)) { isPinned = shouldShow }
    }

    func select(_ id: MenuSection.ID) {
        selectedSection = id
        withAnimation(.snappy(duration: 0.2)) { railTarget = Self.pillID(id) }
        // Mute the spy briefly so it doesn't reselect mid-scroll, then request
        // the imperative scroll. isPinned stays/turns on; the spy resumes after.
        spyMutedUntil = .now + .seconds(0.6)
        if !isPinned { withAnimation(.snappy(duration: 0.22)) { isPinned = true } }
        scrollRequest = id
    }
}

struct ContentView: View {
    private let topScrollID = "menu-top"

    @State private var appStore = AppStore()
    @State private var selectedLocationID: String?
    @State private var scrollSync = MenuScrollSync(sections: [])
    @State private var cartsByStore: [String: [CartLine: Int]] = [:]
    @State private var configuringItem: MenuItem?
    @State private var showCheckout = false
    @State private var showStoreSwitcher = false
    @State private var showViceStripGame = false
    @State private var showViceRunGame = false
    @State private var showViceCatchGame = false
    @State private var appear = false
    @State private var showSettings = false
    @State private var showTrackingPreview = false
    @State private var logExport: URL?
    @AppStorage("rowLayout_v2") private var rowLayoutRaw = RowLayout.tapToAdd.rawValue
    @AppStorage("funnelMode_v2") private var funnelMode = true
    @AppStorage("clearButtonPreset_v2") private var clearButtonPresetRaw = ClearButtonPreset.inkPlate.rawValue
    @AppStorage("clearButtonIcon_v2") private var clearButtonIconRaw = ClearButtonIcon.minus.rawValue
    @AppStorage("clearButtonShape_v2") private var clearButtonShapeRaw = ClearButtonShape.circle.rawValue
    @AppStorage("clearButtonTone_v2") private var clearButtonToneRaw = ClearButtonTone.violet.rawValue
    private var rowLayout: RowLayout { .tapToAdd }
    private var clearButtonIcon: ClearButtonIcon { ClearButtonIcon(rawValue: clearButtonIconRaw) ?? .xmark }
    private var clearButtonShape: ClearButtonShape { ClearButtonShape(rawValue: clearButtonShapeRaw) ?? .roundedSquare }
    private var clearButtonTone: ClearButtonTone { ClearButtonTone(rawValue: clearButtonToneRaw) ?? .coral }

    // The pinned bar overlays the content instead of insetting it, so
    // programmatic scrolls anchor section headers just below the bar.
    private var selectedStore: StoreLocation {
        appStore.location(id: selectedLocationID) ?? StoreLocation(
            id: "fallback",
            displayName: "Chargement…",
            addressLine: "",
            city: nil,
            postalCode: nil,
            brand: appStore.brand,
            sections: [],
            featuredItem: nil,
            preparationTime: 15,
            isClosed: false,
            todaySlots: [],
            orderTypes: []
        )
    }

    private var menuSections: [MenuSection] { selectedStore.actionableSections }
    private var currentCart: [CartLine: Int] { cartsByStore[selectedStore.id, default: [:]] }
    private var cartCount: Int { currentCart.values.reduce(0, +) }
    private var total: Double { currentCart.reduce(0) { $0 + $1.key.totalPrice * Double($1.value) } }
    private var storeAccent: Color { TastyTheme.violet }
    private let pinnedRailHeight: CGFloat = 56
    private let pillScrollInset: CGFloat = 8
    private var productImageURLs: [String] {
        menuSections.flatMap(\.items).map(\.image).filter { !$0.isEmpty }
    }

    private var isDebugBuild: Bool {
        Bundle.main.bundleIdentifier?.hasSuffix(".debug") ?? false
    }

    private var buildTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        // Try to get build date from bundle, fall back to current date in debug
        if let executablePath = Bundle.main.executablePath,
           let attributes = try? FileManager.default.attributesOfItem(atPath: executablePath),
           let buildDate = attributes[.modificationDate] as? Date {
            return formatter.string(from: buildDate)
        }

        return formatter.string(from: Date())
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            background

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        Color.clear
                            .frame(height: 0)
                            .id(topScrollID)
                        header
                            .offset(y: appear ? 0 : -14).opacity(appear ? 1 : 0)
                            .padding(.bottom, 6)

                        ForEach(menuSections) { section in
                            Section {
                                ForEach(section.items) { item in
                                    ProductCard(
                                        item: item,
                                        quantity: quantity(for: item),
                                        layout: rowLayout,
                                        hidePlus: true,
                                        clearIcon: clearButtonIcon,
                                        clearShape: clearButtonShape,
                                        clearTone: clearButtonTone,
                                        stepperAdd: { repeatAdd(item) }
                                    ) {
                                        beginAdd(item)
                                    } decrease: {
                                        remove(item)
                                    } clear: {
                                        removeAll(item)
                                    }
                                }
                            } header: {
                                sectionHeader(section)
                                    .padding(.top, section.id == menuSections.first?.id ? 8 : 22)
                                    .id(section.id)
                                    .onGeometryChange(for: CGFloat.self) { proxy in
                                        proxy.frame(in: .scrollView).minY
                                    } action: { minY in
                                        scrollSync.headerMoved(section.id, minY: minY, activationY: pinnedRailHeight + 12)
                                        if section.id == menuSections.first?.id {
                                            scrollSync.updateCategoryBarVisibility(
                                                firstHeaderMinY: minY,
                                                showAt: pinnedRailHeight + 36,
                                                hideAt: pinnedRailHeight + 72
                                            )
                                        }
                                    }
                                    .onDisappear { scrollSync.headerGone(section.id) }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, cartCount > 0 ? 118 : 30)
                }
                .contentMargins(
                    .top,
                    scrollSync.isPinned ? pinnedRailHeight + pillScrollInset : 0,
                    for: .scrollContent
                )
                .overlay(alignment: .top) {
                    PinnedCategoryBar(sync: scrollSync, sections: menuSections, accent: storeAccent)
                }
                .onChange(of: scrollSync.scrollRequest) { _, target in
                    guard let target else { return }
                    withAnimation(.snappy(duration: 0.34)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                    scrollSync.scrollRequest = nil
                }
                .onChange(of: selectedLocationID) { _, _ in
                    scrollSync.reset(to: menuSections)
                    proxy.scrollTo(topScrollID, anchor: .top)
                }
                .refreshable {
                    await refreshCatalog()
                }
            }

            if cartCount > 0 { cartBar.transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.45)) { appear = true }
        }
        .task {
            await refreshCatalog()
        }
        .task(id: selectedStore.id) {
            await ProductImageCache.shared.prefetch(productImageURLs)
        }
        .confirmationDialog("Changer de point de vente", isPresented: $showStoreSwitcher, titleVisibility: .visible) {
            ForEach(appStore.locations) { location in
                Button(location.displayName) {
                    selectLocation(location.id)
                }
            }
        }
        .sheet(item: $configuringItem) { item in
            if funnelMode {
                ProductFunnelSheet(item: item, accent: storeAccent) { line, quantity in
                    add(line, quantity: quantity)
                }
            } else {
                ProductOptionsSheet(item: item, accent: storeAccent) { line, quantity in
                    add(line, quantity: quantity)
                }
            }
        }
        .sheet(isPresented: $showCheckout) {
            CheckoutFlow(cart: currentCart, store: selectedStore, total: total) {
                cartsByStore[selectedStore.id] = [:]
            }
        }
        .fullScreenCover(isPresented: $showTrackingPreview) {
            OrderTrackingView(
                mode: .delivery,
                storeName: selectedStore.displayName,
                address: "22 Rue de la Déserte, 69800 Saint-Priest",
                grandTotal: 12.35,
                onDismiss: { showTrackingPreview = false }
            )
        }
        .fullScreenCover(isPresented: $showViceStripGame) {
            ViceStripGame(onFinish: { _ in }, allowsReplay: true)
        }
        .fullScreenCover(isPresented: $showViceRunGame) {
            ViceRunGame(onComplete: { _ in }, allowsReplay: true)
        }
        .fullScreenCover(isPresented: $showViceCatchGame) {
            ViceCatchGame(onFinish: { _ in }, allowsReplay: true)
        }
        .sheet(item: $logExport) { url in
            ShareSheet(items: [url])
        }
        .overlay(alignment: .top) {
            if showSettings {
                DisplaySettingsPanel(
                    rowLayoutRaw: $rowLayoutRaw,
                    funnelMode: $funnelMode,
                    clearButtonPresetRaw: $clearButtonPresetRaw,
                    clearButtonIconRaw: $clearButtonIconRaw,
                    clearButtonShapeRaw: $clearButtonShapeRaw,
                    clearButtonToneRaw: $clearButtonToneRaw,
                    accent: storeAccent,
                    close: { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showSettings = false } }
                )
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .onOpenURL { url in
            guard url.scheme == "burgernine" else { return }
            let host = url.host ?? ""
            let slug = url.pathComponents.dropFirst().first ?? ""
            switch host {
            case "store":
                if let loc = appStore.locations.first(where: { $0.id == slug || $0.id.contains(slug) }) {
                    selectLocation(loc.id)
                }
            default: break
            }
        }
        .overlay(alignment: .top) {
            if isDebugBuild {
                TastyTheme.coral
                    .frame(height: 4)
                    .frame(maxWidth: .infinity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .zIndex(100)
            }
        }
    }

    /// Refreshes the live brand snapshot while keeping the current location
    /// whenever it still exists. AppStore applies the cached snapshot first,
    /// then replaces it with the API response and persists the fresh result.
    private func refreshCatalog() async {
        await appStore.load()

        // After the refresh, switch to the first API-sourced location only when
        // the previous selection disappeared. This keeps a pull gesture from
        // unexpectedly moving the customer to another restaurant.
        if appStore.locations.first(where: { $0.id == selectedLocationID }) == nil {
            selectedLocationID = appStore.locations.first?.id
            scrollSync.reset(to: appStore.locations.first?.actionableSections ?? [])
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(colors: [TastyTheme.surface, TastyTheme.surfaceDepth], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(storeAccent.opacity(0.19)).blur(radius: 92).offset(x: 155, y: -260)
            Circle().fill(TastyTheme.orange.opacity(0.10)).blur(radius: 86).offset(x: -150, y: 180)
            Circle().fill(TastyTheme.neonViolet.opacity(0.10)).blur(radius: 112).offset(x: 140, y: 420)
        }.ignoresSafeArea()
    }

    private var brandInitials: String {
        let words = selectedStore.brand.appName.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(selectedStore.brand.appName.prefix(2)).uppercased()
    }

    /// Avoid repeating the brand name when displayName already embeds it.
    private var headerSubtitle: String? {
        if let city = selectedStore.city, !city.isEmpty { return city }
        let brand = selectedStore.brand.appName
        let display = selectedStore.displayName
        guard display.caseInsensitiveCompare(brand) != .orderedSame else { return nil }
        let trimmed = display
            .replacingOccurrences(of: brand, with: "", options: .caseInsensitive)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–—·,"))
        return trimmed.isEmpty ? display : trimmed
    }

    private let brandMarkWidth: CGFloat = 52
    private let brandMarkSpacing: CGFloat = 12

    private var header: some View {
        let isOpen = !selectedStore.isClosed && !selectedStore.todaySlots.isEmpty
        let closingTime = selectedStore.todaySlots.last.flatMap { $0.components(separatedBy: "-").last }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: brandMarkSpacing) {
                brandMark

                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedStore.brand.appName.uppercased())
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(TastyTheme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)

                    if let headerSubtitle {
                        Text(headerSubtitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(TastyTheme.muted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                headerMenuButton
            }

            StoreMetaBar(
                isOpen: isOpen,
                closingTime: closingTime,
                preparationTime: selectedStore.preparationTime,
                hasDelivery: selectedStore.orderTypes.contains("delivery")
            )
            .padding(.leading, brandMarkWidth + brandMarkSpacing)
        }
        .padding(.top, 18)
    }

    private var hasBrandLogo: Bool {
        guard let logoURL = selectedStore.brand.logoURL else { return false }
        return !logoURL.isEmpty
    }

    @ViewBuilder
    private var brandMark: some View {
        if hasBrandLogo, let logoURL = selectedStore.brand.logoURL {
            AsyncImage(url: URL(string: logoURL)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .padding(7)
                case .failure:
                    brandMonogram
                default:
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(width: brandMarkWidth, height: brandMarkWidth)
            .background(TastyTheme.surfaceGradient, in: RoundedRectangle(cornerRadius: TastyTheme.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: TastyTheme.controlRadius, style: .continuous)
                    .stroke(TastyTheme.hairline, lineWidth: 1)
            }
        } else {
            brandMonogram
        }
    }
    

    private var brandMonogram: some View {
        Text(brandInitials)
            .font(.system(.subheadline, design: .rounded, weight: .black))
            .foregroundStyle(.white)
            .frame(width: brandMarkWidth, height: brandMarkWidth)
            .background(
                LinearGradient(
                    colors: [TastyTheme.violet, TastyTheme.neonViolet],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: TastyTheme.controlRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: TastyTheme.controlRadius, style: .continuous)
                    .stroke(TastyTheme.hairline, lineWidth: 1)
            }
    }

    private var headerMenuButton: some View {
        Menu {
            Button("Changer de point de vente") { showStoreSwitcher = true }
            Button("Preview: Suivi commande") { showTrackingPreview = true }
            Divider()
            Button {
                showSettings = true
            } label: {
                Label("Affichage", systemImage: "gearshape")
            }
            Section("Jeux") {
                Button {
                    showViceStripGame = true
                } label: {
                    Label("Vice Strip", systemImage: "dice.fill")
                }
                .help("Joue au mini-jeu classique de la roue.")

                Button {
                    showViceRunGame = true
                } label: {
                    Label("Vice Run", systemImage: "gamecontroller.fill")
                }
                .help("Lance le runner mobile et rejoue autant de fois que tu veux.")

                Button {
                    showViceCatchGame = true
                } label: {
                    Label("Vice Catch", systemImage: "hand.point.up.fill")
                }
                .help("Attrape les bons plats et évite les mauvais !")
            }
            Button {
                logExport = MenuDiag.exportFile()
            } label: {
                Label("Exporter les logs", systemImage: "square.and.arrow.up")
            }
            Divider()
            Section("Build \(buildTimestamp)") { }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(TastyTheme.ink)
                .frame(width: 38, height: 38)
                .background {
                    Circle()
                        .fill(
                            TastyTheme.surfaceGradient
                        )
                        .overlay {
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [TastyTheme.hairline, TastyTheme.violet.opacity(0.18)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                        .shadow(color: TastyTheme.violet.opacity(0.12), radius: 12, y: 6)
                }
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ section: MenuSection) -> some View {
        HStack(alignment: .lastTextBaseline) {
            Text(section.name.uppercased())
                .font(.system(.title3, design: .rounded, weight: .black))
                .foregroundStyle(TastyTheme.ink)
            Spacer()
            Text(section.subtitle)
                .font(.footnote.weight(.black))
                .foregroundStyle(TastyTheme.orange.opacity(0.72))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(UITestID.sectionHeader(sectionID: section.id))
        .accessibilityAddTraits(.isHeader)
    }

    private var cartBar: some View {
        Button {
            MenuDiag.record("tap cartBar → checkout (count=\(cartCount), total=\(String(format: "%.2f", total)))")
            showCheckout = true
        } label: {
            HStack(spacing: 14) {
                Text("\(cartCount)").font(.headline.bold()).foregroundStyle(TastyTheme.surface).frame(width: 40, height: 40).background(TastyTheme.gold, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Panier").font(.headline.bold()).foregroundStyle(.white)
                    Text("\(cartCount) article\(cartCount > 1 ? "s" : "") · " + total.formatted(.currency(code: "EUR"))).font(.caption.bold()).foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.headline.bold()).foregroundStyle(.white)
            }
            .padding(14)
            .background(
                TastyTheme.primaryGradient,
                in: RoundedRectangle(cornerRadius: TastyTheme.cardRadius)
            )
            .overlay(RoundedRectangle(cornerRadius: TastyTheme.cardRadius).stroke(.white.opacity(0.22)))
            .padding(.horizontal, 16)
            .shadow(color: storeAccent.opacity(0.22), radius: 24, y: 12)
        }
        .accessibilityIdentifier(UITestID.cartBar)
        .buttonStyle(.bouncy)
    }

    private func beginAdd(_ item: MenuItem) {
        if item.optionGroups.isEmpty {
            MenuDiag.record("beginAdd direct '\(item.name)'")
            add(CartLine(item: item), quantity: 1)
        } else {
            MenuDiag.record("beginAdd → options sheet '\(item.name)' (\(item.optionGroups.count) groups)")
            HapticFeedback.select()
            configuringItem = item
        }
    }

    private func add(_ line: CartLine, quantity: Int) {
        mutateCurrentCart { cart in
            cart[line, default: 0] += quantity
        }
        MenuDiag.record("add '\(line.item.name)' x\(quantity) → cartCount=\(cartCount)")
        HapticFeedback.add()
    }

    /// Stepper `+` increments the existing line with its saved config instead
    /// of reopening the options form. Falls back to the form for the first add.
    private func repeatAdd(_ item: MenuItem) {
        let existing = currentCart.keys
            .filter { $0.item.id == item.id }
            .sorted { $0.selectedOptions.count > $1.selectedOptions.count }
            .first
        if let line = existing {
            add(line, quantity: 1)
        } else {
            beginAdd(item)
        }
    }

    private func remove(_ item: MenuItem) {
        var didChange = false
        mutateCurrentCart { cart in
            guard let line = cart.keys
                .filter({ $0.item.id == item.id })
                .sorted(by: { $0.selectedOptions.count < $1.selectedOptions.count })
                .first
            else { return }

            let next = cart[line, default: 0] - 1
            didChange = true
            if next <= 0 {
                cart.removeValue(forKey: line)
            } else {
                cart[line] = next
            }
        }
        if didChange {
            MenuDiag.record("remove '\(item.name)' → cartCount=\(cartCount)")
            HapticFeedback.select()
        }
    }

    private func removeAll(_ item: MenuItem) {
        var didChange = false
        mutateCurrentCart { cart in
            let lines = cart.keys.filter { $0.item.id == item.id }
            guard !lines.isEmpty else { return }
            didChange = true
            for line in lines {
                cart.removeValue(forKey: line)
            }
        }
        if didChange {
            MenuDiag.record("removeAll '\(item.name)' → cartCount=\(cartCount)")
            HapticFeedback.select()
        }
    }

    private func quantity(for item: MenuItem) -> Int {
        currentCart.reduce(0) { partial, entry in
            entry.key.item.id == item.id ? partial + entry.value : partial
        }
    }

    private func mutateCurrentCart(_ update: (inout [CartLine: Int]) -> Void) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            var cart = cartsByStore[selectedStore.id, default: [:]]
            update(&cart)
            cartsByStore[selectedStore.id] = cart
        }
    }

    private func selectLocation(_ id: String) {
        MenuDiag.record("selectLocation \(id)")
        withAnimation(.snappy(duration: 0.34)) {
            selectedLocationID = id
        }
        scrollSync.reset(to: appStore.location(id: id)?.actionableSections ?? [])
    }
}

/// Searchable franchise picker. Filters by name, sorts the current one to the
/// top with a checkmark, and shows store counts.
private struct FranchiseSwitcher: View {
    let franchises: [FranchiseSummary]
    let currentID: String
    let accent: Color
    let select: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [FranchiseSummary] {
        let base = query.isEmpty ? franchises : franchises.filter {
            $0.name.localizedCaseInsensitiveContains(query)
        }
        return base.sorted {
            if ($0.id == currentID) != ($1.id == currentID) { return $0.id == currentID }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { franchise in
                Button {
                    select(franchise.id)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(franchise.name)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(TastyTheme.ink)
                            Text("\(franchise.storeCount) point\(franchise.storeCount > 1 ? "s" : "") de vente")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(TastyTheme.muted)
                        }
                        Spacer()
                        if franchise.id == currentID {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.headline)
                                .foregroundStyle(accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .searchable(text: $query, prompt: "Rechercher une franchise")
            .navigationTitle("Franchises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .fontWeight(.bold)
                        .tint(accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct PinnedCategoryBar: View {
    let sync: MenuScrollSync
    let sections: [MenuSection]
    let accent: Color

    var body: some View {
        // Always mounted; we animate visibility instead of inserting/removing.
        // Mounting/unmounting this overlay (which holds a horizontal ScrollView)
        // mid-scroll left the underlying vertical ScrollView with a stale
        // horizontal content offset → the "everything shifted right" bug that
        // only cleared on a sheet dismissal (full re-layout). Keeping it in the
        // tree and toggling opacity/offset removes that compositor thrash.
        CategoryRail(sync: sync, sections: sections, accent: accent, compact: true)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background {
                ZStack(alignment: .bottom) {
                    LinearGradient(
                        colors: [TastyTheme.surface.opacity(0.98), TastyTheme.surfaceDepth.opacity(0.94)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Rectangle()
                        .fill(LinearGradient(colors: [TastyTheme.orange.opacity(0.0), TastyTheme.orange.opacity(0.45), accent.opacity(0.28)], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 1)
                }
                .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
                .ignoresSafeArea(edges: .top)
            }
            .opacity(sync.isPinned ? 1 : 0)
            .offset(y: sync.isPinned ? 0 : -64)
            .allowsHitTesting(sync.isPinned)
            .animation(.snappy(duration: 0.22), value: sync.isPinned)
    }
}

private struct CategoryRail: View {
    let sync: MenuScrollSync
    let sections: [MenuSection]
    let accent: Color
    var compact = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sections) { section in
                    pill(section, isSelected: sync.selectedSection == section.id)
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, compact ? 6 : 2)
            .padding(.horizontal, 18)
        }
        .scrollPosition(id: Bindable(sync).railTarget, anchor: .center)
        .animation(.snappy(duration: 0.22), value: sync.selectedSection)
    }

    private func pill(_ section: MenuSection, isSelected: Bool) -> some View {
        Button {
            sync.select(section.id)
        } label: {
            Text(section.name.uppercased())
                .font(.footnote.weight(.black))
                .lineLimit(1)
                .padding(.horizontal, compact ? 14 : 15)
                .padding(.vertical, compact ? 9 : 10)
                .foregroundStyle(isSelected ? .white : TastyTheme.ink.opacity(0.72))
                .background {
                    // No matchedGeometryEffect: it interpolated a shared capsule
                    // across pills, and when selectedSection changed in the same
                    // tick PinnedCategoryBar unmounted (isPinned→false), the
                    // matched frame resolved inside a vanishing hierarchy → bad
                    // horizontal frame / freeze. A per-pill crossfade is robust.
                    Capsule()
                        .fill(LinearGradient(colors: [accent, TastyTheme.neonViolet], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .opacity(isSelected ? 1 : 0)
                        .background {
                            Capsule()
                                .fill(TastyTheme.elevated)
                                .overlay(Capsule().strokeBorder(TastyTheme.ink.opacity(0.08), lineWidth: 1.5))
                                .opacity(isSelected ? 0 : 1)
                        }
                        .shadow(color: isSelected ? accent.opacity(0.28) : .black.opacity(0.04), radius: isSelected ? 10 : 6, y: isSelected ? 4 : 3)
                }
                .id(MenuScrollSync.pillID(section.id))
        }
        .accessibilityIdentifier(UITestID.categoryPill(sectionID: section.id))
        .buttonStyle(.bouncy)
    }
}

/// Store facts as inline metadata — typographic, not pill-shaped like category nav.
private struct StoreMetaBar: View {
    let isOpen: Bool
    let closingTime: String?
    let preparationTime: Int
    let hasDelivery: Bool

    private var statusLabel: String {
        isOpen ? (closingTime.map { "Jusqu'\u{00E0} \($0)" } ?? "Ouvert") : "Ferm\u{00E9}"
    }

    private var hasExtras: Bool { preparationTime > 0 || hasDelivery }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) {
                statusRow
                if hasExtras {
                    metaDot
                    extrasContent
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                statusRow
                if hasExtras { extrasContent }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(TastyTheme.muted)
    }

    private var statusRow: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isOpen ? Color(red: 0.18, green: 0.78, blue: 0.45) : TastyTheme.coral)
                .frame(width: 6, height: 6)
            Text(statusLabel)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder
    private var extrasContent: some View {
        HStack(spacing: 7) {
            if preparationTime > 0 {
                Text("\(preparationTime) min")
            }
            if preparationTime > 0 && hasDelivery {
                metaDot
            }
            if hasDelivery {
                Text("Livraison")
            }
        }
    }

    private var metaDot: some View {
        Text("·")
            .font(.footnote.weight(.bold))
            .foregroundStyle(TastyTheme.muted.opacity(0.42))
    }
}

/// Floating top panel for product-row display and ordering experiments. Stays
/// out of the way — no modal dimming, no full-height sheet.
struct DisplaySettingsPanel: View {
    @Binding var rowLayoutRaw: Int
    @Binding var funnelMode: Bool
    @Binding var clearButtonPresetRaw: Int
    @Binding var clearButtonIconRaw: Int
    @Binding var clearButtonShapeRaw: Int
    @Binding var clearButtonToneRaw: Int
    let accent: Color
    let close: () -> Void

    @State private var logExport: URL?

    private var panelMaxHeight: CGFloat {
        let screen = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.bounds.height }
            .first ?? 800
        return screen * 0.5
    }

    private var selectedIcon: ClearButtonIcon {
        ClearButtonIcon(rawValue: clearButtonIconRaw) ?? .xmark
    }

    private var selectedShape: ClearButtonShape {
        ClearButtonShape(rawValue: clearButtonShapeRaw) ?? .roundedSquare
    }

    private var selectedTone: ClearButtonTone {
        ClearButtonTone(rawValue: clearButtonToneRaw) ?? .coral
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Affichage")
                    .font(.system(.headline, design: .rounded, weight: .black))
                    .foregroundStyle(TastyTheme.ink)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(TastyTheme.muted)
                }
                .buttonStyle(.plain)
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    settingsBody
                }
            }
            .frame(maxHeight: panelMaxHeight)
        }
        .sheet(item: $logExport) { url in
            ShareSheet(items: [url])
        }
        .tint(accent)
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(TastyTheme.hairline))
        .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
        .onAppear {
            rowLayoutRaw = RowLayout.tapToAdd.rawValue
        }
    }

    @ViewBuilder
    private var settingsBody: some View {
            settingsSection("MODE PRODUIT") {
                settingsCard {
                    HStack(spacing: 12) {
                        Image(systemName: "hand.tap.fill")
                            .font(.headline.weight(.black))
                            .foregroundStyle(accent)
                            .frame(width: 38, height: 38)
                            .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Ligne à toucher")
                                .font(.subheadline.weight(.black))
                                .foregroundStyle(TastyTheme.ink)
                            Text("Pas d'indicateur au repos. Après ajout: badge quantité sur l'image et bouton clear à droite.")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(TastyTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            settingsSection("BOUTON CLEAR") {
                pickerRow("Proposition", selection: $clearButtonPresetRaw) {
                    ForEach(ClearButtonPreset.allCases, id: \.rawValue) { preset in
                        Text(preset.label).tag(preset.rawValue)
                    }
                }
                .onChange(of: clearButtonPresetRaw) { _, value in
                    guard let preset = ClearButtonPreset(rawValue: value) else { return }
                    applyPreset(preset)
                }

                VStack(spacing: 8) {
                    ForEach(ClearButtonPreset.allCases, id: \.rawValue) { preset in
                        presetRow(preset)
                    }
                }

                pickerRow("Icône", selection: $clearButtonIconRaw) {
                    ForEach(ClearButtonIcon.allCases, id: \.rawValue) { icon in
                        Label(icon.label, systemImage: icon.systemName).tag(icon.rawValue)
                    }
                }

                pickerRow("Forme", selection: $clearButtonShapeRaw) {
                    ForEach(ClearButtonShape.allCases, id: \.rawValue) { shape in
                        Text(shape.label).tag(shape.rawValue)
                    }
                }

                pickerRow("Couleur", selection: $clearButtonToneRaw) {
                    ForEach(ClearButtonTone.allCases, id: \.rawValue) { tone in
                        Text(tone.label).tag(tone.rawValue)
                    }
                }
            }

            Divider().overlay(TastyTheme.hairline)

            Text("OPTIONS")
                .font(.caption2.weight(.black)).tracking(1.1)
                .foregroundStyle(TastyTheme.muted)

            Toggle(isOn: $funnelMode.animation(.spring(response: 0.3, dampingFraction: 0.85))) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mode entonnoir").font(.subheadline.weight(.semibold))
                    Text("Une option à la fois, étape par étape")
                        .font(.caption).foregroundStyle(TastyTheme.muted)
                }
            }

            Divider().overlay(TastyTheme.hairline)

            Button {
                logExport = MenuDiag.exportFile()
            } label: {
                Label("Exporter les logs", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TastyTheme.muted)
            }
            .buttonStyle(.plain)
    }

    private func applyPreset(_ preset: ClearButtonPreset) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            clearButtonIconRaw = preset.icon.rawValue
            clearButtonShapeRaw = preset.shape.rawValue
            clearButtonToneRaw = preset.tone.rawValue
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.caption2.weight(.black)).tracking(1.1)
                .foregroundStyle(TastyTheme.muted)
            content()
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TastyTheme.elevatedSoft.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(TastyTheme.hairline))
    }

    private func pickerRow<Content: View>(_ title: String, selection: Binding<Int>, @ViewBuilder content: () -> Content) -> some View {
        settingsCard {
            Picker(title, selection: selection) {
                content()
            }
            .pickerStyle(.menu)
            .font(.subheadline.weight(.bold))
            .tint(TastyTheme.ink)
        }
    }

    private func presetRow(_ preset: ClearButtonPreset) -> some View {
        Button {
            clearButtonPresetRaw = preset.rawValue
            applyPreset(preset)
        } label: {
            settingsCard {
                HStack(spacing: 12) {
                    clearPreview(icon: preset.icon, shape: preset.shape, tone: preset.tone)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(preset.label)
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(TastyTheme.ink)
                        Text(preset.detail)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TastyTheme.muted)
                    }
                    Spacer()
                    if clearButtonPresetRaw == preset.rawValue {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(accent)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func clearPreview(icon: ClearButtonIcon, shape: ClearButtonShape, tone: ClearButtonTone) -> some View {
        let width: CGFloat = shape == .capsule ? 58 : 44
        let height: CGFloat = shape == .capsule ? 38 : 44
        let radius: CGFloat = shape == .roundedSquare ? 16 : height / 2
        let color = tone.color

        return Image(systemName: icon.systemName)
            .font(.subheadline.weight(.black))
            .foregroundStyle(tone == .ink ? TastyTheme.elevated : color)
            .frame(width: width, height: height)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tone == .ink ? TastyTheme.ink.opacity(0.94) : color.opacity(0.12))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(color.opacity(0.48), lineWidth: 1.2)
            }
    }
}

#Preview("Light") { ContentView() }

#Preview("Dark") {
    ContentView()
        .preferredColorScheme(.dark)
}
