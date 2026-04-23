import Foundation
import Testing

struct KeyboardDictionaryTests {
    @Test func englishEngineProvidesCaseVariantsAndDictionaryPredictions() throws {
        let engine = try Self.makeEnglishEngine()

        let input = try #require(Self.findDictionaryBackedEnglishInput(using: engine))
        let predictions = engine.getPrediction(input: input)

        #expect(predictions.contains { $0.word == input })
        #expect(predictions.contains { $0.word == input.replacingFirstCharacter { $0.uppercased() } })
        #expect(predictions.contains { $0.word == input.uppercased() })
        #expect(predictions.contains { $0.word.lowercased() != input.lowercased() })
    }

    @Test func englishFallbackCandidatesAreReturnedWithoutEngine() {
        let fallbackCandidates = EnglishEngine.fallbackPrediction(input: "hel")

        #expect(fallbackCandidates.map(\.word) == ["hel", "Hel", "HEL"])
    }

    @Test func englishPredictionsAreDeduplicatedBySurface() throws {
        let engine = try Self.makeEnglishEngine()
        let predictions = engine.getPrediction(input: "hel")
        let words = predictions.map(\.word)

        #expect(Set(words).count == words.count)
    }

    @Test func missingEnglishArtifactsFailGracefully() {
        let missingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        #expect(EnglishArtifactIO.containsArtifacts(at: missingDirectory) == false)

        var didThrow = false
        do {
            _ = try EnglishDictionary(artifactsDirectory: missingDirectory)
        } catch {
            didThrow = true
        }
        #expect(didThrow)
    }

    @Test func auxiliaryCandidatesPreferLowerScoreForDuplicateTextAcrossSources() {
        let mainDictionary = MozcDictionary(entries: [
            DictionaryEntry(yomi: "あ", leftId: 0, rightId: 0, cost: 900, surface: "重複候補")
        ])
        let emojiDictionary = MozcDictionary(entries: [
            DictionaryEntry(yomi: "あい", leftId: 0, rightId: 0, cost: 100, surface: "重複候補")
        ])
        let converter = KanaKanjiConverter(
            dictionarySet: LoadedDictionarySet(
                main: mainDictionary,
                supplementals: SupplementalDictionaryStore([.emoji: emojiDictionary])
            )
        )

        let candidates = converter.auxiliaryCandidates(
            "あい",
            options: ConversionOptions(yomiSearchMode: .commonPrefixPlusPredictive),
            limit: 10
        )

        let duplicate = candidates.first { $0.text == "重複候補" }
        #expect(duplicate?.score == 100)
    }

    @Test func commonWordsHaveExpectedTopCandidatesAndScores() throws {
        let converter = try Self.makeArtifactBackedConverter()

        let watashiCandidates = converter.convert(
            "わたし",
            options: ConversionOptions(limit: 20, beamWidth: 50, yomiSearchMode: .commonPrefixPlusOmission)
        )
        let watashiTop = try #require(watashiCandidates.first)
        #expect(watashiTop.text == "私", "expected top for わたし to be 私, got \(watashiTop.text) score=\(watashiTop.score)")
        #expect(watashiTop.score < 10_000, "expected dictionary-derived score for わたし top candidate, got \(watashiTop.score)")

        let nokogiriCandidates = converter.convert(
            "のこぎり",
            options: ConversionOptions(limit: 20, beamWidth: 50, yomiSearchMode: .commonPrefixPlusOmission)
        )
        let nokogiriTop = try #require(nokogiriCandidates.first)
        #expect(nokogiriTop.text == "ノコギリ", "expected top for のこぎり to be ノコギリ, got \(nokogiriTop.text) score=\(nokogiriTop.score)")
        #expect(nokogiriTop.score < 10_000, "expected dictionary-derived score for のこぎり top candidate, got \(nokogiriTop.score)")
    }

