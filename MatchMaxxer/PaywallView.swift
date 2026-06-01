import SwiftUI
import StoreKit

struct PaywallView: View {
    var category: GameCategory
    var onClose: () -> Void
    var onUnlocked: () -> Void
    @Bindable var store = Store.shared
    @State private var purchaseMessage: String?

    private var product: Product? { store.product(for: category) }
    private var isUnlocked: Bool { store.isUnlocked(category) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            backdrop
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
        .onChange(of: isUnlocked) { _, unlocked in
            if unlocked {
                purchaseMessage = nil
                onUnlocked()
            }
        }
    }

    @ViewBuilder
    private var backdrop: some View {
        switch category {
        case .sound:
            WavelengthView(frequency: 320, energy: 0.95)
                .opacity(0.95)
                .ignoresSafeArea()
        case .hex:
            // Same column-of-rainbow-codes vibe as the menu card, scaled up.
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    paywallHexSample("#FF3B30", hue: 0)
                    paywallHexSample("#FF9500", hue: 30)
                    paywallHexSample("#FFCC00", hue: 52)
                    paywallHexSample("#34C759", hue: 135)
                    paywallHexSample("#5AC8FA", hue: 200)
                    paywallHexSample("#007AFF", hue: 220)
                    paywallHexSample("#AF52DE", hue: 280)
                    paywallHexSample("#FF2D55", hue: 340)
                }
                .padding(.trailing, 24)
            }
            .ignoresSafeArea()
        case .time:
            VortexView(energy: 0.7)
                .opacity(0.9)
                .ignoresSafeArea()
        case .shape:
            ShapeShowcaseView()
                .opacity(0.55)
                .ignoresSafeArea()
        case .color:
            EmptyView()
        }
    }

    private func paywallHexSample(_ hex: String, hue: Double) -> some View {
        Text(hex)
            .font(.system(size: 22, weight: .heavy, design: .monospaced))
            .foregroundStyle(Color(hue: hue / 360, saturation: 0.95, brightness: 1))
            .opacity(0.55)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("UNLOCK")
                .font(.system(size: 12, weight: .black))
                .kerning(2)
                .foregroundStyle(.white.opacity(0.65))
            Text(category.displayName.lowercased())
                .font(.system(size: 84, weight: .black))
                .foregroundStyle(.white)
                .kerning(-2)
            Text(tagline)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private var tagline: String {
        switch category {
        case .sound: return "Recreate tones from memory."
        case .hex:   return "Find hex codes on the palette."
        case .time:  return "Recreate durations from memory."
        case .shape: return "Recreate shapes from memory."
        case .color: return ""
        }
    }

    private var bullets: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch category {
            case .sound:
                bullet("waveform", "Five tones per round, dial each from memory")
                bullet("dial.high", "Easy and Hard modes")
                bullet("person.2.fill", "Pass-and-play multiplayer")
                bullet("globe", "Same global leaderboard as Color")
            case .hex:
                bullet("eyedropper", "Five hex codes per round, eyedropper to match")
                bullet("dial.high", "Easy and Hard reveal timings")
                bullet("person.2.fill", "Pass-and-play multiplayer")
                bullet("globe", "Dedicated global leaderboard")
            case .time:
                bullet("hourglass", "Five durations per round, hold to recreate")
                bullet("dial.high", "Easy and Hard duration ranges")
                bullet("person.2.fill", "Pass-and-play multiplayer")
                bullet("globe", "Dedicated global leaderboard")
            case .shape:
                bullet("triangle", "Five shapes per round, transform to match")
                bullet("dial.high", "Easy and Hard reveal timings")
                bullet("person.2.fill", "Pass-and-play multiplayer")
                bullet("globe", "Dedicated global leaderboard")
            case .color:
                EmptyView()
            }
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
        guard let p = product else { return }
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
