import SwiftUI

// MARK: - Game outcome

/// What the player walks away with. The house controls the odds via the
/// size of the FREE segment — small center = controlled payout.
enum ViceWheelPrize: Equatable {
    case free                 // repas offert 🎉
    case discount(Int)        // % off as consolation

    var isWin: Bool { if case .free = self { return true } else { return false } }

    var title: String {
        switch self {
        case .free: return "REPAS OFFERT"
        case .discount(let p): return "-\(p)%"
        }
    }

    var subtitle: String {
        switch self {
        case .free: return "Ta commande est pour nous 🌴"
        case .discount(let p): return "Code appliqué : VICE\(p)"
        }
    }
}

// MARK: - Wheel segment

/// One slice of the wheel. `share` is its proportion (sum = 1.0).
/// FREE is the smallest to control payout (~7% chance).
private struct WheelSegment: Identifiable {
    let id = UUID()
    let prize: ViceWheelPrize
    let share: Double
    let color: Color
}

private let kSegments: [WheelSegment] = [
    WheelSegment(prize: .discount(10), share: 0.22, color: TastyTheme.cyan),
    WheelSegment(prize: .discount(15), share: 0.18, color: TastyTheme.neonViolet),
    WheelSegment(prize: .free,         share: 0.07, color: TastyTheme.gold),   // the jackpot
    WheelSegment(prize: .discount(15), share: 0.18, color: TastyTheme.neonViolet),
    WheelSegment(prize: .discount(10), share: 0.22, color: TastyTheme.cyan),
    WheelSegment(prize: .discount(20), share: 0.13, color: TastyTheme.coral),
]

/// Hot-pink + cyan, the Vice palette.
private enum Vice {
    static let pink = Color(red: 1.0, green: 0.27, blue: 0.67)
    static let sky = Color(red: 0.34, green: 0.20, blue: 0.55)
    static let sunTop = Color(red: 1.0, green: 0.84, blue: 0.38)
    static let sunBottom = Color(red: 1.0, green: 0.28, blue: 0.55)
    static let grid = Color(red: 0.95, green: 0.25, blue: 0.85)
    static let neonPink = Color(red: 1.0, green: 0.18, blue: 0.58)
}

// MARK: - Game view

/// "VICE WHEEL" — a neon dart wheel spins with a sweeping pointer.
/// Tap to throw the dart. Land on the golden FREE center and the meal is free.
/// One thumb, ~5 seconds, no tutorial: the FREE segment glows and pulses.
struct ViceWheelGame: View {
    let onFinish: (ViceWheelPrize) -> Void
    var allowsReplay = false

    @Environment(\.dismiss) private var dismiss

    private enum Phase { case ready, spinning, landed }
    @State private var phase = Phase.ready
    @State private var wheelAngle: Double = 0       // current rotation in degrees
    @State private var dartAngle: Double = 0        // where dart lands
    @State private var result: ViceWheelPrize?
    @State private var spinStartTime: Date?

    // Spin speed in degrees per second (full rotation ~2 seconds)
    private let baseSpeed: Double = 180
    // Deceleration curve - wheel slows down over time
    private let friction: Double = 0.985

    var body: some View {
        ZStack {
            ViceBackdrop()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 8)
                title
                Spacer(minLength: 18)
                wheelArea
                Spacer(minLength: 24)
                actionArea
                Spacer(minLength: 12)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)

