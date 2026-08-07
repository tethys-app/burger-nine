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
    // A restrained night-market palette: warm paper for content, plum for
    // primary actions and only a few semantic accents. Keeping these tokens
    // here makes every catalog, options and checkout surface feel like one app.
    static let ink = Color(red: 1, green: 247 / 255, blue: 241 / 255)
    static let surface = Color(red: 17 / 255, green: 12 / 255, blue: 20 / 255)
    static let surfaceDepth = Color(red: 28 / 255, green: 18 / 255, blue: 31 / 255)
    static let elevated = Color(red: 37 / 255, green: 25 / 255, blue: 43 / 255)
    static let elevatedSoft = Color(red: 48 / 255, green: 33 / 255, blue: 55 / 255)
    static let orange = Color(red: 1, green: 154 / 255, blue: 105 / 255)
    static let gold = Color(red: 1, green: 199 / 255, blue: 87 / 255)
    static let coral = Color(red: 244 / 255, green: 94 / 255, blue: 113 / 255)
    static let violet = Color(red: 173 / 255, green: 112 / 255, blue: 1)
    static let neonViolet = Color(red: 111 / 255, green: 75 / 255, blue: 236 / 255)
    static let cyan = Color(red: 83 / 255, green: 214 / 255, blue: 194 / 255)
    static let muted = Color(red: 201 / 255, green: 188 / 255, blue: 207 / 255)
    static let hairline = Color.white.opacity(0.12)

    static let cardRadius: CGFloat = 24
    static let controlRadius: CGFloat = 16
    static let sheetRadius: CGFloat = 28

    static var primaryGradient: LinearGradient {
        LinearGradient(
            colors: [violet, neonViolet],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var surfaceGradient: LinearGradient {
        LinearGradient(
            colors: [elevatedSoft, elevated],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.035 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == BouncyButtonStyle {
    static var bouncy: BouncyButtonStyle { BouncyButtonStyle() }
}
