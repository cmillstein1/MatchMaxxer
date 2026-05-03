import SwiftUI

// DNA-style helix: a bundle of N parallel "strands" that wrap perpendicularly
// around a vertical spine. The bundle's apparent width is modulated by both a
// fast helical twist (rotating the strands around the spine) and a slow bulge
// envelope along Y, producing the flowing, knot-and-spread look of the
// reference visualization. Smoothness comes from sampling many points and
// connecting them with quadratic curves through their midpoints (quick
// approximation of a Catmull–Rom spline) instead of straight lines.
struct WavelengthView: View {
    var frequency: Double          // 80 ... 1200
    var energy: Double = 1.0       // 0...1, scales line opacity
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
        let centerX = size.width / 2
        // Lots of densely packed thin strands so the wide regions read as a
        // smooth wash instead of striped lines.
        let strandCount = 64
        let maxSpread = min(size.width * 0.22, 92)

        // Log-frequency 0..1 across the playable range
        let logFrac = max(0, min(1, (log2(max(20, frequency)) - log2(80.0)) /
                                      (log2(1200.0) - log2(80.0))))

        // Slower, calmer parameters — fewer bulges, gentler twist. The
        // visualization should feel like a flowing ribbon, not a coiled
        // spring.
        let bulgesPerScreen = 1.4 + logFrac * 2.6   // 1.4 .. 4.0
        let twistsPerScreen = 1.2 + logFrac * 2.3   // 1.2 .. 3.5
        let twistTimeSpeed = 0.28 + logFrac * 0.45  // 0.28 .. 0.73
        let bulgeTimeSpeed = 0.13                   // slow drift on the envelope

        let cyan   = SIMD3<Double>(0.18, 0.95, 0.92)
        let purple = SIMD3<Double>(0.62, 0.32, 0.95)

        let stepCount = 180
        var points = [CGPoint](repeating: .zero, count: stepCount + 1)

        for i in 0..<strandCount {
            // -1 ... +1, position of this strand within the bundle
            let strandFrac = (Double(i) - Double(strandCount - 1) / 2.0) /
                             (Double(strandCount - 1) / 2.0)

            for j in 0...stepCount {
                let normY = Double(j) / Double(stepCount)
                let y = CGFloat(normY) * size.height

                // Soft bulge envelope: 0.30 .. 1.00, slowly drifting in time.
                let env = 0.30 + 0.70 *
                    (0.5 + 0.5 * sin(normY * .pi * 2.0 * bulgesPerScreen
                                    + time * bulgeTimeSpeed))

                let spineX = centerX + sin(normY * .pi * 1.3 + time * 0.18) * 5.0

                // Twist angle around the spine. cos(twist) makes the bundle's
                // *apparent width* breathe between full spread (cos=±1) and
                // collapsed (cos=0) — that's the DNA twist.
                let twist = normY * .pi * 2.0 * twistsPerScreen + time * twistTimeSpeed
                let perpOffset = strandFrac * maxSpread * env * cos(twist)
                points[j] = CGPoint(x: spineX + perpOffset, y: y)
            }

            // Quadratic-curve smoothing through midpoints of adjacent samples
            // (cheap Catmull–Rom approximation).
            var path = Path()
            path.move(to: points[0])
            for k in 1..<points.count {
                let prev = points[k - 1]
                let curr = points[k]
                let mid = CGPoint(x: (prev.x + curr.x) / 2, y: (prev.y + curr.y) / 2)
                path.addQuadCurve(to: mid, control: prev)
            }
            path.addLine(to: points.last!)

            // Color: cyan in the middle of the bundle, purple on the edges.
            let mix = abs(strandFrac)
            let rgb = cyan * (1 - mix) + purple * mix
            let edgeFade = 1 - pow(abs(strandFrac), 1.5)
            // Lower per-strand opacity since we have more of them; the
            // additive screen blend brings the bundle back to a strong wash
            // without the visible stripes.
            let opacity = (0.10 + 0.30 * energy) * (0.45 + 0.55 * edgeFade)

            ctx.stroke(
                path,
                with: .color(Color(red: rgb.x, green: rgb.y, blue: rgb.z).opacity(opacity)),
                lineWidth: 0.55
            )
        }
    }
}
