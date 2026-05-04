import SwiftUI
import UIKit

// Renders a beautiful, dense share image for posting to Stories / Messages /
// etc. Always 4:5 portrait with the wordmark, score, verdict, and per-round
// breakdown so a glance is enough to compete or be jealous.
struct ShareCardView: View {
    let total: Double
    let outOf: Double
    let verdict: String
    let category: GameCategory
    let difficulty: String
    let initials: String
    let rounds: [PlayerRound]
    let targetsColor: [HSB]
    let targetsHz: [Double]
    let targetsHex: [HSB]

    var body: some View {
        ZStack {
            Color.black
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("Match")
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(.white)
                    Text("Maxxer")
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(.white)
                        .italic()
                    Text(".")
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(LinearGradient(
                            colors: [
                                Color(red: 0.18, green: 0.95, blue: 0.92),
                                Color(red: 0.62, green: 0.32, blue: 0.95)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                    Spacer()
                    Text(category.displayName.uppercased())
                        .font(.system(size: 11, weight: .black))
                        .kerning(1.6)
                        .foregroundStyle(.white.opacity(0.55))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(difficulty.uppercased())
                        .font(.system(size: 11, weight: .black))
                        .kerning(1.6)
                        .foregroundStyle(.white.opacity(0.45))
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(String(format: "%.2f", total))
                            .font(.system(size: 76, weight: .black))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                        Text("/ \(Int(outOf))")
                            .font(.system(size: 28, weight: .black))
                            .foregroundStyle(.white.opacity(0.40))
                            .monospacedDigit()
                    }
                    Text(verdict)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    ForEach(rounds.indices, id: \.self) { i in
                        cell(round: rounds[i], index: i)
                    }
                }

                HStack(alignment: .firstTextBaseline) {
                    if !initials.isEmpty {
                        Text(initials)
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().stroke(.white.opacity(0.5), lineWidth: 1))
                    }
                    Spacer()
                    Text("matchmaxxer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(28)
        }
        .frame(width: 1080, height: 1350) // 4:5 portrait, hi-res
    }

    @ViewBuilder
    private func cell(round: PlayerRound, index: Int) -> some View {
        let scoreText = String(format: "%.1f", round.score)
        ZStack {
            if category == .color, targetsColor.indices.contains(index) {
                ZStack {
                    targetsColor[index].color
                    round.guess.color.clipShape(TopLeftTriangle())
                }
            } else if category == .hex, targetsHex.indices.contains(index) {
                ZStack {
                    targetsHex[index].color
                    round.guess.color.clipShape(TopLeftTriangle())
                }
            } else if category == .sound, targetsHz.indices.contains(index) {
                ZStack {
                    Color(red: 0.05, green: 0.06, blue: 0.10)
                    WavelengthView(frequency: targetsHz[index], energy: 0.9, paused: true)
                }
            } else {
                Color.white.opacity(0.05)
            }
            VStack {
                HStack {
                    Text(scoreText)
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .shadow(color: .black.opacity(0.55), radius: 1.5, y: 0.5)
                    Spacer()
                }
                Spacer()
            }
            .padding(8)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Renderer + share sheet

@MainActor
func renderShareCard(_ view: ShareCardView) -> UIImage? {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1 // already at hi-res via the .frame
    renderer.proposedSize = .init(width: 1080, height: 1350)
    return renderer.uiImage
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
