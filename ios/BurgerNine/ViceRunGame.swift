import SwiftUI
import Combine

struct ViceRunGame: View {
    let onComplete: (GamePrize) -> Void
    var allowsReplay = false

    @Environment(\.dismiss) private var dismiss
    @State private var phase = GamePhase.ready
    @State private var playerX: CGFloat = 0.5
    @State private var chickenCount = 0
    @State private var hits = 0
    @State private var timeLeft = Self.duration
    @State private var objects: [FallingObject] = []
    @State private var nextSpawn = 0.0
    @State private var lastTick = Date()
    @State private var result: GamePrize?
    @State private var roadPulse = false

    private static let duration = 15.0
    private let tick = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()
    private let lanes: [CGFloat] = [0.18, 0.38, 0.62, 0.82]

    var body: some View {
        ZStack {
            viceBackdrop
            gameContent
        }
        .preferredColorScheme(.dark)
        .onAppear {
            lastTick = Date()
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: true)) {
                roadPulse = true
            }
        }
        .onReceive(tick) { now in
            guard phase == .playing else {
                lastTick = now
                return
            }
            let delta = min(0.08, now.timeIntervalSince(lastTick))
            lastTick = now
            advance(by: delta)
        }
    }

    private var gameContent: some View {
        VStack(spacing: 14) {
            topBar

            GeometryReader { geometry in
                playfield(size: geometry.size)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 470)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.14), lineWidth: 1))
            .shadow(color: TastyTheme.coral.opacity(0.22), radius: 28, y: 16)

            bottomControls
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .safeAreaPadding(.top, 8)
        .safeAreaPadding(.bottom, 8)
        .overlay {
            if phase == .ready {
                startOverlay.transition(.scale(scale: 0.94).combined(with: .opacity))
            } else if phase == .finished, let result {
                resultOverlay(result).transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.24), value: phase)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.25), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 2))
                    .shadow(color: .black.opacity(0.45), radius: 0, x: 3, y: 3)
            }
            .buttonStyle(.bouncy)

            VStack(alignment: .leading, spacing: 2) {
                Text("Vice Run")
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .italic()
                    .foregroundStyle(.white)
                Text("Fried chicken & rice: attrape 8 pieces, evite 3 barrages")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.72))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(max(0, Int(ceil(timeLeft))))s")
                    .font(.system(.title3, design: .rounded, weight: .black))
                    .foregroundStyle(TastyTheme.gold)
                Text("\(chickenCount)/8")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Jeu Vice Run. \(Int(ceil(timeLeft))) secondes restantes. \(chickenCount) pieces de poulet attrapees.")
    }

    private func playfield(size: CGSize) -> some View {
        let playerSize = min(size.width * 0.18, 70)
        let playerPoint = CGPoint(x: playerX * size.width, y: size.height - playerSize * 0.86)

        return ZStack {
            road

            ForEach(objects) { object in
                fallingObject(object)
                    .position(x: object.x * size.width, y: object.y * size.height)
                    .transition(.scale.combined(with: .opacity))
            }

            scooter(size: playerSize)
                .position(playerPoint)
                .shadow(color: TastyTheme.gold.opacity(0.45), radius: 18, y: 8)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard phase == .playing else { return }
                    playerX = clamp(value.location.x / max(1, size.width), min: 0.12, max: 0.88)
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zone de jeu")
        .accessibilityHint("Glissez horizontalement pour deplacer le scooter.")
    }

    private var road: some View {
        ZStack {
            Color(red: 0.05, green: 0.03, blue: 0.08)

            Circle()
                .fill(LinearGradient(colors: [TastyTheme.gold.opacity(0.98), TastyTheme.coral.opacity(0.92)], startPoint: .top, endPoint: .bottom))
                .frame(width: 220, height: 220)
                .blur(radius: 1.5)
                .offset(y: -124)
                .opacity(0.95)
                .overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 3))
                .shadow(color: .black.opacity(0.35), radius: 0, x: 5, y: 5)

            BurgerNineGrid()
                .stroke(TastyTheme.coral.opacity(0.72), lineWidth: 1.2)
                .shadow(color: .black.opacity(0.5), radius: 0, x: 2, y: 2)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ForEach(0..<9, id: \.self) { index in
                    Rectangle()
                        .fill(index.isMultiple(of: 2) ? TastyTheme.gold.opacity(0.18) : TastyTheme.coral.opacity(0.10))
                        .frame(height: 42)
                        .overlay(Rectangle().stroke(.white.opacity(0.08), lineWidth: 1))
                }
            }
            .opacity(roadPulse ? 0.42 : 0.22)

            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { index in
                    Rectangle()
                        .fill(index == 0 || index == 4 ? .white.opacity(0.32) : .white.opacity(0.08))
                        .frame(width: index == 0 || index == 4 ? 2 : 1)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 28)

            riceFloor

            VStack {
                Text("RIZ CROUSTY")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .italic()
                    .foregroundStyle(TastyTheme.gold.opacity(0.95))
                    .padding(.top, 18)
                Spacer()
            }

            sticker(label: "fried", system: "flame.fill", rotation: -8, x: 54, y: 92, color: TastyTheme.coral)
            sticker(label: "rice", system: "circle.grid.2x2.fill", rotation: 10, x: 286, y: 78, color: TastyTheme.violet)
            sticker(label: "combo", system: "takeoutbag.and.cup.and.straw.fill", rotation: -4, x: 54, y: 334, color: TastyTheme.gold)
        }
    }

    private func scooter(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(LinearGradient(colors: [TastyTheme.coral, TastyTheme.violet], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size * 1.02, height: size * 0.7)
            Image(systemName: "scooter")
                .font(.system(size: size * 0.48, weight: .black))
                .foregroundStyle(.white)
            Circle()
                .fill(TastyTheme.gold)
                .frame(width: size * 0.22)
                .offset(x: size * 0.33, y: size * 0.26)
        }
        .frame(width: size * 1.15, height: size)
    }

    private func fallingObject(_ object: FallingObject) -> some View {
        ZStack {
            if object.kind == .chicken {
                friedChickenPiece(size: object.kind.size)
            } else {
                RoundedRectangle(cornerRadius: 15)
                    .fill(object.kind.fill)
                    .frame(width: object.kind.size, height: object.kind.size)
                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.18)))
                Image(systemName: object.kind.icon)
                    .font(.system(size: object.kind.size * 0.43, weight: .black))
                    .foregroundStyle(.white)
            }
        }
        .shadow(color: object.kind.glow, radius: 12, y: 6)
        .accessibilityHidden(true)
    }

    private var bottomControls: some View {
        HStack(spacing: 10) {
            statusPill(icon: "takeoutbag.and.cup.and.straw.fill", text: "\(chickenCount) pieces", color: TastyTheme.gold)
            statusPill(icon: "exclamationmark.triangle.fill", text: "\(hits)/3 barrages", color: TastyTheme.coral)
            Spacer(minLength: 0)
            Button {
                if phase == .playing {
                    finish(with: finalPrize())
                } else {
                    start()
                }
            } label: {
                Image(systemName: phase == .playing ? "flag.checkered" : "play.fill")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 42)
                    .background(TastyTheme.coral, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.bouncy)
            .accessibilityLabel(phase == .playing ? "Terminer maintenant" : "Commencer")
        }
    }

    private func statusPill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
            Text(text).lineLimit(1).minimumScaleFactor(0.76)
        }
        .font(.caption.weight(.black))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(color.opacity(0.22), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.35)))
    }

    private var startOverlay: some View {
        overlayPanel {
            VStack(spacing: 16) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 78, height: 78)
                    .background(LinearGradient(colors: [TastyTheme.coral, TastyTheme.gold], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 3))
                    .shadow(color: .black.opacity(0.4), radius: 0, x: 4, y: 4)
                VStack(spacing: 6) {
                    Text("Fried chicken & rice")
                        .font(.system(.title2, design: .rounded, weight: .black))
                        .italic()
                        .foregroundStyle(.white)
                    Text("15 secondes. Glisse le scooter, attrape les pieces de poulet, evite les barrages.")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                }
                Button {
                    start()
                } label: {
                    Text("Lancer Vice Run")
                        .font(.headline.weight(.black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(TastyTheme.coral, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.bouncy)
            }
        }
    }

    private func resultOverlay(_ prize: GamePrize) -> some View {
        overlayPanel {
            VStack(spacing: 16) {
                Image(systemName: prize.isWin ? "crown.fill" : "sparkles")
                    .font(.system(size: 36, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 82, height: 82)
                    .background(prize.isWin ? TastyTheme.gold : TastyTheme.violet, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.65), lineWidth: 3))
                    .shadow(color: .black.opacity(0.42), radius: 0, x: 4, y: 4)
                VStack(spacing: 6) {
                    Text(prize.title)
                        .font(.system(.title2, design: .rounded, weight: .black))
                        .italic()
                        .foregroundStyle(.white)
                    Text(prize.subtitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 10) {
                    scoreTile(title: "Pieces", value: "\(chickenCount)")
                    scoreTile(title: "Barrages", value: "\(hits)")
                }
                if allowsReplay {
                    Button {
                        restart()
                    } label: {
                        Text("Rejouer")
                            .font(.headline.weight(.black))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(prize.isWin ? TastyTheme.gold : TastyTheme.coral, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.bouncy)
                } else {
                    Button {
                        onComplete(prize)
                        dismiss()
                    } label: {
                        Text("Appliquer au panier")
                            .font(.headline.weight(.black))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(prize.isWin ? TastyTheme.gold : TastyTheme.coral, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.bouncy)
                }
            }
        }
    }

    private func overlayPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Color.black.opacity(0.54)
            .ignoresSafeArea()
            .overlay {
                content()
                    .padding(20)
                    .frame(maxWidth: 360)
                    .background(Color(red: 0.12, green: 0.08, blue: 0.16), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.55), lineWidth: 2))
                    .shadow(color: .black.opacity(0.45), radius: 0, x: 10, y: 10)
                    .padding(24)
            }
    }

    private func scoreTile(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .black))
                .foregroundStyle(.white)
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.16)))
    }

    private var viceBackdrop: some View {
        Color(red: 0.05, green: 0.03, blue: 0.08)
            .ignoresSafeArea()
            .overlay {
                LinearGradient(
                    colors: [
                        TastyTheme.coral.opacity(0.16),
                        TastyTheme.gold.opacity(0.10),
                        TastyTheme.violet.opacity(0.14)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blur(radius: 24)
                .offset(x: 10, y: -20)
            }
    }

    private func start() {
        HapticFeedback.select()
        withAnimation(.snappy(duration: 0.24)) {
            phase = .playing
            playerX = 0.5
            chickenCount = 0
            hits = 0
            timeLeft = Self.duration
            objects = []
            nextSpawn = 0.05
            result = nil
            lastTick = Date()
        }
    }

    private func restart() {
        withAnimation(.snappy(duration: 0.24)) {
            phase = .ready
            playerX = 0.5
            chickenCount = 0
            hits = 0
            timeLeft = Self.duration
            objects = []
            nextSpawn = 0
            result = nil
            roadPulse = false
        }
        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: true)) {
            roadPulse = true
        }
    }

    private func advance(by delta: TimeInterval) {
        timeLeft -= delta
        nextSpawn -= delta

        if nextSpawn <= 0 {
            spawnObject()
            nextSpawn = max(0.34, 0.72 - (Self.duration - timeLeft) * 0.018)
        }

        for index in objects.indices {
            objects[index].y += objects[index].speed * delta
        }

        resolveCollisions()
        objects.removeAll { $0.y > 1.12 || $0.collected }

        if timeLeft <= 0 || hits >= 3 || chickenCount >= 8 {
            finish(with: finalPrize())
        }
    }

    private func spawnObject() {
        let elapsed = Self.duration - timeLeft
        let shouldThreat = Int(elapsed * 10).isMultiple(of: 4) || Double.random(in: 0...1) < 0.34
        let kind: FallingObject.Kind = shouldThreat ? .barrier : .chicken
        let object = FallingObject(
            x: lanes.randomElement() ?? 0.5,
            y: -0.08,
            speed: Double.random(in: 0.50...0.72),
            kind: kind
        )
        objects.append(object)
    }

    private func resolveCollisions() {
        for index in objects.indices where !objects[index].collected {
            let dx = abs(objects[index].x - playerX)
            let dy = abs(objects[index].y - 0.86)
            guard dx < 0.12, dy < 0.08 else { continue }

            objects[index].collected = true
            switch objects[index].kind {
            case .chicken:
                chickenCount += 1
                HapticFeedback.select()
            case .barrier:
                hits += 1
                HapticFeedback.error()
            }
        }
    }

    private func finalPrize() -> GamePrize {
        if chickenCount >= 8 && hits < 3 { return .free }
        if chickenCount >= 5 && hits < 3 { return .discount(20) }
        if chickenCount >= 3 { return .discount(10) }
        return .discount(5)
    }

    private func finish(with prize: GamePrize) {
        guard phase == .playing else { return }
        result = prize
        withAnimation(.snappy(duration: 0.3)) {
            phase = .finished
        }
        prize.isWin ? HapticFeedback.add() : HapticFeedback.select()
    }

    private func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minimum), maximum)
    }

    private var riceFloor: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.90, blue: 0.80).opacity(0.85),
                        Color(red: 0.97, green: 0.94, blue: 0.88).opacity(0.95),
                        Color(red: 0.92, green: 0.85, blue: 0.72).opacity(0.92)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                ForEach(0..<46, id: \.self) { index in
                    let x = CGFloat((index * 41) % 100) / 100
                    let y = CGFloat((index * 19) % 100) / 100
                    Capsule()
                        .fill(Color.white.opacity(index.isMultiple(of: 4) ? 0.72 : 0.44))
                        .frame(width: index.isMultiple(of: 2) ? 16 : 11, height: index.isMultiple(of: 2) ? 4 : 3)
                        .rotationEffect(.degrees(Double((index * 23) % 20) - 10))
                        .position(
                            x: 18 + x * max(1, geo.size.width - 36),
                            y: 16 + y * 96
                        )
                }
            }
            .clipShape(Rectangle())
        }
        .ignoresSafeArea()
    }

    private func friedChickenPiece(size: CGFloat) -> some View {
        ZStack {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.62, green: 0.35, blue: 0.10), Color(red: 0.91, green: 0.62, blue: 0.20)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.82, height: size * 0.58)
                .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 2))
                .shadow(color: .black.opacity(0.45), radius: 0, x: 4, y: 4)

            Circle()
                .fill(Color(red: 0.94, green: 0.80, blue: 0.64))
                .frame(width: size * 0.34, height: size * 0.34)
                .offset(x: size * 0.34, y: size * 0.02)
                .overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 1.5))

            Capsule()
                .fill(Color.white.opacity(0.40))
                .frame(width: size * 0.12, height: size * 0.18)
                .offset(x: size * 0.37, y: -size * 0.12)
            Capsule()
                .fill(Color.white.opacity(0.40))
                .frame(width: size * 0.12, height: size * 0.18)
                .offset(x: size * 0.40, y: size * 0.18)
        }
    }

    private func sticker(label: String, system: String, rotation: Double, x: CGFloat, y: CGFloat, color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .black))
            Text(label.uppercased())
                .font(.system(size: 10, weight: .black, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.5), lineWidth: 2))
        .shadow(color: .black.opacity(0.45), radius: 0, x: 3, y: 3)
        .rotationEffect(.degrees(rotation))
        .position(x: x, y: y)
    }
}

