import SwiftUI

struct CartLine: Identifiable, Hashable {
    let item: MenuItem
    let selectedOptions: [MenuOptionItem]

    init(item: MenuItem, selectedOptions: [MenuOptionItem] = []) {
        self.item = item
        self.selectedOptions = selectedOptions.sorted {
            if $0.position == $1.position {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.position < $1.position
        }
    }

    var id: String {
        ([item.id] + selectedOptions.map(\.id).sorted()).joined(separator: "|")
    }

    var totalPrice: Double {
        item.price + selectedOptions.reduce(0) { $0 + $1.price }
    }
}

struct ProductOptionsSheet: View {
    /// When enabled, single-choice groups collapse to a summary after picking one option.
    static let collapsesSingleChoiceGroups = false

    let item: MenuItem
    let accent: Color
    let onAdd: (CartLine, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedOptionCounts: [MenuOptionGroup.ID: [MenuOptionItem.ID: Int]] = [:]
    @State private var expandedOptionGroupIDs: Set<MenuOptionGroup.ID> = []
    /// Set briefly when validate is tapped with this mandatory group unmet, to flash it.
    @State private var invalidGroupID: MenuOptionGroup.ID?

    init(
        item: MenuItem,
        accent: Color,
        initialSelectedOptionCounts: [MenuOptionGroup.ID: [MenuOptionItem.ID: Int]] = [:],
        initialExpandedOptionGroupIDs: Set<MenuOptionGroup.ID> = [],
        onAdd: @escaping (CartLine, Int) -> Void
    ) {
        self.item = item
        self.accent = accent
        self.onAdd = onAdd
        _selectedOptionCounts = State(initialValue: initialSelectedOptionCounts)
        _expandedOptionGroupIDs = State(initialValue: initialExpandedOptionGroupIDs)
    }

    private var selectedOptions: [MenuOptionItem] {
        activeGroups.flatMap { group in
            let counts = selectedOptionCounts[group.id, default: [:]]
            return group.items.flatMap { option in
                Array(repeating: option, count: counts[option.id, default: 0])
            }
        }
    }

    // Flat ordered list of groups to display: top-level groups interleaved with their active sub-groups.
    private var activeGroups: [MenuOptionGroup] {
        var result: [MenuOptionGroup] = []
        for group in item.optionGroups {
            result.append(group)
            let selected = selectedOptions(in: group)
            let subIDs = selected.flatMap(\.subcategoryGroupIDs)
            for id in subIDs {
                if let sub = item.subcategoryGroups[id] {
                    result.append(sub)
                }
            }
        }
        return result
    }

    private var itemTotal: Double {
        item.price + selectedOptions.reduce(0) { $0 + $1.price }
    }

    private var canAdd: Bool {
        activeGroups.allSatisfy { totalQuantity(in: $0) >= $0.min }
    }

    private var firstUnsatisfiedGroup: MenuOptionGroup? {
        activeGroups.first { totalQuantity(in: $0) < $0.min }
    }

    private func attemptAdd(proxy: ScrollViewProxy) {
        guard let unmet = firstUnsatisfiedGroup else {
            onAdd(CartLine(item: item, selectedOptions: selectedOptions), 1)
            dismiss()
            return
        }
        HapticFeedback.error()
        withAnimation(.snappy(duration: 0.3)) {
            proxy.scrollTo(unmet.id, anchor: .center)
            invalidGroupID = unmet.id
        }
        // Clear the flash so it can re-trigger on the next tap.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            if invalidGroupID == unmet.id { invalidGroupID = nil }
        }
    }

