import SwiftUI

// Shown right before sound mode starts so the user can put on headphones /
// unmute the device. Tap anywhere to proceed. Doubles as the user-gesture
// that primes the audio session — iOS won't always start tones cleanly
// without one.
struct AudioGateView: View {
    var onProceed: () -> Void

    @State private var pulse: CGFloat = 1.0
    @State private var hint: Double = 0

    var body: some View {
        ZStack {
            sweptGradient
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                    .scaleEffect(pulse)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                            pulse = 1.06
                        }
                    }

                VStack(spacing: 6) {
                    Text("Turn on your sound.")
                    Text("Put on your headphones.")
                }
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 2)

                Text("Tap anywhere to start")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .opacity(0.5 + 0.5 * hint)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                            hint = 1
                        }
                    }
                    .padding(.top, 6)
                Spacer()
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            SoundPlayer.haptic(.medium)
            onProceed()
        }
    }

    // Diagonal "swept" gradient: bright violet top-left, deep crimson
    // bottom-right, with a darker shadow band running through the middle to
    // give it the cinematic falloff from the reference design.
    private var sweptGradient: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
            ],
            colors: [
                Color(red: 0.42, green: 0.30, blue: 0.92), // top-left bright violet
                Color(red: 0.20, green: 0.15, blue: 0.45),
                Color(red: 0.05, green: 0.05, blue: 0.10), // top-right dark
                Color(red: 0.18, green: 0.13, blue: 0.30),
                Color(red: 0.10, green: 0.08, blue: 0.14), // center dark band
                Color(red: 0.32, green: 0.10, blue: 0.20),
                Color(red: 0.05, green: 0.04, blue: 0.08), // bottom-left dark
                Color(red: 0.55, green: 0.20, blue: 0.40),
                Color(red: 0.85, green: 0.35, blue: 0.55)  // bottom-right pink
            ]
        )
    }
}
