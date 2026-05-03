import SwiftUI

struct SoundGameView: View {
    @Bindable var model: GameModel
    @State private var memorizeTimer: Timer?
    @State private var phaseTimer: Timer?
    @State private var scoreTimer: Timer?
    @State private var introOpacity: Double = 0

    // Live frequency the user is dialing during .guess. Decoupled from
    // model.guessHz so we update it from a continuous drag without thrashing
    // observation — model.guessHz only updates when we settle.
    @State private var liveHz: Double = 440
    @State private var dragInProgress: Bool = false
    @State private var targetRevealOpacity: Double = 0

    private var tone: ToneGenerator { ToneGenerator.shared }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            backgroundLayer
            overlayLayer
        }
        .onAppear { startPhase(model.phase) }
        .onChange(of: model.phase) { _, newPhase in startPhase(newPhase) }
        .onDisappear { invalidateAll(); tone.stop() }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundLayer: some View {
        switch model.phase {
        case .ready, .set, .go:
            // Solid black during ready/set/go
            EmptyView()
        case .memorize:
            WavelengthView(frequency: model.currentTargetHz, energy: 1.0)
                .ignoresSafeArea()
                .opacity(introOpacity)
        case .guess:
            WavelengthView(frequency: liveHz, energy: dragInProgress ? 1.0 : 0.6)
                .ignoresSafeArea()
        case .result:
            resultBackground
        case .fadeToBlack, .revealFromBlack:
            EmptyView()
        }
    }

    // MARK: - Overlay

    @ViewBuilder
    private var overlayLayer: some View {
        switch model.phase {
        case .ready, .set, .go:
            preCardOverlay
        case .memorize:
            memorizeOverlay.opacity(introOpacity)
        case .guess:
            guessOverlay
        case .result:
            resultOverlay
        case .fadeToBlack, .revealFromBlack:
            EmptyView()
        }
    }

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
        VStack {
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

    private var guessOverlay: some View {
        ZStack {
            // Drag surface — full screen so the player can pull anywhere.
            // Up = higher Hz, down = lower Hz. Mapped logarithmically so the
            // perceived pitch change feels uniform across the swipe.
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            handleDrag(translationY: g.translation.height,
                                       began: !dragInProgress)
                        }
                        .onEnded { _ in
                            // Tone keeps playing at the current frequency so the
                            // player can listen and compare; only stops when they
                            // tap the lock-in arrow.
                            dragInProgress = false
                            model.guessHz = liveHz
                        }
                )

            VStack {
                HStack {
                    roundIndicator
                    Spacer()
                    Text("MatchMaxxer")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                Spacer()
                hzReadout
            }
        }
    }

    private var hzReadout: some View {
        HStack(alignment: .lastTextBaseline) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(String(format: "%.2f", liveHz))
                    .font(.system(size: 64, weight: .black))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText(value: liveHz))
                Text("Hz")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Button(action: commitGuess) {
                ZStack {
                    Circle().fill(.white)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.black)
                }
                .frame(width: 64, height: 64)
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 22)
    }

    // MARK: - Drag → frequency

    @State private var dragStartLogHz: Double = log2(440)

    private func handleDrag(translationY: CGFloat, began: Bool) {
        if began {
            dragStartLogHz = log2(liveHz)
            dragInProgress = true
            tone.play(frequency: liveHz)
        }
        // 1800pt of vertical pull == one full sweep across the entire range
        // (log-space, 80 → 1200 ≈ 3.9 octaves). Generous so users can
        // fine-tune in a small region. Inverted: dragging up = up in pitch.
        let span = SoundRange.logMax - SoundRange.logMin
        let deltaLogHz = -Double(translationY) / 1800.0 * span
        let newLog = max(SoundRange.logMin,
                         min(SoundRange.logMax, dragStartLogHz + deltaLogHz))
        liveHz = pow(2.0, newLog)
        tone.setFrequency(liveHz)
    }

    // MARK: - Result
    //
    // Single full-screen black background with the target frequency's
    // wavelength behind everything. Score + verdict pinned top-right; target
    // (gray) fades in above the user's guess (white) at the bottom-left.

    @ViewBuilder
    private var resultBackground: some View {
        ZStack {
            Color.black
            WavelengthView(frequency: model.currentTargetHz, energy: 0.85)
        }
        .ignoresSafeArea()
    }

    private var resultOverlay: some View {
        ZStack(alignment: .topLeading) {
            // Round indicator top-left
            VStack {
                HStack {
                    roundIndicator
                    Spacer()
                }
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)

            // Score + verdict top-right
            VStack(alignment: .trailing, spacing: 6) {
                Text(String(format: "%.2f", model.displayedScore))
                    .font(.system(size: 64, weight: .black))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText(value: model.displayedScore))
                Text(soundVerdict(model.revealedScore))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .frame(maxWidth: 240, alignment: .trailing)
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            // Target (faded gray, fades in) above user guess (bright white)
            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("TARGET")
                        .font(.system(size: 11, weight: .bold))
                        .kerning(1.6)
                        .foregroundStyle(.white.opacity(0.45))
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(String(format: "%.2f", model.currentTargetHz))
                            .font(.system(size: 60, weight: .black))
                            .foregroundStyle(.white.opacity(0.42))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                        Text("Hz")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                .opacity(targetRevealOpacity)

                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(String(format: "%.2f", model.guessHz))
                        .font(.system(size: 60, weight: .black))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                    Text("Hz")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.bottom, 18)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            // Next button bottom-right
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: { SoundPlayer.haptic(.medium); model.nextRound() }) {
                        ZStack {
                            Circle().fill(.white)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.black)
                        }
                        .frame(width: 60, height: 60)
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
    }

    // MARK: - Phase orchestration

    private func startPhase(_ phase: Phase) {
        invalidateAll()
        switch phase {
        case .ready:
            introOpacity = 0
            model.displayedScore = 0
            withAnimation(.easeInOut(duration: 0.5)) { introOpacity = 1 }
            // No beeps in sound mode — the user is about to hear a target tone
            // and we don't want to muddy their ears. Haptics only.
            SoundPlayer.haptic(.light)
            schedule(after: 0.85) {
                withAnimation(.easeInOut(duration: 0.18)) { model.phase = .set }
            }
        case .set:
            SoundPlayer.haptic(.light)
            schedule(after: 0.7) {
                withAnimation(.easeInOut(duration: 0.18)) { model.phase = .go }
            }
        case .go:
            SoundPlayer.haptic(.medium)
            schedule(after: 0.7) { model.phase = .memorize }
        case .memorize:
            startMemorize()
        case .guess:
            // Start the user at a random Hz so they're not anchored anywhere
            // near the target. Log-space sample for perceptual uniformity.
            var rng = SplitMix64(seed: UInt64.random(in: 1...UInt64.max))
            liveHz = pow(2.0, rng.double(in: SoundRange.logMin...SoundRange.logMax))
            model.guessHz = liveHz
        case .result:
            tone.stop()
            targetRevealOpacity = 0
            withAnimation(.easeInOut(duration: 0.7).delay(0.15)) {
                targetRevealOpacity = 1
            }
            animateScoreCountUp()
        case .fadeToBlack, .revealFromBlack:
            // Sound mode skips the black-fade phases; route forward.
            model.phase = .memorize
        }
    }

    private func startMemorize() {
        // Sound runs much shorter than color: 2s easy, 1s hard.
        let totalSeconds: Double = (model.difficulty == .hard) ? 1.0 : 2.0
        let totalMs: Double = totalSeconds * 1000
        let totalCs = Int(totalSeconds * 100)
        model.memorizeRemainingCs = totalCs
        // Start the target tone for the entire memorize window.
        tone.play(frequency: model.currentTargetHz, gain: 0.32)
        let start = Date()
        SoundPlayer.haptic(.light)
        memorizeTimer?.invalidate()
        memorizeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            Task { @MainActor in
                let elapsed = Date().timeIntervalSince(start) * 1000
                let remainingMs = max(0, totalMs - elapsed)
                model.memorizeRemainingCs = Int(remainingMs / 10)
                if remainingMs <= 0 {
                    memorizeTimer?.invalidate()
                    memorizeTimer = nil
                    model.memorizeRemainingCs = 0
                    tone.stop()
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
        tone.stop()
        model.guessHz = liveHz
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
