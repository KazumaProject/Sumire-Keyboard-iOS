import Foundation

final class SQLiteLearningDictionaryRepository: @unchecked Sendable,
    LearningDictionaryLearningRepository,
    LearningDictionaryQueryRepository,
    LearningDictionaryEditorRepository {
    private let store: SQLiteDictionaryStore

    init(store: SQLiteDictionaryStore) {
        self.store = store
    }

    func recordCommittedSelection(_ selection: CommittedSelection) async throws {
        try store.recordCommittedSelection(selection)
    }

    func searchExact(reading: String, limit: Int) async throws -> [LearningDictionaryEntry] {
        try store.searchLearningExact(reading: reading, limit: limit)
    }

    func searchCommonPrefix(inputReading: String, limit: Int) async throws -> [LearningDictionaryEntry] {
        try store.searchLearningPrefix(prefix: inputReading, limit: limit)
    }

    func searchPredictive(prefix: String, limit: Int) async throws -> [LearningDictionaryEntry] {
        try store.searchLearningPrefix(prefix: prefix, limit: limit)
    }

    func searchForManagementUI(query: String, limit: Int, offset: Int) async throws -> [LearningDictionaryEntry] {
        try store.searchLearningForManagementUI(query: query, limit: limit, offset: offset)
    }

    func add(_ entry: LearningDictionaryEntry) async throws {
        try store.addLearning(entry)
    }

    func update(_ entry: LearningDictionaryEntry) async throws {
        try store.updateLearning(entry)
    }

    func delete(id: LearningDictionaryEntryID) async throws {
        try store.deleteLearning(id: id)
    }

    func deleteAll() async throws {
        try store.deleteAllLearning()
    }
}

final class SQLiteUserDictionaryRepository: @unchecked Sendable,
    UserDictionaryManagementQueryRepository,
    UserDictionaryCandidateQueryRepository,
    UserDictionaryEditorRepository {
    private let store: SQLiteDictionaryStore

    init(store: SQLiteDictionaryStore) {
        self.store = store
    }

    func searchForManagementUI(query: String, limit: Int, offset: Int) async throws -> [UserDictionaryEntry] {
        try store.searchUserForManagementUI(query: query, limit: limit, offset: offset)
    }

    func count(query: String) async throws -> Int {
        try store.countUserEntries(query: query)
    }

    func allEntries() async throws -> [UserDictionaryEntry] {
        try store.allUserEntries()
    }

    func searchExact(reading: String, limit: Int) async throws -> [UserDictionaryEntry] {
        try store.searchUserExact(reading: reading, limit: limit)
    }

    func searchCommonPrefix(inputReading: String, limit: Int) async throws -> [UserDictionaryEntry] {
        try store.searchUserPrefix(prefix: inputReading, limit: limit)
    }

    func searchPredictive(prefix: String, limit: Int) async throws -> [UserDictionaryEntry] {
        try store.searchUserPrefix(prefix: prefix, limit: limit)
    }

    func add(_ entry: UserDictionaryEntry) async throws {
        try store.addUser(entry)
    }

    func update(_ entry: UserDictionaryEntry) async throws {
        try store.updateUser(entry)
    }

    func delete(id: UserDictionaryEntryID) async throws {
        try store.deleteUser(id: id)
    }

    func deleteAll() async throws {
        try store.deleteAllUser()
    }
}

struct DictionaryRepositories: Sendable {
    let store: SQLiteDictionaryStore
    let learningRepository: SQLiteLearningDictionaryRepository
    let userRepository: SQLiteUserDictionaryRepository
    let learningCandidateSource: LearningDictionaryCandidateSource
    let userCandidateSource: UserDictionaryCandidateSource

    init(store: SQLiteDictionaryStore) {
        self.store = store
        self.learningRepository = SQLiteLearningDictionaryRepository(store: store)
        self.userRepository = SQLiteUserDictionaryRepository(store: store)
        self.learningCandidateSource = LearningDictionaryCandidateSource(store: store)
        self.userCandidateSource = UserDictionaryCandidateSource(store: store)
    }
}