            if let result, phase == .landed {
                ResultOverlay(
                    prize: result,
                    onDismiss: {
                        onFinish(result)
                        dismiss()
                    },
                    onReplay: allowsReplay ? { restart() } : nil
                )
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: header

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.12), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.18)))
            }
            Spacer()
            Text("1 essai")
                .font(.system(.caption, design: .rounded, weight: .black))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.white.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(Vice.pink.opacity(0.5)))
        }
        .padding(.top, 8)
    }

    private var title: some View {
        VStack(spacing: 6) {
            Text("VICE WHEEL")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .tracking(2)
                .foregroundStyle(
                    LinearGradient(colors: [Vice.sunTop, Vice.pink],
                                   startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: Vice.pink.opacity(0.6), radius: 14, y: 0)
            Text("Lance le dart et touche la zone OR — ton repas est offert.")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.white.opacity(0.82))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: wheel

    private var wheelArea: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height) * 0.85
            ZStack {
                // Wheel
                wheelBody(size: size)
                    .rotationEffect(.degrees(phase == .landed ? dartAngle : wheelAngle))

                // Pointer (fixed at top)
                wheelPointer()
                    .offset(y: -size / 2 - 12)

                // Dart (appears when landed)
                if phase == .landed {
                    dartAtCenter(size: size)
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { throwDart() }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func wheelBody(size: CGFloat) -> some View {
        ZStack {
            // Segments
            ForEach(Array(kSegments.enumerated()), id: \.element.id) { index, segment in
                wheelSegmentShape(
                    startAngle: startAngle(for: index),
                    endAngle: endAngle(for: index),
                    size: size
                )
                .fill(segmentColor(for: segment, index: index))
                .overlay(
                    wheelSegmentShape(
                        startAngle: startAngle(for: index),
                        endAngle: endAngle(for: index),
                        size: size
                    )
                    .stroke(.white.opacity(0.2), lineWidth: 1.5)
                )
            }

            // Center bullseye
            Circle()
                .fill(TastyTheme.gold)
                .frame(width: size * 0.18, height: size * 0.18)
                .overlay(
                    Circle()
                        .fill(TastyTheme.gold.opacity(phase == .spinning ? 0.6 : 0.9))
                        .blur(radius: phase == .spinning ? 8 : 4)
                        .scaleEffect(phase == .spinning ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: phase)
                )
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.3), lineWidth: 2)
                )
                .overlay(
                    Text("FREE")
                        .font(.system(size: size * 0.045, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                )

            // Outer ring
            Circle()
                .stroke(
                    LinearGradient(colors: [Vice.sunTop, Vice.pink, Vice.sunTop],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 4
                )
                .frame(width: size, height: size)

            // Decorative dots around edge
            ForEach(0..<24, id: \.self) { i in
                let angle = Double(i) * 15
                Circle()
                    .fill(Vice.sunTop)
                    .frame(width: 6, height: 6)
                    .offset(y: -size / 2 + 8)
                    .rotationEffect(.degrees(angle))
            }
        }
    }

    private func segmentColor(for segment: WheelSegment, index: Int) -> Color {
        let isWin = segment.prize.isWin
        if isWin {
            return segment.color
        }
        return segment.color.opacity(0.25)
    }

    private func wheelSegmentShape(startAngle: Double, endAngle: Double, size: CGFloat) -> some Shape {
        ArcShape(startAngle: startAngle, endAngle: endAngle,
                 innerRadius: size * 0.09, outerRadius: size * 0.5)
    }

    private func startAngle(for index: Int) -> Double {
        var acc = 0.0
        for i in 0..<index {
            acc += kSegments[i].share
        }
        return acc * 360 - 90  // -90 to start at top
    }

    private func endAngle(for index: Int) -> Double {
        var acc = 0.0
        for i in 0...index {
            acc += kSegments[i].share
        }
        return acc * 360 - 90
    }

    private func wheelPointer() -> some View {
        ZStack {
            // Glow
            Triangle()
                .fill(Vice.pink)
                .frame(width: 24, height: 20)
                .blur(radius: 4)
                .opacity(0.7)

            // Pointer
            Triangle()
                .fill(.white)
                .frame(width: 20, height: 16)
                .shadow(color: Vice.pink, radius: 6)
        }
    }

    private func dartAtCenter(size: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Dart body
            RoundedRectangle(cornerRadius: 2)
                .fill(LinearGradient(colors: [Vice.pink, .white], startPoint: .top, endPoint: .bottom))
                .frame(width: 8, height: 28)
                .shadow(color: Vice.pink, radius: 8)

            // Dart tip
            Triangle()
                .fill(Vice.sunTop)
                .frame(width: 8, height: 10)
                .rotationEffect(.degrees(180))
        }
        .offset(y: -size * 0.12)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: action

    @ViewBuilder
    private var actionArea: some View {
        switch phase {
        case .ready:
            Button { startSpin() } label: {
                gameButton("LANCER", icon: "target")
            }
            .buttonStyle(.bouncy)
        case .spinning:
            Button { throwDart() } label: {
                gameButton("DART !", icon: "paperplane.fill")
            }
            .buttonStyle(.bouncy)
        case .landed:
            Color.clear.frame(height: 56)
        }
    }

    private func gameButton(_ label: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
            Text(label).tracking(1)
        }
        .font(.system(.title3, design: .rounded, weight: .black))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            LinearGradient(colors: [Vice.pink, Vice.sunBottom],
                           startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .shadow(color: Vice.pink.opacity(0.5), radius: 18, y: 8)
    }

    // MARK: drive loop

    private func startSpin() {
        HapticFeedback.select()
        phase = .spinning
        spinStartTime = Date()
        spinLoop()
    }

    private func restart() {
        withAnimation(.snappy(duration: 0.25)) {
            phase = .ready
            wheelAngle = 0
            dartAngle = 0
            result = nil
            spinStartTime = nil
        }
    }

    /// Spinning animation with realistic deceleration (friction).
    private func spinLoop() {
        Task { @MainActor in
            var velocity = baseSpeed
            while phase == .spinning && velocity > 0.5 {
                try? await Task.sleep(nanoseconds: 16_000_000)
                guard phase == .spinning else { break }

                // Apply friction and update angle
                velocity *= friction
                wheelAngle += velocity * 0.016  // ~60fps

                // Keep angle in reasonable range
                if wheelAngle > 360 { wheelAngle -= 360 }
            }

            // Final landing position
            if phase == .spinning {
                // Calculate where dart lands (fixed position at top)
                dartAngle = wheelAngle
                landDart()
            }
        }
    }

    private func throwDart() {
        guard phase == .spinning else { return }
        // Force land immediately with current position
        dartAngle = wheelAngle
        landDart()
    }

    private func landDart() {
        phase = .landed
        let prize = prize(at: dartAngle)
        result = prize
        if prize.isWin { HapticFeedback.add() } else { HapticFeedback.error() }
    }

    /// Maps the wheel angle to whichever segment the pointer (top) is pointing at.
    private func prize(at angle: Double) -> ViceWheelPrize {
        // Normalize angle to 0-360 range (pointer is at top = 0°)
        var normalized = -angle.truncatingRemainder(dividingBy: 360)
        if normalized < 0 { normalized += 360 }

        var acc = 0.0
        for segment in kSegments {
            acc += segment.share * 360
            if normalized <= acc {
                return segment.prize
            }
        }
        return kSegments.last!.prize
    }
}

// MARK: - Arc shape

/// A custom shape representing a circular arc (pie slice without the center filled).
private struct ArcShape: Shape {
    var startAngle: Double
    var endAngle: Double
    var innerRadius: CGFloat
    var outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)

        // Outer arc
        p.addArc(center: center, radius: outerRadius,
                 startAngle: .degrees(startAngle),
                 endAngle: .degrees(endAngle),
                 clockwise: false)

        // Line to inner arc
        p.addArc(center: center, radius: innerRadius,
                 startAngle: .degrees(endAngle),
                 endAngle: .degrees(startAngle),
                 clockwise: true)

        p.closeSubpath()
        return p
    }
}

