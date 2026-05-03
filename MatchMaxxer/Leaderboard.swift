import GameKit
import SwiftUI

// Stable identifier the user must also create in App Store Connect under
// Game Center > Leaderboards. Until that's set up, GKLeaderboard.submitScore
// will return an error and we fall back to the local-only history.
enum LeaderboardID {
    static let colorAllTime = "matchmaxxer.color.alltime"
}

struct LocalScoreEntry: Identifiable, Codable {
    let id: UUID
    let date: Date
    let score: Double
    let difficulty: String
    var category: String = "color"
    var initials: String = ""

    init(score: Double, difficulty: String, category: String = "color", initials: String = "") {
        self.id = UUID()
        self.date = Date()
        self.score = score
        self.difficulty = difficulty
        self.category = category
        self.initials = initials
    }
}

@MainActor
@Observable
final class LeaderboardManager {
    static let shared = LeaderboardManager()

    var isAuthenticated: Bool = false
    var localPlayerName: String = "You"
    var lastError: String?
    var localHistory: [LocalScoreEntry] = []

    private let historyKey = "matchmaxxer.localHistory.v1"

    private init() {
        loadLocalHistory()
    }

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] vc, error in
            guard let self else { return }
            if let error {
                self.lastError = error.localizedDescription
            }
            if let vc {
                self.present(vc)
                return
            }
            let player = GKLocalPlayer.local
            self.isAuthenticated = player.isAuthenticated
            if player.isAuthenticated {
                self.localPlayerName = player.alias
            }
        }
    }

    func submit(score: Double, difficulty: String, category: String = "color") {
        // Always record locally so there's always something to show.
        let entry = LocalScoreEntry(
            score: score,
            difficulty: difficulty,
            category: category,
            initials: UserPrefs.shared.initials
        )
        localHistory.insert(entry, at: 0)
        if localHistory.count > 50 { localHistory = Array(localHistory.prefix(50)) }
        saveLocalHistory()

        guard isAuthenticated else { return }
        let scaled = Int((score * 100).rounded()) // GameKit expects Int; we store hundredths
        Task {
            do {
                try await GKLeaderboard.submitScore(
                    scaled,
                    context: 0,
                    player: GKLocalPlayer.local,
                    leaderboardIDs: [LeaderboardID.colorAllTime]
                )
            } catch {
                await MainActor.run { self.lastError = error.localizedDescription }
            }
        }
    }

    func presentDashboard() {
        guard isAuthenticated else {
            authenticate()
            return
        }
        let vc = GKGameCenterViewController(leaderboardID: LeaderboardID.colorAllTime,
                                            playerScope: .global,
                                            timeScope: .allTime)
        vc.gameCenterDelegate = LeaderboardCloseDelegate.shared
        present(vc)
    }

    private func present(_ vc: UIViewController) {
        let scenes = UIApplication.shared.connectedScenes
        guard let window = scenes.compactMap({ $0 as? UIWindowScene }).first?.keyWindow,
              let root = window.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(vc, animated: true)
    }

    private func loadLocalHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([LocalScoreEntry].self, from: data)
        else { return }
        localHistory = decoded
    }

    private func saveLocalHistory() {
        if let data = try? JSONEncoder().encode(localHistory) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }
}

private final class LeaderboardCloseDelegate: NSObject, GKGameCenterControllerDelegate {
    static let shared = LeaderboardCloseDelegate()
    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
    }
}

// MARK: - Local-only leaderboard view (shown when Game Center isn't authenticated
// or while waiting on it). Always works offline, gives players something to see.

struct LocalLeaderboardView: View {
    @Bindable var manager: LeaderboardManager
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 22)
                    .padding(.top, 24)
                    .padding(.bottom, 14)

                content

                pinnedCTA
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 18)
                    .background(
                        // Soft fade so list items behind the pinned button
                        // don't appear to abruptly clip into it.
                        LinearGradient(
                            colors: [.black.opacity(0), .black, .black],
                            startPoint: .top, endPoint: .bottom
                        )
                        .allowsHitTesting(false)
                    )
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your recent runs")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(.white)
                Text(manager.isAuthenticated
                     ? "Signed in as \(manager.localPlayerName)"
                     : "Sign in to compete globally")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
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
    }

    @ViewBuilder
    private var content: some View {
        if manager.localHistory.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "list.number")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.white.opacity(0.30))
                Text("Play a round to see your scores here.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 22)
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(manager.localHistory) { entry in
                        historyRow(entry)
                    }
                    // Bottom inset so the last row isn't hidden behind the pinned CTA's gradient.
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 22)
                .padding(.top, 4)
            }
        }
    }

    private func historyRow(_ entry: LocalScoreEntry) -> some View {
        HStack {
            Text(entry.difficulty)
                .font(.system(size: 11, weight: .bold))
                .kerning(1.2)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 44, alignment: .leading)
            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.65))
            Spacer()
            Text(String(format: "%.2f", entry.score))
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text("/ 50")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.06))
        )
    }

    private var pinnedCTA: some View {
        Button(action: {
            SoundPlayer.haptic(.medium)
            if manager.isAuthenticated {
                manager.presentDashboard()
            } else {
                manager.authenticate()
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: manager.isAuthenticated ? "globe" : "person.crop.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                Text(manager.isAuthenticated
                     ? "Open world leaderboard"
                     : "Sign in to Game Center")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Capsule().fill(.white))
        }
        .buttonStyle(PressableButtonStyle())
    }
}
