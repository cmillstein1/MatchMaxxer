import SwiftUI

// Shape mode: a regular conic-filled shape appears centered, then animates to
// its target position / size / orientation while a countdown runs (memorize).
// The shape snaps back to neutral and the player pinches (scale), two-finger
// rotates (orientation), and drags (position) to recreate it. "Done" reveals a
// dashed outline of the target overlaid on the player's shape; tap to zoom out.
struct ShapeGameView: View {
    @Bindable var model: GameModel
    @State private var phaseTimer: Timer?
    @State private var memorizeTimer: Timer?
    @State private var scoreTimer: Timer?

    // What's shown during the ready/memorize reveal. Animates from neutral to
    // the target transform.
    @State private var revealTransform: ShapeTransform = .regular

    // Committed guess components; live gesture deltas are layered on top.
    @State private var committedScale: CGFloat = 1
    @State private var committedRotation: Double = 0      // degrees
    @State private var committedPos = CGPoint(x: 0.5, y: 0.5)
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var twist: Angle = .zero
    @GestureState private var drag: CGSize = .zero

    @State private var playSize: CGSize = .zero
    @State private var targetRevealOpacity: Double = 0
    @State private var resultZoomedIn = false

    private let baseSize: CGFloat = 150
    private let minScale: CGFloat = 0.3
    private let maxScale: CGFloat = 2.6

