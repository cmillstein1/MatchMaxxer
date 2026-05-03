import SwiftUI
import StoreKit

struct MenuView: View {
    var onChoose: (GameCategory) -> Void
    @State private var soundShake: Bool = false
    @State private var showLeaderboard: Bool = false
    @State private var showPaywall: Bool = false
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
                    HStack(spacing: 20) {
                        choiceCard(.color)
                        choiceCard(.sound)
                    }
                } else {
                    VStack(spacing: 20) {
                        choiceCard(.color)
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
        .sheet(isPresented: $showPaywall) {
            PaywallView(
                onClose: { showPaywall = false },
                onUnlocked: {
                    showPaywall = false
                    onChoose(.sound)
                }
            )
        }
    }

    @ViewBuilder
    private func choiceCard(_ cat: GameCategory) -> some View {
        let isColor = cat == .color
        let isLocked = cat == .sound && !store.isSoundUnlocked
        Button {
            SoundPlayer.haptic(.medium)
            if isLocked {
                showPaywall = true
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
                if isColor {
                    LinearGradient(
                        gradient: HueGradient.stops,
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .opacity(0.18)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                } else {
                    // Live wavelength behind the sound card so it teases the
                    // actual game aesthetic, the same way the hue gradient
                    // does for the color card.
                    WavelengthView(frequency: 320, energy: 0.6)
                        .opacity(0.85)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .allowsHitTesting(false)
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: isColor ? "paintpalette.fill" : "waveform")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                        Spacer()
                        if isLocked {
                            HStack(spacing: 6) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 11, weight: .black))
                                Text(store.soundProduct?.displayPrice ?? "$1.99")
                                    .font(.system(size: 12, weight: .black))
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(.white))
                        }
                    }
                    Spacer(minLength: 0)
                    Text(isColor ? "color" : "sound")
                        .font(.system(size: 64, weight: .black))
                        .foregroundStyle(.white)
                        .kerning(-1.5)
                    Text(isColor
                         ? "Recreate colors from memory."
                         : "Recreate tones from memory.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, minHeight: 230)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = sin(animatableData * .pi * 6) * 6
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}
