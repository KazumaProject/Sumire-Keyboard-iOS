import Foundation

public enum SupplementalDictionaryKind: String, CaseIterable, Sendable {
    case emoji
    case emoticon
    case readingCorrection = "reading_correction"
    case symbol

    public var resourceDirectoryName: String {
        rawValue
    }
}

public struct SupplementalDictionaryStore: Sendable {
    private let dictionariesByKind: [SupplementalDictionaryKind: MozcDictionary]

    public init(_ dictionariesByKind: [SupplementalDictionaryKind: MozcDictionary] = [:]) {
        self.dictionariesByKind = dictionariesByKind
    }

    public var loadedKinds: [SupplementalDictionaryKind] {
        SupplementalDictionaryKind.allCases.filter { dictionariesByKind[$0] != nil }
    }

    public var isEmpty: Bool {
        dictionariesByKind.isEmpty
    }

    func dictionary(for kind: SupplementalDictionaryKind) -> MozcDictionary? {
        dictionariesByKind[kind]
    }

    func orderedDictionaries() -> [MozcDictionary] {
        SupplementalDictionaryKind.allCases.compactMap { dictionariesByKind[$0] }
    }
}

public struct LoadedDictionarySet: Sendable {
    public let main: MozcDictionary
    public let supplementals: SupplementalDictionaryStore

    public init(
        main: MozcDictionary,
        supplementals: SupplementalDictionaryStore = SupplementalDictionaryStore()
    ) {
        self.main = main
        self.supplementals = supplementals
    }
}

public struct CompositeMozcDictionary: Sendable {
    private let dictionaries: [MozcDictionary]

    public init(main: MozcDictionary, supplementals: SupplementalDictionaryStore = SupplementalDictionaryStore()) {
        self.dictionaries = [main] + supplementals.orderedDictionaries()
    }

    public init(dictionarySet: LoadedDictionarySet) {
        self.init(main: dictionarySet.main, supplementals: dictionarySet.supplementals)
    }

    func prefixMatches(
        in characters: [Character],
        from start: Int,
        mode: YomiSearchMode = .commonPrefix,
        predictivePrefixLength: Int = 1
    ) -> [MozcDictionary.PrefixMatch] {
        dictionaries.flatMap {
            $0.prefixMatches(
                in: characters,
                from: start,
                mode: mode,
                predictivePrefixLength: predictivePrefixLength
            )
        }
    }

    func predictiveEntries(
        for input: String,
        predictivePrefixLength: Int = 1,
        limit: Int = 50,
        maxYomiLength: Int? = nil
    ) -> [DictionaryEntry] {
        guard limit > 0 else {
            return []
        }

        let perDictionaryLimit = max(limit, limit * max(1, dictionaries.count))
        let entries = dictionaries.flatMap {
            $0.predictiveEntries(
                for: input,
                predictivePrefixLength: predictivePrefixLength,
                limit: perDictionaryLimit,
                maxYomiLength: maxYomiLength
            )
        }

        return MozcDictionary.sortedPredictiveEntries(entries).prefix(limit).map { $0 }
    }
}
