import Foundation

enum L10n {
    static let languageKey = "app.language"

    static func tr(_ key: String) -> String {
        let bundle = localizedBundle()
        return NSLocalizedString(key, bundle: bundle, comment: "")
    }

    private static func localizedBundle() -> Bundle {
        let value = UserDefaults.standard.string(forKey: languageKey) ?? "system"
        guard value != "system" else {
            return .module
        }

        let candidates = [
            value,
            value.lowercased(),
            value.replacingOccurrences(of: "-", with: "_").lowercased(),
            value.components(separatedBy: CharacterSet(charactersIn: "-_ ")).first?.lowercased() ?? value
        ]

        for candidate in candidates {
            if let path = Bundle.module.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }

        return .module
    }
}
