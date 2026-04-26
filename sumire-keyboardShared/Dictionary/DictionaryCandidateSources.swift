import Foundation

// MARK: - DictionaryPredictiveSearchPolicy

/// 辞書ソース別の予測変換ルールをまとめたヘルパー。
///
/// - ユーザー辞書は `allowsSystemStylePredictiveSearch` に従う（通常予測変換と同じ 3文字開始）。
/// - 学習辞書は `allowsLearningPredictiveSearch` に従う（KeyboardSettings で可変）。
/// - 読み長上限 `maxReadingLength` は両辞書共通: input.count < 6 → input.count + 2, それ以上 → nil。
struct DictionaryPredictiveSearchPolicy: Sendable {
    /// ユーザー辞書 / 通常予測変換の開始文字数（KanaKanjiConverter.predict() と同じ値）。
    static let defaultSystemPredictiveStartLength = 3

    /// ユーザー辞書向け: 通常予測変換ルールで prefix / predictive 検索を許可するか。
    /// `predictiveConversionStartLength` 設定には依存しない。
    static func allowsSystemStylePredictiveSearch(input: String) -> Bool {
        input.count >= defaultSystemPredictiveStartLength
    }

    /// 学習辞書向け: `startLength` 以上の入力長で prefix / predictive 検索を許可するか。
    /// - Parameter startLength: `KeyboardSettings.predictiveConversionStartLength` を渡す。
    static func allowsLearningPredictiveSearch(input: String, startLength: Int) -> Bool {
        input.count >= startLength
    }

    /// 読み長の上限を返す（両辞書共通ルール、KanaKanjiConverter.predictiveMaxYomiLength と同じ）。
    /// - Returns: `input.count < 6` のとき `input.count + 2`、それ以上のとき `nil`（上限なし）。
    static func maxReadingLength(forInput input: String) -> Int? {
        let inputLength = input.count
        return inputLength < 6 ? inputLength + 2 : nil
    }
}

// MARK: - LearningDictionaryCandidateSource

struct LearningDictionaryCandidateSource: CandidateSource {
    let kind: CandidateSourceKind = .learning
    private let store: SQLiteDictionaryStore

    init(store: SQLiteDictionaryStore) {
        self.store = store
    }

    func searchExact(reading: String, limit: Int) -> [Candidate] {
        (try? store.searchLearningExact(reading: reading, limit: limit).map(Self.candidate(from:))) ?? []
    }

    /// prefix / predictive 検索: `KeyboardSettings.predictiveConversionStartLength` 文字未満では返さない。
    /// exact 検索 (`searchExact`) は設定値に関係なく常に動作する。
    func searchCommonPrefix(inputReading: String, limit: Int) -> [Candidate] {
        guard DictionaryPredictiveSearchPolicy.allowsLearningPredictiveSearch(
            input: inputReading,
            startLength: KeyboardSettings.predictiveConversionStartLength
        ) else {
            return []
        }
        let maxReadingLength = DictionaryPredictiveSearchPolicy.maxReadingLength(forInput: inputReading)
        return (try? store.searchLearningPrefix(
            prefix: inputReading,
            limit: limit,
            maxReadingLength: maxReadingLength
        ).map(Self.candidate(from:))) ?? []
    }

    func searchPredictive(prefix: String, limit: Int) -> [Candidate] {
        guard DictionaryPredictiveSearchPolicy.allowsLearningPredictiveSearch(
            input: prefix,
            startLength: KeyboardSettings.predictiveConversionStartLength
        ) else {
            return []
        }
        let maxReadingLength = DictionaryPredictiveSearchPolicy.maxReadingLength(forInput: prefix)
        return (try? store.searchLearningPrefix(
            prefix: prefix,
            limit: limit,
            maxReadingLength: maxReadingLength
        ).map(Self.candidate(from:))) ?? []
    }

    private static func candidate(from entry: LearningDictionaryEntry) -> Candidate {
        Candidate(
            reading: entry.reading,
            word: entry.word,
            consumedReadingLength: entry.reading.count,
            sourceKind: .learning,
            lexicalInfo: CandidateLexicalInfo(score: entry.score, leftId: entry.leftId, rightId: entry.rightId)
        )
    }
}

final class UserDictionaryCandidateSource: @unchecked Sendable, CandidateSource {
    let kind: CandidateSourceKind = .user
    private let store: SQLiteDictionaryStore
    private let locator: UserDictionaryArtifactLocator
    private let lock = NSLock()
    private var cachedArtifact: UserDictionaryBinaryArtifact?

