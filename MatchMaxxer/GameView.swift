import SwiftUI

struct GameView: View {
    @Bindable var model: GameModel
    @State private var memorizeTimer: Timer?
    @State private var phaseTimer: Timer?
    @State private var scoreTimer: Timer?
    @State private var blackOpacity: Double = 0
    @State private var introOpacity: Double = 0

    @State private var guessHue: Double = 0
    @State private var guessSat: Double = 0
    @State private var guessBri: Double = 50

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            backgroundLayer
            overlayLayer
        }
        .onAppear { startPhase(model.phase) }
        .onChange(of: model.phase) { _, newPhase in startPhase(newPhase) }
        .onDisappear { invalidateAll() }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundLayer: some View {
        switch model.phase {
        case .ready, .set, .go, .fadeToBlack, .revealFromBlack, .memorize:
            memorizeBackground
        case .guess:
            liveGuess.color.ignoresSafeArea()
        case .result:
            resultBackground
        }
    }

    private var memorizeBackground: some View {
        let underlying: Color
        if model.difficulty == .hard {
            switch model.phase {
            case .ready:        underlying = safeDistractor(0)
            case .set:          underlying = safeDistractor(1)
            case .go:           underlying = safeDistractor(2)
            case .fadeToBlack:  underlying = safeDistractor(2)
            default:            underlying = model.currentTarget.color
            }
        } else {
            underlying = model.currentTarget.color
        }
        return ZStack {
            underlying.opacity(introOpacity)
            Color.black.opacity(blackOpacity)
        }
        .ignoresSafeArea()
    }

    private func safeDistractor(_ i: Int) -> Color {
        guard !model.distractors.isEmpty, model.currentDistractors.indices.contains(i)
        else { return model.currentTarget.color }
        return model.currentDistractors[i].color
    }

    // MARK: - Overlay

    @ViewBuilder
    private var overlayLayer: some View {
        switch model.phase {
        case .ready, .set, .go:
            preCardOverlay
        case .fadeToBlack, .revealFromBlack:
            EmptyView()
        case .memorize:
            memorizeOverlay.transition(.opacity)
        case .guess:
            guessOverlay
        case .result:
            resultOverlay
        }
    }

    // Ready / Set / Go: round indicator at top-left, phase word at top-right.
    private var preCardOverlay: some View {
        VStack {
            HStack(alignment: .top) {
                roundIndicator
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

    private var memorizeOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                roundIndicator
                Spacer()
                Text(String(format: "%03d", model.memorizeRemainingCs))
                    .font(.system(size: 76, weight: .black))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var roundIndicator: some View {
        Text("\(model.roundIndex + 1) / \(model.totalRounds)")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white.opacity(0.75))
    }

    // MARK: - Guess

    private var liveGuess: HSB {
        HSB(h: guessHue, s: guessSat, b: guessBri)
    }

    private var guessOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                roundIndicator
                Spacer()
                Text(model.players.count > 1 ? model.currentPlayer.name : "MatchMaxxer")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)

            Spacer(minLength: 0)

            sliderPanel
        }
        .onChange(of: liveGuess) { _, new in
            model.guess = new
        }
    }

    @ViewBuilder
    private var sliderPanel: some View {
        VStack(spacing: 18) {
            HorizontalColorSlider(
                value: $guessHue,
                range: 0...360,
                label: "Hue",
                displayValue: "\(Int(guessHue.rounded()))",
                trackGradient: LinearGradient(gradient: HueGradient.stops,
                                              startPoint: .leading, endPoint: .trailing),
                foreground: .white
            )
            HorizontalColorSlider(
                value: $guessSat,
                range: 0...100,
                label: "Saturation",
                displayValue: "\(Int(guessSat.rounded()))",
                trackGradient: LinearGradient(
                    colors: [
                        Color(hue: guessHue / 360, saturation: 0,
                              brightness: max(0.25, guessBri / 100)),
                        Color(hue: guessHue / 360, saturation: 1,
                              brightness: max(0.25, guessBri / 100))
                    ],
                    startPoint: .leading, endPoint: .trailing),
                foreground: .white
            )
            HorizontalColorSlider(
                value: $guessBri,
                range: 0...100,
                label: "Brightness",
                displayValue: "\(Int(guessBri.rounded()))",
                trackGradient: LinearGradient(
                    colors: [
                        .black,
                        Color(hue: guessHue / 360,
                              saturation: max(0.05, guessSat / 100),
                              brightness: 1)
                    ],
                    startPoint: .leading, endPoint: .trailing),
                foreground: .white
            )

            HStack {
                Spacer()
                Button(action: commitGuess) {
                    HStack(spacing: 10) {
                        Image(systemName: "target")
                            .font(.system(size: 15, weight: .bold))
                        Text("Lock in")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(.white))
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 22)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.32))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                )
                .ignoresSafeArea(edges: .bottom)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Result

    @ViewBuilder
    private var resultBackground: some View {
        VStack(spacing: 0) {
            model.guess.color.frame(maxHeight: .infinity)
            model.currentTarget.color.frame(maxHeight: .infinity)
        }
        .ignoresSafeArea()
    }

    private var resultOverlay: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Top half — your selection
                ZStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(model.roundIndex + 1) / \(model.totalRounds)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                        Spacer()
                        Text("Your selection")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                        Text(model.guess.label)
                            .font(.system(size: 15, weight: .bold))
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
                        Text(scoreVerdict(model.revealedScore))
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

                // Bottom half — original
                ZStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Original")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                        Text(model.currentTarget.label)
                            .font(.system(size: 15, weight: .bold))
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

    private func startPhase(_ phase: Phase) {
        invalidateAll()
        switch phase {
        case .ready:
            blackOpacity = 0
            model.displayedScore = 0
            introOpacity = 0
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
            let next: Phase = (model.difficulty == .hard) ? .fadeToBlack : .memorize
            schedule(after: 0.7) { model.phase = next }
        case .fadeToBlack:
            blackOpacity = 0
            withAnimation(.easeInOut(duration: 0.35)) { blackOpacity = 1 }
            schedule(after: 1.0) { model.phase = .revealFromBlack }
        case .revealFromBlack:
            withAnimation(.easeInOut(duration: 0.45)) { blackOpacity = 0 }
            schedule(after: 0.45) { model.phase = .memorize }
        case .memorize:
            startMemorize()
        case .guess:
            // Start the user on a random color so they have something to dial AWAY from,
            // not on a flat gray that might get confused with the target.
            let start = HSB(
                h: Double.random(in: 0..<360),
                s: Double.random(in: 30...80),
                b: Double.random(in: 30...80)
            )
            guessHue = start.h
            guessSat = start.s
            guessBri = start.b
            model.guess = start
        case .result:
            animateScoreCountUp()
        }
    }

    private func startMemorize() {
        // Easy = 5 seconds, Hard = 3 seconds. Display = centiseconds remaining
        // (3 digits). Updated at ~60Hz so the digits visibly blur — matches
        // Dialed's fast counter. Sound beat fires at every full-second boundary.
        let totalSeconds: Double = (model.difficulty == .hard) ? 3.0 : 5.0
        let totalMs: Double = totalSeconds * 1000
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
                let remainingCs = Int(remainingMs / 10)
                model.memorizeRemainingCs = remainingCs
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

    private func commitGuess() {
        SoundPlayer.play(.lock)
        SoundPlayer.haptic(.medium)
        model.submitGuess()
    }

    private func schedule(after seconds: TimeInterval, _ block: @escaping () -> Void) {
        phaseTimer?.invalidate()
        phaseTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            Task { @MainActor in block() }
        }
    }

    private func invalidateAll() {
        phaseTimer?.invalidate(); phaseTimer = nil
        memorizeTimer?.invalidate(); memorizeTimer = nil
        scoreTimer?.invalidate(); scoreTimer = nil
    }
}
