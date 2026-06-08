import SwiftUI

struct ContentView: View {
    @State private var model = GameModel()
    @Bindable private var leaderboard = LeaderboardManager.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            screenView
                .id(screenId)
                .transition(.opacity)
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.45), value: screenId)
        // Global leaderboard consent. Attached at the root so it can surface
        // whenever the user signs into Game Center, not just after a game.
        .alert("Share to global leaderboard?", isPresented: $leaderboard.showConsentPrompt) {
            Button("Not now", role: .cancel) { leaderboard.declineGlobalConsent() }
            Button("Share my scores") { leaderboard.grantGlobalConsent() }
        } message: {
            Text("Post your scores to the worldwide Game Center leaderboard so you can compete with other players? Your Game Center alias and scores will be visible to others. Your scores are always saved on this device either way, and you can change this anytime from the leaderboard.")
        }
    }

    private var screenId: String {
        switch model.screen {
        case .menu: return "menu"
        case .instructions: return "instructions"
        case .audioGate: return "audioGate"
        case .handoff(let i): return "handoff-\(i)"
        case .game: return "game"
        case .finalSummary: return "summary"
        }
    }

    @ViewBuilder
    private var screenView: some View {
        switch model.screen {
        case .menu:
            MenuView { cat in model.startCategory(cat) }
        case .instructions:
            InstructionsView(
                model: model,
                onBack: { model.backToMenu() },
                onStart: { model.startGame() }
            )
        case .audioGate:
            AudioGateView(onProceed: { model.proceedAfterAudioGate() })
        case .handoff(let i):
            HandoffView(
                playerName: model.players[i].name,
                playerNumber: i + 1,
                totalPlayers: model.players.count,
                isFirst: i == 0,
                previousScores: previousScores(upTo: i),
                onContinue: { model.advanceFromHandoff() }
            )
        case .game:
            switch model.category {
            case .color: GameView(model: model)
            case .sound: SoundGameView(model: model)
            case .hex:   HexGameView(model: model)
            case .time:  TimeGameView(model: model)
            case .shape: ShapeGameView(model: model)
            }
        case .finalSummary:
            FinalSummaryView(
                model: model,
                onPlayAgainSameSeed: { model.playAgainSameSeed() },
                onMenu: { model.backToMenu() }
            )
        }
    }

    private func previousScores(upTo index: Int) -> [(name: String, total: Double)] {
        guard index > 0 else { return [] }
        return (0..<index).map { i in (model.players[i].name, model.players[i].total) }
    }
}

#Preview {
    ContentView()
}
