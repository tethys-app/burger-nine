import SwiftUI

/// Copy this file to start a new mini-game.
/// Replace the placeholder logic in `makeOutcome()` and `playfield`.
struct GameTemplate: View {
    let onComplete: (GameTemplateOutcome) -> Void
    var allowsReplay = false

    @Environment(\.dismiss) private var dismiss
    @State private var phase = Phase.ready
    @State private var outcome: GameTemplateOutcome?

    var body: some View {
        ZStack {
            background
            VStack(spacing: 16) {
                header
                playfield
                controls
            }
            .padding(18)

            if let outcome, phase == .finished {
                resultOverlay(outcome)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.bouncy)

            VStack(alignment: .leading, spacing: 2) {
                Text("Game Template")
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .foregroundStyle(.white)
                Text("Replace this scaffold with your game rules.")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.72))
            }

            Spacer()
        }
    }

    private var playfield: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(.white.opacity(0.08))
            .overlay {
                VStack(spacing: 8) {
                    Text("Game area")
                        .font(.headline.weight(.black))
                        .foregroundStyle(.white)
                    Text("Put the core interaction here.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 420)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                start()
            } label: {
                Text(phase == .playing ? "Finish" : "Start")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(TastyTheme.violet, in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.bouncy)

            if allowsReplay {
                Button {
                    restart()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.headline.weight(.black))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.bouncy)
            }
        }
    }

    private func resultOverlay(_ outcome: GameTemplateOutcome) -> some View {
        Color.black.opacity(0.55)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 14) {
                    Text(outcome.title)
                        .font(.system(.title2, design: .rounded, weight: .black))
                        .foregroundStyle(.white)
                    Text(outcome.subtitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.76))
                        .multilineTextAlignment(.center)

                    Button {
                        onComplete(outcome)
                        dismiss()
                    } label: {
                        Text("Apply")
                            .font(.headline.weight(.black))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(TastyTheme.coral, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.bouncy)

                    if allowsReplay {
                        Button("Replay") {
                            restart()
                        }
                        .font(.headline.weight(.black))
                        .foregroundStyle(.white)
                    }
                }
                .padding(20)
                .frame(maxWidth: 360)
                .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 26))
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.16)))
                .padding(24)
            }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.06, green: 0.03, blue: 0.11),
                Color(red: 0.18, green: 0.07, blue: 0.25),
                Color(red: 0.03, green: 0.16, blue: 0.18)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private func start() {
        phase = .playing
        // Hook your game loop or interaction state here.
        finish(with: makeOutcome())
    }

    private func restart() {
        phase = .ready
        outcome = nil
    }

    private func finish(with value: GameTemplateOutcome) {
        outcome = value
        phase = .finished
    }

    private func makeOutcome() -> GameTemplateOutcome {
        // Replace with your own scoring or reduction logic.
        .discount(10)
    }
}

enum GameTemplateOutcome: Equatable {
    case free
    case discount(Int)

    var title: String {
        switch self {
        case .free: return "Repas offert"
        case .discount(let percent): return "-\(percent)%"
        }
    }

    var subtitle: String {
        switch self {
        case .free: return "Template win state."
        case .discount(let percent): return "Template reduction: \(percent)%"
        }
    }
}

private enum Phase {
    case ready
    case playing
    case finished
}

