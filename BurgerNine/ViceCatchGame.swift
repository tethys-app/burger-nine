import SwiftUI

// MARK: - Game outcome

enum ViceCatchPrize: Equatable {
    case free
    case discount(Int)

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

// MARK: - Chicken parts

private enum ChickenPart: String, CaseIterable, Identifiable {
    case wing = "Aile"
    case drumstick = "Pilón"
    case breast = "Filet"
    case thigh = "Cuisse"

    var id: String { rawValue }

    var neonColor: Color {
        switch self {
        case .wing: return TastyTheme.gold
        case .drumstick: return TastyTheme.coral
        case .breast: return TastyTheme.orange
        case .thigh: return TastyTheme.neonViolet
        }
    }
}

// MARK: - Falling item

private struct FallingItem: Identifiable {
    let id = UUID()
    let part: ChickenPart
    var x: CGFloat
    var y: CGFloat
    var speed: CGFloat
    var isTarget: Bool
    var rotation: Double
}

// MARK: - Chicken part view

private struct ChickenPartView: View {
    let part: ChickenPart
    let isTarget: Bool
    let rotation: Double

    var body: some View {
        ZStack {
            partShape(for: part)
                .fill(part.neonColor)
                .frame(width: 50, height: 50)
                .shadow(color: part.neonColor.opacity(isTarget ? 0.8 : 0.4), radius: isTarget ? 12 : 6)

            if isTarget {
                partShape(for: part)
                    .stroke(part.neonColor, lineWidth: 2)
                    .frame(width: 50, height: 50)
            }
        }
        .rotationEffect(.degrees(rotation))
        .scaleEffect(isTarget ? 1.0 : 0.85)
        .opacity(isTarget ? 1.0 : 0.7)
    }

    private func partShape(for part: ChickenPart) -> AnyShape {
        switch part {
        case .wing:
            return AnyShape(WingShape())
        case .drumstick:
            return AnyShape(DrumstickShape())
        case .breast:
            return AnyShape(BreastShape())
        case .thigh:
            return AnyShape(ThighShape())
        }
    }
}

// Helper type eraser
private struct AnyShape: Shape {
    private let pathBuilder: (CGRect) -> Path

    init<S: Shape>(_ shape: S) {
        pathBuilder = { rect in
            var p = Path()
            p.addPath(shape.path(in: rect))
            return p
        }
    }

    func path(in rect: CGRect) -> Path {
        pathBuilder(rect)
    }
}

// MARK: - Custom chicken shapes

private struct WingShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height

        p.move(to: CGPoint(x: w * 0.5, y: h * 0.1))
        p.addQuadCurve(to: CGPoint(x: w * 0.9, y: h * 0.4),
                       control: CGPoint(x: w * 0.85, y: h * 0.15))
        p.addQuadCurve(to: CGPoint(x: w * 0.7, y: h * 0.9),
                       control: CGPoint(x: w * 0.95, y: h * 0.7))
        p.addQuadCurve(to: CGPoint(x: w * 0.3, y: h * 0.9),
                       control: CGPoint(x: w * 0.5, y: h * 0.95))
        p.addQuadCurve(to: CGPoint(x: w * 0.1, y: h * 0.4),
                       control: CGPoint(x: w * 0.05, y: h * 0.7))
        p.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.1),
                       control: CGPoint(x: w * 0.15, y: h * 0.15))
        p.closeSubpath()

        return p
    }
}

private struct DrumstickShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height

        // Meat part (oval)
        p.addEllipse(in: CGRect(x: w * 0.15, y: h * 0.1, width: w * 0.7, height: h * 0.55))

        // Bone
        p.move(to: CGPoint(x: w * 0.5, y: h * 0.55))
        p.addLine(to: CGPoint(x: w * 0.5, y: h * 0.95))
        p.addLine(to: CGPoint(x: w * 0.4, y: h * 0.95))
        p.addLine(to: CGPoint(x: w * 0.4, y: h * 0.6))
        p.addLine(to: CGPoint(x: w * 0.6, y: h * 0.6))
        p.addLine(to: CGPoint(x: w * 0.6, y: h * 0.95))
        p.addLine(to: CGPoint(x: w * 0.5, y: h * 0.95))
        p.closeSubpath()

        return p
    }
}

