import SwiftUI

struct ProductFunnelSheet: View {
    let item: MenuItem
    let accent: Color
    let onAdd: (CartLine, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedOptionCounts: [MenuOptionGroup.ID: [MenuOptionItem.ID: Int]] = [:]
    @State private var stepIndex = 0
    @State private var direction: Int = 1

    // Ordered groups: top-level groups with sub-groups injected immediately after their parent.
    private var steps: [MenuOptionGroup] {
        var result: [MenuOptionGroup] = []
        for group in item.optionGroups {
            result.append(group)
            let sel = selectedOptions(in: group)
            for subID in sel.flatMap(\.subcategoryGroupIDs) {
                if let sub = item.subcategoryGroups[subID] {
                    result.append(sub)
                }
            }
        }
        return result
    }

    private var safeStepIndex: Int { min(stepIndex, max(steps.count - 1, 0)) }
    private var currentGroup: MenuOptionGroup? { steps[safe: safeStepIndex] }
    private var isLastStep: Bool { safeStepIndex >= steps.count - 1 }
    private var isFirstStep: Bool { safeStepIndex == 0 }

    private var itemTotal: Double {
        item.price + allSelectedOptions.reduce(0) { $0 + $1.price }
    }

    private var allSelectedOptions: [MenuOptionItem] {
        steps.flatMap { group in
            let counts = selectedOptionCounts[group.id, default: [:]]
            return group.items.flatMap { opt in Array(repeating: opt, count: counts[opt.id, default: 0]) }
        }
    }

    private var canFinish: Bool {
        steps.allSatisfy { totalQuantity(in: $0) >= $0.min }
    }

    // Current step is satisfied when the user has met the minimum for the current group.
    private var stepSatisfied: Bool {
        guard let group = currentGroup else { return true }
        return totalQuantity(in: group) >= group.min
    }

    // Single required pick auto-advances on tap — no CTA button needed.
    private var needsCTA: Bool {
        guard let group = currentGroup else { return false }
        return group.allowsMultiple || group.min == 0 || (group.max ?? 2) > 1
    }

    var body: some View {
        VStack(spacing: 0) {
            handle
            if steps.count > 1 { progressBar }
            stepContent
            funnelFooter
        }
        .background(composerBackground)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(28)
        .preferredColorScheme(.light)
    }

    private var handle: some View {
        Capsule()
            .fill(TastyTheme.muted.opacity(0.28))
            .frame(width: 36, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private var progressBar: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { idx, _ in
                let done = idx <= safeStepIndex
                Rectangle()
                    .fill(done ? TastyTheme.ink : TastyTheme.hairline)
                    .frame(height: 3)
                    .animation(.snappy(duration: 0.25), value: safeStepIndex)
            }
        }
        .clipShape(Capsule())
        .padding(.horizontal, 18)
        .padding(.bottom, 2)
        .overlay(alignment: .trailing) {
            Text("\(safeStepIndex + 1) / \(steps.count)")
                .font(.caption2.weight(.black))
                .foregroundStyle(TastyTheme.muted)
                .padding(.trailing, 18)
                .padding(.bottom, 2)
        }
    }

    // MARK: – Step content

    private var stepContent: some View {
        Group {
            if let group = currentGroup {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.name)
                                .font(.system(.title2, design: .rounded, weight: .black))
                                .foregroundStyle(TastyTheme.ink)
                            Text(requirementText(for: group))
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(TastyTheme.muted)
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 12)

                        VStack(spacing: 5) {
                            ForEach(group.items) { option in
                                if group.allowsMultiple {
                                    FunnelQuantityRow(
                                        option: option,
                                        quantity: quantity(of: option, in: group),
                                        canIncrease: canIncrease(option, in: group),
                                        accent: accent,
                                        onIncrease: { adjustQuantity(of: option, in: group, delta: 1) },
                                        onDecrease: { adjustQuantity(of: option, in: group, delta: -1) }
                                    )
                                } else {
                                    FunnelSingleRow(
                                        option: option,
                                        isSelected: quantity(of: option, in: group) > 0,
                                        accent: accent,
                                        onTap: { pickSingle(option, in: group) }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 16)
                    }
                }
                .id(group.id)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: direction > 0 ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: direction > 0 ? .leading : .trailing).combined(with: .opacity)
                    )
                )
            }
        }
        .animation(.snappy(duration: 0.24, extraBounce: 0.03), value: safeStepIndex)
        .frame(maxWidth: .infinity)
    }

    // MARK: – Footer

    private var funnelFooter: some View {
        HStack(spacing: 10) {
            if !isFirstStep {
                Button { advance(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.black))
                        .foregroundStyle(TastyTheme.ink)
                        .frame(width: 48, height: 48)
                        .background(TastyTheme.elevatedSoft, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(TastyTheme.hairline))
                }
                .buttonStyle(.bouncy)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }

            if isLastStep {
                Button {
                    onAdd(CartLine(item: item, selectedOptions: allSelectedOptions), 1)
                    dismiss()
                } label: {
                    HStack {
                        Text(canFinish ? "Ajouter" : "Choisis les options")
                        Spacer()
                        Text(itemTotal, format: .currency(code: "EUR")).contentTransition(.numericText())
                    }
                    .font(.headline.weight(.black))
                    .foregroundStyle(canFinish ? TastyTheme.ink : TastyTheme.muted.opacity(0.72))
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(canFinish ? TastyTheme.gold : TastyTheme.muted.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(canFinish ? 0.72 : 0.28), lineWidth: 1))
                    .shadow(color: canFinish ? TastyTheme.gold.opacity(0.22) : .clear, radius: 12, y: 6)
                }
                .buttonStyle(.bouncy)
                .disabled(!canFinish)
            } else if stepSatisfied && needsCTA {
                let label = steps[safe: safeStepIndex + 1]?.name ?? "Suivant"

                Button { advance(by: 1) } label: {
                    HStack {
                        Text(label)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(TastyTheme.ink, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12), lineWidth: 1))
                    .shadow(color: TastyTheme.ink.opacity(0.18), radius: 10, y: 5)
                }
                .buttonStyle(.bouncy)
                .transition(.scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: isFirstStep)
        .animation(.snappy(duration: 0.2), value: isLastStep)
        .animation(.snappy(duration: 0.22, extraBounce: 0.04), value: stepSatisfied)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    // MARK: – Logic

    private func advance(by delta: Int) {
        let target = safeStepIndex + delta
        guard target >= 0 && target < steps.count else { return }
        direction = delta
        withAnimation(.snappy(duration: 0.24, extraBounce: 0.03)) {
            stepIndex = target
        }
        HapticFeedback.select()
    }

    private func pickSingle(_ option: MenuOptionItem, in group: MenuOptionGroup) {
        let wasSelected = quantity(of: option, in: group) > 0
        withAnimation(.snappy(duration: 0.12)) {
            if wasSelected {
                selectedOptionCounts.removeValue(forKey: group.id)
            } else {
                selectedOptionCounts[group.id] = [option.id: 1]
            }
        }
        HapticFeedback.add()

        let isRequiredSingle = group.min == 1 && group.max == 1 && !group.allowsMultiple
        if isRequiredSingle && !wasSelected && !isLastStep {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                advance(by: 1)
            }
        }
    }

    private func selectedOptions(in group: MenuOptionGroup) -> [MenuOptionItem] {
        let counts = selectedOptionCounts[group.id, default: [:]]
        return group.items.flatMap { opt in Array(repeating: opt, count: counts[opt.id, default: 0]) }
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

    private func adjustQuantity(of option: MenuOptionItem, in group: MenuOptionGroup, delta: Int) {
        let current = quantity(of: option, in: group)
        let next = current + delta
        guard next >= 0 else { return }
        if delta > 0, !canIncrease(option, in: group) { return }
        withAnimation(.snappy(duration: 0.12)) {
            var counts = selectedOptionCounts[group.id, default: [:]]
            if next == 0 { counts.removeValue(forKey: option.id) } else { counts[option.id] = next }
            if counts.isEmpty { selectedOptionCounts.removeValue(forKey: group.id) }
            else { selectedOptionCounts[group.id] = counts }
        }
        if delta > 0 { HapticFeedback.add() } else { HapticFeedback.select() }
    }

    private func requirementText(for group: MenuOptionGroup) -> String {
        if group.min > 0, let max = group.max, max == group.min { return "Choisis \(group.min)" }
        if group.min > 0, let max = group.max { return "Au moins \(group.min), jusqu'à \(max)" }
        if let max = group.max { return group.allowsMultiple ? "Jusqu'à \(max)" : "Optionnel" }
        return group.allowsMultiple ? "Optionnel, plusieurs choix" : "Optionnel"
    }

    private var composerBackground: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            LinearGradient(
                colors: [accent.opacity(0.12), TastyTheme.surface.opacity(0.75), Color(uiColor: .systemBackground)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: – Row views

private struct FunnelSingleRow: View {
    let option: MenuOptionItem
    let isSelected: Bool
    let accent: Color
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2.weight(.bold))
                .foregroundStyle(isSelected ? accent : TastyTheme.muted.opacity(0.4))
                .frame(width: 30)

            Text(option.name)
                .font(.body.weight(.bold))
                .foregroundStyle(TastyTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            if option.price > 0 {
                Text("+ " + option.price.formatted(.currency(code: "EUR")))
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(isSelected ? TastyTheme.ink : TastyTheme.orange)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(isSelected ? accent.opacity(0.12) : TastyTheme.elevatedSoft, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? accent.opacity(0.45) : TastyTheme.hairline))
        .animation(.snappy(duration: 0.12), value: isSelected)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { onTap() }
    }
}

private struct FunnelQuantityRow: View {
    let option: MenuOptionItem
    let quantity: Int
    let canIncrease: Bool
    let accent: Color
    let onIncrease: () -> Void
    let onDecrease: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(option.name)
                    .font(.body.weight(.bold))
                    .foregroundStyle(TastyTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if option.price > 0 {
                    Text("+ " + option.price.formatted(.currency(code: "EUR")))
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(quantity > 0 ? TastyTheme.ink : TastyTheme.orange)
                }
            }
            if quantity > 0 {
                StepperCapsule(quantity: quantity, canAdd: canIncrease, add: onIncrease, decrease: onDecrease)
                    .transition(.scale(scale: 0.85, anchor: .trailing).combined(with: .opacity))
            } else {
                Image(systemName: "plus")
                    .font(.headline.weight(.black))
                    .foregroundStyle(canIncrease ? TastyTheme.ink : TastyTheme.muted.opacity(0.4))
                    .frame(width: 38, height: 38)
                    .background(canIncrease ? accent.opacity(0.18) : TastyTheme.muted.opacity(0.08), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
                    .transition(.scale(scale: 0.85, anchor: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(quantity > 0 ? TastyTheme.gold.opacity(0.16) : TastyTheme.elevatedSoft, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(quantity > 0 ? TastyTheme.gold.opacity(0.55) : TastyTheme.hairline))
        .animation(.snappy(duration: 0.12), value: quantity)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { if canIncrease { onIncrease() } }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
