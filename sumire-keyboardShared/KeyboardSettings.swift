import Foundation

enum KeyboardSettings {
    enum Keys {
        static let japaneseFlickInputMode = "SumireKeyboardJapaneseFlickInputMode"
        static let liveConversionEnabled = "SumireKeyboardLiveConversionEnabled"
        static let usesHalfWidthSpace = "SumireKeyboardUsesHalfWidthSpace"
    }

    enum JapaneseFlickInputMode: String, CaseIterable, Identifiable {
        case toggle
        case flick

        var id: String { rawValue }

        var title: String {
            switch self {
            case .toggle:
                return "Toggle"
            case .flick:
                return "フリック"
            }
        }
    }

    static let appGroupIdentifier = "group.com.kazumaproject.sumire-keyboard"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    static var japaneseFlickInputMode: JapaneseFlickInputMode {
        get {
            let rawValue = defaults.string(forKey: Keys.japaneseFlickInputMode)
            return JapaneseFlickInputMode(rawValue: rawValue ?? "") ?? .toggle
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.japaneseFlickInputMode)
        }
    }

    static var liveConversionEnabled: Bool {
        get {
            guard defaults.object(forKey: Keys.liveConversionEnabled) != nil else {
                return true
            }
            return defaults.bool(forKey: Keys.liveConversionEnabled)
        }
        set {
            defaults.set(newValue, forKey: Keys.liveConversionEnabled)
        }
    }

    static var usesHalfWidthSpace: Bool {
        get {
            guard defaults.object(forKey: Keys.usesHalfWidthSpace) != nil else {
                return false
            }
            return defaults.bool(forKey: Keys.usesHalfWidthSpace)
        }
        set {
            defaults.set(newValue, forKey: Keys.usesHalfWidthSpace)
        }
    }

    static var spaceText: String {
        usesHalfWidthSpace ? " " : "　"
    }
}
