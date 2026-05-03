import SwiftUI

struct HandoffView: View {
    var playerName: String
    var playerNumber: Int
    var totalPlayers: Int
    var isFirst: Bool
    var previousScores: [(name: String, total: Double)]
    var onContinue: () -> Void

    @State private var pulse: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LinearGradient(gradient: HueGradient.stops,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(0.10).ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                Text(isFirst ? "Pass-and-play" : "Pass the device")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .kerning(2)
                    .textCase(.uppercase)
                Text(playerName)
                    .font(.system(size: 84, weight: .black))
                    .foregroundStyle(.white)
                    .kerning(-2)
                Text("Player \(playerNumber) of \(totalPlayers) — when you're ready, tap to begin your 5 colors.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)

                if !previousScores.isEmpty {
                    VStack(spacing: 8) {
                        Text("Score to beat")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.45))
                            .kerning(1.5)
                            .textCase(.uppercase)
                        ForEach(Array(previousScores.enumerated()), id: \.offset) { _, p in
                            HStack {
                                Text(p.name)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.85))
                                Spacer()
                                Text(String(format: "%.2f / 50", p.total))
                                    .font(.system(size: 18, weight: .black))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.white.opacity(0.06))
                            )
                        }
                    }
                    .frame(maxWidth: 360)
                    .padding(.top, 8)
                }

                Spacer()
                Button(action: {
                    SoundPlayer.haptic(.medium)
                    onContinue()
                }) {
                    HStack(spacing: 12) {
                        Text("I'm ready")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.black)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.black)
                    }
                    .padding(.horizontal, 28).padding(.vertical, 18)
                    .background(Capsule().fill(.white))
                    .scaleEffect(pulse)
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.bottom, 36)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                        pulse = 1.04
                    }
                }
            }
        }
    }
}