private struct BreastShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height

        p.move(to: CGPoint(x: w * 0.5, y: h * 0.05))
        p.addCurve(to: CGPoint(x: w * 0.9, y: h * 0.5),
                   control1: CGPoint(x: w * 0.85, y: h * 0.15),
                   control2: CGPoint(x: w * 0.95, y: h * 0.35))
        p.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.95),
                   control1: CGPoint(x: w * 0.85, y: h * 0.75),
                   control2: CGPoint(x: w * 0.5, y: h * 0.9))
        p.addCurve(to: CGPoint(x: w * 0.1, y: h * 0.5),
                   control1: CGPoint(x: w * 0.15, y: h * 0.9),
                   control2: CGPoint(x: w * 0.05, y: h * 0.75))
        p.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.05),
                   control1: CGPoint(x: w * 0.15, y: h * 0.35),
                   control2: CGPoint(x: w * 0.15, y: h * 0.15))
        p.closeSubpath()

        return p
    }
}

private struct ThighShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height

        // Thigh meat (rounded)
        p.addEllipse(in: CGRect(x: w * 0.1, y: h * 0.05, width: w * 0.8, height: h * 0.6))

        // Small bone at bottom
        p.move(to: CGPoint(x: w * 0.4, y: h * 0.55))
        p.addLine(to: CGPoint(x: w * 0.4, y: h * 0.95))
        p.addLine(to: CGPoint(x: w * 0.6, y: h * 0.95))
        p.addLine(to: CGPoint(x: w * 0.6, y: h * 0.55))
        p.closeSubpath()

        return p
    }
}

// MARK: - Rice baguette paddle

private struct BaguettePaddle: View {
    let x: CGFloat

    var body: some View {
        ZStack {
            // Glow
            RoundedRectangle(cornerRadius: 8)
                .fill(TastyTheme.gold.opacity(0.3))
                .frame(width: 120, height: 28)
                .blur(radius: 8)

            // Baguette body
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.98, green: 0.95, blue: 0.88),
                                Color(red: 0.92, green: 0.85, blue: 0.72)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 110, height: 22)

            // Rice texture dots
            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { _ in
                    Circle()
                        .fill(Color(red: 0.95, green: 0.92, blue: 0.85))
                        .frame(width: 4, height: 4)
                }
            }

            // Crust edge
            RoundedRectangle(cornerRadius: 8)
                .stroke(TastyTheme.gold.opacity(0.6), lineWidth: 2)
                .frame(width: 110, height: 22)
        }
        .position(x: x, y: 0)
    }
}

// MARK: - Vice palette

private enum Vice {
    static let pink = Color(red: 1.0, green: 0.27, blue: 0.67)
    static let sky = Color(red: 0.34, green: 0.20, blue: 0.55)
    static let sunTop = Color(red: 1.0, green: 0.84, blue: 0.38)
    static let sunBottom = Color(red: 1.0, green: 0.28, blue: 0.55)
    static let grid = Color(red: 0.95, green: 0.25, blue: 0.85)
}

// MARK: - Game view

struct ViceCatchGame: View {
    let onFinish: (ViceCatchPrize) -> Void
    var allowsReplay = false

    @Environment(\.dismiss) private var dismiss

    private enum Phase { case ready, playing, won, lost }
    @State private var phase: Phase = .ready
    @State private var items: [FallingItem] = []
    @State private var score: Int = 0
    @State private var lives: Int = 3
    @State private var targetPart: ChickenPart = .wing
    @State private var timeLeft: Double = 12.0
    @State private var result: ViceCatchPrize?
    @State private var caughtParts: [ChickenPart] = []
    @State private var paddleX: CGFloat = 150

    private let gameDuration: Double = 12.0
    private let spawnInterval: Double = 0.7
    private let fallSpeed: CGFloat = 160

    var body: some View {
        ZStack {
            ViceBackdrop()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 8)
                title
                Spacer(minLength: 12)
                gameArea
                Spacer(minLength: 12)
                actionArea
                Spacer(minLength: 12)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)

