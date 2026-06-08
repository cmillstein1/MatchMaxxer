import SwiftUI
import UIKit

// Diagonal triangle clip for the color guess-vs-target swatch.
struct TopLeftTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

struct FinalSummaryView: View {
    @Bindable var model: GameModel
    var onPlayAgainSameSeed: () -> Void
    var onMenu: () -> Void

    @State private var showLocalLeaderboard = false
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?
    @State private var initialsDraft: String = ""
    @FocusState private var initialsFocused: Bool
    @Bindable var leaderboard = LeaderboardManager.shared
    private var prefs: UserPrefs { UserPrefs.shared }

    private var solo: Bool { model.players.count <= 1 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                topBar
                if solo, let me = model.players.first {
                    soloCard(player: me)
                } else {
                    ScrollView {
                        VStack(spacing: 18) {
                            ForEach(0..<rankedPlayers.count, id: \.self) { i in
                                let entry = rankedPlayers[i]
                                playerCard(player: entry.player, rank: entry.rank)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                bottomButtons
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 18)
        }
        .onAppear {
            initialsDraft = prefs.initials
            let submitted = solo ? model.players.first?.total : rankedPlayers.first?.player.total
            if let s = submitted {
                leaderboard.submit(
                    score: s,
                    difficulty: model.difficulty.rawValue,
                    category: model.category.slug
                )
            }
        }
        .sheet(isPresented: $showLocalLeaderboard) {
            LocalLeaderboardView(manager: leaderboard,
                                 category: model.category) { showLocalLeaderboard = false }
        }
        .sheet(isPresented: $showShareSheet) {
            if let img = shareImage {
                ShareSheet(items: [img, "I scored \(scoreString)/50 on MatchMaxxer."])
            }
        }
    }

    // MARK: - Header / footer

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(solo ? "Round complete" : "Final standings")
                    .font(.system(size: 12, weight: .black))
                    .kerning(1.6)
                    .foregroundStyle(.white.opacity(0.55))
                Text(headerSubtitle)
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(.white)
            }
            Spacer()
            Button(action: onMenu) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Circle().fill(.white.opacity(0.10)))
            }
        }
    }

    private var headerSubtitle: String {
        "\(model.category.displayName) · \(model.difficulty.rawValue)"
    }

    private var bottomButtons: some View {
        VStack(spacing: 12) {
            // Primary CTA: post the score
            Button(action: { SoundPlayer.haptic(.medium); presentShare() }) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .bold))
                    Text("Post score & challenge")
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Capsule().fill(.white))
            }
            .buttonStyle(PressableButtonStyle())

            // Inline initials text field — used on the leaderboard + share card
            initialsField

            // Utility row: Leaderboard + Play again
            HStack(spacing: 10) {
                Button(action: { SoundPlayer.haptic(.light); showLocalLeaderboard = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                            .font(.system(size: 13, weight: .bold))
                        Text("Leaderboard")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(.white.opacity(0.10)))
                }
                .buttonStyle(PressableButtonStyle())
                Button(action: { SoundPlayer.haptic(.light); onPlayAgainSameSeed() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 13, weight: .bold))
                        Text("Play again")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(.white.opacity(0.10)))
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
    }

    private var initialsField: some View {
        HStack(spacing: 10) {
            Text("INITIALS")
                .font(.system(size: 11, weight: .black))
                .kerning(1.6)
                .foregroundStyle(.white.opacity(0.55))
            TextField("ABC", text: $initialsDraft)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($initialsFocused)
                .submitLabel(.done)
                .onChange(of: initialsDraft) { _, new in
                    let cleaned = UserPrefs.sanitize(new)
                    if cleaned != new { initialsDraft = cleaned }
                    prefs.initials = cleaned
                }
                .onSubmit { initialsFocused = false }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(initialsFocused
                                ? .white.opacity(0.45)
                                : .white.opacity(0.15), lineWidth: 1)
                )
        )
    }

    private func verdictFor(_ avg: Double) -> String {
        switch model.category {
        case .color: return scoreVerdict(avg)
        case .sound: return soundVerdict(avg)
        case .hex:   return hexVerdict(avg)
        case .time:  return timeVerdict(avg)
        case .shape: return shapeVerdict(avg)
        }
    }

    // MARK: - Solo card (Dialed-style hero)

    private func soloCard(player: PlayerScorecard) -> some View {
        let total = player.total
        let avg = player.rounds.isEmpty ? 0 : total / Double(player.rounds.count)
        let verdict = verdictFor(avg)
        return VStack(alignment: .leading, spacing: 14) {
            Text(verdict)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            rankLine(score: total)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(String(format: "%.2f", total))
                    .font(.system(size: 76, weight: .black))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("/ 50")
                    .font(.system(size: 32, weight: .black))
                    .foregroundStyle(.white.opacity(0.40))
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rankLine(score: Double) -> some View {
        // Local rank: how many of the player's local plays beat or equal this
        // score. Real worldwide rank is delegated to the GameKit leaderboard
        // sheet (which we link from the buttons below).
        let category = model.category.slug
        let history = leaderboard.localHistory.filter { $0.category == category }
        let total = history.count
        let rank = max(1, history.filter { $0.score > score }.count + 1)
        return HStack(spacing: 6) {
            Text("#\(rank.formatted())")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(.yellow)
                .monospacedDigit()
            Text("of \(total.formatted()) \(total == 1 ? "play" : "plays")")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    @ViewBuilder
    private func roundCell(_ round: PlayerRound, index: Int) -> some View {
        VStack(spacing: 4) {
            ZStack {
                if model.category == .color, model.targets.indices.contains(index) {
                    ZStack {
                        model.targets[index].color
                        round.guess.color.clipShape(TopLeftTriangle())
                    }
                } else if model.category == .hex, model.hexTargets.indices.contains(index) {
                    ZStack {
                        model.hexTargets[index].color
                        round.guess.color.clipShape(TopLeftTriangle())
                    }
                } else if model.category == .sound, model.targetFreqs.indices.contains(index) {
                    ZStack {
                        Color(red: 0.05, green: 0.06, blue: 0.10)
                        WavelengthView(frequency: model.targetFreqs[index],
                                       energy: 0.85, paused: true)
                    }
                } else if model.category == .time, model.targetDurations.indices.contains(index) {
                    ZStack {
                        Color(red: 0.05, green: 0.06, blue: 0.10)
                        VortexView(energy: 0.7, paused: true)
                        VStack {
                            Spacer()
                            Text(String(format: "%.1fs", model.targetDurations[index]))
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(.white.opacity(0.85))
                                .monospacedDigit()
                                .shadow(color: .black.opacity(0.6), radius: 1.5, y: 0.5)
                        }
                        .padding(6)
                    }
                } else if model.category == .shape, let gs = round.guessShape {
                    ShapeResultMini(transform: gs)
                } else {
                    Color.white.opacity(0.05)
                }
                VStack {
                    HStack {
                        Text(String(format: "%.2f", round.score))
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .shadow(color: .black.opacity(0.6), radius: 1.5, y: 0.5)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(6)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.45))
                .monospacedDigit()
        }
    }

    // MARK: - Multiplayer cards

    private struct RankedEntry {
        let player: PlayerScorecard
        let rank: Int
    }

    private var rankedPlayers: [RankedEntry] {
        let sorted = model.players.sorted { $0.total > $1.total }
        return sorted.enumerated().map { RankedEntry(player: $0.element, rank: $0.offset + 1) }
    }

    @ViewBuilder
    private func playerCard(player: PlayerScorecard, rank: Int) -> some View {
        let isWinner = rank == 1 && !solo
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("#\(rank)")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(isWinner ? .yellow : .white.opacity(0.55))
                Text(player.name)
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(.white)
                if isWinner {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.yellow)
                }
                Spacer()
                Text(String(format: "%.2f", player.total))
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text("/ 50")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.40))
            }
            HStack(spacing: 6) {
                ForEach(player.rounds.indices, id: \.self) { i in
                    roundCell(player.rounds[i], index: i)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(isWinner ? 0.10 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(isWinner ? 0.22 : 0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - Share

    private var scoreString: String {
        String(format: "%.2f", solo ? (model.players.first?.total ?? 0) : rankedPlayers.first?.player.total ?? 0)
    }

    private func presentShare() {
        guard let me = (solo ? model.players.first : rankedPlayers.first?.player) else { return }
        let avg = me.rounds.isEmpty ? 0 : me.total / Double(me.rounds.count)
        let card = ShareCardView(
            total: me.total,
            outOf: 50,
            verdict: verdictFor(avg),
            category: model.category,
            difficulty: model.difficulty.rawValue,
            initials: prefs.initials,
            rounds: me.rounds,
            targetsColor: model.targets,
            targetsHz: model.targetFreqs,
            targetsHex: model.hexTargets,
            targetsDuration: model.targetDurations
        )
        // Note: per-round shape guesses live on the rounds themselves.
        if let img = renderShareCard(card) {
            shareImage = img
            showShareSheet = true
        }
    }
}

// MARK: - Initials editor sheet

struct InitialsEditorView: View {
    var onClose: () -> Void
    @State private var draft: String = ""
    private var prefs: UserPrefs { UserPrefs.shared }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your initials")
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(.white)
                        Text("Up to 3 characters. Used on the leaderboard and share cards.")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Circle().fill(.white.opacity(0.10)))
                    }
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(.white.opacity(0.18), lineWidth: 1)
                        )
                        .frame(height: 140)
                    TextField("ABC", text: $draft)
                        .font(.system(size: 56, weight: .black))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: draft) { _, new in
                            draft = UserPrefs.sanitize(new)
                        }
                        .padding(.horizontal, 22)
                }

                Spacer()

                Button(action: {
                    SoundPlayer.haptic(.medium)
                    prefs.initials = draft
                    onClose()
                }) {
                    Text("Save")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(PressableButtonStyle())
                .opacity(draft.isEmpty ? 0.4 : 1)
                .disabled(draft.isEmpty)
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 18)
        }
        .onAppear { draft = prefs.initials }
    }
}