private enum GamePhase {
    case ready
    case playing
    case finished
}

private struct FallingObject: Identifiable, Equatable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var speed: Double
    var kind: Kind
    var collected = false

    enum Kind: Equatable {
        case chicken
        case barrier

        var icon: String {
            switch self {
            case .chicken: return "bird.fill"
            case .barrier: return "exclamationmark.triangle.fill"
            }
        }

        var size: CGFloat {
            switch self {
            case .chicken: return 54
            case .barrier: return 48
            }
        }

        var fill: LinearGradient {
            switch self {
            case .chicken:
                return LinearGradient(colors: [TastyTheme.gold, TastyTheme.orange], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .barrier:
                return LinearGradient(colors: [TastyTheme.coral, Color(red: 0.55, green: 0.05, blue: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }

        var glow: Color {
            switch self {
            case .chicken: return TastyTheme.gold.opacity(0.38)
            case .barrier: return TastyTheme.coral.opacity(0.40)
            }
        }
    }
}

private struct BurgerNineGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let horizon = rect.midY + 24
        let bottom = rect.maxY
        let centerX = rect.midX

        for row in 0...9 {
            let t = Double(row) / 9.0
            let y = horizon + (bottom - horizon) * (t * t)
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }

        for col in -10...10 {
            let spread = Double(col) / 10.0
            let topX = centerX + spread * 26
            let botX = centerX + spread * rect.width
            path.move(to: CGPoint(x: topX, y: horizon))
            path.addLine(to: CGPoint(x: botX, y: bottom))
        }

        return path
    }
}

#Preview {
    ViceRunGame { _ in }
}
