import Foundation

enum Preferences {
    private static let dimDisplayKey = "wedge.dimDisplayOnLidClose"
    private static let languageKey = "wedge.preferredLanguage"

    static var dimDisplayOnLidClose: Bool {
        get {
            UserDefaults.standard.object(forKey: dimDisplayKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: dimDisplayKey)
        }
    }

    /// Returns the language override, or nil if Wedge should follow system.
    /// Valid codes: "en", "ru".
    static var preferredLanguage: String? {
        get {
            UserDefaults.standard.string(forKey: languageKey)
        }
        set {
            if let value = newValue, !value.isEmpty {
                UserDefaults.standard.set(value, forKey: languageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: languageKey)
            }
        }
    }

    /// Applies the language preference by overriding AppleLanguages for this
    /// process. Must be called BEFORE any string lookups for the change to
    /// affect already-bound bundle resources — practically that means at the
    /// very top of `main.swift`, before NSApplication.shared touches anything.
    static func applyLanguageAtLaunch() {
        guard let lang = preferredLanguage else { return }
        UserDefaults.standard.set([lang], forKey: "AppleLanguages")
    }
}
