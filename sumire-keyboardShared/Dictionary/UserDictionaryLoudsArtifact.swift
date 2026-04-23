import Foundation

enum UserDictionaryArtifactError: Error, LocalizedError {
    case artifactNotFound
    case invalidArtifact(String)

    var errorDescription: String? {
        switch self {
        case .artifactNotFound:
            return "User dictionary artifact was not found."
        case .invalidArtifact(let message):
            return "Invalid user dictionary artifact: \(message)"
        }
    }
}

struct UserDictionaryArtifactLocator: Sendable {
    let rootDirectoryURL: URL

    init(rootDirectoryURL: URL = DictionaryRepositoryContainer.sharedDictionaryDirectoryURL()) {
        self.rootDirectoryURL = rootDirectoryURL
    }

    var artifactsDirectoryURL: URL {
        rootDirectoryURL.appendingPathComponent("UserDictionaryArtifacts", isDirectory: true)
    }

    var buildsDirectoryURL: URL {
        artifactsDirectoryURL.appendingPathComponent("builds", isDirectory: true)
    }

    var currentManifestURL: URL {
        artifactsDirectoryURL.appendingPathComponent("current-manifest.json")
    }

    var buildStateURL: URL {
        artifactsDirectoryURL.appendingPathComponent("build-state.json")
    }

    func buildDirectoryURL(version: String) -> URL {
        buildsDirectoryURL.appendingPathComponent(version, isDirectory: true)
    }
}

private struct UserDictionaryArtifactManifest: Codable {
    let version: String
    let builtAt: Double
    let artifactsDirectoryRelativePath: String
}

private struct PublishedUserDictionaryArtifact {
    let version: String
    let builtAt: Date
    let artifactsDirectoryURL: URL

    static func loadCurrent(
        locator: UserDictionaryArtifactLocator = UserDictionaryArtifactLocator()
    ) throws -> PublishedUserDictionaryArtifact {
        let manifestData = try Data(contentsOf: locator.currentManifestURL)
        let manifest = try JSONDecoder().decode(UserDictionaryArtifactManifest.self, from: manifestData)
        let artifactsDirectoryURL = locator.artifactsDirectoryURL.appendingPathComponent(
            manifest.artifactsDirectoryRelativePath,
            isDirectory: true
        )
        return PublishedUserDictionaryArtifact(
            version: manifest.version,
            builtAt: Date(timeIntervalSince1970: manifest.builtAt),
            artifactsDirectoryURL: artifactsDirectoryURL
        )
    }
}

final class UserDictionaryBinaryArtifact: @unchecked Sendable {
    let version: String
    let builtAt: Date
    private let dictionary: MozcDictionary

    init(version: String, builtAt: Date, dictionary: MozcDictionary) {
        self.version = version
        self.builtAt = builtAt
        self.dictionary = dictionary
    }

    static func loadCurrent(
        locator: UserDictionaryArtifactLocator = UserDictionaryArtifactLocator()
    ) throws -> UserDictionaryBinaryArtifact {
        let published = try PublishedUserDictionaryArtifact.loadCurrent(locator: locator)
        return try load(
            version: published.version,
            builtAt: published.builtAt,
            artifactsDirectoryURL: published.artifactsDirectoryURL
        )
    }

    static func load(
        version: String,
        builtAt: Date,
        artifactsDirectoryURL: URL
    ) throws -> UserDictionaryBinaryArtifact {
        guard MozcArtifactIO.containsDictionaryArtifacts(at: artifactsDirectoryURL) else {
            throw UserDictionaryArtifactError.artifactNotFound
        }

        let posTableURL = artifactsDirectoryURL.appendingPathComponent(MozcDictionary.posTableFileName)
        guard FileManager.default.fileExists(atPath: posTableURL.path) else {
            throw UserDictionaryArtifactError.invalidArtifact("POS table is missing.")
        }

        let dictionary = try MozcDictionary(artifactsDirectory: artifactsDirectoryURL)
        return UserDictionaryBinaryArtifact(
            version: version,
            builtAt: builtAt,
            dictionary: dictionary
        )
    }

