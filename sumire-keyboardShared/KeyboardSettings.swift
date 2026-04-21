import Foundation

enum KeyboardSettings {
    enum Keys {
        static let japaneseFlickInputMode = "SumireKeyboardJapaneseFlickInputMode"
        static let liveConversionEnabled = "SumireKeyboardLiveConversionEnabled"
        static let preeditReadingPreviewEnabled = "SumireKeyboardPreeditReadingPreviewEnabled"
        static let usesHalfWidthSpace = "SumireKeyboardUsesHalfWidthSpace"
        static let keyboards = "SumireKeyboardKeyboards"
        static let currentKeyboardID = "SumireKeyboardCurrentKeyboardID"
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

    enum KeyboardKind: String, Codable, CaseIterable, Identifiable {
        case japaneseFlick
        case qwerty

        var id: String { rawValue }

        var title: String {
            switch self {
            case .japaneseFlick:
                return "日本語 Flick"
            case .qwerty:
                return "QWERTY"
            }
        }
    }

    enum QWERTYLanguage: String, Codable, CaseIterable, Identifiable {
        case japanese
        case english

        var id: String { rawValue }

        var title: String {
            switch self {
            case .japanese:
                return "日本語"
            case .english:
                return "英語"
            }
        }
    }

    struct SumireKeyboard: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var kind: KeyboardKind
        var qwertyLanguage: QWERTYLanguage?

        var displayKind: String {
            switch kind {
            case .japaneseFlick:
                return KeyboardKind.japaneseFlick.title
            case .qwerty:
                return "\(qwertyLanguageTitle) QWERTY"
            }
        }

        var qwertyLanguageTitle: String {
            (qwertyLanguage ?? .japanese).title
        }

