import SwiftUI

// Hex mode: ready/set/go intro → memorize (animated-gradient hex text only —
// no fullscreen swatch, so the player has to perceive the color through the
// glyphs themselves) → guess (palette + brightness rail) → result.
struct HexGameView: View {
    @Bindable var model: GameModel
    @State private var scoreTimer: Timer?
    @State private var memorizeTimer: Timer?
    @State private var phaseTimer: Timer?

    @State private var introOpacity: Double = 0

    @State private var guessHue: Double = 180
    @State private var guessSat: Double = 60
    @State private var guessLight: Double = 50  // 0=black, 50=full color, 100=white

    @State private var fingerInSquare: CGPoint? = nil
    @State private var paletteSize: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch model.phase {
            case .ready, .set, .go:
                preCardOverlay
            case .memorize:
                memorizeLayer
            case .guess:
                guessLayer
            case .result:
                resultLayer
            default:
                EmptyView()
            }
        }
        .onAppear { onPhase(model.phase) }
        .onChange(of: model.phase) { _, p in onPhase(p) }
        .onDisappear { invalidateTimers() }
    }

    // Lightness rail semantics:
    // - light ≤ 50: scales brightness 0 → 100 (sat unchanged)        → black ramp to color
    // - light > 50: scales sat 100% → 0% at brightness 100           → color ramp to white
    // (Standard "color slider" UX, not raw HSB brightness.)
    private static func effectiveBriSat(light: Double, paletteSat: Double) -> (bri: Double, sat: Double) {
        if light <= 50 {
            return (bri: light * 2, sat: paletteSat)
        } else {
            return (bri: 100, sat: paletteSat * (1 - (light - 50) / 50))
        }
    }

    private var liveGuess: HSB {
        let (bri, sat) = Self.effectiveBriSat(light: guessLight, paletteSat: guessSat)
        return HSB(h: guessHue, s: sat, b: bri)
    }

    // MARK: - Pre-card (ready / set / go)

    private var preCardOverlay: some View {
        VStack {
            HStack(alignment: .top) {
                Text("\(model.roundIndex + 1) / \(model.totalRounds)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                phaseWord
                    .id("\(model.phase)")
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.6).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .opacity(introOpacity)
    }

    private var phaseWord: some View {
        let txt: String
        switch model.phase {
        case .ready: txt = "ready"
        case .set:   txt = "set"
        case .go:    txt = "go"
        default:     txt = ""
        }
        return Text(txt)
            .font(.system(size: 64, weight: .black))
            .foregroundStyle(.white)
            .kerning(-1.5)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    // MARK: - Memorize layer

    // No fullscreen color reveal — only the hex code in big monospaced glyphs
    // filled with the target color itself, so the player perceives the color
    // through the letterforms. A soft target-tinted halo gives the strokes
    // enough surface area to read.
    private var memorizeLayer: some View {
        let target = model.currentTarget
        return VStack {
            HStack {
                Text("\(model.roundIndex + 1) / \(model.totalRounds)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(String(format: "%03d", model.memorizeRemainingCs))
                    .font(.system(size: 56, weight: .black))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)

            Spacer()

            Text(target.hexString)
                .font(.system(size: 64, weight: .black, design: .monospaced))
                .kerning(2)
                .foregroundStyle(target.color)
                .shadow(color: target.color.opacity(0.45), radius: 18)
                .shadow(color: target.color.opacity(0.25), radius: 4)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 22)

            Spacer()
        }
    }

    // MARK: - Guess layer

    private var guessLayer: some View {
        VStack(spacing: 18) {
            HStack {
                Text("\(model.roundIndex + 1) / \(model.totalRounds)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text(model.players.count > 1 ? model.currentPlayer.name : "MatchMaxxer")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)

            targetReadout
                .padding(.horizontal, 22)

            paletteSquareView
                .padding(.horizontal, 16)

            railAndSwatch
                .padding(.horizontal, 22)

            Spacer(minLength: 0)

            lockInButton
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
        }
        .onChange(of: liveGuess) { _, new in model.guess = new }
    }

    private var targetReadout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("FIND")
                .font(.system(size: 11, weight: .black))
                .kerning(1.6)
                .foregroundStyle(.white.opacity(0.45))
            Text(model.currentTarget.hexString)
                .font(.system(size: 40, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
                .kerning(1.0)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var paletteSquareView: some View {
        HSBPaletteSquare(
            hue: $guessHue,
            sat: $guessSat,
            light: guessLight,
            fingerLocation: $fingerInSquare,
            size: $paletteSize
        )
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    private var railAndSwatch: some View {
        HStack(spacing: 12) {
            LightnessRail(light: $guessLight, hue: guessHue, sat: guessSat)
                .frame(height: 56)

            // Visible confirmation of the picked color (never the hex value —
            // that would let players reverse-engineer a perfect match).
            // Sized to the rail so the row reads as one unit.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(liveGuess.color)
                .frame(width: 56, height: 56)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.28), lineWidth: 1.5)
                )
                .shadow(color: liveGuess.color.opacity(0.35), radius: 6)
        }
    }

    private var lockInButton: some View {
        Button(action: commitGuess) {
            HStack(spacing: 10) {
                Image(systemName: "eyedropper")
                    .font(.system(size: 15, weight: .bold))
                Text("Lock in")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Capsule().fill(.white))
        }
        .buttonStyle(PressableButtonStyle())
    }

    // MARK: - Result layer (mirrors GameView)

    private var resultLayer: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                ZStack {
                    model.guess.color.ignoresSafeArea()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(model.roundIndex + 1) / \(model.totalRounds)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        Text("Your pick")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        Text(model.guess.hexString)
                            .font(.system(size: 18, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 14)
                    .padding(.bottom, 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                    VStack(alignment: .trailing, spacing: 8) {
                        Text(String(format: "%.2f", model.displayedScore))
                            .font(.system(size: 60, weight: .black))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(.numericText(value: model.displayedScore))
                            .padding(.top, 4)
                        Text(hexVerdict(model.revealedScore))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                            .frame(maxWidth: 220, alignment: .trailing)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
                .frame(height: geo.size.height / 2)

                ZStack {
                    model.currentTarget.color.ignoresSafeArea()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Target")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        Text(model.currentTarget.hexString)
                            .font(.system(size: 18, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                    HStack {
                        Spacer()
                        CircleIconButton(systemName: "arrow.right", size: 60) {
                            SoundPlayer.haptic(.medium)
                            model.nextRound()
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
                .frame(height: geo.size.height / 2)
            }
        }
    }

    // MARK: - Phase orchestration

    private func onPhase(_ phase: Phase) {
        switch phase {
        case .ready:
            introOpacity = 0
            model.displayedScore = 0
            withAnimation(.easeInOut(duration: 0.6)) { introOpacity = 1 }
            SoundPlayer.play(.ready)
            SoundPlayer.haptic(.light)
            schedule(after: 0.85) {
                withAnimation(.easeInOut(duration: 0.18)) { model.phase = .set }
            }
        case .set:
            SoundPlayer.play(.set)
            SoundPlayer.haptic(.light)
            schedule(after: 0.7) {
                withAnimation(.easeInOut(duration: 0.18)) { model.phase = .go }
            }
        case .go:
            SoundPlayer.play(.go)
            SoundPlayer.haptic(.medium)
            schedule(after: 0.7) { model.phase = .memorize }
        case .memorize:
            startMemorize()
        case .guess:
            // Seed the picker far from the target so the player has to actually move.
            let target = model.currentTarget
            var rng = SystemRandomNumberGenerator()
            let offset = Double.random(in: 120...240, using: &rng)
            guessHue = (target.h + offset).truncatingRemainder(dividingBy: 360)
            guessSat = max(20, min(95, target.s + Double.random(in: -40...40)))
            // Lightness in [0,100] — start mid (~full color) but jittered.
            guessLight = max(20, min(80, 50 + Double.random(in: -25...25)))
            model.guess = liveGuess
            fingerInSquare = nil
        case .result:
            animateScoreCountUp()
        default:
            break
        }
    }

    // Easy = 5s reveal, Hard = 3s. Mirrors GameView.startMemorize so the
    // countdown feel is consistent across game modes.
    private func startMemorize() {
        let totalSeconds: Double = (model.difficulty == .hard) ? 3.0 : 5.0
        let totalMs = totalSeconds * 1000
        let totalCs = Int(totalSeconds * 100)
        model.memorizeRemainingCs = totalCs
        let start = Date()
        SoundPlayer.play(.tick)
        var lastBeatSecond = Int(totalSeconds)
        memorizeTimer?.invalidate()
        memorizeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            Task { @MainActor in
                let elapsed = Date().timeIntervalSince(start) * 1000
                let remainingMs = max(0, totalMs - elapsed)
                model.memorizeRemainingCs = Int(remainingMs / 10)
                let secondNow = Int(remainingMs / 1000)
                if secondNow < lastBeatSecond {
                    SoundPlayer.play(.tick)
                    lastBeatSecond = secondNow
                }
                if remainingMs <= 0 {
                    memorizeTimer?.invalidate()
                    memorizeTimer = nil
                    model.memorizeRemainingCs = 0
                    withAnimation(.easeInOut(duration: 0.35)) {
                        model.phase = .guess
                    }
                }
            }
        }
    }

    private func commitGuess() {
        SoundPlayer.play(.lock)
        SoundPlayer.haptic(.medium)
        model.submitGuess()
    }

    private func invalidateTimers() {
        scoreTimer?.invalidate(); scoreTimer = nil
        memorizeTimer?.invalidate(); memorizeTimer = nil
        phaseTimer?.invalidate(); phaseTimer = nil
    }

    private func schedule(after seconds: TimeInterval, _ block: @escaping () -> Void) {
        phaseTimer?.invalidate()
        phaseTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            Task { @MainActor in block() }
        }
    }

    private func animateScoreCountUp() {
        scoreTimer?.invalidate()
        let target = model.revealedScore
        let steps = 12
        var i = 0
        scoreTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { _ in
            Task { @MainActor in
                i += 1
                let f = Double(i) / Double(steps)
                let eased = 1 - pow(1 - f, 2)
                withAnimation(.easeOut(duration: 0.06)) {
                    model.displayedScore = min(target, target * eased)
                }
                SoundPlayer.play(.scoreTick)
                if i >= steps {
                    model.displayedScore = target
                    scoreTimer?.invalidate()
                    scoreTimer = nil
                }
            }
        }
    }
}

// MARK: - Palette square (H × S, previewed at the rail's effective brightness/sat)

// Renders the palette as it would actually look at the current lightness:
//   - light ≤ 50: scale brightness down (paint dims toward black)
//   - light > 50: scale saturation down (paint washes toward white)
// So a pixel under the crosshair matches what the user will pick.
private struct HSBPaletteSquare: View {
    @Binding var hue: Double         // 0...360
    @Binding var sat: Double         // 0...100, palette-Y axis (0 = top, 100 = bottom)
    var light: Double                // 0...100, from the rail
    @Binding var fingerLocation: CGPoint?
    @Binding var size: CGSize

    private var effBri: Double {
        light <= 50 ? light * 2 : 100
    }
    private var effSatMax: Double {
        light <= 50 ? 1.0 : (1 - (light - 50) / 50)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let bri01 = effBri / 100
            let satMax = effSatMax

            ZStack {
                // Bottom row of the palette is HSB(h, satMax*100, effBri). At
                // light=100 satMax=0, so the whole palette flattens to white.
                LinearGradient(
                    colors: stride(from: 0.0, through: 360.0, by: 20.0).map {
                        Color(hue: $0 / 360, saturation: satMax, brightness: bri01)
                    },
                    startPoint: .leading, endPoint: .trailing
                )
                // Top of column = pure neutral at the same brightness, fading
                // to clear at the bottom (so the saturation gradient lands on
                // the hue gradient below).
                LinearGradient(
                    colors: [
                        Color(hue: 0, saturation: 0, brightness: bri01),
                        Color(hue: 0, saturation: 0, brightness: bri01, opacity: 0)
                    ],
                    startPoint: .top, endPoint: .bottom
                )

                // Crosshair at the current selection. Top = sat 0 (matches the
                // gray overlay above the hue gradient), bottom = sat 100.
                let cx = CGFloat(hue / 360) * w
                let cy = CGFloat(sat / 100) * h
                Crosshair()
                    .frame(width: 22, height: 22)
                    .position(x: cx, y: cy)

                // Loupe — only visible while finger is down
                if let fp = fingerLocation {
                    eyedropperLoupe(at: fp, in: CGSize(width: w, height: h))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let x = max(0, min(w, g.location.x))
                        let y = max(0, min(h, g.location.y))
                        hue = Double(x / w) * 360
                        sat = Double(y / h) * 100
                        fingerLocation = CGPoint(x: x, y: y)
                    }
                    .onEnded { _ in
                        fingerLocation = nil
                    }
            )
            .onAppear { size = geo.size }
            .onChange(of: geo.size) { _, s in size = s }
        }
    }

    @ViewBuilder
    private func eyedropperLoupe(at finger: CGPoint, in container: CGSize) -> some View {
        let radius: CGFloat = 44
        let preferAbove = finger.y > radius * 2 + 12
        let dy: CGFloat = preferAbove ? -(radius + 28) : (radius + 28)
        let cx = max(radius + 4, min(container.width - radius - 4, finger.x))
        let cy = finger.y + dy

        // Picked color reflects the rail's lightness too — this is what gets scored.
        let pickedSat = (sat / 100) * effSatMax
        let pickedColor = Color(
            hue: hue / 360,
            saturation: pickedSat,
            brightness: effBri / 100
        )

        ZStack {
            Circle().fill(pickedColor)
            Circle().strokeBorder(.white, lineWidth: 4)
            Circle().strokeBorder(.black.opacity(0.35), lineWidth: 1)
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(.white)
                .blendMode(.difference)
        }
        .frame(width: radius * 2, height: radius * 2)
        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
        .position(x: cx, y: cy)
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

// MARK: - Lightness rail (horizontal)

// Black on the left → fully saturated current color in the middle → white on
// the right. Drag-position is the "lightness" — the picked color blends from
// black at 0 through the chosen color at 50 to white at 100.
private struct LightnessRail: View {
    @Binding var light: Double
    var hue: Double
    var sat: Double

    private let thumbSize: CGFloat = 28
    private let edgeInset: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            // Gesture covers the full rail [0, w]; the thumb is visually inset
            // so it lives entirely inside the capsule at both ends.
            let frac = light / 100
            let thumbCenterX = edgeInset + (w - edgeInset * 2) * CGFloat(frac)

            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [
                        .black,
                        Color(hue: hue / 360,
                              saturation: max(0.05, sat / 100),
                              brightness: 1),
                        .white
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )

                Circle()
                    .fill(.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(Circle().stroke(.black.opacity(0.15), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .offset(x: thumbCenterX - thumbSize / 2,
                            y: (geo.size.height - thumbSize) / 2)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let raw = max(0, min(w, g.location.x))
                        let newLight = Double(raw / w) * 100
                        // Soft tap when crossing into either extreme.
                        if (newLight >= 100 && light < 100) ||
                           (newLight <= 0 && light > 0) {
                            SoundPlayer.haptic(.light)
                        }
                        light = newLight
                    }
            )
        }
    }
}

// MARK: - Crosshair

private struct Crosshair: View {
    var body: some View {
        ZStack {
            Circle().strokeBorder(.white, lineWidth: 2)
            Circle().strokeBorder(.black.opacity(0.4), lineWidth: 0.6)
        }
        .frame(width: 18, height: 18)
        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
        .allowsHitTesting(false)
    }
}
