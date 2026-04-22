import Foundation
import Testing

struct KeyboardDictionaryTests {
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