// MARK: - Result overlay

private struct ResultOverlay: View {
    let prize: ViceWheelPrize
    let onDismiss: () -> Void
    var onReplay: (() -> Void)? = nil

    @State private var appear = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            if prize.isWin { Confetti() }
            VStack(spacing: 20) {
                Image(systemName: prize.isWin ? "party.popper.fill" : "target")
                    .font(.system(size: 56, weight: .black))
                    .foregroundStyle(prize.isWin ? Vice.sunTop : .white)
                    .shadow(color: prize.isWin ? Vice.sunTop : Vice.pink, radius: 18)
                    .scaleEffect(appear ? 1 : 0.5)

                VStack(spacing: 8) {
                    Text(prize.title)
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: prize.isWin ? [Vice.sunTop, Vice.pink] : [.white, Vice.pink],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .shadow(color: Vice.pink.opacity(0.6), radius: 12)
                    Text(prize.subtitle)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }

                Button(action: onDismiss) {
                    Text(prize.isWin ? "Encaisser 🎁" : "Utiliser le code")
                        .font(.system(.headline, design: .rounded, weight: .black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(colors: [Vice.pink, Vice.sunBottom],
                                           startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 20)
                        )
                        .shadow(color: Vice.pink.opacity(0.5), radius: 16, y: 8)
                }
                .buttonStyle(.bouncy)
                .padding(.top, 4)

                if let onReplay {
                    Button(action: onReplay) {
                        Text("Rejouer")
                            .font(.system(.headline, design: .rounded, weight: .black))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.bouncy)
                }
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.15)))
            .padding(.horizontal, 36)
            .scaleEffect(appear ? 1 : 0.9)
            .opacity(appear ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { appear = true } }
    }
}

