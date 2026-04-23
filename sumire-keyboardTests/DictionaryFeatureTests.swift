import Foundation
import Testing
@testable import sumire_keyboard

struct DictionaryFeatureTests {
    @Test func candidatePipelineDeduplicatesByReadingAndWordUsingSourcePriority() {
        let system = StubCandidateSource(kind: .systemMain, candidates: [
            Candidate(
                reading: "すみれ",
                word: "菫",
                consumedReadingLength: 3,
                sourceKind: .systemMain,
                lexicalInfo: CandidateLexicalInfo(score: 500, leftId: 1, rightId: 1)
            )
        ])
        let user = StubCandidateSource(kind: .user, candidates: [
            Candidate(
                reading: "すみれ",
                word: "菫",
                consumedReadingLength: 3,
                sourceKind: .user,
                lexicalInfo: CandidateLexicalInfo(score: 1, leftId: 2, rightId: 2)
            )
        ])
        let pipeline = CandidatePipeline(
            sources: [user, system],
            mergePolicy: CandidateMergePolicy(
                sourcePriority: [.systemMain, .user],
                scoreStrategy: .max,
                totalLimit: 10,
                includesAuxiliaryCandidates: true
            )
        )

        let candidates = pipeline.candidates(for: "すみれ", limit: 10)

        #expect(candidates.count == 1)
        #expect(candidates.first?.sourceKind == .systemMain)
    }

    @Test func candidatePipelineAppliesTotalLimit() {
        let source = StubCandidateSource(kind: .user, candidates: [
            Candidate(reading: "a", word: "a1", consumedReadingLength: 1, sourceKind: .user, lexicalInfo: nil),
            Candidate(reading: "a", word: "a2", consumedReadingLength: 1, sourceKind: .user, lexicalInfo: nil),
            Candidate(reading: "a", word: "a3", consumedReadingLength: 1, sourceKind: .user, lexicalInfo: nil)
        ])
        let pipeline = CandidatePipeline(
            sources: [source],
            mergePolicy: CandidateMergePolicy(
                sourcePriority: [.user],
                scoreStrategy: .max,
                totalLimit: 2,
                includesAuxiliaryCandidates: true
            )
        )

        #expect(pipeline.candidates(for: "a", limit: 10).count == 2)
    }

    @Test func sqliteUserRepositorySupportsCRUDAndPrefixSearch() async throws {
        let repositories = try makeRepositories()
        let userRepository = repositories.userRepository
        let entry = UserDictionaryEntry(
            id: UUID(),
            reading: "すみれ",
            word: "菫",
            score: 100,
            leftId: 10,
            rightId: 20,
            updatedAt: Date()
        )

        try await userRepository.add(entry)
        #expect(try await userRepository.searchExact(reading: "すみれ", limit: 10).map(\.word) == ["菫"])
        #expect(try await userRepository.searchCommonPrefix(inputReading: "す", limit: 10).map(\.word) == ["菫"])

        var updated = entry
        updated.word = "すみれ"
        try await userRepository.update(updated)
        #expect(try await userRepository.searchExact(reading: "すみれ", limit: 10).map(\.word) == ["すみれ"])

        try await userRepository.delete(id: entry.id)
        #expect(try await userRepository.searchExact(reading: "すみれ", limit: 10).isEmpty)

        try await userRepository.add(entry)
        try await userRepository.deleteAll()
        #expect(try await userRepository.searchForManagementUI(query: "", limit: 10, offset: 0).isEmpty)
    }

    @Test func learningRepositoryRecordsOnlyValidCommittedSelectionsAndUpdatesDuplicates() async throws {
        let repositories = try makeRepositories()
        let learningRepository = repositories.learningRepository

        try await learningRepository.recordCommittedSelection(CommittedSelection(
            inputReading: "すみれ",
            candidateReading: "す",
            word: "菫",
            sourceKind: .systemMain,
            lexicalInfo: CandidateLexicalInfo(score: 10, leftId: 1, rightId: 2),
            committedAt: Date()
        ))
        #expect(try await learningRepository.searchExact(reading: "す", limit: 10).isEmpty)

        let validSelection = CommittedSelection(
            inputReading: "すみれ",
            candidateReading: "すみれ",
            word: "菫",
            sourceKind: .systemMain,
            lexicalInfo: CandidateLexicalInfo(score: 10, leftId: 1, rightId: 2),
            committedAt: Date()
        )
        try await learningRepository.recordCommittedSelection(validSelection)
        try await learningRepository.recordCommittedSelection(validSelection)

        let entries = try await learningRepository.searchExact(reading: "すみれ", limit: 10)
        #expect(entries.count == 1)
        #expect(entries.first?.word == "菫")
        #expect(entries.first?.score == -490)
    }