    @Test func singleKanjiSupplementalProducesCandidates() throws {
        let resourceDirectory = Self.repositoryRoot()
            .appendingPathComponent("sumire-keyboardKeyboard/KanaKanjiResources", isDirectory: true)
        let sharedPOSTableURL = resourceDirectory.appendingPathComponent("pos_table.bin")
        let mainDirectory = resourceDirectory.appendingPathComponent("main", isDirectory: true)
        let singleKanjiDirectory = resourceDirectory.appendingPathComponent(
            SupplementalDictionaryKind.singleKanji.resourceDirectoryName,
            isDirectory: true
        )
        let connectionMatrixURL = mainDirectory.appendingPathComponent("connection_single_column.bin")

        #expect(FileManager.default.fileExists(atPath: sharedPOSTableURL.path))
        #expect(MozcArtifactIO.containsDictionaryArtifacts(at: singleKanjiDirectory))
        #expect(FileManager.default.fileExists(atPath: singleKanjiDirectory.appendingPathComponent("pos_table.bin").path) == false)

        let mainDictionary = try MozcDictionary(
            artifactsDirectory: mainDirectory,
            sharedPOSTableURL: sharedPOSTableURL
        )
        let singleKanjiDictionary = try MozcDictionary(
            artifactsDirectory: singleKanjiDirectory,
            sharedPOSTableURL: sharedPOSTableURL
        )
        let converter = KanaKanjiConverter(
            dictionarySet: LoadedDictionarySet(
                main: mainDictionary,
                supplementals: SupplementalDictionaryStore([.singleKanji: singleKanjiDictionary])
            ),
            connectionMatrix: try ConnectionMatrix.loadBinaryBigEndianInt16(connectionMatrixURL)
        )

        let candidates = converter.singleKanjiCandidates(
            "あ",
            options: ConversionOptions(limit: 100, beamWidth: 20, yomiSearchMode: .commonPrefix)
        )

        #expect(candidates.contains { $0.text == "亜" })
        #expect(candidates.contains { $0.text == "阿" })
    }

    @Test func mainNBestLimitDoesNotIncludeSingleKanjiSupplemental() throws {
        let mainDictionary = MozcDictionary(entries: [
            DictionaryEntry(yomi: "あ", leftId: 0, rightId: 0, cost: 10, surface: "main-a")
        ])
        let singleKanjiDictionary = MozcDictionary(entries: [
            DictionaryEntry(yomi: "あ", leftId: 0, rightId: 0, cost: 1, surface: "亜")
        ])
        let converter = KanaKanjiConverter(
            dictionarySet: LoadedDictionarySet(
                main: mainDictionary,
                supplementals: SupplementalDictionaryStore([.singleKanji: singleKanjiDictionary])
            )
        )

        let mainCandidates = converter.convert("あ", options: ConversionOptions(limit: 10))
        let singleKanjiCandidates = converter.singleKanjiCandidates("あ", options: ConversionOptions())

        #expect(mainCandidates.map(\.text) == ["main-a"])
        #expect(singleKanjiCandidates.map(\.text) == ["亜"])
    }

    @Test func auxiliaryCandidatesExcludeSingleKanjiAndSortByScore() throws {
        let mainDictionary = MozcDictionary(entries: [
            DictionaryEntry(yomi: "あい", leftId: 0, rightId: 0, cost: 500, surface: "main-full"),
            DictionaryEntry(yomi: "あ", leftId: 0, rightId: 0, cost: 300, surface: "main-partial")
        ])
        let emojiDictionary = MozcDictionary(entries: [
            DictionaryEntry(yomi: "あい", leftId: 0, rightId: 0, cost: 100, surface: "emoji-full")
        ])
        let singleKanjiDictionary = MozcDictionary(entries: [
            DictionaryEntry(yomi: "あい", leftId: 0, rightId: 0, cost: 1, surface: "亜")
        ])
        let converter = KanaKanjiConverter(
            dictionarySet: LoadedDictionarySet(
                main: mainDictionary,
                supplementals: SupplementalDictionaryStore([
                    .emoji: emojiDictionary,
                    .singleKanji: singleKanjiDictionary
                ])
            )
        )

        let auxiliaryCandidates = converter.auxiliaryCandidates(
            "あい",
            options: ConversionOptions(yomiSearchMode: .commonPrefixPlusPredictive),
            limit: 10
        )

        #expect(auxiliaryCandidates.map(\.text).prefix(2) == ["emoji-full", "main-partial"])
        #expect(auxiliaryCandidates.contains { $0.text == "亜" } == false)
    }

