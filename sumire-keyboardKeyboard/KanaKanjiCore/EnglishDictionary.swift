import Foundation

struct EnglishTokenEntry: Sendable {
    let wordCost: Int16
    let nodeId: Int32
}

struct EnglishTokenArray: Sendable {
    let wordCost: [Int16]
    let nodeId: [Int32]
    let postingsBits: CompatibleBitVector

    func tokens(forTermId termId: Int) -> [EnglishTokenEntry] {
        let p0 = postingsBits.select0(termId + 1)
        let p1 = postingsBits.select0(termId + 2)
        guard p0 >= 0, p1 >= 0 else {
            return []
        }

        let begin = postingsBits.rank1(p0)
        let end = postingsBits.rank1(p1)
        guard begin <= end, end <= wordCost.count, end <= nodeId.count else {
            return []
        }

        return (begin..<end).map {
            EnglishTokenEntry(wordCost: wordCost[$0], nodeId: nodeId[$0])
        }
    }
}

enum EnglishDictionaryError: Error, LocalizedError {
    case artifactNotFound(URL)

    var errorDescription: String? {
        switch self {
        case .artifactNotFound(let url):
            return "English dictionary artifact not found: \(url.path)"
        }
    }
}

enum EnglishArtifactIO {
    static let artifactFileNames = ["reading.dat", "word.dat", "token.dat"]

    static func containsArtifacts(at directory: URL) -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }

        return artifactFileNames.allSatisfy { fileName in
            fileManager.fileExists(atPath: directory.appendingPathComponent(fileName).path)
        }
    }

    static func loadArtifacts(from directory: URL) throws -> (
        reading: CompatibleLOUDS,
        word: CompatibleLOUDS,
        tokens: EnglishTokenArray
    ) {
        let readingURL = directory.appendingPathComponent("reading.dat")
        let wordURL = directory.appendingPathComponent("word.dat")
        let tokenURL = directory.appendingPathComponent("token.dat")

        for url in [readingURL, wordURL, tokenURL] {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw EnglishDictionaryError.artifactNotFound(url)
            }
        }

        return (
            reading: try readLOUDS(readingURL, withTermIds: true),
            word: try readLOUDS(wordURL, withTermIds: false),
            tokens: try readTokenArray(tokenURL)
        )
    }

    private static func readLOUDS(_ url: URL, withTermIds: Bool) throws -> CompatibleLOUDS {
        var reader = BinaryReader(data: try Data(contentsOf: url, options: [.mappedIfSafe]))
        let lbs = try readBitVector(reader: &reader)
        let leaf = try readBitVector(reader: &reader)
        let labelCount = try reader.readIntCount()
        let labels = try reader.readUInt16ArrayLE(count: labelCount)

        let termIds: [Int32]?
        if withTermIds {
            let termCount = try reader.readIntCount()
            termIds = try reader.readInt32ArrayLE(count: termCount)
        } else {
            termIds = nil
        }

        return CompatibleLOUDS(lbs: lbs, isLeaf: leaf, labels: labels, termIds: termIds)
    }

    private static func readTokenArray(_ url: URL) throws -> EnglishTokenArray {
        var reader = BinaryReader(data: try Data(contentsOf: url, options: [.mappedIfSafe]))
        let costCount = Int(try reader.readUInt32LE())
        let costs = try reader.readInt16ArrayLE(count: costCount)
        let nodeCount = Int(try reader.readUInt32LE())
        let nodes = try reader.readInt32ArrayLE(count: nodeCount)
        return EnglishTokenArray(
            wordCost: costs,
            nodeId: nodes,
            postingsBits: try readBitVector(reader: &reader)
        )
    }

    private static func readBitVector(reader: inout BinaryReader) throws -> CompatibleBitVector {
        let bitCount = try reader.readIntCount()
        let wordCount = try reader.readIntCount()
        let words = try reader.readUInt64ArrayLE(count: wordCount)
        return CompatibleBitVector(bitCount: bitCount, words: words)
    }
}

struct EnglishDictionary: Sendable {
    let reading: CompatibleLOUDS
    let word: CompatibleLOUDS
    let tokens: EnglishTokenArray

    init(artifactsDirectory directory: URL) throws {
        let artifacts = try EnglishArtifactIO.loadArtifacts(from: directory)
        self.reading = artifacts.reading
        self.word = artifacts.word
        self.tokens = artifacts.tokens
    }
}

struct EnglishEngine: Sendable {
    struct Candidate: Sendable, Equatable {
        let reading: String
        let word: String
        let score: Int
    }

    private let dictionary: EnglishDictionary

    init(dictionary: EnglishDictionary) {
        self.dictionary = dictionary
    }

    func getPrediction(input: String) -> [Candidate] {
        guard input.isEmpty == false else {
            return []
        }

        let hits = dictionary.reading.predictiveSearchTermIds(Array(input.lowercased().utf16))
        var candidates: [Candidate] = []
        candidates.reserveCapacity(hits.count * 2)

        for (reading, termId) in hits {
            for token in dictionary.tokens.tokens(forTermId: termId) {
                let word = token.nodeId == -1
                    ? reading
                    : dictionary.word.getLetter(nodeIndex: Int(token.nodeId))
                candidates.append(Candidate(
                    reading: reading,
                    word: word,
                    score: Int(token.wordCost)
                ))
            }
        }

        return candidates.sorted {
            if $0.score != $1.score {
                return $0.score < $1.score
            }
            return $0.word < $1.word
        }
    }
}
