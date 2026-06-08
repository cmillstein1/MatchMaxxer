import GameKit
import SwiftUI

// Stable identifier the user must also create in App Store Connect under
// Game Center > Leaderboards. Until that's set up, GKLeaderboard.submitScore
// will return an error and we fall back to the local-only history.
enum LeaderboardID {
    static let colorAllTime = "matchmaxxer.color.alltime"
    static let hexAllTime = "matchmaxxer.hex.alltime"
    static let soundAllTime = "matchmaxxer.sound.alltime"
    static let timeAllTime = "matchmaxxer.time.alltime"
    static let shapeAllTime = "matchmaxxer.shape.alltime"

    static func forCategory(_ slug: String) -> String? {
        switch slug {
        case "color": return colorAllTime
        case "hex":   return hexAllTime
        case "sound": return soundAllTime
        case "time":  return timeAllTime
        case "shape": return shapeAllTime
        default:      return nil
        }
    }

    static func forCategory(_ category: GameCategory) -> String {
        switch category {
        case .color: return colorAllTime
        case .hex:   return hexAllTime
        case .sound: return soundAllTime
        case .time:  return timeAllTime
        case .shape: return shapeAllTime
        }
    }
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

    // Apple requires explicit user consent before we upload scores to the
    // *global* Game Center leaderboard. Local history is always kept on-device
    // and is unaffected by this. `hasGlobalConsent` is the user's choice;
    // `consentAsked` records whether we've prompted yet so we only ask once.
    var hasGlobalConsent: Bool {
        didSet { UserDefaults.standard.set(hasGlobalConsent, forKey: consentKey) }
    }
    var consentAsked: Bool {
        didSet { UserDefaults.standard.set(consentAsked, forKey: consentAskedKey) }
    }
    // Drives a one-time consent alert in the UI. Set when a score is ready to
    // upload but the user hasn't been asked yet.
    var showConsentPrompt: Bool = false

    // Most recent score waiting on a consent decision, so we can upload it
    // immediately if the user opts in from the prompt.
    private var pendingScore: (scaled: Int, leaderboardID: String)?

    private let historyKey = "matchmaxxer.localHistory.v1"
    private let consentKey = "matchmaxxer.leaderboard.globalConsent.v1"
    private let consentAskedKey = "matchmaxxer.leaderboard.consentAsked.v1"

    private init() {
        self.hasGlobalConsent = UserDefaults.standard.bool(forKey: consentKey)
        self.consentAsked = UserDefaults.standard.bool(forKey: consentAskedKey)
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
                // First time signed in and never asked: get consent up front,
                // before any score is ready to upload.
                if !self.consentAsked {
                    self.showConsentPrompt = true
                }
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
        // GameKit expects Int; we store hundredths so leaderboards have 2 decimals of resolution.
        let scaled = Int((score * 100).rounded())
        guard let lbID = LeaderboardID.forCategory(category) else { return }

        // Consent gate: never upload to the global leaderboard without the
        // user's explicit opt-in. If they haven't been asked, stash the score
        // and trigger the consent prompt; the local entry above is already saved.
        guard hasGlobalConsent else {
            if !consentAsked {
                pendingScore = (scaled, lbID)
                showConsentPrompt = true
            }
            return
        }
        uploadGlobal(scaled: scaled, leaderboardID: lbID)
    }

    private func uploadGlobal(scaled: Int, leaderboardID: String) {
        Task {
            do {
                try await GKLeaderboard.submitScore(
                    scaled,
                    context: 0,
                    player: GKLocalPlayer.local,
                    leaderboardIDs: [leaderboardID]
                )
            } catch {
                await MainActor.run { self.lastError = error.localizedDescription }
            }
        }
    }

    // MARK: - Consent

    /// User opted in from the prompt. Persists the choice and uploads any score
    /// that was waiting on the decision.
    func grantGlobalConsent() {
        hasGlobalConsent = true
        consentAsked = true
        showConsentPrompt = false
        if let pending = pendingScore {
            uploadGlobal(scaled: pending.scaled, leaderboardID: pending.leaderboardID)
            pendingScore = nil
        }
    }

    /// User declined. We remember that we've asked so we don't nag, and drop
    /// the pending score.
    func declineGlobalConsent() {
        hasGlobalConsent = false
        consentAsked = true
        showConsentPrompt = false
        pendingScore = nil
    }

    /// Toggle used by the leaderboard's privacy control so users can change
    /// their mind later.
    func setGlobalConsent(_ enabled: Bool) {
        hasGlobalConsent = enabled
        consentAsked = true
        if !enabled { pendingScore = nil }
    }

    func presentDashboard(for category: GameCategory = .color) {
        guard isAuthenticated else {
            authenticate()
            return
        }
        let vc = GKGameCenterViewController(leaderboardID: LeaderboardID.forCategory(category),
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
    // When non-nil: filter recent runs to that mode and route the GC button
    // to that mode's leaderboard. nil = show all runs, default GC to color.
    var category: GameCategory? = nil
    var onClose: () -> Void

    private var visibleHistory: [LocalScoreEntry] {
        guard let slug = category?.slug else { return manager.localHistory }
        return manager.localHistory.filter { $0.category == slug }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 22)
                    .padding(.top, 24)
                    .padding(.bottom, 14)

                content

                if manager.isAuthenticated {
                    consentToggle
                        .padding(.horizontal, 22)
                        .padding(.top, 6)
                }

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
                Text(category.map { "Your recent \($0.displayName.lowercased()) runs" } ?? "Your recent runs")
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
        if visibleHistory.isEmpty {
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
                    ForEach(visibleHistory) { entry in
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

    private var consentToggle: some View {
        Toggle(isOn: Binding(
            get: { manager.hasGlobalConsent },
            set: { manager.setGlobalConsent($0) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Share scores globally")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Text("Post your scores to the worldwide leaderboard.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .tint(.white)
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
                manager.presentDashboard(for: category ?? .color)
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
