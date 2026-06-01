import SwiftUI

struct HSB: Equatable, Hashable {
    var h: Double
    var s: Double
    var b: Double

    static let neutral = HSB(h: 0, s: 0, b: 50)

    var color: Color {
        Color(hue: h / 360, saturation: s / 100, brightness: b / 100)
    }

    var label: String {
        "H\(Int(h.rounded())) S\(Int(s.rounded())) B\(Int(b.rounded()))"
    }

    static func random(using rng: inout SplitMix64) -> HSB {
        HSB(
            h: rng.double(in: 0..<360),
            s: rng.double(in: 35...92),
            b: rng.double(in: 32...82)
        )
    }

    static func distinctSequence(count: Int, seed: UInt64, minHueGap: Double = 35) -> [HSB] {
        var rng = SplitMix64(seed: seed)
        var out: [HSB] = []
        while out.count < count {
            var candidate = HSB.random(using: &rng)
            var attempts = 0
            while attempts < 30 && out.contains(where: { hueDistance(candidate.h, $0.h) < minHueGap }) {
                candidate = HSB.random(using: &rng)
                attempts += 1
            }
            out.append(candidate)
        }
        return out
    }
}

struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xDEADBEEFCAFEBABE : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func double(in range: Range<Double>) -> Double {
        let n = Double(next() >> 11) / Double(1 << 53)
        return range.lowerBound + n * (range.upperBound - range.lowerBound)
    }
    mutating func double(in range: ClosedRange<Double>) -> Double {
        let n = Double(next() >> 11) / Double(1 << 53)
        return range.lowerBound + n * (range.upperBound - range.lowerBound)
    }
}

func hueDistance(_ a: Double, _ b: Double) -> Double {
    let raw = abs(a - b).truncatingRemainder(dividingBy: 360)
    return min(raw, 360 - raw)
}

private func hsbToLinearRGB(_ hsb: HSB) -> (r: Double, g: Double, b: Double) {
    let h = hsb.h / 60
    let s = hsb.s / 100
    let v = hsb.b / 100
    let c = v * s
    let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
    let m = v - c
    let (r1, g1, b1): (Double, Double, Double)
    switch h {
    case 0..<1: (r1, g1, b1) = (c, x, 0)
    case 1..<2: (r1, g1, b1) = (x, c, 0)
    case 2..<3: (r1, g1, b1) = (0, c, x)
    case 3..<4: (r1, g1, b1) = (0, x, c)
    case 4..<5: (r1, g1, b1) = (x, 0, c)
    default:    (r1, g1, b1) = (c, 0, x)
    }
    func toLinear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return (toLinear(r1 + m), toLinear(g1 + m), toLinear(b1 + m))
}

private func rgbToLab(_ rgb: (r: Double, g: Double, b: Double)) -> (l: Double, a: Double, b: Double) {
    let x = (rgb.r * 0.4124 + rgb.g * 0.3576 + rgb.b * 0.1805) / 0.95047
    let y = (rgb.r * 0.2126 + rgb.g * 0.7152 + rgb.b * 0.0722) / 1.00000
    let z = (rgb.r * 0.0193 + rgb.g * 0.1192 + rgb.b * 0.9505) / 1.08883
    func f(_ t: Double) -> Double {
        t > 0.008856 ? pow(t, 1.0 / 3.0) : (7.787 * t + 16.0 / 116.0)
    }
    let fx = f(x), fy = f(y), fz = f(z)
    return (l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz))
}

func deltaE(_ a: HSB, _ b: HSB) -> Double {
    let la = rgbToLab(hsbToLinearRGB(a))
    let lb = rgbToLab(hsbToLinearRGB(b))
    let dl = la.l - lb.l
    let da = la.a - lb.a
    let db = la.b - lb.b
    return sqrt(dl * dl + da * da + db * db)
}

func score(guess: HSB, target: HSB) -> Double {
    let dE = deltaE(guess, target)
    let base = 10.0 / (1.0 + pow(dE / 38.0, 1.6))
    let hueDist = hueDistance(guess.h, target.h)
    let huePenalty = hueDist > 60 ? base * 0.4 * min(1.0, (hueDist - 60) / 120) : 0
    let hueRecovery = hueDist < 12 ? (10 - base) * 0.5 * (1 - hueDist / 12) : 0
    return max(0, min(10, base - huePenalty + hueRecovery))
}

// MARK: - Sound

enum SoundRange {
    static let minHz: Double = 80
    static let maxHz: Double = 1200
    static let logMin = log2(80.0)
    static let logMax = log2(1200.0)
}

// Pitch perception is logarithmic — humans hear octaves equally spaced. Scoring
// in cents (1/100 of a semitone, 1200/octave) is the perceptually correct unit.
func centsBetween(_ a: Double, _ b: Double) -> Double {
    guard a > 0, b > 0 else { return Double.greatestFiniteMagnitude }
    return abs(1200.0 * log2(a / b))
}

func scoreSound(guessHz: Double, targetHz: Double) -> Double {
    let cents = centsBetween(guessHz, targetHz)
    // Sigmoid centered at 120 cents (one whole tone) — reaching 5/10 there
    // feels right: a confidently wrong octave-class still gets some credit,
    // but a near-perfect match is clearly distinguished.
    let base = 10.0 / (1.0 + pow(cents / 120.0, 1.6))
    return max(0, min(10, base))
}