// MARK: - Backdrop (reused from ViceStripGame)

private struct ViceBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Vice.sky, Color(red: 0.12, green: 0.06, blue: 0.20), .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            // Sun
            Circle()
                .fill(LinearGradient(colors: [Vice.sunTop, Vice.sunBottom], startPoint: .top, endPoint: .bottom))
                .frame(width: 220, height: 220)
                .blur(radius: 2)
                .offset(y: -120)
                .opacity(0.9)

            // Perspective grid in the lower half
            BurgerNineGrid()
                .stroke(Vice.grid.opacity(0.55), lineWidth: 1.2)
                .shadow(color: Vice.grid.opacity(0.7), radius: 6)
                .ignoresSafeArea()
        }
    }
}

/// Vanishing-point grid: horizontal lines bunched toward the horizon, vertical
/// lines fanning out to the bottom edge — the classic outrun floor.
private struct BurgerNineGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let horizon = rect.midY + 30
        let bottom = rect.maxY
        let cx = rect.midX

        // Horizontal lines, exponentially spaced for depth.
        let rows = 9
        for i in 0...rows {
            let t = Double(i) / Double(rows)
            let y = horizon + (bottom - horizon) * (t * t)
            p.move(to: CGPoint(x: rect.minX, y: y))
            p.addLine(to: CGPoint(x: rect.maxX, y: y))
        }

        // Vertical lines fanning from the vanishing point.
        let cols = 10
        for i in -cols...cols {
            let spread = Double(i) / Double(cols)
            let topX = cx + spread * 26
            let botX = cx + spread * rect.width
            p.move(to: CGPoint(x: topX, y: horizon))
            p.addLine(to: CGPoint(x: botX, y: bottom))
        }
        return p
    }
}

// MARK: - Bits

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

/// Lightweight falling confetti for the win state.
private struct Confetti: View {
    private let pieces = (0..<60).map { _ in ConfettiPiece() }
    @State private var fall = false

    var body: some View {
        GeometryReader { geo in
            ForEach(pieces) { piece in
                RoundedRectangle(cornerRadius: 1)
                    .fill(piece.color)
                    .frame(width: 7, height: 11)
                    .rotationEffect(.degrees(piece.rotation))
                    .position(x: piece.x * geo.size.width,
                              y: fall ? geo.size.height + 40 : -40)
                    .animation(.easeIn(duration: piece.duration).delay(piece.delay), value: fall)
            }
        }
        .ignoresSafeArea()
        .onAppear { fall = true }
    }
}

private struct ConfettiPiece: Identifiable {
    let id = UUID()
    let x = Double.random(in: 0...1)
    let rotation = Double.random(in: 0...360)
    let duration = Double.random(in: 1.4...2.6)
    let delay = Double.random(in: 0...0.5)
    let color = [Vice.pink, Vice.sunTop, TastyTheme.cyan, TastyTheme.neonViolet, .white].randomElement()!
}
