import SwiftUI

// MARK: - Shape geometry

// The shapes the player memorizes and recreates. Each draws centered in its
// rect with the first vertex pointing straight up (so a 4-gon reads as a
// diamond, a 3-gon as an upright triangle — matching the reference design).
enum GameShape: CaseIterable, Hashable {
    case circle, triangle, square, pentagon, hexagon, star

    var displayName: String {
        switch self {
        case .circle:   return "Circle"
        case .triangle: return "Triangle"
        case .square:   return "Diamond"
        case .pentagon: return "Pentagon"
        case .hexagon:  return "Hexagon"
        case .star:     return "Star"
        }
    }

    // Rotational symmetry in degrees — the smallest turn that maps the shape
    // onto itself. Scoring folds rotation error into this range so a square
    // turned 90° counts as a perfect match. 0 means continuous (a circle), so
    // rotation is ignored entirely.
    var symmetryDegrees: Double {
        switch self {
        case .circle:   return 0
        case .triangle: return 120
        case .square:   return 90
        case .pentagon: return 72
        case .hexagon:  return 60
        case .star:     return 72
        }
    }

    func path(in rect: CGRect) -> Path {
        switch self {
        case .circle:   return Path(ellipseIn: rect)
        case .triangle: return Self.polygon(sides: 3, in: rect)
        case .square:   return Self.polygon(sides: 4, in: rect)
        case .pentagon: return Self.polygon(sides: 5, in: rect)
        case .hexagon:  return Self.polygon(sides: 6, in: rect)
        case .star:     return Self.star(points: 5, in: rect)
        }
    }

    private static func polygon(sides: Int, in rect: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        for i in 0..<sides {
            let a = -Double.pi / 2 + 2 * Double.pi * Double(i) / Double(sides)
            let pt = CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }

    private static func star(points: Int, in rect: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let rOuter = min(rect.width, rect.height) / 2
        let rInner = rOuter * 0.42
        let total = points * 2
        for i in 0..<total {
            let r = i % 2 == 0 ? rOuter : rInner
            let a = -Double.pi / 2 + Double.pi * Double(i) / Double(points)
            let pt = CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }

    // Full hue wheel used to fill the shapes, just like the reference art.
    static let rainbowColors: [Color] = stride(from: 0.0, through: 1.0, by: 1.0 / 12.0)
        .map { Color(hue: $0, saturation: 0.92, brightness: 1.0) }

    static var rainbow: AngularGradient {
        AngularGradient(gradient: Gradient(colors: rainbowColors), center: .center)
    }
}

struct ShapeMark: Shape {
    var type: GameShape
    func path(in rect: CGRect) -> Path { type.path(in: rect) }
}

// A shape plus the three things the player has to reproduce: where it sits
// (position, normalized 0...1 within the play area), how big it is (scale, a
// multiplier on the base size), and how it's turned (rotation, degrees).
struct ShapeTransform: Equatable {
    var type: GameShape
    var position: CGPoint
    var scale: Double
    var rotation: Double

    static let regular = ShapeTransform(type: .triangle,
                                        position: CGPoint(x: 0.5, y: 0.5),
                                        scale: 1.0, rotation: 0)

    // The neutral starting state for a guess: centered, default size, upright —
    // but keeping the round's shape type.
    func reset() -> ShapeTransform {
        ShapeTransform(type: type, position: CGPoint(x: 0.5, y: 0.5), scale: 1.0, rotation: 0)
    }
}

// MARK: - Generation

func randomShapeTransform(using rng: inout SplitMix64) -> ShapeTransform {
    let shapes = GameShape.allCases
    let type = shapes[Int(rng.double(in: 0..<Double(shapes.count)))]
    let pos = CGPoint(x: rng.double(in: 0.22...0.78), y: rng.double(in: 0.24...0.76))
    let scale = rng.double(in: 0.55...1.6)
    let rotation = type.symmetryDegrees == 0 ? 0 : rng.double(in: 0..<360)
    return ShapeTransform(type: type, position: pos, scale: scale, rotation: rotation)
}

// MARK: - Scoring

// Blends three independent errors — position, scale, and (where it matters)
// rotation — into a single 0...10. Each sub-score is a sigmoid so being close
// is rewarded steeply and being way off bottoms out gracefully.
func scoreShape(guess: ShapeTransform, target: ShapeTransform) -> Double {
    // Position: straight-line distance in normalized play-area units.
    let dx = guess.position.x - target.position.x
    let dy = guess.position.y - target.position.y
    let posErr = Double(hypot(dx, dy))
    let posScore = 1.0 / (1.0 + pow(posErr / 0.10, 1.6))

    // Scale: judged on the octave ratio so 2× and ½× are equally wrong.
    let logRatio = abs(log2(max(0.01, guess.scale) / max(0.01, target.scale)))
    let scaleScore = 1.0 / (1.0 + pow(logRatio / 0.25, 1.6))

    var parts = [posScore, scaleScore]

    // Rotation: only for shapes where orientation is meaningful. Error is folded
    // into the shape's symmetry range first.
    let sym = target.type.symmetryDegrees
    if sym > 0 {
        var d = abs(guess.rotation - target.rotation).truncatingRemainder(dividingBy: sym)
        if d < 0 { d += sym }
        d = min(d, sym - d) // 0 ... sym/2
        let rotScore = 1.0 / (1.0 + pow(d / 14.0, 1.6))
        parts.append(rotScore)
    }

    let avg = parts.reduce(0, +) / Double(parts.count)
    return max(0, min(10, avg * 10))
}

func shapeVerdict(_ s: Double) -> String {
    switch s {
    case 9.5...: return "Are you a human protractor?"
    case 8.5..<9.5: return "Eerie. You've got CAD in your head."
    case 7.0..<8.5: return "Sharp eye for size and spin."
    case 5.0..<7.0: return "Right neighborhood. Wrong house."
    case 3.0..<5.0: return "Close-ish. Geometry is unimpressed."
    case 1.0..<3.0: return "Was the grid just a suggestion?"
    default: return "You rotated reality, not the shape."
    }
}

// MARK: - Shared visuals

// Faint reference grid behind the shape — the player's only spatial anchor.
// Lines step outward from the center so the field stays symmetric, and a
// brighter center cross divides it into four clean quadrants.
struct GridView: View {
    var spacing: CGFloat = 84
    var lineOpacity: Double = 0.06
    var axisOpacity: Double = 0.18

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let cy = size.height / 2

            var grid = Path()
            var dx = spacing
            while cx - dx > -0.5 || cx + dx < size.width + 0.5 {
                for x in [cx - dx, cx + dx] where x >= 0 && x <= size.width {
                    grid.move(to: CGPoint(x: x, y: 0))
                    grid.addLine(to: CGPoint(x: x, y: size.height))
                }
                dx += spacing
            }
            var dy = spacing
            while cy - dy > -0.5 || cy + dy < size.height + 0.5 {
                for y in [cy - dy, cy + dy] where y >= 0 && y <= size.height {
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                }
                dy += spacing
            }
            ctx.stroke(grid, with: .color(.white.opacity(lineOpacity)), lineWidth: 1)

            // Center cross — the four-quadrant divider.
            var axis = Path()
            axis.move(to: CGPoint(x: cx, y: 0)); axis.addLine(to: CGPoint(x: cx, y: size.height))
            axis.move(to: CGPoint(x: 0, y: cy)); axis.addLine(to: CGPoint(x: size.width, y: cy))
            ctx.stroke(axis, with: .color(.white.opacity(axisOpacity)), lineWidth: 1.2)
        }
    }
}

