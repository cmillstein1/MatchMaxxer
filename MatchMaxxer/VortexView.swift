import SwiftUI

// Animated vortex: a stack of concentric rings whose centers spiral out from the
// middle and rotate over time, producing the swirling "pull" of the reference
// design. Brand palette — cyan at the core fading to purple at the rim, drawn
// with an additive screen blend so overlapping strokes glow.
//
// `energy` (0...1) scales both the spin speed and the line opacity, so the same
// view can idle quietly (menu card) or surge while the player holds the screen.
struct VortexView: View {
    var energy: Double = 1.0
    var paused: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: paused)) { context in
            Canvas { ctx, size in
                draw(into: ctx, size: size, time: context.date.timeIntervalSinceReferenceDate)
            }
            .drawingGroup()
            .blendMode(.screen)
        }
    }

    private func draw(into ctx: GraphicsContext, size: CGSize, time: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let ringCount = 28
        let maxRadius = min(size.width, size.height) * 0.62

        // Overall rotation of the spiral. Faster as energy rises.
        let spin = time * (0.16 + energy * 0.55)
        // A slow breathing wobble so even a low-energy idle has life.
        let breathe = 0.5 + 0.5 * sin(time * 0.4)

        let cyan   = SIMD3<Double>(0.18, 0.95, 0.92)
        let purple = SIMD3<Double>(0.62, 0.32, 0.95)

        for i in 0..<ringCount {
            // 0 at the core, 1 at the rim.
            let frac = Double(i) / Double(ringCount - 1)
            // Slight power curve so the rings bunch toward the center like the
            // reference image, with a small floor so the core never collapses.
            let radius = maxRadius * pow(frac, 1.12) + 5

            // Each ring's center is displaced from the middle along an angle that
            // winds with the radius and rotates in time — that winding is what
            // reads as a vortex rather than plain concentric circles.
            let angle = frac * .pi * 4.0 + spin
            let offsetMag = maxRadius * (0.12 + 0.06 * breathe) * frac
            let cx = center.x + cos(angle) * offsetMag
            let cy = center.y + sin(angle) * offsetMag

            let rect = CGRect(x: cx - radius, y: cy - radius,
                              width: radius * 2, height: radius * 2)

            let rgb = cyan * (1 - frac) + purple * frac
            // Brighter overall with energy; rim rings fade slightly so the focus
            // stays on the swirling core.
            let opacity = (0.10 + 0.34 * energy) * (1 - frac * 0.30)

            ctx.stroke(
                Path(ellipseIn: rect),
                with: .color(Color(red: rgb.x, green: rgb.y, blue: rgb.z).opacity(opacity)),
                lineWidth: 1.1
            )
        }
    }
}
