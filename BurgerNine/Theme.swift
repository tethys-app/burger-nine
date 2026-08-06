import SwiftUI
import UIKit

@MainActor
enum HapticFeedback {
    // Reused + pre-armed generators: a freshly-allocated, un-prepared generator
    // often produces no perceptible tap on first fire.
    private static let selection = UISelectionFeedbackGenerator()
    private static let impact = UIImpactFeedbackGenerator(style: .medium)

    static func select() {
        selection.prepare()
        selection.selectionChanged()
    }

    static func add() {
        impact.prepare()
        impact.impactOccurred()
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

enum TastyTheme {
    static let ink = adaptive(
        light: UIColor(red: 0.07, green: 0.055, blue: 0.075, alpha: 1),
        dark: UIColor(red: 0.96, green: 0.92, blue: 1.0, alpha: 1)
    )
    static let surface = adaptive(
        light: UIColor(red: 0.985, green: 0.97, blue: 0.94, alpha: 1),
        dark: UIColor(red: 0.045, green: 0.035, blue: 0.075, alpha: 1)
    )
    static let surfaceDepth = adaptive(
        light: UIColor(red: 0.96, green: 0.94, blue: 0.91, alpha: 1),
        dark: UIColor(red: 0.075, green: 0.050, blue: 0.12, alpha: 1)
    )
    static let elevated = adaptive(
        light: UIColor.white,
        dark: UIColor(red: 0.105, green: 0.080, blue: 0.145, alpha: 1)
    )
    static let elevatedSoft = adaptive(
        light: UIColor(white: 1.0, alpha: 0.86),
        dark: UIColor(red: 0.14, green: 0.10, blue: 0.19, alpha: 0.90)
    )
    static let orange = Color(red: 1.0, green: 0.49, blue: 0.13)
    static let gold = Color(red: 1.0, green: 0.77, blue: 0.18)
    static let coral = Color(red: 1.0, green: 0.28, blue: 0.36)
    static let violet = Color(red: 0.52, green: 0.24, blue: 1.0)
    static let neonViolet = Color(red: 0.72, green: 0.38, blue: 1.0)
    static let cyan = Color(red: 0.0, green: 0.70, blue: 0.86)
    static let muted = adaptive(
        light: UIColor(red: 0.48, green: 0.42, blue: 0.38, alpha: 1),
        dark: UIColor(red: 0.72, green: 0.67, blue: 0.78, alpha: 1)
    )
    static let hairline = adaptive(
        light: UIColor(white: 0.0, alpha: 0.06),
        dark: UIColor(red: 0.78, green: 0.58, blue: 1.0, alpha: 0.18)
    )

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

enum RowLayout: Int, CaseIterable {
    case committed        // original: title 1 line, fixed 96pt trailing slot
    case floatingCorner   // plus floats bottom-right, text spans full width
    case wrapTwoLines     // reserved slot, title wraps to 2 lines
    case overlayTopRight  // plus pinned top-right corner over the text
    case fullWidthControl // controls on their own row below full-width text
    case compactPlus      // smaller plus in a tight reserved slot
    case tapToAdd         // no trailing +; whole row adds; right-side button clears cart qty

    var label: String {
        switch self {
        case .committed: return "Original"
        case .floatingCorner: return "Floating corner"
        case .wrapTwoLines: return "Wrap 2 lines"
        case .overlayTopRight: return "Overlay top-right"
        case .fullWidthControl: return "Controls row"
        case .compactPlus: return "Compact plus"
        case .tapToAdd: return "Tap row"
        }
    }
}

enum ClearButtonIcon: Int, CaseIterable {
    case xmark
    case minus
    case minusCircle
    case slash

    var systemName: String {
        switch self {
        case .xmark: return "xmark"
        case .minus: return "minus"
        case .minusCircle: return "minus.circle"
        case .slash: return "slash.circle"
        }
    }

    var label: String {
        switch self {
        case .xmark: return "Croix"
        case .minus: return "Trait"
        case .minusCircle: return "Cercle -"
        case .slash: return "Slash"
        }
    }
}

enum ClearButtonShape: Int, CaseIterable {
    case roundedSquare
    case circle
    case capsule

    var label: String {
        switch self {
        case .roundedSquare: return "Carré doux"
        case .circle: return "Rond"
        case .capsule: return "Pilule"
        }
    }
}

enum ClearButtonTone: Int, CaseIterable {
    case coral
    case ink
    case cyan
    case violet

    var label: String {
        switch self {
        case .coral: return "Corail"
        case .ink: return "Encre"
        case .cyan: return "Cyan"
        case .violet: return "Violet"
        }
    }

    var color: Color {
        switch self {
        case .coral: return TastyTheme.coral
        case .ink: return TastyTheme.ink
        case .cyan: return TastyTheme.cyan
        case .violet: return TastyTheme.violet
        }
    }
}

enum ClearButtonPreset: Int, CaseIterable {
    case softCoral
    case inkPlate
    case cyanPill

    var label: String {
        switch self {
        case .softCoral: return "Soft coral"
        case .inkPlate: return "Ink plate"
        case .cyanPill: return "Cyan pill"
        }
    }

    var detail: String {
        switch self {
        case .softCoral: return "Calme, clair, non-jaune"
        case .inkPlate: return "Premium, contrasté"
        case .cyanPill: return "Plus visible, très action"
        }
    }

    var icon: ClearButtonIcon {
        switch self {
        case .softCoral: return .xmark
        case .inkPlate: return .minus
        case .cyanPill: return .slash
        }
    }

    var shape: ClearButtonShape {
        switch self {
        case .softCoral: return .roundedSquare
        case .inkPlate: return .circle
        case .cyanPill: return .capsule
        }
    }

    var tone: ClearButtonTone {
        switch self {
        case .softCoral: return .coral
        case .inkPlate: return .ink
        case .cyanPill: return .cyan
        }
    }
}

struct BouncyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.68), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == BouncyButtonStyle {
    static var bouncy: BouncyButtonStyle { BouncyButtonStyle() }
}