    @Test func learningRepositoryResolvesMissingLexicalInfoToDefaultGeneralNoun() async throws {
        let repositories = try makeRepositories()
        let learningRepository = repositories.learningRepository

        try await learningRepository.recordCommittedSelection(CommittedSelection(
            inputReading: "すみれ",
            candidateReading: "すみれ",
            word: "菫",
            sourceKind: .systemMain,
            lexicalInfo: nil,
            committedAt: Date()
        ))

        let entries = try await learningRepository.searchExact(reading: "すみれ", limit: 10)
        let entry = try #require(entries.first)
        #expect(entry.leftId == DictionaryDefaultLexicalIDs.generalNoun)
        #expect(entry.rightId == DictionaryDefaultLexicalIDs.generalNoun)
        #expect(entry.score == DictionaryDefaultLexicalInfo.generalNoun.score)
    }

    @Test func learningRepositoryPreservesExistingLexicalInfo() async throws {
        let repositories = try makeRepositories()
        let learningRepository = repositories.learningRepository

        try await learningRepository.recordCommittedSelection(CommittedSelection(
            inputReading: "すみれ",
            candidateReading: "すみれ",
            word: "菫",
            sourceKind: .systemMain,
            lexicalInfo: CandidateLexicalInfo(score: 77, leftId: 10, rightId: 20),
            committedAt: Date()
        ))

        let entries = try await learningRepository.searchExact(reading: "すみれ", limit: 10)
        let entry = try #require(entries.first)
        #expect(entry.leftId == 10)
        #expect(entry.rightId == 20)
        #expect(entry.score == 77)
    }

    @Test func userDictionaryLoudsBuildPublishesSearchableArtifact() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repositories = try makeRepositories(directory: directory)
        let locator = UserDictionaryArtifactLocator(rootDirectoryURL: directory.appendingPathComponent("Dictionary", isDirectory: true))
        let userRepository = repositories.userRepository

        try await userRepository.add(UserDictionaryEntry(
            id: UUID(),
            reading: "すみれ",
            word: "菫",
            score: 100,
            leftId: 1851,
            rightId: 1851,
            updatedAt: Date()
        ))
        try await userRepository.add(UserDictionaryEntry(
            id: UUID(),
            reading: "すみれいろ",
            word: "菫色",
            score: 90,
            leftId: 1851,
            rightId: 1851,
            updatedAt: Date()
        ))

        let builder = FileUserDictionaryLoudsBuilder(locator: locator)
        let artifacts = try await builder.build(from: try await userRepository.allEntries())
        #expect(FileManager.default.fileExists(atPath: artifacts.directoryURL.path))
        #expect(MozcArtifactIO.containsDictionaryArtifacts(at: artifacts.directoryURL))
        #expect(FileManager.default.fileExists(
            atPath: artifacts.directoryURL.appendingPathComponent(MozcDictionary.posTableFileName).path
        ))

        try await FileUserDictionaryLoudsValidator().validate(artifacts)
        try await FileUserDictionaryArtifactPublisher(locator: locator).publish(artifacts)
        #expect(FileManager.default.fileExists(atPath: locator.currentManifestURL.path))

        let source = UserDictionaryCandidateSource(store: repositories.store, locator: locator)
        #expect(source.searchExact(reading: "すみれ", limit: 10).map(\.word) == ["菫"])
        #expect(source.searchCommonPrefix(inputReading: "す", limit: 10).map(\.word).contains("菫"))
        #expect(source.searchPredictive(prefix: "すみ", limit: 10).map(\.word).contains("菫色"))
    }

    @Test func userDictionaryBuildStateRepositoryPersistsStatuses() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let locator = UserDictionaryArtifactLocator(rootDirectoryURL: directory.appendingPathComponent("Dictionary", isDirectory: true))
        let repository = FileUserDictionaryBuildStateRepository(locator: locator)

        let building = UserDictionaryBuildState(status: .building, updatedAt: Date())
        try await repository.save(building)
        #expect(try await repository.load().status == .building)

        let ready = UserDictionaryBuildState(status: .ready, updatedAt: Date(), artifactVersion: "v1")
        try await repository.save(ready)
        let loadedReady = try await repository.load()
        #expect(loadedReady.status == .ready)
        #expect(loadedReady.artifactVersion == "v1")

        let failed = UserDictionaryBuildState(status: .failed("boom"), updatedAt: Date(), lastErrorMessage: "boom")
        try await repository.save(failed)
        #expect(try await repository.load().status == .failed("boom"))
    }

    private func makeRepositories() throws -> DictionaryRepositories {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return try makeRepositories(directory: directory)
    }

    private func makeRepositories(directory: URL) throws -> DictionaryRepositories {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("dictionary.sqlite")
        return try DictionaryRepositories(store: SQLiteDictionaryStore(databaseURL: databaseURL))
    }
}

private struct StubCandidateSource: CandidateSource {
    let kind: CandidateSourceKind
    let candidates: [Candidate]

    func searchExact(reading: String, limit: Int) -> [Candidate] {
        candidates.prefix(limit).map { $0 }
    }

    func searchCommonPrefix(inputReading: String, limit: Int) -> [Candidate] {
        []
    }

    func searchPredictive(prefix: String, limit: Int) -> [Candidate] {
        []
    }
}