    var body: some View {
        ZStack {
            composerBackground

            VStack(spacing: 0) {
                composerHeader

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            if !item.description.isEmpty {
                                Text(item.description)
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(TastyTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 4)
                            }

                            optionContent
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 18)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        addBar { attemptAdd(proxy: proxy) }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(TastyTheme.sheetRadius)
        .preferredColorScheme(.dark)
    }

    private var composerBackground: some View {
        ZStack {
            TastyTheme.surface
            LinearGradient(
                colors: [
                    accent.opacity(0.16),
                    TastyTheme.surface.opacity(0.86),
                    TastyTheme.surface
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    private var composerHeader: some View {
        HStack(spacing: 12) {
            RemoteProductImage(url: item.image)
                .frame(width: 66, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(.white.opacity(0.70), lineWidth: 1.5)
                }
                .shadow(color: accent.opacity(0.22), radius: 18, y: 10)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.name.trimmingCharacters(in: .whitespaces).uppercased())
                    .font(.system(.headline, design: .rounded, weight: .black))
                    .foregroundStyle(TastyTheme.ink)
                    .lineLimit(2)

                Text(itemTotal, format: .currency(code: "EUR"))
                    .font(.system(.title3, design: .rounded, weight: .black))
                    .foregroundStyle(TastyTheme.orange)
                    .contentTransition(.identity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.black))
                    .foregroundStyle(TastyTheme.ink)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.58), lineWidth: 1))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 7)
            }
            .buttonStyle(.bouncy)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background {
            ZStack(alignment: .bottom) {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.36), accent.opacity(0.18), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Rectangle()
                    .fill(TastyTheme.hairline)
                    .frame(height: 1)
            }
            .ignoresSafeArea(edges: .top)
        }
    }

    private var optionContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(activeGroups) { group in
                optionGroupCard(group)
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func optionGroupHeader(_ group: MenuOptionGroup, isCollapsed: Bool) -> some View {
        let selected = selectedOptions(in: group)
        let header = HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.system(.headline, design: .rounded, weight: .black))
                    .foregroundStyle(TastyTheme.ink)

                Text(requirementText(for: group))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TastyTheme.muted)
                    .lineLimit(1)
                    .contentTransition(.identity)
            }

            Spacer()

            optionStatusPill(group: group, selected: selected.first, isCollapsed: isCollapsed)

            if Self.collapsesSingleChoiceGroups {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.black))
                    .foregroundStyle(TastyTheme.muted)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 180))
                    .frame(width: 16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())

        if Self.collapsesSingleChoiceGroups {
            Button {
                guard isCollapsed else { return }
                withAnimation(optionCollapseAnimation) {
                    _ = expandedOptionGroupIDs.insert(group.id)
                }
            } label: { header }
                .buttonStyle(.plain)
        } else {
            header
        }
    }

    @ViewBuilder
    private func optionGroupCard(_ group: MenuOptionGroup) -> some View {
        let isCollapsed = shouldCollapse(group)

        VStack(alignment: .leading, spacing: 0) {
            optionGroupHeader(group, isCollapsed: isCollapsed)

            if isCollapsed, !group.allowsMultiple, let selected = selectedOptions(in: group).first {
                selectedSingleChoiceSummary(selected, in: group)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
                        removal: .opacity
                    ))
            } else if !isCollapsed {
                VStack(spacing: 6) {
                    ForEach(group.items) { option in
                        if group.allowsMultiple {
                            QuantityOptionRow(
                                option: option,
                                quantity: quantity(of: option, in: group),
                                canIncrease: canIncrease(option, in: group),
                                accent: accent,
                                onIncrease: { adjustQuantity(of: option, in: group, delta: 1) },
                                onDecrease: { adjustQuantity(of: option, in: group, delta: -1) }
                            )
                        } else {
                            SingleChoiceOptionRow(
                                option: option,
                                isSelected: quantity(of: option, in: group) > 0,
                                onTap: { toggleSingleChoice(option, in: group) }
                            )
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.99, anchor: .top)),
                    removal: .opacity
                ))
            }
        }
        .background(TastyTheme.elevatedSoft, in: RoundedRectangle(cornerRadius: TastyTheme.controlRadius))
        .overlay(
            RoundedRectangle(cornerRadius: TastyTheme.controlRadius)
                .stroke(invalidGroupID == group.id ? TastyTheme.coral : TastyTheme.hairline,
                        lineWidth: invalidGroupID == group.id ? 2 : 1)
        )
        .shadow(color: invalidGroupID == group.id ? TastyTheme.coral.opacity(0.3) : TastyTheme.violet.opacity(0.045),
                radius: 10, y: 5)
        .clipShape(RoundedRectangle(cornerRadius: TastyTheme.controlRadius))
        .id(group.id)
        .animation(.snappy(duration: 0.2), value: invalidGroupID)
    }

    @ViewBuilder
    private func optionStatusPill(group: MenuOptionGroup, selected: MenuOptionItem?, isCollapsed: Bool) -> some View {
        let showsSelection = isCollapsed && selected != nil
        let shouldShowPill = group.min > 0 || showsSelection

        if shouldShowPill {
            HStack(spacing: 0) {
                Text(showsSelection ? "OK" : "Requis")
                    .font(.caption.weight(.black))
                    .lineLimit(1)
                    .contentTransition(.identity)
            }
            .foregroundStyle(TastyTheme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(showsSelection ? TastyTheme.gold.opacity(0.92) : accent.opacity(0.16), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.42)))
            .transition(.scale(scale: 0.92, anchor: .trailing).combined(with: .opacity))
        }
    }

    private func selectedSingleChoiceSummary(_ option: MenuOptionItem, in group: MenuOptionGroup) -> some View {
        Button {
            withAnimation(optionCollapseAnimation) {
                _ = expandedOptionGroupIDs.insert(group.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3.weight(.black))
                    .foregroundStyle(TastyTheme.orange)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.name)
                        .font(.body.weight(.black))
                        .foregroundStyle(TastyTheme.ink)
                        .lineLimit(2)

                    Text("Toucher pour modifier")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TastyTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if option.price > 0 {
                    Text("+ " + option.price.formatted(.currency(code: "EUR")))
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(TastyTheme.ink)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(TastyTheme.gold.opacity(0.24), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(TastyTheme.orange.opacity(0.34), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func toggleSingleChoice(_ option: MenuOptionItem, in group: MenuOptionGroup) {
        let wasSelected = quantity(of: option, in: group) > 0
        withAnimation(optionCollapseAnimation) {
            if wasSelected {
                selectedOptionCounts.removeValue(forKey: group.id)
            } else {
                selectedOptionCounts[group.id] = [option.id: 1]
            }
            expandedOptionGroupIDs.remove(group.id)
        }
        if wasSelected {
            HapticFeedback.select()
        } else {
            HapticFeedback.add()
        }
    }

    private func addBar(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(canAdd ? "Ajouter" : "Choisis les options")
                    .lineLimit(1)

                Spacer()

                Text(itemTotal, format: .currency(code: "EUR"))
                    .contentTransition(.identity)
            }
            .font(.headline.weight(.black))
            .foregroundStyle(canAdd ? TastyTheme.ink : TastyTheme.muted.opacity(0.72))
            .padding(18)
            .background(canAdd ? TastyTheme.gold : TastyTheme.muted.opacity(0.14), in: RoundedRectangle(cornerRadius: TastyTheme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: TastyTheme.cardRadius).stroke(.white.opacity(canAdd ? 0.72 : 0.28), lineWidth: 1))
            .shadow(color: canAdd ? TastyTheme.gold.opacity(0.24) : .clear, radius: 18, y: 9)
        }
        .buttonStyle(.bouncy)
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(TastyTheme.hairline)
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func requirementText(for group: MenuOptionGroup) -> String {
        if group.min > 0, let max = group.max, max == group.min {
            return group.allowsMultiple ? "Choisis \(group.min)" : "Choisis \(group.min)"
        }
        if group.min > 0, let max = group.max {
            return "Choisis au moins \(group.min), jusqu'à \(max)"
        }
        if let max = group.max {
            return group.allowsMultiple ? "Choisissez jusqu'à \(max)" : "Optionnel, jusqu'à \(max)"
        }
        return group.allowsMultiple ? "Optionnel, plusieurs choix" : "Optionnel"
    }

    private func selectedOptions(in group: MenuOptionGroup) -> [MenuOptionItem] {
        let counts = selectedOptionCounts[group.id, default: [:]]
        return group.items.flatMap { option in
            Array(repeating: option, count: counts[option.id, default: 0])
        }
    }

    private func quantity(of option: MenuOptionItem, in group: MenuOptionGroup) -> Int {
        selectedOptionCounts[group.id]?[option.id] ?? 0
    }

    private func totalQuantity(in group: MenuOptionGroup) -> Int {
        selectedOptionCounts[group.id, default: [:]].values.reduce(0, +)
    }

    private func canIncrease(_ option: MenuOptionItem, in group: MenuOptionGroup) -> Bool {
        guard group.allowsMultiple else { return quantity(of: option, in: group) == 0 }
        return totalQuantity(in: group) < (group.max ?? .max)
    }

    private func shouldCollapse(_ group: MenuOptionGroup) -> Bool {
        Self.collapsesSingleChoiceGroups
            && !group.allowsMultiple
            && !expandedOptionGroupIDs.contains(group.id)
            && !selectedOptions(in: group).isEmpty
    }

    private func adjustQuantity(of option: MenuOptionItem, in group: MenuOptionGroup, delta: Int) {
        guard group.allowsMultiple else { return }
        let current = quantity(of: option, in: group)
        let next = current + delta
        guard next >= 0 else { return }
        if delta > 0, !canIncrease(option, in: group) { return }

        withAnimation(optionCollapseAnimation) {
            var groupCounts = selectedOptionCounts[group.id, default: [:]]
            if next == 0 {
                groupCounts.removeValue(forKey: option.id)
            } else {
                groupCounts[option.id] = next
            }

            if groupCounts.isEmpty {
                selectedOptionCounts.removeValue(forKey: group.id)
            } else {
                selectedOptionCounts[group.id] = groupCounts
            }
            expandedOptionGroupIDs.remove(group.id)
        }
        if delta > 0 {
            HapticFeedback.add()
        } else {
            HapticFeedback.select()
        }
    }

    private var optionCollapseAnimation: Animation {
        .snappy(duration: 0.18, extraBounce: 0)
    }
}

private struct SingleChoiceOptionRow: View {
    let option: MenuOptionItem
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .font(.title3.weight(.bold))
                .foregroundStyle(isSelected ? TastyTheme.orange : TastyTheme.muted.opacity(0.48))
                .frame(width: 28)

            Text(option.name)
                .font(.body.weight(.bold))
                .foregroundStyle(TastyTheme.ink)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if option.price > 0 {
                Text("+ " + option.price.formatted(.currency(code: "EUR")))
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(isSelected ? TastyTheme.ink : TastyTheme.orange)
                    .contentTransition(.identity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 13)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(isSelected ? TastyTheme.gold.opacity(0.22) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? TastyTheme.gold.opacity(0.70) : Color.clear, lineWidth: 1)
        }
        .scaleEffect(isPressed ? 0.97 : (isSelected ? 1.012 : 1))
        .animation(
            isPressed ? .easeOut(duration: 0.08) : .spring(response: 0.28, dampingFraction: 0.65),
            value: isPressed
        )
        .animation(.snappy(duration: 0.12, extraBounce: 0), value: isSelected)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            InstantPressGesture(
                onPressingChanged: { isPressed = $0 },
                action: onTap
            )
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct QuantityOptionRow: View {
    let option: MenuOptionItem
    let quantity: Int
    let canIncrease: Bool
    let accent: Color
    let onIncrease: () -> Void
    let onDecrease: () -> Void

    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(option.name)
                    .font(.body.weight(.bold))
                    .foregroundStyle(TastyTheme.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if option.price > 0 {
                    Text("+ " + option.price.formatted(.currency(code: "EUR")))
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(quantity > 0 ? TastyTheme.ink : TastyTheme.orange)
                        .contentTransition(.identity)
                }
            }

            if quantity > 0 {
                StepperCapsule(quantity: quantity, canAdd: canIncrease, add: onIncrease, decrease: onDecrease)
                    .transition(.scale(scale: 0.85, anchor: .trailing).combined(with: .opacity))
            } else {
                Image(systemName: "plus")
                    .font(.headline.weight(.black))
                    .foregroundStyle(canIncrease ? TastyTheme.ink : TastyTheme.muted.opacity(0.5))
                    .frame(width: 40, height: 40)
                    .background(
                        canIncrease ? accent.opacity(0.22) : TastyTheme.muted.opacity(0.10),
                        in: Circle()
                    )
                    .overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 1))
                    .transition(.scale(scale: 0.85, anchor: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 13)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(quantity > 0 ? TastyTheme.gold.opacity(0.22) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(quantity > 0 ? TastyTheme.gold.opacity(0.70) : Color.clear, lineWidth: 1)
        }
        .scaleEffect(isPressed ? 0.97 : 1)
        .animation(
            isPressed ? .easeOut(duration: 0.08) : .spring(response: 0.28, dampingFraction: 0.65),
            value: isPressed
        )
        .animation(.snappy(duration: 0.16), value: quantity)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            InstantPressGesture(
                onPressingChanged: { isPressed = $0 },
                action: {
                    guard canIncrease else { return }
                    onIncrease()
                }
            )
            .padding(.trailing, quantity > 0 ? 108 : 0)
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(canIncrease ? "Ajoute un supplément" : "Limite atteinte pour ce groupe")
    }
}
