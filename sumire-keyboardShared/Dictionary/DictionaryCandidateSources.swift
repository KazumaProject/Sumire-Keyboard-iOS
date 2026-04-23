import Foundation

struct LearningDictionaryCandidateSource: CandidateSource {
    let kind: CandidateSourceKind = .learning
    private let store: SQLiteDictionaryStore

    init(store: SQLiteDictionaryStore) {
        self.store = store
    }

    func searchExact(reading: String, limit: Int) -> [Candidate] {
        (try? store.searchLearningExact(reading: reading, limit: limit).map(Self.candidate(from:))) ?? []
    }

    func searchCommonPrefix(inputReading: String, limit: Int) -> [Candidate] {
        (try? store.searchLearningPrefix(prefix: inputReading, limit: limit).map(Self.candidate(from:))) ?? []
    }

    func searchPredictive(prefix: String, limit: Int) -> [Candidate] {
        (try? store.searchLearningPrefix(prefix: prefix, limit: limit).map(Self.candidate(from:))) ?? []
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
        if let artifact = currentArtifact() {
            return artifact.searchExact(reading: reading, limit: limit)
        }
        return (try? store.searchUserExact(reading: reading, limit: limit).map(Self.candidate(from:))) ?? []
    }

    func searchCommonPrefix(inputReading: String, limit: Int) -> [Candidate] {
        if let artifact = currentArtifact() {
            return artifact.searchCommonPrefix(inputReading: inputReading, limit: limit)
        }
        return (try? store.searchUserPrefix(prefix: inputReading, limit: limit).map(Self.candidate(from:))) ?? []
    }

    func searchPredictive(prefix: String, limit: Int) -> [Candidate] {
        if let artifact = currentArtifact() {
            return artifact.searchPredictive(prefix: prefix, limit: limit)
        }
        return (try? store.searchUserPrefix(prefix: prefix, limit: limit).map(Self.candidate(from:))) ?? []
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