// Decorative background for the menu / instructions: a conic-filled shape that
// slowly spins while crossfading from one shape type to the next — the "shapes
// shifting into one another" look.
struct ShapeShowcaseView: View {
    var period: Double = 2.4   // seconds per shape
    var spin: Double = 10      // degrees per second
    var scale: CGFloat = 1.0   // shrink to leave breathing room (menu card)

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = t / period
            let i = Int(floor(phase))
            let frac = phase - floor(phase)
            let shapes = GameShape.allCases
            let count = shapes.count
            let a = shapes[((i % count) + count) % count]
            let b = shapes[(((i + 1) % count) + count) % count]
            let rot = t * spin

            ZStack {
                ShapeMark(type: a).fill(GameShape.rainbow).opacity(1 - frac)
                ShapeMark(type: b).fill(GameShape.rainbow).opacity(frac)
            }
            .rotationEffect(.degrees(rot))
            .scaleEffect(scale)
        }
    }
}

// Compact recap of a guessed shape for the summary grid + share card. Shows the
// shape at its guessed rotation and (clamped) scale on a dark grid tile.
struct ShapeResultMini: View {
    var transform: ShapeTransform

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let clampedScale = min(max(transform.scale, 0.4), 1.5)
            ZStack {
                Color(red: 0.05, green: 0.06, blue: 0.10)
                GridView(spacing: s / 4, lineOpacity: 0.10)
                ShapeMark(type: transform.type)
                    .fill(GameShape.rainbow)
                    .frame(width: s * 0.5 * clampedScale, height: s * 0.5 * clampedScale)
                    .rotationEffect(.degrees(transform.rotation))
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}