    private var target: ShapeTransform { model.currentTargetShape }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                GridView()
                    .ignoresSafeArea()
                contentLayer
                overlayLayer
            }
            .onAppear {
                playSize = geo.size
                startPhase(model.phase)
            }
            .onChange(of: geo.size) { _, s in playSize = s }
            .onChange(of: model.phase) { _, p in startPhase(p) }
            .onDisappear { invalidateAll() }
        }
    }

    // MARK: - Shape rendering

    private var liveGuess: ShapeTransform {
        let dxNorm = playSize.width > 0 ? Double(drag.width / playSize.width) : 0
        let dyNorm = playSize.height > 0 ? Double(drag.height / playSize.height) : 0
        let effScale = min(maxScale, max(minScale, committedScale * pinch))
        return ShapeTransform(
            type: target.type,
            position: CGPoint(x: committedPos.x + dxNorm, y: committedPos.y + dyNorm),
            scale: Double(effScale),
            rotation: committedRotation + twist.degrees
        )
    }

    private func shapeNode(_ tf: ShapeTransform) -> some View {
        ShapeMark(type: tf.type)
            .fill(GameShape.rainbow)
            .frame(width: baseSize * tf.scale, height: baseSize * tf.scale)
            .rotationEffect(.degrees(tf.rotation))
            .position(x: tf.position.x * playSize.width,
                      y: tf.position.y * playSize.height)
    }

    private func dashedOutline(_ tf: ShapeTransform) -> some View {
        ShapeMark(type: tf.type)
            .stroke(style: StrokeStyle(lineWidth: 2, lineJoin: .round, dash: [6, 7]))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: baseSize * tf.scale, height: baseSize * tf.scale)
            .rotationEffect(.degrees(tf.rotation))
            .position(x: tf.position.x * playSize.width,
                      y: tf.position.y * playSize.height)
    }

    @ViewBuilder
    private var contentLayer: some View {
        switch model.phase {
        case .ready, .set, .go, .memorize:
            shapeNode(revealTransform)
        case .guess:
            ZStack {
                shapeNode(liveGuess)
                // Full-screen surface so pinch / rotate / drag work anywhere.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(manipulationGesture)
            }
        case .result:
            resultContent
        case .fadeToBlack, .revealFromBlack:
            EmptyView()
        }
    }

    // Grid + shapes, zoomable on the result screen.
    private var resultContent: some View {
        ZStack {
            dashedOutline(target).opacity(targetRevealOpacity)
            shapeNode(model.guessShape)
        }
        .scaleEffect(resultZoomedIn ? 1.9 : 1.0,
                     anchor: UnitPoint(x: target.position.x, y: target.position.y))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.5)) { resultZoomedIn.toggle() }
        }
    }

    // MARK: - Gestures

    private var manipulationGesture: some Gesture {
        let dragG = DragGesture()
            .updating($drag) { v, s, _ in s = v.translation }
            .onEnded { v in
                guard playSize.width > 0, playSize.height > 0 else { return }
                committedPos.x = min(0.97, max(0.03, committedPos.x + v.translation.width / playSize.width))
                committedPos.y = min(0.97, max(0.03, committedPos.y + v.translation.height / playSize.height))
            }
        let magnify = MagnifyGesture()
            .updating($pinch) { v, s, _ in s = v.magnification }
            .onEnded { v in
                committedScale = min(maxScale, max(minScale, committedScale * v.magnification))
            }
        let rotate = RotateGesture()
            .updating($twist) { v, s, _ in s = v.rotation }
            .onEnded { v in committedRotation += v.rotation.degrees }
        return dragG.simultaneously(with: magnify).simultaneously(with: rotate)
    }

    // MARK: - Overlays

    @ViewBuilder
    private var overlayLayer: some View {
        switch model.phase {
        case .memorize:
            memorizeOverlay
        case .guess:
            guessOverlay
        case .result:
            resultOverlay
        default:
            roundOnlyOverlay
        }
    }

    private var roundIndicator: some View {
        Text("\(model.roundIndex + 1) / \(model.totalRounds)")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white.opacity(0.75))
    }

    private var roundOnlyOverlay: some View {
        VStack {
            HStack { roundIndicator; Spacer() }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var memorizeOverlay: some View {
        VStack {
            HStack(alignment: .top) {
                roundIndicator
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%03d", model.memorizeRemainingCs))
                        .font(.system(size: 76, weight: .black))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("seconds to remember scale,\nrotation and position")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.trailing)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var guessOverlay: some View {
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

            HStack {
                Text("Pinch, rotate & drag to match")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Button(action: commitGuess) {
                    ZStack {
                        Circle().fill(.white)
                        Image(systemName: "target")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.black)
                    }
                    .frame(width: 64, height: 64)
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .allowsHitTesting(true)
    }

    private var resultOverlay: some View {
        ZStack(alignment: .topLeading) {
            VStack { HStack { roundIndicator; Spacer() }; Spacer() }
                .padding(.horizontal, 22).padding(.top, 14)

            // Score + verdict + a little "target" pointer toward the dashed shape.
            VStack(alignment: .trailing, spacing: 6) {
                Text(String(format: "%.2f", model.displayedScore))
                    .font(.system(size: 64, weight: .black))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText(value: model.displayedScore))
                Text(shapeVerdict(model.revealedScore))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .frame(maxWidth: 240, alignment: .trailing)
                Text(resultZoomedIn ? "tap to zoom out" : "tap to zoom in")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .allowsHitTesting(false)

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

    // MARK: - Phase orchestration

    private func startPhase(_ phase: Phase) {
        invalidateAll()
        switch phase {
        case .ready:
            // Show the neutral shape, then send it to its target + start the
            // countdown. Shape mode skips the visible ready/set/go words.
            model.displayedScore = 0
            revealTransform = target.reset()
            SoundPlayer.haptic(.light)
            schedule(after: 1.2) { model.phase = .memorize }
        case .set, .go:
            // Unused in shape mode; route forward defensively.
            model.phase = .memorize
        case .memorize:
            startMemorize()
        case .guess:
            committedScale = 1
            committedRotation = 0
            committedPos = CGPoint(x: 0.5, y: 0.5)
        case .result:
            // Start framed on the whole grid, then ease in toward the target so
            // the reveal lands gently instead of snapping.
            targetRevealOpacity = 0
            resultZoomedIn = false
            withAnimation(.easeInOut(duration: 0.6).delay(0.3)) { targetRevealOpacity = 1 }
            withAnimation(.easeInOut(duration: 1.3).delay(0.15)) { resultZoomedIn = true }
            animateScoreCountUp()
        case .fadeToBlack, .revealFromBlack:
            model.phase = .memorize
        }
    }

    private func startMemorize() {
        // Animate the neutral shape into its target transform, then count down.
        withAnimation(.easeInOut(duration: 0.8)) { revealTransform = target }

        let totalSeconds: Double = (model.difficulty == .hard) ? 3.0 : 5.0
        let totalMs = totalSeconds * 1000
        model.memorizeRemainingCs = Int(totalSeconds * 100)
        SoundPlayer.haptic(.light)

        // Start the clock once the reveal settles.
        let revealDelay = 0.85
        phaseTimer = Timer.scheduledTimer(withTimeInterval: revealDelay, repeats: false) { _ in
            Task { @MainActor in
                let start = Date()
                var lastBeatSecond = Int(totalSeconds)
                SoundPlayer.play(.tick)
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
                            withAnimation(.easeInOut(duration: 0.35)) { model.phase = .guess }
                        }
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
        model.guessShape = liveGuess
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