    init(
        store: SQLiteDictionaryStore,
        locator: UserDictionaryArtifactLocator = UserDictionaryArtifactLocator()
    ) {
        self.store = store
        self.locator = locator
    }

    func searchExact(reading: String, limit: Int) -> [Candidate] {
        let sqliteCandidates = (try? store.searchUserExact(reading: reading, limit: limit).map(Self.candidate(from:))) ?? []
        guard let artifact = currentArtifact() else {
            return sqliteCandidates
        }
        let artifactCandidates = artifact.searchExact(reading: reading, limit: limit)
        return Self.mergeDedup(sqlite: sqliteCandidates, artifact: artifactCandidates, limit: limit)
    }

    /// prefix / predictive 検索: 通常予測変換ルール（3文字以上、読み長制限あり）に従う。
    /// `predictiveConversionStartLength` 設定には依存しない。
    /// exact 検索 (`searchExact`) は常に動作する。
    func searchCommonPrefix(inputReading: String, limit: Int) -> [Candidate] {
        guard DictionaryPredictiveSearchPolicy.allowsSystemStylePredictiveSearch(input: inputReading) else {
            return []
        }
        let maxReadingLength = DictionaryPredictiveSearchPolicy.maxReadingLength(forInput: inputReading)
        let sqliteCandidates = (try? store.searchUserPrefix(
            prefix: inputReading,
            limit: limit,
            maxReadingLength: maxReadingLength
        ).map(Self.candidate(from:))) ?? []
        guard let artifact = currentArtifact() else {
            return sqliteCandidates
        }
        let artifactCandidates = artifact.searchCommonPrefix(
            inputReading: inputReading,
            limit: limit,
            maxReadingLength: maxReadingLength
        )
        return Self.mergeDedup(sqlite: sqliteCandidates, artifact: artifactCandidates, limit: limit)
    }

    func searchPredictive(prefix: String, limit: Int) -> [Candidate] {
        guard DictionaryPredictiveSearchPolicy.allowsSystemStylePredictiveSearch(input: prefix) else {
            return []
        }
        let maxReadingLength = DictionaryPredictiveSearchPolicy.maxReadingLength(forInput: prefix)
        let sqliteCandidates = (try? store.searchUserPrefix(
            prefix: prefix,
            limit: limit,
            maxReadingLength: maxReadingLength
        ).map(Self.candidate(from:))) ?? []
        guard let artifact = currentArtifact() else {
            return sqliteCandidates
        }
        let artifactCandidates = artifact.searchPredictive(
            prefix: prefix,
            limit: limit,
            maxReadingLength: maxReadingLength
        )
        return Self.mergeDedup(sqlite: sqliteCandidates, artifact: artifactCandidates, limit: limit)
    }

    /// SQLite 側を優先して artifact 側とマージ・dedup する。
    /// SQLite に同じ reading+word がある場合は SQLite 候補を残し、artifact 候補を捨てる。
    /// これにより、artifact 作成後に SQLite へ追加された新規単語も即時反映される。
    private static func mergeDedup(sqlite: [Candidate], artifact: [Candidate], limit: Int) -> [Candidate] {
        var seen = Set<CandidateDedupKey>()
        var result: [Candidate] = []
        result.reserveCapacity(min(sqlite.count + artifact.count, limit))

        for candidate in sqlite {
            guard result.count < limit else { break }
            if seen.insert(candidate.dedupKey).inserted {
                result.append(candidate)
            }
        }

        for candidate in artifact {
            guard result.count < limit else { break }
            if seen.insert(candidate.dedupKey).inserted {
                result.append(candidate)
            }
        }

        return result
    }

    private func currentArtifact() -> UserDictionaryBinaryArtifact? {
        lock.lock()
        defer {
            lock.unlock()
        }

        do {
            let artifact = try UserDictionaryBinaryArtifact.loadCurrent(locator: locator)
            if cachedArtifact?.version != artifact.version {
                cachedArtifact = artifact
            }
            return cachedArtifact
        } catch {
            cachedArtifact = nil
            return nil
        }
    }

    private static func candidate(from entry: UserDictionaryEntry) -> Candidate {
        Candidate(
            reading: entry.reading,
            word: entry.word,
            consumedReadingLength: entry.reading.count,
            sourceKind: .user,
            lexicalInfo: CandidateLexicalInfo(score: entry.score, leftId: entry.leftId, rightId: entry.rightId)
        )
    }
}