    func searchExact(reading: String, limit: Int) -> [Candidate] {
        guard reading.isEmpty == false, limit > 0 else {
            return []
        }

        let matches = dictionary.prefixMatches(
            in: Array(reading),
            from: 0,
            mode: .commonPrefix
        )
            .filter { $0.length == reading.count }

        var entries: [DictionaryEntry] = []
        entries.reserveCapacity(limit)
        for match in matches {
            for entry in match.entries where entry.yomi == reading {
                entries.append(entry)
                if entries.count >= limit {
                    break
                }
            }
            if entries.count >= limit {
                break
            }
        }

        return entries
            .sorted(by: Self.entrySort)
            .prefix(limit)
            .map(Self.candidate(from:))
    }

    func searchCommonPrefix(inputReading: String, limit: Int) -> [Candidate] {
        guard inputReading.isEmpty == false, limit > 0 else {
            return []
        }

        return entries(forPrefix: inputReading, limit: limit)
    }

    func searchPredictive(prefix: String, limit: Int) -> [Candidate] {
        guard prefix.isEmpty == false, limit > 0 else {
            return []
        }

        return entries(
            forPrefix: prefix,
            limit: limit
        )
    }

    private func entries(forPrefix prefix: String, limit: Int) -> [Candidate] {
        dictionary.predictiveEntries(
            for: prefix,
            predictivePrefixLength: prefix.count,
            limit: limit
        ).map(Self.candidate(from:))
    }

    private static func candidate(from entry: DictionaryEntry) -> Candidate {
        Candidate(
            reading: entry.yomi,
            word: entry.surface,
            consumedReadingLength: entry.yomi.count,
            sourceKind: .user,
            lexicalInfo: CandidateLexicalInfo(
                score: entry.cost,
                leftId: entry.leftId,
                rightId: entry.rightId
            )
        )
    }

    private static func entrySort(_ lhs: DictionaryEntry, _ rhs: DictionaryEntry) -> Bool {
        if lhs.cost != rhs.cost {
            return lhs.cost < rhs.cost
        }
        if lhs.yomi.count != rhs.yomi.count {
            return lhs.yomi.count > rhs.yomi.count
        }
        return lhs.surface < rhs.surface
    }
}

struct FileUserDictionaryLoudsBuilder: UserDictionaryLoudsBuilder {
    let locator: UserDictionaryArtifactLocator

    init(locator: UserDictionaryArtifactLocator = UserDictionaryArtifactLocator()) {
        self.locator = locator
    }

    func build(from entries: [UserDictionaryEntry]) async throws -> UserDictionaryLoudsArtifacts {
        let version = Self.makeVersion()
        let buildDirectoryURL = locator.buildDirectoryURL(version: version)
        try FileManager.default.createDirectory(at: buildDirectoryURL, withIntermediateDirectories: true)

        let dictionaryEntries = entries
            .filter { $0.reading.isEmpty == false && $0.word.isEmpty == false }
            .map {
                DictionaryEntry(
                    yomi: $0.reading,
                    leftId: $0.leftId,
                    rightId: $0.rightId,
                    cost: $0.score,
                    surface: $0.word
                )
            }

        try MozcArtifactIO.writeDictionaryArtifacts(from: dictionaryEntries, to: buildDirectoryURL)

        let manifest = UserDictionaryArtifactManifest(
            version: version,
            builtAt: Date().timeIntervalSince1970,
            artifactsDirectoryRelativePath: "builds/\(version)"
        )
        let manifestURL = buildDirectoryURL.appendingPathComponent("manifest.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        return UserDictionaryLoudsArtifacts(
            directoryURL: buildDirectoryURL,
            manifestURL: manifestURL
        )
    }

    private static func makeVersion() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }
}