    @Test func singleKanjiUsesSharedPOSTableEvenIfLocalPOSTableExists() throws {
        let resourceDirectory = Self.repositoryRoot()
            .appendingPathComponent("sumire-keyboardKeyboard/KanaKanjiResources", isDirectory: true)
        let originalSingleKanjiDirectory = resourceDirectory.appendingPathComponent("single_kanji", isDirectory: true)
        let sharedPOSTableURL = resourceDirectory.appendingPathComponent("pos_table.bin")

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        for fileName in MozcDictionary.supplementalArtifactFileNames {
            try FileManager.default.copyItem(
                at: originalSingleKanjiDirectory.appendingPathComponent(fileName),
                to: temporaryDirectory.appendingPathComponent(fileName)
            )
        }

        var localPOSTable = Data()
        localPOSTable.append(contentsOf: UInt32(1).littleEndianBytes)
        localPOSTable.append(contentsOf: Int16(0).littleEndianBytes)
        localPOSTable.append(contentsOf: Int16(0).littleEndianBytes)
        try localPOSTable.write(to: temporaryDirectory.appendingPathComponent("pos_table.bin"))

        let dictionary = try MozcDictionary(
            artifactsDirectory: temporaryDirectory,
            sharedPOSTableURL: sharedPOSTableURL
        )
        let matches = dictionary.prefixMatches(in: Array("あ"), from: 0)
        let firstEntry = try #require(matches.first?.entries.first)

        #expect(firstEntry.leftId == 1920)
        #expect(firstEntry.rightId == 1927)
    }

    private static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func makeArtifactBackedConverter() throws -> KanaKanjiConverter {
        let resourceDirectory = repositoryRoot()
            .appendingPathComponent("sumire-keyboardKeyboard/KanaKanjiResources", isDirectory: true)
        let mainDirectory = resourceDirectory.appendingPathComponent("main", isDirectory: true)
        let sharedPOSTableURL = resourceDirectory.appendingPathComponent("pos_table.bin")
        let connectionMatrixURL = mainDirectory.appendingPathComponent(MozcDictionary.connectionMatrixFileName)

        let mainDictionary = try MozcDictionary(
            artifactsDirectory: mainDirectory,
            sharedPOSTableURL: sharedPOSTableURL
        )

        var supplementals: [SupplementalDictionaryKind: MozcDictionary] = [:]
        for kind in SupplementalDictionaryKind.allCases {
            let directory = resourceDirectory.appendingPathComponent(kind.resourceDirectoryName, isDirectory: true)
            guard MozcArtifactIO.containsDictionaryArtifacts(at: directory) else {
                continue
            }
            supplementals[kind] = try MozcDictionary(
                artifactsDirectory: directory,
                sharedPOSTableURL: sharedPOSTableURL
            )
        }

        let dictionarySet = LoadedDictionarySet(
            main: mainDictionary,
            supplementals: SupplementalDictionaryStore(supplementals)
        )
        let connectionMatrix = try ConnectionMatrix.loadBinaryBigEndianInt16(connectionMatrixURL)
        return KanaKanjiConverter(dictionarySet: dictionarySet, connectionMatrix: connectionMatrix)
    }

    private static func makeEnglishEngine() throws -> EnglishEngine {
        let englishDirectory = repositoryRoot()
            .appendingPathComponent("sumire-keyboardKeyboard/KanaKanjiResources/english", isDirectory: true)
        #expect(EnglishArtifactIO.containsArtifacts(at: englishDirectory))
        let dictionary = try EnglishDictionary(artifactsDirectory: englishDirectory)
        return EnglishEngine(dictionary: dictionary)
    }

    private static func findDictionaryBackedEnglishInput(using engine: EnglishEngine) -> String? {
        ["hel", "app", "sum", "pro", "con", "de", "a"]
            .first { input in
                engine.getPrediction(input: input)
                    .contains { candidate in
                        candidate.word.lowercased() != input.lowercased()
                    }
            }
    }
}

private extension UInt32 {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: littleEndian) { Array($0) }
    }
}

private extension Int16 {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: littleEndian) { Array($0) }
    }
}

private extension String {
    func replacingFirstCharacter(_ transform: (Character) -> String) -> String {
        guard let first else {
            return self
        }

        var output = String(self)
        output.replaceSubrange(startIndex...startIndex, with: transform(first))
        return output
    }
}