func soundVerdict(_ s: Double) -> String {
    switch s {
    case 9.5...: return "Are your ears calibrated in a lab?"
    case 8.5..<9.5: return "Eerie. Your cochlea is showing off."
    case 7.0..<8.5: return "Solid pitch memory."
    case 5.0..<7.0: return "In the right octave. Mostly."
    case 3.0..<5.0: return "A piano somewhere just winced."
    case 1.0..<3.0: return "That was a vibe, not a frequency."
    default: return "You guessed with your knees."
    }
}

func randomTargetHz(using rng: inout SplitMix64) -> Double {
    // Sample uniformly in log-frequency space so low and high pitches are
    // equally likely from the player's perceptual standpoint.
    let logHz = rng.double(in: SoundRange.logMin...SoundRange.logMax)
    return pow(2.0, logHz)
}

// MARK: - Time

enum TimeRange {
    // Easy: shorter, rounder intervals that are easier to count. Hard: a wider,
    // longer range where small percentage drifts add up to big absolute misses.
    static func bounds(for difficulty: Difficulty) -> ClosedRange<Double> {
        switch difficulty {
        case .easy: return 2.0...6.0
        case .hard: return 3.0...12.0
        }
    }
    static let minSeconds: Double = 2.0
    static let maxSeconds: Double = 12.0
}

func randomTargetDuration(difficulty: Difficulty, using rng: inout SplitMix64) -> Double {
    let range = TimeRange.bounds(for: difficulty)
    // Quantize to quarter-seconds so targets feel deliberate, not arbitrary.
    let raw = rng.double(in: range)
    return (raw * 4).rounded() / 4
}

// Time perception obeys Weber's law — the just-noticeable error scales with the
// interval. Scoring on *relative* (percentage) error means a 0.3s miss on a 2s
// target is judged the same as a 1.8s miss on a 12s target.
func scoreTime(guess: Double, target: Double) -> Double {
    guard target > 0 else { return 0 }
    let pctError = abs(guess - target) / target
    // Sigmoid centered at 15% error → 5/10. Within ~5% lands around 8.5/10.
    let base = 10.0 / (1.0 + pow(pctError / 0.15, 1.6))
    return max(0, min(10, base))
}

func timeVerdict(_ s: Double) -> String {
    switch s {
    case 9.5...: return "Are you a human stopwatch?"
    case 8.5..<9.5: return "Eerie. Your internal clock is atomic."
    case 7.0..<8.5: return "Solid sense of time. The metronome nods."
    case 5.0..<7.0: return "Roughly right. Time got a little slippery."
    case 3.0..<5.0: return "Time is a flat circle and you missed it."
    case 1.0..<3.0: return "You counted Mississippi-ishly."
    default: return "You and time are not on speaking terms."
    }
}

extension HSB {
    var hexString: String {
        let rgb = hsbToSRGB(self)
        let r = Int((rgb.r * 255).rounded()).clamped(to: 0...255)
        let g = Int((rgb.g * 255).rounded()).clamped(to: 0...255)
        let b = Int((rgb.b * 255).rounded()).clamped(to: 0...255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self = sRGBToHSB(r: r, g: g, b: b)
    }
}

// MARK: - HSB ↔ sRGB (display values, 0...1)

func hsbToSRGB(_ hsb: HSB) -> (r: Double, g: Double, b: Double) {
    let h = (hsb.h.truncatingRemainder(dividingBy: 360) + 360)
        .truncatingRemainder(dividingBy: 360) / 60
    let s = hsb.s / 100
    let v = hsb.b / 100
    let c = v * s
    let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
    let m = v - c
    let (r1, g1, b1): (Double, Double, Double)
    switch h {
    case 0..<1: (r1, g1, b1) = (c, x, 0)
    case 1..<2: (r1, g1, b1) = (x, c, 0)
    case 2..<3: (r1, g1, b1) = (0, c, x)
    case 3..<4: (r1, g1, b1) = (0, x, c)
    case 4..<5: (r1, g1, b1) = (x, 0, c)
    default:    (r1, g1, b1) = (c, 0, x)
    }
    return (r1 + m, g1 + m, b1 + m)
}

func sRGBToHSB(r: Double, g: Double, b: Double) -> HSB {
    let mx = max(r, g, b), mn = min(r, g, b)
    let d = mx - mn
    var h: Double = 0
    if d > 0 {
        switch mx {
        case r: h = ((g - b) / d).truncatingRemainder(dividingBy: 6)
        case g: h = (b - r) / d + 2
        default: h = (r - g) / d + 4
        }
        h *= 60
        if h < 0 { h += 360 }
    }
    let s = mx == 0 ? 0 : d / mx
    return HSB(h: h, s: s * 100, b: mx * 100)
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

func hexVerdict(_ s: Double) -> String {
    switch s {
    case 9.5...: return "Pixel-perfect. Are you a hex code?"
    case 8.5..<9.5: return "Surgical. Your retinas have a CS degree."
    case 7.0..<8.5: return "Confident eye. The cones know hex."
    case 5.0..<7.0: return "Right neighborhood. Wrong block."
    case 3.0..<5.0: return "That hex code is filing a restraining order."
    case 1.0..<3.0: return "Did you read it as base 10?"
    default: return "A designer somewhere just rage-quit."
    }
}

func scoreVerdict(_ s: Double) -> String {
    switch s {
    case 9.5...: return "Are you a color sommelier?"
    case 8.5..<9.5: return "Eerily close. The retina respects you."
    case 7.0..<8.5: return "Solid eye. The cones are firing."
    case 5.0..<7.0: return "In the neighborhood. Wrong house."
    case 3.0..<5.0: return "This is a hate crime against the visible spectrum."
    case 1.0..<3.0: return "Did you guess with your elbow?"
    default: return "A monitor somewhere is crying."
    }
}
