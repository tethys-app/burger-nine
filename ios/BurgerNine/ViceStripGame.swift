import SwiftUI

// MARK: - Game outcome

/// What the player walks away with. The house controls the odds via the
/// width of each band on the strip — `free` is a thin sliver in the middle.
enum GamePrize: Equatable {
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

// MARK: - Strip band

/// One slice of the strip. `share` is its proportion of the full width — the
/// sum across all bands is 1. Keep `free` small to control payout.
private struct Band: Identifiable {
    let id = UUID()
    let prize: GamePrize
    let share: Double
    let color: Color
}

private let kBands: [Band] = [
    Band(prize: .discount(10), share: 0.30, color: TastyTheme.cyan),
    Band(prize: .discount(20), share: 0.16, color: TastyTheme.neonViolet),
    Band(prize: .free,         share: 0.08, color: TastyTheme.gold),   // the sliver
    Band(prize: .discount(20), share: 0.16, color: TastyTheme.neonViolet),
    Band(prize: .discount(10), share: 0.30, color: TastyTheme.cyan),
]

/// Hot-pink + cyan, the Vice palette.
private enum Vice {
    static let pink = Color(red: 1.0, green: 0.27, blue: 0.67)
    static let sky = Color(red: 0.34, green: 0.20, blue: 0.55)
    static let sunTop = Color(red: 1.0, green: 0.84, blue: 0.38)
    static let sunBottom = Color(red: 1.0, green: 0.28, blue: 0.55)
    static let grid = Color(red: 0.95, green: 0.25, blue: 0.85)
}

// MARK: - Game view

/// "VICE STRIP" — a neon marker sweeps across the strip; one tap locks it.
/// Land on the gold sliver and the meal is free. One thumb, ~6 seconds, no
/// tutorial: the FREE band glows and pulses so the target reads instantly.
struct ViceStripGame: View {
    let onFinish: (GamePrize) -> Void
    var allowsReplay = false

    @Environment(\.dismiss) private var dismiss

    private enum Phase { case ready, running, locked }
    @State private var phase = Phase.ready
    @State private var marker: Double = 0          // 0…1 position across the strip
    @State private var direction: Double = 1
    @State private var result: GamePrize?
    @State private var lockedX: Double = 0
    @State private var startTime: Date?

    // Sweep speed in strip-widths per second. Fast enough to feel like skill.
    private let speed: Double = 1.35

    var body: some View {
        ZStack {
            ViceBackdrop()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 8)
                title
                Spacer(minLength: 18)
                strip
                Spacer(minLength: 18)
                actionArea
                Spacer(minLength: 12)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)

            if let result, phase == .locked {
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
            Text("VICE STRIP")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .tracking(2)
                .foregroundStyle(
                    LinearGradient(colors: [Vice.sunTop, Vice.pink],
                                   startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: Vice.pink.opacity(0.6), radius: 14, y: 0)
            Text("Arrête le curseur sur la zone OR — ton repas est offert.")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.white.opacity(0.82))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: strip

    private var strip: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h: CGFloat = 92
            ZStack(alignment: .leading) {
                // Bands
                HStack(spacing: 0) {
                    ForEach(kBands) { band in
                        bandCell(band)
                            .frame(width: w * band.share)
                    }
                }
                .frame(height: h)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.18), lineWidth: 1.5))