struct FileUserDictionaryLoudsValidator: UserDictionaryLoudsValidator {
    func validate(_ artifacts: UserDictionaryLoudsArtifacts) async throws {
        guard let manifestURL = artifacts.manifestURL else {
            throw UserDictionaryArtifactError.invalidArtifact("Manifest URL is missing.")
        }

        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(UserDictionaryArtifactManifest.self, from: manifestData)
        let artifactsDirectoryURL = artifacts.directoryURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(manifest.artifactsDirectoryRelativePath, isDirectory: true)

        guard MozcArtifactIO.containsDictionaryArtifacts(at: artifactsDirectoryURL) else {
            throw UserDictionaryArtifactError.invalidArtifact("Required dictionary artifact files are missing.")
        }

        let posTableURL = artifactsDirectoryURL.appendingPathComponent(MozcDictionary.posTableFileName)
        guard FileManager.default.fileExists(atPath: posTableURL.path) else {
            throw UserDictionaryArtifactError.invalidArtifact("POS table file is missing.")
        }

        _ = try UserDictionaryBinaryArtifact.load(
            version: manifest.version,
            builtAt: Date(timeIntervalSince1970: manifest.builtAt),
            artifactsDirectoryURL: artifactsDirectoryURL
        )
    }
}

struct FileUserDictionaryArtifactPublisher: UserDictionaryArtifactPublisher {
    let locator: UserDictionaryArtifactLocator

    init(locator: UserDictionaryArtifactLocator = UserDictionaryArtifactLocator()) {
        self.locator = locator
    }

    func publish(_ artifacts: UserDictionaryLoudsArtifacts) async throws {
        guard let manifestURL = artifacts.manifestURL else {
            throw UserDictionaryArtifactError.invalidArtifact("Manifest URL is missing.")
        }
        try FileManager.default.createDirectory(at: locator.artifactsDirectoryURL, withIntermediateDirectories: true)
        let data = try Data(contentsOf: manifestURL)
        try data.write(to: locator.currentManifestURL, options: .atomic)
    }
}

final class FileUserDictionaryBuildStateRepository: @unchecked Sendable, UserDictionaryBuildStateRepository {
    private struct StoredState: Codable {
        let status: String
        let failedMessage: String?
        let updatedAt: Double
        let artifactVersion: String?
        let lastErrorMessage: String?
    }

    private let locator: UserDictionaryArtifactLocator
    private let queue = DispatchQueue(label: "com.kazumaproject.sumire-keyboard.user-dictionary-build-state")

    init(locator: UserDictionaryArtifactLocator = UserDictionaryArtifactLocator()) {
        self.locator = locator
    }

    func load() async throws -> UserDictionaryBuildState {
        try queue.sync {
            guard FileManager.default.fileExists(atPath: locator.buildStateURL.path) else {
                return UserDictionaryBuildState(status: .idle, updatedAt: Date())
            }
            let data = try Data(contentsOf: locator.buildStateURL)
            let stored = try JSONDecoder().decode(StoredState.self, from: data)
            return Self.state(from: stored)
        }
    }

    func save(_ state: UserDictionaryBuildState) async throws {
        try queue.sync {
            try FileManager.default.createDirectory(at: locator.artifactsDirectoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Self.stored(from: state))
            try data.write(to: locator.buildStateURL, options: .atomic)
        }
    }

    private static func state(from stored: StoredState) -> UserDictionaryBuildState {
        let status: UserDictionaryBuildStatus
        switch stored.status {
        case "building":
            status = .building
        case "validating":
            status = .validating
        case "ready":
            status = .ready
        case "failed":
            status = .failed(stored.failedMessage ?? stored.lastErrorMessage ?? "Unknown error")
        default:
            status = .idle
        }
        return UserDictionaryBuildState(
            status: status,
            updatedAt: Date(timeIntervalSince1970: stored.updatedAt),
            artifactVersion: stored.artifactVersion,
            lastErrorMessage: stored.lastErrorMessage
        )
    }

    private static func stored(from state: UserDictionaryBuildState) -> StoredState {
        let status: String
        let failedMessage: String?
        switch state.status {
        case .idle:
            status = "idle"
            failedMessage = nil
        case .building:
            status = "building"
            failedMessage = nil
        case .validating:
            status = "validating"
            failedMessage = nil
        case .ready:
            status = "ready"
            failedMessage = nil
        case .failed(let message):
            status = "failed"
            failedMessage = message
        }
        return StoredState(
            status: status,
            failedMessage: failedMessage,
            updatedAt: state.updatedAt.timeIntervalSince1970,
            artifactVersion: state.artifactVersion,
            lastErrorMessage: state.lastErrorMessage
        )
    }
}
