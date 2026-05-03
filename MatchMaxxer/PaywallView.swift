import SwiftUI
import StoreKit

struct PaywallView: View {
    var onClose: () -> Void
    var onUnlocked: () -> Void
    @Bindable var store = Store.shared
    @State private var purchaseMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // Wavelength behind the content — same vibe as the actual game
            WavelengthView(frequency: 320, energy: 0.7)
                .opacity(0.85)
                .ignoresSafeArea()
            LinearGradient(
                colors: [.black.opacity(0.0), .black.opacity(0.55), .black],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Circle().fill(.white.opacity(0.10)))
                    }
                }
                Spacer(minLength: 0)
                title
                bullets
                priceCTA
                Button(action: { Task { await store.restore() } }) {
                    Text("Restore Purchases")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .underline()
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                if let msg = purchaseMessage {
                    Text(msg)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                }
                Text("One-time purchase. Family sharing supported.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                    .padding(.bottom, 4)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .onChange(of: store.isSoundUnlocked) { _, unlocked in
            if unlocked {
                purchaseMessage = nil
                onUnlocked()
            }
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("UNLOCK")
                .font(.system(size: 12, weight: .black))
                .kerning(2)
                .foregroundStyle(.white.opacity(0.65))
            Text("sound")
                .font(.system(size: 84, weight: .black))
                .foregroundStyle(.white)
                .kerning(-2)
            Text("Recreate tones from memory.")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private var bullets: some View {
        VStack(alignment: .leading, spacing: 10) {
            bullet("waveform", "Five tones per round, dial each from memory")
            bullet("dial.high", "Easy and Hard modes")
            bullet("person.2.fill", "Pass-and-play multiplayer")
            bullet("globe", "Same global leaderboard as Color")
        }
        .padding(.top, 8)
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    @ViewBuilder
    private var priceCTA: some View {
        let product = store.soundProduct
        let isLoading = product == nil && store.lastError == nil
        Button(action: { Task { await purchase() } }) {
            HStack {
                Group {
                    if let product {
                        Text("Unlock for \(product.displayPrice)")
                    } else if isLoading {
                        Text("Loading…")
                    } else {
                        Text("Unavailable")
                    }
                }
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(.black)
                Spacer()
                if store.purchaseInProgress || isLoading {
                    ProgressView().progressViewStyle(.circular).tint(.black)
                } else {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(.white))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(store.purchaseInProgress || product == nil)
        .opacity(product == nil ? 0.55 : 1)
        .padding(.top, 18)

        if product == nil && !isLoading {
            Text("Sign into the App Store and try again, or run from Xcode with the StoreKit configuration file to test locally.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.top, 4)
        }
    }

    private func purchase() async {
        guard let p = store.soundProduct else { return }
        let outcome = await store.purchase(p)
        switch outcome {
        case .success:
            purchaseMessage = nil
        case .pending:
            purchaseMessage = "Purchase is awaiting approval."
        case .cancelled:
            purchaseMessage = nil
        case .unverified:
            purchaseMessage = "Could not verify the purchase."
        case .failed:
            purchaseMessage = store.lastError ?? "Purchase failed."
        case .alreadyInProgress, .unknown:
            break
        }
    }
}
