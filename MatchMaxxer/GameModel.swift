import SwiftUI
import Observation

enum GameCategory: Identifiable, Hashable {
    case color
    case sound
    case hex
    case time
    case shape

    var id: String { slug }

    var slug: String {
        switch self {
        case .color: return "color"
        case .sound: return "sound"
        case .hex:   return "hex"
        case .time:  return "time"
        case .shape: return "shape"
        }
    }

    var displayName: String {
        switch self {
        case .color: return "Color"
        case .sound: return "Sound"
        case .hex:   return "Hex"
        case .time:  return "Time"
        case .shape: return "Shape"
        }
    }
}

enum Difficulty: String, CaseIterable, Identifiable {
    case easy = "Easy"
    case hard = "Hard"
    var id: String { rawValue }
}

enum PlayMode {
    case solo
    case multi(playerCount: Int)
    var playerCount: Int {
        if case .multi(let n) = self { return n }
        return 1
    }
}

enum Screen: Equatable {
    case menu
    case instructions(GameCategory)
    case audioGate
    case handoff(playerIndex: Int)
    case game
    case finalSummary
}

enum Phase: Equatable {
    case ready
    case set
    case go
    case fadeToBlack
    case revealFromBlack
    case memorize
    case guess
    case result
}

struct PlayerRound: Identifiable {
    let id = UUID()
    var guess: HSB = .neutral
    var guessHz: Double = 440
    var guessDuration: Double = 0
    var guessShape: ShapeTransform? = nil
    var score: Double
}

struct PlayerScorecard: Identifiable {
    let id = UUID()
    var name: String
    var rounds: [PlayerRound] = []
    var total: Double { rounds.reduce(0) { $0 + $1.score } }
}

@MainActor
@Observable
final class GameModel {
    var screen: Screen = .menu
    var category: GameCategory = .color
    var difficulty: Difficulty = .easy
    var mode: PlayMode = .solo

    var seed: UInt64 = 0
    var targets: [HSB] = []
    var distractors: [HSB] = []
    var targetFreqs: [Double] = []
    var hexTargets: [HSB] = []
    var targetDurations: [Double] = []
    var targetShapes: [ShapeTransform] = []

    var roundIndex: Int = 0
    var phase: Phase = .ready
    var phaseStart: Date = .now

    var currentPlayerIndex: Int = 0
    var players: [PlayerScorecard] = []

    var guess: HSB = .neutral
    var guessHz: Double = 440
    var guessDuration: Double = 0
    var guessShape: ShapeTransform = .regular
    var memorizeRemainingCs: Int = 500
    var displayedScore: Double = 0
    var revealedScore: Double = 0

    let totalRounds: Int = 5

    var currentTarget: HSB {
        category == .hex ? hexTargets[roundIndex] : targets[roundIndex]
    }
    var currentTargetHz: Double { targetFreqs[roundIndex] }
    var currentTargetDuration: Double { targetDurations[roundIndex] }
    var currentTargetShape: ShapeTransform { targetShapes[roundIndex] }
    var currentDistractors: [HSB] {
        Array(distractors[roundIndex * 3 ..< roundIndex * 3 + 3])
    }
    var currentPlayer: PlayerScorecard {
        get { players[currentPlayerIndex] }
        set { players[currentPlayerIndex] = newValue }
    }

    func startCategory(_ cat: GameCategory) {
        category = cat
        screen = .instructions(cat)
    }

    func backToMenu() {
        screen = .menu
        roundIndex = 0
        currentPlayerIndex = 0
        players = []
    }

    func startGame() {
        seed = UInt64.random(in: 1...UInt64.max)
        targets = HSB.distinctSequence(count: totalRounds, seed: seed)
        var distractorRng = SplitMix64(seed: seed &+ 1)
        distractors = (0..<(totalRounds * 3)).map { _ in
            HSB(
                h: distractorRng.double(in: 0..<360),
                s: distractorRng.double(in: 35...92),
                b: distractorRng.double(in: 32...82)
            )
        }
        var freqRng = SplitMix64(seed: seed &+ 2)
        targetFreqs = (0..<totalRounds).map { _ in randomTargetHz(using: &freqRng) }
        var hexRng = SplitMix64(seed: seed &+ 3)
        hexTargets = (0..<totalRounds).map { _ in
            HSB(
                h: hexRng.double(in: 0..<360),
                s: hexRng.double(in: 25...100),
                b: hexRng.double(in: 22...95)
            )
        }
        var durationRng = SplitMix64(seed: seed &+ 4)
        targetDurations = (0..<totalRounds).map { _ in
            randomTargetDuration(difficulty: difficulty, using: &durationRng)
        }
        var shapeRng = SplitMix64(seed: seed &+ 5)
        targetShapes = (0..<totalRounds).map { _ in
            randomShapeTransform(using: &shapeRng)
        }
        players = (0..<mode.playerCount).map { i in
            PlayerScorecard(name: mode.playerCount == 1 ? "You" : "Player \(i + 1)")
        }
        roundIndex = 0
        currentPlayerIndex = 0
        // Sound and Time both play audio (tones / a low hum), so they show the
        // audio-gate screen first — it lets the user unmute / grab headphones
        // and primes the audio session with a user gesture.
        if category == .sound || category == .time {
            screen = .audioGate
        } else if mode.playerCount > 1 {
            screen = .handoff(playerIndex: 0)
        } else {
            beginRound()
        }
    }

    func proceedAfterAudioGate() {
        if mode.playerCount > 1 {
            screen = .handoff(playerIndex: 0)
        } else {
            beginRound()
        }
    }

    func beginRound() {
        guess = .neutral
        phase = .ready
        phaseStart = .now
        screen = .game
    }

    func advanceFromHandoff() {
        beginRound()
    }

    func submitGuess() {
        let s: Double
        let round: PlayerRound
        switch category {
        case .color, .hex:
            s = score(guess: guess, target: currentTarget)
            round = PlayerRound(guess: guess, score: s)
        case .sound:
            s = scoreSound(guessHz: guessHz, targetHz: currentTargetHz)
            round = PlayerRound(guessHz: guessHz, score: s)
        case .time:
            s = scoreTime(guess: guessDuration, target: currentTargetDuration)
            round = PlayerRound(guessDuration: guessDuration, score: s)
        case .shape:
            s = scoreShape(guess: guessShape, target: currentTargetShape)
            round = PlayerRound(guessShape: guessShape, score: s)
        }
        players[currentPlayerIndex].rounds.append(round)
        revealedScore = s
        displayedScore = 0
        phase = .result
    }

    func nextRound() {
        if roundIndex + 1 < totalRounds {
            roundIndex += 1
            beginRound()
        } else if currentPlayerIndex + 1 < players.count {
            currentPlayerIndex += 1
            roundIndex = 0
            screen = .handoff(playerIndex: currentPlayerIndex)
        } else {
            screen = .finalSummary
        }
    }

    func playAgainSameSeed() {
        players = (0..<mode.playerCount).map { i in
            PlayerScorecard(name: mode.playerCount == 1 ? "You" : "Player \(i + 1)")
        }
        roundIndex = 0
        currentPlayerIndex = 0
        if mode.playerCount > 1 {
            screen = .handoff(playerIndex: 0)
        } else {
            beginRound()
        }
    }
}
