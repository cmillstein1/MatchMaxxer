import SwiftUI
import StoreKit

struct MenuView: View {
    var onChoose: (GameCategory) -> Void
    @State private var soundShake: Bool = false
    @State private var showLeaderboard: Bool = false
    @State private var paywallCategory: GameCategory? = nil
    var leaderboard = LeaderboardManager.shared
    @Bindable var store = Store.shared

    var body: some View {
        GeometryReader { geo in
            let isWide = geo.size.width > geo.size.height
            VStack(spacing: 24) {
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("Match")
                        .font(.system(size: 26, weight: .black))
                        .foregroundStyle(.white)
                        .kerning(-0.6)
                    Text("Maxxer")
                        .font(.system(size: 26, weight: .black))
                        .foregroundStyle(.white)
                        .kerning(-0.6)
                        .italic()
                    Text(".")
                        .font(.system(size: 26, weight: .black))
                        .foregroundStyle(LinearGradient(
                            colors: [
                                Color(red: 0.18, green: 0.95, blue: 0.92),
                                Color(red: 0.62, green: 0.32, blue: 0.95)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                    Spacer()
                }
                Spacer(minLength: 0)

                if isWide {
                    HStack(spacing: 16) {
                        choiceCard(.color)
                        choiceCard(.hex)
                        choiceCard(.sound)
                    }
                } else {
                    VStack(spacing: 14) {
                        choiceCard(.color)
                        choiceCard(.hex)
                        choiceCard(.sound)
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    Button(action: { showLeaderboard = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "globe")
                                .font(.system(size: 13, weight: .bold))
                            Text("Leaderboard")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(Capsule().fill(.white.opacity(0.10)))
                    }
                    .buttonStyle(PressableButtonStyle())
                    Button(action: { Task { await store.restore() } }) {
                        Text("Restore")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                            .underline()
                            .padding(.horizontal, 6).padding(.vertical, 8)
                    }
                }
                .padding(.bottom, 8)
            }
            .padding(28)
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showLeaderboard) {
            LocalLeaderboardView(manager: leaderboard) {
                showLeaderboard = false
            }
        }
        .sheet(item: $paywallCategory) { cat in
            PaywallView(
                category: cat,
                onClose: { paywallCategory = nil },
                onUnlocked: {
                    paywallCategory = nil
                    onChoose(cat)
                }
            )
        }
    }

    @ViewBuilder
    private func choiceCard(_ cat: GameCategory) -> some View {
        let isLocked = !store.isUnlocked(cat)
        Button {
            SoundPlayer.haptic(.medium)
            if isLocked {
                paywallCategory = cat
            } else {
                onChoose(cat)
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    )
                cardBackdrop(for: cat)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: cardIcon(for: cat))
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                        Spacer()
                        if isLocked {
                            HStack(spacing: 6) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 11, weight: .black))
                                Text(store.product(for: cat)?.displayPrice ?? "$1.99")
                                    .font(.system(size: 12, weight: .black))
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(.white))
                        }
                    }
                    Spacer(minLength: 0)
                    Text(cardTitle(for: cat))
                        .font(.system(size: 52, weight: .black))
                        .foregroundStyle(.white)
                        .kerning(-1.4)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(cardSubtitle(for: cat))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, minHeight: 170)
        }
        .buttonStyle(PressableButtonStyle())
    }

    @ViewBuilder
    private func cardBackdrop(for cat: GameCategory) -> some View {
        switch cat {
        case .color:
            LinearGradient(
                gradient: HueGradient.stops,
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .opacity(0.18)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        case .hex:
            // Column of sample hex codes, each rendered in its own rainbow
            // hue. Lives on the right so it doesn't compete with the title /
            // subtitle on the left.
            ZStack {
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        hexSample("#FF3B30", hue: 0)
                        hexSample("#FF9500", hue: 30)
                        hexSample("#FFCC00", hue: 52)
                        hexSample("#34C759", hue: 135)
                        hexSample("#5AC8FA", hue: 200)
                        hexSample("#AF52DE", hue: 280)
                    }
                    .padding(.trailing, 18)
                    .padding(.vertical, 14)
                }

                // Soft fade from top so the icon stays clean, plus a left-edge
                // wash so the title text doesn't fight the colored codes.
                LinearGradient(
                    colors: [.black.opacity(0.65), .black.opacity(0.0)],
                    startPoint: .leading, endPoint: .trailing
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        case .sound:
            WavelengthView(frequency: 320, energy: 0.6)
                .opacity(0.85)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .allowsHitTesting(false)
        }
    }

    private func cardIcon(for cat: GameCategory) -> String {
        switch cat {
        case .color: return "paintpalette.fill"
        case .hex:   return "eyedropper"
        case .sound: return "waveform"
        }
    }

    private func cardTitle(for cat: GameCategory) -> String {
        switch cat {
        case .color: return "color"
        case .hex:   return "hex"
        case .sound: return "sound"
        }
    }

    private func cardSubtitle(for cat: GameCategory) -> String {
        switch cat {
        case .color: return "Recreate colors from memory."
        case .hex:   return "Find the hex code on the palette."
        case .sound: return "Recreate tones from memory."
        }
    }

    private func hexSample(_ hex: String, hue: Double) -> some View {
        Text(hex)
            .font(.system(size: 14, weight: .heavy, design: .monospaced))
            .foregroundStyle(Color(hue: hue / 360, saturation: 0.95, brightness: 1))
            .kerning(0.3)
    }

}

struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = sin(animatableData * .pi * 6) * 6
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}
