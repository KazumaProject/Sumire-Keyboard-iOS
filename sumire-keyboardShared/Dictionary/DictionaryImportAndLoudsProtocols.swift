import Foundation

enum UserDictionarySourceType: Hashable, Sendable {
    case plainText
    case csv
    case customNamed(String)
}

protocol UserDictionaryImporter: Sendable {
    var sourceType: UserDictionarySourceType { get }
    func parse(data: Data) throws -> [RawImportedDictionaryRow]
}

struct RawImportedDictionaryRow: Hashable, Sendable {
    let reading: String?
    let word: String?
    let score: Int?
    let leftId: Int?
    let rightId: Int?
    let sourceLineNumber: Int?
}

struct NormalizedImportEntry: Hashable, Sendable {
    let reading: String
    let word: String
    let score: Int
    let leftId: Int
    let rightId: Int
}

struct ImportNormalizationResult: Sendable {
    let entries: [NormalizedImportEntry]
    let rejectedRows: [RawImportedDictionaryRow]
    let mergedDuplicateCount: Int
}

protocol ImportNormalizer: Sendable {
    func normalize(
        rows: [RawImportedDictionaryRow],
        sourceType: UserDictionarySourceType
    ) throws -> ImportNormalizationResult
}

struct ImportPersistResult: Sendable {
    let insertedCount: Int
    let updatedCount: Int
    let skippedCount: Int
}

protocol UserDictionaryImportCoordinator: Sendable {
    func importDictionary(data: Data, importer: any UserDictionaryImporter) async throws -> ImportPersistResult
}

struct UserDictionaryLoudsArtifacts: Sendable {
    let directoryURL: URL
    let manifestURL: URL?
}

enum UserDictionaryBuildStatus: Hashable, Sendable {
    case idle
    case building
    case validating
    case ready
    case failed(String)
}

struct UserDictionaryBuildState: Hashable, Sendable {
    let status: UserDictionaryBuildStatus
    let updatedAt: Date
    let artifactVersion: String?
    let lastErrorMessage: String?

    init(
        status: UserDictionaryBuildStatus,
        updatedAt: Date,
        artifactVersion: String? = nil,
        lastErrorMessage: String? = nil
    ) {
        self.status = status
        self.updatedAt = updatedAt
        self.artifactVersion = artifactVersion
        self.lastErrorMessage = lastErrorMessage
    }
}

protocol UserDictionaryLoudsBuilder: Sendable {
    func build(from entries: [UserDictionaryEntry]) async throws -> UserDictionaryLoudsArtifacts
}

protocol UserDictionaryLoudsValidator: Sendable {
    func validate(_ artifacts: UserDictionaryLoudsArtifacts) async throws
}

protocol UserDictionaryArtifactPublisher: Sendable {
    func publish(_ artifacts: UserDictionaryLoudsArtifacts) async throws
}

protocol UserDictionaryBuildStateRepository: Sendable {
    func load() async throws -> UserDictionaryBuildState
    func save(_ state: UserDictionaryBuildState) async throws
}
