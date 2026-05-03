import SwiftUI

struct DifficultyToggle: View {
    @Binding var difficulty: Difficulty
    var enabledOptions: [Difficulty] = [.easy, .hard]

    var body: some View {
        GeometryReader { geo in
            let count = CGFloat(enabledOptions.count)
            let segmentWidth = geo.size.width / count
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.10))
                    .overlay(
                        Capsule().stroke(.white.opacity(0.18), lineWidth: 1)
                    )
                Capsule()
                    .fill(.white)
                    .frame(width: segmentWidth)
                    .offset(x: segmentWidth * CGFloat(enabledOptions.firstIndex(of: difficulty) ?? 0))
                    .animation(.spring(response: 0.45, dampingFraction: 0.78), value: difficulty)
                HStack(spacing: 0) {
                    ForEach(enabledOptions) { d in
                        Text(d.rawValue)
                            .font(.system(size: 14, weight: .semibold, design: .default))
                            .frame(width: segmentWidth)
                            .foregroundStyle(d == difficulty ? .black : .white)
                            .animation(.easeInOut(duration: 0.2), value: difficulty)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                                    difficulty = d
                                }
                            }
                    }
                }
            }
        }
        .frame(height: 38)
    }
}

struct CircleIconButton: View {
    var systemName: String
    var size: CGFloat = 64
    var foreground: Color = .black
    var background: Color = .white
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(background)
                Image(systemName: systemName)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(foreground)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct HorizontalColorSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var label: String
    var displayValue: String
    var trackGradient: LinearGradient
    var foreground: Color = .white

    var trackHeight: CGFloat = 18
    var thumbSize: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .heavy))
                    .kerning(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(foreground.opacity(0.65))
                Spacer()
                Text(displayValue)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(foreground.opacity(0.85))
            }
            GeometryReader { geo in
                let w = geo.size.width
                let frac = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
                let cx = w * CGFloat(frac)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(trackGradient)
                        .frame(height: trackHeight)
                        .overlay(
                            Capsule().stroke(.white.opacity(0.18), lineWidth: 0.6)
                        )
                    Circle()
                        .fill(.white)
                        .frame(width: thumbSize, height: thumbSize)
                        .overlay(Circle().stroke(.black.opacity(0.15), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                        .offset(x: cx - thumbSize / 2)
                }
                .frame(height: max(trackHeight, thumbSize))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let raw = max(0, min(w, g.location.x))
                            let f = Double(raw / w)
                            value = range.lowerBound + f * (range.upperBound - range.lowerBound)
                        }
                )
            }
            .frame(height: max(trackHeight, thumbSize))
        }
    }
}

struct VerticalColorSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var gradient: LinearGradient
    var width: CGFloat = 36
    var handleSize: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let frac = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let y = h * (1 - CGFloat(frac))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: width / 2)
                    .fill(gradient)
                Circle()
                    .fill(.white)
                    .frame(width: handleSize, height: handleSize)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .offset(x: (width - handleSize) / 2, y: y - handleSize / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let raw = max(0, min(h, g.location.y))
                        let f = 1 - Double(raw / h)
                        value = range.lowerBound + f * (range.upperBound - range.lowerBound)
                    }
            )
        }
        .frame(width: width)
    }
}

struct HueGradient {
    // Hue 0 (red) at the leading edge, hue 360 (red) at the trailing edge —
    // this keeps the gradient direction aligned with the slider's value direction
    // so the color under the thumb matches the chosen hue.
    static var stops: Gradient {
        Gradient(colors: stride(from: 0, through: 360, by: 30).map { h in
            Color(hue: h / 360, saturation: 1, brightness: 1)
        })
    }
}

struct FlipDigit: View {
    var character: Character
    var fontSize: CGFloat
    var color: Color
    var body: some View {
        Text(String(character))
            .font(.system(size: fontSize, weight: .black, design: .default))
            .foregroundStyle(color)
            .id(character)
            .transition(
                .asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                )
            )
    }
}

struct FlipNumber: View {
    var text: String
    var fontSize: CGFloat
    var color: Color
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                ZStack {
                    FlipDigit(character: ch, fontSize: fontSize, color: color)
                }
                .frame(width: fontSize * 0.62, height: fontSize * 1.05)
                .clipped()
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: ch)
            }
        }
    }
}

extension Color {
    static func contrastingText(against bg: HSB) -> Color {
        bg.b > 55 ? .black : .white
    }
}
