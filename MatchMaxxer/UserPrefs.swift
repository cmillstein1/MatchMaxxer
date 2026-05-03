import Foundation
import Observation

@MainActor
@Observable
final class UserPrefs {
    static let shared = UserPrefs()

    var initials: String {
        didSet { UserDefaults.standard.set(initials, forKey: Keys.initials) }
    }

    private enum Keys {
        static let initials = "matchmaxxer.player.initials"
    }

    private init() {
        self.initials = UserDefaults.standard.string(forKey: Keys.initials) ?? ""
    }

    var displayInitials: String {
        initials.isEmpty ? "—" : initials
    }

    static func sanitize(_ raw: String) -> String {
        let upper = raw.uppercased()
        let allowed = upper.unicodeScalars.filter {
            CharacterSet.uppercaseLetters.contains($0) || CharacterSet.decimalDigits.contains($0)
        }
        return String(String.UnicodeScalarView(allowed.prefix(3)))
    }
}
