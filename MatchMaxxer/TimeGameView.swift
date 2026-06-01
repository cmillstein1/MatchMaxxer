import SwiftUI

// Time mode: ready/set/go intro → observe (the vortex swirls and a low hum
// plays for the target duration, with NO on-screen clock so the player has to
// *feel* the interval) → reproduce (press and hold; the hum + vortex come back
// to life while held, release locks in the elapsed time) → result.
//
// Same five-round / count-up scoring scaffolding as the other modes.
struct TimeGameView: View {
    @Bindable var model: GameModel
    @State private var phaseTimer: Timer?
    @State private var scoreTimer: Timer?
    @State private var introOpacity: Double = 0

    // Reproduction state. `pressStart` is non-nil only while a finger is down.
    @State private var pressStart: Date? = nil
    @State private var isHolding: Bool = false
    @State private var targetRevealOpacity: Double = 0

    // The low hum frequency — felt more than heard, so the player focuses on
    // duration rather than pitch.
    private let humHz: Double = 68
    // Ignore stray taps shorter than this so a fumble doesn't end the round.
    private let minHold: Double = 0.3

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
            // A faint, slowly drifting vortex under the countdown.
            VortexView(energy: 0.22)
                .ignoresSafeArea()
                .opacity(introOpacity)
        case .memorize:
            VortexView(energy: 1.0)
                .ignoresSafeArea()
                .opacity(introOpacity)
        case .guess:
            // Frozen + dim until the player holds; alive while held.
            VortexView(energy: isHolding ? 1.0 : 0.16, paused: !isHolding)
                .ignoresSafeArea()
        case .result:
            VortexView(energy: 0.5, paused: true)
                .ignoresSafeArea()
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

    // Observe phase: deliberately NO numeric clock — just the round indicator and
    // a quiet prompt. The player has to internalize how long the interval feels.
    private var memorizeOverlay: some View {
        VStack {
            HStack(alignment: .top) {
                roundIndicator
                Spacer()
                Text("observe")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(.white.opacity(0.85))
                    .kerning(-0.5)
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

    // MARK: - Reproduce (press & hold)

    private var guessOverlay: some View {
        ZStack {
            // Full-screen hold surface.
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if pressStart == nil { beginHold() }
                        }
                        .onEnded { _ in endHold() }
                )

            VStack {
                HStack {
                    roundIndicator
                    Spacer()
                    Text(model.players.count > 1 ? model.currentPlayer.name : "MatchMaxxer")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)

                Spacer()

                // Prompt swaps between the instruction and a live "holding…"
                // pulse — but never a number.
                VStack(spacing: 10) {
                    Image(systemName: isHolding ? "hand.tap.fill" : "hand.tap")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.white.opacity(isHolding ? 0.95 : 0.6))
                    Text(isHolding ? "Release when the time feels right"
                                   : "Press and hold for the same duration")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white.opacity(isHolding ? 0.95 : 0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 64)
                .allowsHitTesting(false)
            }
        }
    }

    private func beginHold() {
        pressStart = Date()
        withAnimation(.easeOut(duration: 0.25)) { isHolding = true }
        tone.play(frequency: humHz, gain: 0.30)
        SoundPlayer.haptic(.medium)
    }

    private func endHold() {
        guard let start = pressStart else { return }
        let elapsed = Date().timeIntervalSince(start)
        // Too-short presses are treated as fumbles: reset and let them try again.
        guard elapsed >= minHold else {
            pressStart = nil
            withAnimation(.easeOut(duration: 0.2)) { isHolding = false }
            tone.stop()
            return
        }
        pressStart = nil
        withAnimation(.easeOut(duration: 0.2)) { isHolding = false }
        tone.stop()
        SoundPlayer.play(.lock)
        SoundPlayer.haptic(.medium)
        model.guessDuration = elapsed
        model.submitGuess()
    }

    // MARK: - Result

    private var resultOverlay: some View {
        ZStack(alignment: .topLeading) {
            VStack {
                HStack {
                    roundIndicator
                    Spacer()
                }
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)

            // Score + verdict top-right.
            VStack(alignment: .trailing, spacing: 6) {
                Text(String(format: "%.2f", model.displayedScore))
                    .font(.system(size: 64, weight: .black))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText(value: model.displayedScore))
                Text(timeVerdict(model.revealedScore))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .frame(maxWidth: 240, alignment: .trailing)
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            // Target (faded, fades in) above the player's reproduction.
            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("TARGET")
                        .font(.system(size: 11, weight: .bold))
                        .kerning(1.6)
                        .foregroundStyle(.white.opacity(0.45))
                    durationText(model.currentTargetDuration,
                                 color: .white.opacity(0.42))
                }
                .opacity(targetRevealOpacity)

                VStack(alignment: .leading, spacing: 2) {
                    Text("YOU")
                        .font(.system(size: 11, weight: .bold))
                        .kerning(1.6)
                        .foregroundStyle(.white.opacity(0.55))
                    durationText(model.guessDuration, color: .white)
                }
                .padding(.bottom, 18)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            // Next button bottom-right.
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

    private func durationText(_ seconds: Double, color: Color) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 3) {
            Text(String(format: "%.2f", seconds))
                .font(.system(size: 60, weight: .black))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text("s")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(color.opacity(0.7))
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
            startObserve()
        case .guess:
            pressStart = nil
            isHolding = false
        case .result:
            tone.stop()
            targetRevealOpacity = 0
            withAnimation(.easeInOut(duration: 0.7).delay(0.15)) {
                targetRevealOpacity = 1
            }
            animateScoreCountUp()
        case .fadeToBlack, .revealFromBlack:
            // Time mode skips the black-fade phases; route forward.
            model.phase = .memorize
        }
    }

    // Play the hum + swirl the vortex for exactly the target duration, then cut
    // to the reproduction phase.
    private func startObserve() {
        let seconds = model.currentTargetDuration
        introOpacity = 1
        tone.play(frequency: humHz, gain: 0.30)
        SoundPlayer.haptic(.light)
        schedule(after: seconds) {
            tone.stop()
            SoundPlayer.haptic(.rigid)
            withAnimation(.easeInOut(duration: 0.35)) {
                model.phase = .guess
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

    private func schedule(after seconds: TimeInterval, _ block: @escaping () -> Void) {
        phaseTimer?.invalidate()
        phaseTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            Task { @MainActor in block() }
        }
    }

    private func invalidateAll() {
        phaseTimer?.invalidate(); phaseTimer = nil
        scoreTimer?.invalidate(); scoreTimer = nil
    }
}
