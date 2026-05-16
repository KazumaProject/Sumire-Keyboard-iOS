import Foundation

typealias LearningDictionaryEntryID = UUID
typealias UserDictionaryEntryID = UUID

struct LearningDictionaryEntry: Identifiable, Hashable, Sendable {
    let id: LearningDictionaryEntryID
    var reading: String
    var word: String
    var score: Int
    var leftId: Int
    var rightId: Int
    var updatedAt: Date
}

struct CommittedSelection: Sendable {
    let inputReading: String
    let candidateReading: String
    let word: String
    let sourceKind: CandidateSourceKind
    let lexicalInfo: CandidateLexicalInfo?
    let committedAt: Date
}

protocol LearningDictionaryLearningRepository: Sendable {
    func recordCommittedSelection(_ selection: CommittedSelection) async throws
}

protocol LearningDictionaryQueryRepository: Sendable {
    func searchExact(reading: String, limit: Int) async throws -> [LearningDictionaryEntry]
    func searchCommonPrefix(inputReading: String, limit: Int) async throws -> [LearningDictionaryEntry]
    func searchPredictive(prefix: String, limit: Int) async throws -> [LearningDictionaryEntry]
    func searchForManagementUI(query: String, limit: Int, offset: Int) async throws -> [LearningDictionaryEntry]
}

protocol LearningDictionaryEditorRepository: Sendable {
    func add(_ entry: LearningDictionaryEntry) async throws
    func update(_ entry: LearningDictionaryEntry) async throws
    func delete(id: LearningDictionaryEntryID) async throws
    func deleteAll() async throws
}

struct UserDictionaryEntry: Identifiable, Hashable, Sendable {
    let id: UserDictionaryEntryID
    var reading: String
    var word: String
    var score: Int
    var leftId: Int
    var rightId: Int
    var updatedAt: Date
}

protocol UserDictionaryManagementQueryRepository: Sendable {
    func searchForManagementUI(query: String, limit: Int, offset: Int) async throws -> [UserDictionaryEntry]
    func count(query: String) async throws -> Int
    func allEntries() async throws -> [UserDictionaryEntry]
}

protocol UserDictionaryCandidateQueryRepository: Sendable {
    func searchExact(reading: String, limit: Int) async throws -> [UserDictionaryEntry]
    func searchCommonPrefix(inputReading: String, limit: Int) async throws -> [UserDictionaryEntry]
    func searchPredictive(prefix: String, limit: Int) async throws -> [UserDictionaryEntry]
}

protocol UserDictionaryEditorRepository: Sendable {
    func add(_ entry: UserDictionaryEntry) async throws
    func update(_ entry: UserDictionaryEntry) async throws
    func delete(id: UserDictionaryEntryID) async throws
    func deleteAll() async throws
}