        static var defaultJapaneseFlick: SumireKeyboard {
            SumireKeyboard(
                id: "default-japanese-flick",
                name: "日本語 Flick",
                kind: .japaneseFlick,
                qwertyLanguage: nil
            )
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

    static var preeditReadingPreviewEnabled: Bool {
        get {
            guard defaults.object(forKey: Keys.preeditReadingPreviewEnabled) != nil else {
                return false
            }
            return defaults.bool(forKey: Keys.preeditReadingPreviewEnabled)
        }
        set {
            defaults.set(newValue, forKey: Keys.preeditReadingPreviewEnabled)
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

    static var keyboards: [SumireKeyboard] {
        get {
            guard let data = defaults.data(forKey: Keys.keyboards),
                  let decodedKeyboards = try? JSONDecoder().decode([SumireKeyboard].self, from: data) else {
                let defaultKeyboards = [SumireKeyboard.defaultJapaneseFlick]
                saveKeyboards(defaultKeyboards)
                return defaultKeyboards
            }

            let normalizedKeyboards = normalized(keyboards: decodedKeyboards)
            if normalizedKeyboards != decodedKeyboards {
                saveKeyboards(normalizedKeyboards)
            }
            return normalizedKeyboards
        }
        set {
            saveKeyboards(normalized(keyboards: newValue))
        }
    }

    static var currentKeyboardID: String {
        get {
            let savedID = defaults.string(forKey: Keys.currentKeyboardID)
            let availableKeyboards = keyboards
            if let savedID, availableKeyboards.contains(where: { $0.id == savedID }) {
                return savedID
            }

            let fallbackID = availableKeyboards[0].id
            defaults.set(fallbackID, forKey: Keys.currentKeyboardID)
            return fallbackID
        }
        set {
            guard keyboards.contains(where: { $0.id == newValue }) else {
                return
            }
            defaults.set(newValue, forKey: Keys.currentKeyboardID)
        }
    }

    static var currentKeyboard: SumireKeyboard {
        keyboards.first(where: { $0.id == currentKeyboardID }) ?? keyboards[0]
    }

    @discardableResult
    static func addKeyboard(
        name: String,
        kind: KeyboardKind,
        qwertyLanguage: QWERTYLanguage? = nil
    ) -> SumireKeyboard {
        var nextKeyboard = SumireKeyboard(
            id: UUID().uuidString,
            name: sanitizedKeyboardName(name, fallback: defaultKeyboardName(kind: kind, qwertyLanguage: qwertyLanguage)),
            kind: kind,
            qwertyLanguage: kind == .qwerty ? (qwertyLanguage ?? .japanese) : nil
        )
        nextKeyboard.name = uniqueKeyboardName(nextKeyboard.name, excludingID: nextKeyboard.id)

        var nextKeyboards = keyboards
        nextKeyboards.append(nextKeyboard)
        keyboards = nextKeyboards
        currentKeyboardID = nextKeyboard.id
        return nextKeyboard
    }

    static func updateKeyboard(_ keyboard: SumireKeyboard) {
        var nextKeyboards = keyboards
        guard let index = nextKeyboards.firstIndex(where: { $0.id == keyboard.id }) else {
            return
        }

        var updatedKeyboard = keyboard
        updatedKeyboard.name = sanitizedKeyboardName(
            keyboard.name,
            fallback: defaultKeyboardName(kind: keyboard.kind, qwertyLanguage: keyboard.qwertyLanguage)
        )
        updatedKeyboard.name = uniqueKeyboardName(updatedKeyboard.name, excludingID: updatedKeyboard.id)
        if updatedKeyboard.kind != .qwerty {
            updatedKeyboard.qwertyLanguage = nil
        } else if updatedKeyboard.qwertyLanguage == nil {
            updatedKeyboard.qwertyLanguage = .japanese
        }

        nextKeyboards[index] = updatedKeyboard
        keyboards = nextKeyboards
    }

    @discardableResult
    static func deleteKeyboard(id: String) -> Bool {
        var nextKeyboards = keyboards
        guard nextKeyboards.count > 1,
              let index = nextKeyboards.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let deletedKeyboard = nextKeyboards.remove(at: index)
        keyboards = nextKeyboards
        if currentKeyboardID == deletedKeyboard.id {
            currentKeyboardID = self.keyboards[0].id
        }
        return true
    }

    static func canDeleteKeyboard(id: String) -> Bool {
        keyboards.count > 1 && keyboards.contains(where: { $0.id == id })
    }

    static func defaultKeyboardName(
        kind: KeyboardKind,
        qwertyLanguage: QWERTYLanguage? = nil
    ) -> String {
        switch kind {
        case .japaneseFlick:
            return "日本語 Flick"
        case .qwerty:
            return "\(qwertyLanguage?.title ?? QWERTYLanguage.japanese.title) QWERTY"
        }
    }

    private static func normalized(keyboards: [SumireKeyboard]) -> [SumireKeyboard] {
        guard keyboards.isEmpty == false else {
            return [SumireKeyboard.defaultJapaneseFlick]
        }

        return keyboards.map { keyboard in
            var normalizedKeyboard = keyboard
            normalizedKeyboard.name = sanitizedKeyboardName(
                keyboard.name,
                fallback: defaultKeyboardName(kind: keyboard.kind, qwertyLanguage: keyboard.qwertyLanguage)
            )
            if normalizedKeyboard.kind == .qwerty {
                normalizedKeyboard.qwertyLanguage = normalizedKeyboard.qwertyLanguage ?? .japanese
            } else {
                normalizedKeyboard.qwertyLanguage = nil
            }
            return normalizedKeyboard
        }
    }

    private static func saveKeyboards(_ keyboards: [SumireKeyboard]) {
        let nextKeyboards = normalized(keyboards: keyboards)
        guard let data = try? JSONEncoder().encode(nextKeyboards) else {
            return
        }

        defaults.set(data, forKey: Keys.keyboards)
        let savedCurrentKeyboardID = defaults.string(forKey: Keys.currentKeyboardID)
        if savedCurrentKeyboardID == nil || nextKeyboards.contains(where: { $0.id == savedCurrentKeyboardID }) == false {
            defaults.set(nextKeyboards[0].id, forKey: Keys.currentKeyboardID)
        }
    }

    private static func sanitizedKeyboardName(_ name: String, fallback: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? fallback : trimmedName
    }

    private static func uniqueKeyboardName(_ name: String, excludingID id: String) -> String {
        let existingNames = Set(keyboards.filter { $0.id != id }.map(\.name))
        guard existingNames.contains(name) else {
            return name
        }

        var suffix = 2
        while existingNames.contains("\(name) \(suffix)") {
            suffix += 1
        }
        return "\(name) \(suffix)"
    }
}