            if phase == .won || phase == .lost {
                ResultOverlay(
                    prize: result ?? .discount(10),
                    onDismiss: {
                        onFinish(result ?? .discount(10))
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
            livesAndScore
        }
        .padding(.top, 8)
    }

    private var livesAndScore: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < lives ? "heart.fill" : "heart")
                    .foregroundStyle(i < lives ? Vice.pink : .white.opacity(0.3))
                    .font(.system(size: 16, weight: .black))
            }
            Text("\(score)")
                .font(.system(.headline, design: .rounded, weight: .black))
                .foregroundStyle(.white)
                .frame(minWidth: 40)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.white.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(Vice.pink.opacity(0.5)))
    }

    private var title: some View {
        VStack(spacing: 6) {
            Text("CATCH LE POULET")
                .font(.system(size: 36, weight: .black, design: .rounded))
                .tracking(2)
                .foregroundStyle(
                    LinearGradient(colors: [Vice.sunTop, Vice.pink],
                                   startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: Vice.pink.opacity(0.6), radius: 14, y: 0)

            HStack(spacing: 12) {
                Text("Attrape les")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                targetPartBadge
                Text("et évite les autres !")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var targetPartBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(targetPart.neonColor.opacity(0.3))
                .frame(width: 44, height: 44)

            ChickenPartView(part: targetPart, isTarget: true, rotation: 0)
                .frame(width: 36, height: 36)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(targetPart.neonColor, lineWidth: 2))
        .shadow(color: targetPart.neonColor, radius: 8)
    }

    // MARK: game area

    private var gameArea: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            ZStack {
                timeBar(width: width)
                targetIndicator
                fallingItemsView
                caughtPartsView
                BaguettePaddle(x: paddleX)
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if phase == .playing {
                            paddleX = max(60, min(width - 60, value.location.x))
                        }
                    }
            )
            .contentShape(Rectangle())
            .onTapGesture { location in
                catchClosestItem(to: location)
            }
        }
        .aspectRatio(9/16, contentMode: .fit)
        .background(.ultraThinMaterial.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.2)))
    }

    private func timeBar(width: CGFloat) -> some View {
        VStack {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.2))
                    .frame(height: 8)
                let barColor: Color = timeLeft > 4 ? Vice.pink : Color.red
                let barWidth = width * CGFloat(timeLeft / gameDuration)
                RoundedRectangle(cornerRadius: 4)
                    .fill(barColor)
                    .frame(width: barWidth, height: 8)
                    .shadow(color: barColor, radius: 6)
            }
            Spacer()
        }
    }

    private var targetIndicator: some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                ChickenPartView(part: targetPart, isTarget: true, rotation: 0)
                    .frame(width: 56, height: 56)
                Text("CATCH")
                    .font(.system(.caption, design: .rounded, weight: .black))
                    .foregroundStyle(Vice.pink)
            }
            .padding(.bottom, 16)
            Spacer()
        }
    }

    private var fallingItemsView: some View {
        ForEach(items) { item in
            ChickenPartView(part: item.part, isTarget: item.isTarget, rotation: item.rotation)
                .frame(width: 50, height: 50)
                .position(x: item.x, y: item.y)
                .onTapGesture {
                    catchItem(item)
                }
        }
    }

    private var caughtPartsView: some View {
        HStack(spacing: 6) {
            ForEach(caughtParts, id: \.self) { part in
                ChickenPartView(part: part, isTarget: true, rotation: 0)
                    .frame(width: 28, height: 28)
            }
        }
        .padding(.top, 30)
    }

    private func catchClosestItem(to location: CGPoint) {
        let threshold: CGFloat = 50
        if let closest = items.min(by: { item1, item2 in
            let d1 = distance(item1.x, item1.y, location.x, location.y)
            let d2 = distance(item2.x, item2.y, location.x, location.y)
            return d1 < d2 && d1 < threshold
        }) {
            catchItem(closest)
        }
    }

    private func distance(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> CGFloat {
        sqrt(pow(x2 - x1, 2) + pow(y2 - y1, 2))
    }

    // MARK: action

    @ViewBuilder
    private var actionArea: some View {
        switch phase {
        case .ready:
            Button { startGame() } label: {
                gameButton("JOUER", icon: "play.fill")
            }
            .buttonStyle(.bouncy)
        case .playing:
            Text("Glisse pour bouger la baguette")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(height: 56)
        case .won, .lost:
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

    // MARK: game logic

    private func startGame() {
        HapticFeedback.select()
        phase = .playing
        score = 0
        lives = 3
        timeLeft = gameDuration
        items = []
        caughtParts = []
        targetPart = ChickenPart.allCases.randomElement() ?? .wing
        paddleX = 150
        gameLoop()
        spawnLoop()
    }

    private func restart() {
        withAnimation(.snappy(duration: 0.25)) {
            phase = .ready
            items = []
            result = nil
            caughtParts = []
        }
    }

    private func gameLoop() {
        Task { @MainActor in
            let startTime = Date()
            while phase == .playing && timeLeft > 0 {
                try? await Task.sleep(nanoseconds: 16_000_000)
                guard phase == .playing else { break }

                let elapsed = Date().timeIntervalSince(startTime)
                timeLeft = max(0, gameDuration - elapsed)

                let dt: CGFloat = 0.016
                for i in items.indices {
                    items[i].y += items[i].speed * dt
                    items[i].rotation += items[i].speed * 0.02
                }

                let screenHeight: CGFloat = 380
                let missed = items.filter { $0.y > screenHeight }
                for item in missed {
                    if item.isTarget {
                        lives -= 1
                        HapticFeedback.error()
                        if lives <= 0 {
                            endGame(won: false)
                            return
                        }
                    }
                }
                items.removeAll { $0.y > screenHeight }

                if score >= 6 {
                    endGame(won: true)
                    return
                }
            }

            if phase == .playing {
                endGame(won: false)
            }
        }
    }

    private func spawnLoop() {
        Task { @MainActor in
            while phase == .playing {
                try? await Task.sleep(nanoseconds: UInt64(spawnInterval * 1_000_000_000))
                guard phase == .playing else { break }
                spawnItem()
            }
        }
    }

    private func spawnItem() {
        let width: CGFloat = 300
        let isTarget = Bool.random()
        var part: ChickenPart
        if isTarget {
            part = targetPart
        } else {
            part = ChickenPart.allCases.filter { $0 != targetPart }.randomElement() ?? .wing
        }

        let item = FallingItem(
            part: part,
            x: CGFloat.random(in: 40...(width - 40)),
            y: -40,
            speed: fallSpeed + CGFloat.random(in: -20...20),
            isTarget: isTarget,
            rotation: Double.random(in: -30...30)
        )
        items.append(item)
    }

    private func catchItem(_ item: FallingItem) {
        guard phase == .playing else { return }

        if item.isTarget {
            score += 1
            caughtParts.append(item.part)
            HapticFeedback.select()
        } else {
            lives -= 1
            HapticFeedback.error()
            if lives <= 0 {
                endGame(won: false)
                return
            }
        }

        items.removeAll { $0.id == item.id }
    }

    private func endGame(won: Bool) {
        phase = won ? .won : .lost
        result = won ? .free : prizeForScore(score)
        if won {
            HapticFeedback.add()
        } else {
            HapticFeedback.error()
        }
    }

    private func prizeForScore(_ s: Int) -> ViceCatchPrize {
        switch s {
        case 6: return .free
        case 5: return .discount(20)
        case 4: return .discount(15)
        case 3: return .discount(10)
        default: return .discount(5)
        }
    }
}

// MARK: - Result overlay

private struct ResultOverlay: View {
    let prize: ViceCatchPrize
    let onDismiss: () -> Void
    var onReplay: (() -> Void)? = nil

    @State private var appear = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            if prize.isWin { Confetti() }
            resultContent
        }
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { appear = true } }
    }

    private var resultContent: some View {
        VStack(spacing: 20) {
            Image(systemName: prize.isWin ? "party.popper.fill" : "hand.raised.fill")
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
}

// MARK: - Backdrop

private struct ViceBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Vice.sky, Color(red: 0.12, green: 0.06, blue: 0.20), .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            Circle()
                .fill(LinearGradient(colors: [Vice.sunTop, Vice.sunBottom], startPoint: .top, endPoint: .bottom))
                .frame(width: 220, height: 220)
                .blur(radius: 2)
                .offset(y: -120)
                .opacity(0.9)

            BurgerNineGrid()
                .stroke(Vice.grid.opacity(0.55), lineWidth: 1.2)
                .shadow(color: Vice.grid.opacity(0.7), radius: 6)
                .ignoresSafeArea()
        }
    }
}

private struct BurgerNineGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let horizon = rect.midY + 30
        let bottom = rect.maxY
        let cx = rect.midX

        let rows = 9
        for i in 0...rows {
            let t = Double(i) / Double(rows)
            let y = horizon + (bottom - horizon) * (t * t)
            p.move(to: CGPoint(x: rect.minX, y: y))
            p.addLine(to: CGPoint(x: rect.maxX, y: y))
        }

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

// MARK: - Confetti

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