                // Marker
                marketNeedle(height: h)
                    .offset(x: (phase == .locked ? lockedX : marker) * w - 2)
            }
            .frame(height: h)
            .contentShape(Rectangle())
            .onTapGesture { lock(width: w) }
        }
        .frame(height: 92)
    }

    private func bandCell(_ band: Band) -> some View {
        let win = band.prize.isWin
        return ZStack {
            band.color.opacity(win ? 0.95 : 0.22)
            if win {
                // Pulsing glow draws the eye straight to the target.
                Rectangle().fill(band.color)
                    .blur(radius: 10)
                    .opacity(phase == .running ? 0.9 : 0.55)
                    .scaleEffect(phase == .running ? 1.0 : 0.92)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: phase)
            }
            Text(win ? "FREE" : band.prize.title)
                .font(.system(win ? .subheadline : .caption, design: .rounded, weight: .black))
                .foregroundStyle(win ? .black : .white.opacity(0.9))
                .shadow(color: win ? band.color : .clear, radius: 6)
        }
        .overlay(Rectangle().stroke(.white.opacity(0.12), lineWidth: 0.5))
    }

    private func marketNeedle(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            Triangle()
                .fill(.white)
                .frame(width: 16, height: 10)
                .shadow(color: Vice.pink, radius: 6)
            Rectangle()
                .fill(LinearGradient(colors: [.white, Vice.pink], startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: height)
                .shadow(color: Vice.pink, radius: 8)
        }
        .offset(y: -10)
    }

    // MARK: action

    @ViewBuilder
    private var actionArea: some View {
        switch phase {
        case .ready:
            Button { start() } label: {
                gameButton("DÉMARRER", icon: "play.fill")
            }
            .buttonStyle(.bouncy)
        case .running:
            Button { lock(width: lastWidth) } label: {
                gameButton("STOP", icon: "hand.tap.fill")
            }
            .buttonStyle(.bouncy)
        case .locked:
            Color.clear.frame(height: 56)
        }
    }

    @State private var lastWidth: Double = 1

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
            LinearGradient(colors: [Vice.pink, Vice.sunBottom], startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .shadow(color: Vice.pink.opacity(0.5), radius: 18, y: 8)
    }

    // MARK: drive loop

    private func start() {
        HapticFeedback.select()
        phase = .running
        startTime = Date()
        driveLoop()
    }

    private func restart() {
        withAnimation(.snappy(duration: 0.25)) {
            phase = .ready
            marker = 0
            direction = 1
            result = nil
            lockedX = 0
            startTime = nil
        }
    }

    /// Hand-rolled animation loop: bounces the marker 0↔1 at constant speed.
    /// CADisplayLink-grade smoothness via SwiftUI's TimelineView would also work,
    /// but a recursive Task keeps the marker state plain and lock math trivial.
    private func driveLoop() {
        Task { @MainActor in
            var last = Date()
            while phase == .running {
                try? await Task.sleep(nanoseconds: 16_000_000)
                guard phase == .running else { break }
                let now = Date()
                let dt = now.timeIntervalSince(last)
                last = now
                marker += direction * speed * dt
                if marker >= 1 { marker = 1; direction = -1 }
                if marker <= 0 { marker = 0; direction = 1 }
            }
        }
    }

    private func lock(width: Double) {
        guard phase == .running else { return }
        lastWidth = width
        phase = .locked
        lockedX = marker
        let prize = prize(at: marker)
        result = prize
        if prize.isWin { HapticFeedback.add() } else { HapticFeedback.error() }
        withAnimation(.snappy(duration: 0.3)) { /* lock snap */ }
    }

    /// Maps the marker position to whichever band it fell on.
    private func prize(at x: Double) -> GamePrize {
        var acc = 0.0
        for band in kBands {
            acc += band.share
            if x <= acc { return band.prize }
        }
        return kBands.last!.prize
    }
}

// MARK: - Result overlay

private struct ResultOverlay: View {
    let prize: GamePrize
    let onDismiss: () -> Void
    var onReplay: (() -> Void)? = nil

    @State private var appear = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            if prize.isWin { Confetti() }
            VStack(spacing: 20) {
                Image(systemName: prize.isWin ? "party.popper.fill" : "ticket.fill")
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
                            LinearGradient(colors: [Vice.pink, Vice.sunBottom], startPoint: .leading, endPoint: .trailing),
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

// MARK: - Backdrop (sunset + neon perspective grid + scanlines)

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
