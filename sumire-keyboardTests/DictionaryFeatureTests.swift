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
        // exact match は常に動作する
        #expect(source.searchExact(reading: "すみれ", limit: 10).map(\.word) == ["菫"])
        // 1文字入力では prefix 検索は動かない（通常予測変換ルール: input.count < 3 → 空を返す）
        #expect(source.searchCommonPrefix(inputReading: "す", limit: 10).map(\.word).isEmpty)
        // 3文字以上では prefix 検索が動く（maxReadingLength=5、"すみれ"=3文字は範囲内）
        #expect(source.searchCommonPrefix(inputReading: "すみれ", limit: 10).map(\.word).contains("菫"))
        // 2文字入力では predictive 検索は動かない
        #expect(source.searchPredictive(prefix: "すみ", limit: 10).map(\.word).isEmpty)
        // 4文字以上では predictive 検索が動く（maxReadingLength=6、"すみれいろ"=6文字は範囲内）
        #expect(source.searchPredictive(prefix: "すみれい", limit: 10).map(\.word).contains("菫色"))
    }

    // MARK: - Regression tests

    /// Test 1: artifact が存在していても、artifact 作成後に SQLite へ追加した単語が
    /// UserDictionaryCandidateSource の検索結果に含まれること。
    @Test func userDictionaryCandidateSourceReturnsSQLiteResultEvenWhenArtifactExists() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repositories = try makeRepositories(directory: directory)
        let locator = UserDictionaryArtifactLocator(
            rootDirectoryURL: directory.appendingPathComponent("Dictionary", isDirectory: true)
        )

        // artifact ビルド前に既存エントリを追加してビルド
        let oldEntry = UserDictionaryEntry(
            id: UUID(), reading: "てすと", word: "テスト", score: 100,
            leftId: 1851, rightId: 1851, updatedAt: Date()
        )
        try await repositories.userRepository.add(oldEntry)

        let builder = FileUserDictionaryLoudsBuilder(locator: locator)
        let artifacts = try await builder.build(from: try await repositories.userRepository.allEntries())
        try await FileUserDictionaryLoudsValidator().validate(artifacts)
        try await FileUserDictionaryArtifactPublisher(locator: locator).publish(artifacts)

        // artifact 作成後に新規エントリを SQLite だけに追加
        let newEntry = UserDictionaryEntry(
            id: UUID(), reading: "しんき", word: "新規", score: 90,
            leftId: 1851, rightId: 1851, updatedAt: Date()
        )
        try await repositories.userRepository.add(newEntry)

        // artifact は存在するが、SQLite に追加した "新規" も検索結果に含まれるべき
        let source = UserDictionaryCandidateSource(store: repositories.store, locator: locator)
        let exactResults = source.searchExact(reading: "しんき", limit: 10)
        #expect(exactResults.map(\.word).contains("新規"),
                "artifact 作成後に SQLite へ追加したエントリが searchExact で返る必要があります")

        // searchCommonPrefix は 3文字以上から動く（通常予測変換ルール）。
        // "しんき" = 3文字なので検索が動き、SQLite の新規エントリが返るべき。
        let prefixResults = source.searchCommonPrefix(inputReading: "しんき", limit: 10)
        #expect(prefixResults.map(\.word).contains("新規"),
                "artifact 作成後に SQLite へ追加したエントリが searchCommonPrefix (3文字) で返る必要があります")
    }

    /// Test 2: artifact に同じ reading+word がある場合、SQLite 側の候補が優先されること。
    /// (SQLite エントリの score が artifact エントリより低く設定されており、SQLite 優先なら score=1 が返る)
    @Test func userDictionaryCandidateSourcePrioritizesSQLiteOverArtifactForSameDedupKey() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repositories = try makeRepositories(directory: directory)
        let locator = UserDictionaryArtifactLocator(
            rootDirectoryURL: directory.appendingPathComponent("Dictionary", isDirectory: true)
        )

        // score=999 で artifact をビルド
        let artifactEntry = UserDictionaryEntry(
            id: UUID(), reading: "すみれ", word: "菫", score: 999,
            leftId: 1851, rightId: 1851, updatedAt: Date()
        )
        try await repositories.userRepository.add(artifactEntry)
        let builder = FileUserDictionaryLoudsBuilder(locator: locator)
        let artifacts = try await builder.build(from: try await repositories.userRepository.allEntries())
        try await FileUserDictionaryLoudsValidator().validate(artifacts)
        try await FileUserDictionaryArtifactPublisher(locator: locator).publish(artifacts)

        // SQLite の同エントリを score=1 に更新（artifact 後の変更を想定）
        var updated = artifactEntry
        updated = UserDictionaryEntry(
            id: artifactEntry.id, reading: "すみれ", word: "菫", score: 1,
            leftId: 1851, rightId: 1851, updatedAt: Date()
        )
        try await repositories.userRepository.update(updated)

        let source = UserDictionaryCandidateSource(store: repositories.store, locator: locator)
        let results = source.searchExact(reading: "すみれ", limit: 10)

        // 重複は 1件に dedup されるべき
        #expect(results.filter { $0.word == "菫" }.count == 1,
                "同じ reading+word の候補は 1件に dedup されるべきです")
        // SQLite 側 (score=1) が優先されているべき
        let sumire = try #require(results.first { $0.word == "菫" })
        #expect(sumire.lexicalInfo?.score == 1,
                "SQLite 側の候補 (score=1) が artifact 側 (score=999) より優先されるべきです")
    }

    /// Test 3: learning 候補が system 候補より sourcePriority で優先され、
    /// system 候補と同じ reading+word を持っていても dedup で消されないこと。
    @Test func candidatePipelinePrefersLearningOverSystemForSameDedupKey() {
        let system = StubCandidateSource(kind: .systemMain, candidates: [
            Candidate(
                reading: "すみれ",
                word: "菫",
                consumedReadingLength: 3,
                sourceKind: .systemMain,
                lexicalInfo: CandidateLexicalInfo(score: 500, leftId: 1, rightId: 1)
            )
        ])
        let learning = StubCandidateSource(kind: .learning, candidates: [
            Candidate(
                reading: "すみれ",
                word: "菫",
                consumedReadingLength: 3,
                sourceKind: .learning,
                lexicalInfo: CandidateLexicalInfo(score: 0, leftId: 1, rightId: 1)
            )
        ])
        // 正しい優先順位: user > learning > systemMain
        let pipeline = CandidatePipeline(
            sources: [system, learning],
            mergePolicy: CandidateMergePolicy(
                sourcePriority: [.user, .learning, .systemMain, .systemAuxiliary, .systemSingleKanji, .systemEnglish, .fallback, .direct],
                scoreStrategy: .max,
                totalLimit: 10,
                includesAuxiliaryCandidates: true
            )
        )

        let candidates = pipeline.candidates(for: "すみれ", limit: 10)

        // 重複は 1件にまとめられ、learning が優先されるべき
        #expect(candidates.count == 1,
                "同じ reading+word の候補は 1件に dedup されるべきです")
        #expect(candidates.first?.sourceKind == .learning,
                "learning は systemMain より sourcePriority が高いため learning 候補が残るべきです")
    }

    /// Test 4 (user > learning > system): 同じ reading+word を持つ user/learning/system 候補が
    /// 揃っているとき、user dictionary 候補が最優先で残ること。
    @Test func candidatePipelinePrefersUserOverLearningAndSystemForSameDedupKey() {
        let system = StubCandidateSource(kind: .systemMain, candidates: [
            Candidate(
                reading: "すみれ",
                word: "菫",
                consumedReadingLength: 3,
                sourceKind: .systemMain,
                lexicalInfo: CandidateLexicalInfo(score: 500, leftId: 1, rightId: 1)
            )
        ])
        let learning = StubCandidateSource(kind: .learning, candidates: [
            Candidate(
                reading: "すみれ",
                word: "菫",
                consumedReadingLength: 3,
                sourceKind: .learning,
                lexicalInfo: CandidateLexicalInfo(score: 200, leftId: 1, rightId: 1)
            )
        ])
        let user = StubCandidateSource(kind: .user, candidates: [
            Candidate(
                reading: "すみれ",
                word: "菫",
                consumedReadingLength: 3,
                sourceKind: .user,
                lexicalInfo: CandidateLexicalInfo(score: 1, leftId: 1, rightId: 1)
            )
        ])
        let pipeline = CandidatePipeline(
            sources: [system, learning, user],
            mergePolicy: CandidateMergePolicy(
                sourcePriority: [.user, .learning, .systemMain, .systemAuxiliary, .systemSingleKanji, .systemEnglish, .fallback, .direct],
                scoreStrategy: .max,
                totalLimit: 10,
                includesAuxiliaryCandidates: true
            )
        )

        let candidates = pipeline.candidates(for: "すみれ", limit: 10)

        #expect(candidates.count == 1,
                "同じ reading+word の候補は 1件に dedup されるべきです")
        #expect(candidates.first?.sourceKind == .user,
                "user dictionary が最優先のため user 候補が残るべきです")
    }

    // MARK: - Predictive search policy tests (pure function, no UserDefaults dependency)

    /// DictionaryPredictiveSearchPolicy のシステムスタイルルール検証。
    @Test func dictionaryPredictiveSearchPolicySystemStyleRequires3Chars() {
        #expect(DictionaryPredictiveSearchPolicy.allowsSystemStylePredictiveSearch(input: "") == false)
        #expect(DictionaryPredictiveSearchPolicy.allowsSystemStylePredictiveSearch(input: "じ") == false)
        #expect(DictionaryPredictiveSearchPolicy.allowsSystemStylePredictiveSearch(input: "じい") == false)
        #expect(DictionaryPredictiveSearchPolicy.allowsSystemStylePredictiveSearch(input: "じいじ") == true)
    }

    /// DictionaryPredictiveSearchPolicy の学習辞書スタイルルール検証。
    @Test func dictionaryPredictiveSearchPolicyLearningStyleUsesStartLength() {
        // startLength=3
        #expect(DictionaryPredictiveSearchPolicy.allowsLearningPredictiveSearch(input: "じ", startLength: 3) == false)
        #expect(DictionaryPredictiveSearchPolicy.allowsLearningPredictiveSearch(input: "じい", startLength: 3) == false)
        #expect(DictionaryPredictiveSearchPolicy.allowsLearningPredictiveSearch(input: "じいじ", startLength: 3) == true)
        // startLength=1: 1文字から許可
        #expect(DictionaryPredictiveSearchPolicy.allowsLearningPredictiveSearch(input: "じ", startLength: 1) == true)
        // startLength=4: 3文字では不許可
        #expect(DictionaryPredictiveSearchPolicy.allowsLearningPredictiveSearch(input: "じいじ", startLength: 4) == false)
        #expect(DictionaryPredictiveSearchPolicy.allowsLearningPredictiveSearch(input: "じいじい", startLength: 4) == true)
    }

    /// maxReadingLength: input < 6 文字なら input + 2、6 文字以上なら nil。
    @Test func dictionaryPredictiveSearchPolicyMaxReadingLength() {
        #expect(DictionaryPredictiveSearchPolicy.maxReadingLength(forInput: "あ") == 3)       // 1+2=3
        #expect(DictionaryPredictiveSearchPolicy.maxReadingLength(forInput: "あい") == 4)      // 2+2=4
        #expect(DictionaryPredictiveSearchPolicy.maxReadingLength(forInput: "あいう") == 5)    // 3+2=5
        #expect(DictionaryPredictiveSearchPolicy.maxReadingLength(forInput: "あいうえ") == 6)  // 4+2=6
        #expect(DictionaryPredictiveSearchPolicy.maxReadingLength(forInput: "あいうえお") == 7) // 5+2=7
        #expect(DictionaryPredictiveSearchPolicy.maxReadingLength(forInput: "あいうえおか") == nil) // 6→上限なし
        #expect(DictionaryPredictiveSearchPolicy.maxReadingLength(forInput: "あいうえおかき") == nil) // 7→上限なし
    }

    // MARK: - User dictionary predictive search suppression tests

    /// ユーザー辞書: 1〜2文字入力では prefix / predictive が動かず、exact match は動く。
    /// reading="じい" / word="自維" を登録して「じ」では出ないことを確認。
    @Test func userDictionaryCandidateSourceIgnoresPredictiveForShortInput() async throws {
        let repositories = try makeRepositories()
        let source = repositories.userCandidateSource

        try await repositories.userRepository.add(UserDictionaryEntry(
            id: UUID(), reading: "じい", word: "自維", score: 3000,
            leftId: 1851, rightId: 1851, updatedAt: Date()
        ))

        // 1文字入力では predictive / prefix は空
        #expect(
            source.searchPredictive(prefix: "じ", limit: 10).map(\.word).contains("自維") == false,
            "1文字入力でユーザー辞書の predictive 候補が出てはいけません"
        )
        #expect(
            source.searchCommonPrefix(inputReading: "じ", limit: 10).map(\.word).contains("自維") == false,
            "1文字入力でユーザー辞書の prefix 候補が出てはいけません"
        )

        // 2文字入力でも出ない
        #expect(
            source.searchPredictive(prefix: "じい", limit: 10).map(\.word).contains("自維") == false,
            "2文字入力でユーザー辞書の predictive 候補が出てはいけません"
        )
        #expect(
            source.searchCommonPrefix(inputReading: "じい", limit: 10).map(\.word).contains("自維") == false,
            "2文字入力でユーザー辞書の prefix 候補が出てはいけません"
        )

        // exact match は常に動く
        #expect(
            source.searchExact(reading: "じい", limit: 10).map(\.word) == ["自維"],
            "exact match はショートカット設定に関係なく常に動く必要があります"
        )
    }

    /// ユーザー辞書: predictiveConversionStartLength を変更してもユーザー辞書のルールは変わらない。
    @Test func userDictionaryCandidateSourceDoesNotUsePredictiveConversionStartLength() async throws {
        let repositories = try makeRepositories()
        let source = repositories.userCandidateSource

        try await repositories.userRepository.add(UserDictionaryEntry(
            id: UUID(), reading: "じい", word: "自維", score: 3000,
            leftId: 1851, rightId: 1851, updatedAt: Date()
        ))

        // predictiveConversionStartLength を 1 にしてもユーザー辞書は 3文字未満で返さない
        let key = KeyboardSettings.Keys.predictiveConversionStartLength
        let original = KeyboardSettings.defaults.object(forKey: key)
        defer {
            if let original {
                KeyboardSettings.defaults.set(original, forKey: key)
            } else {
                KeyboardSettings.defaults.removeObject(forKey: key)
            }
        }
        KeyboardSettings.predictiveConversionStartLength = 1

        #expect(
            source.searchPredictive(prefix: "じ", limit: 10).map(\.word).contains("自維") == false,
            "predictiveConversionStartLength=1 にしてもユーザー辞書の 1文字 predictive は出てはいけません"
        )
        // ユーザー辞書の exact は相変わらず動く
        #expect(source.searchExact(reading: "じい", limit: 10).map(\.word) == ["自維"])
    }

    /// ユーザー辞書: reading.count > input.count + 2 の候補は返さない（maxReadingLength 制限）。
    @Test func userDictionaryCandidateSourceFiltersLongReadingsByMaxLength() async throws {
        let repositories = try makeRepositories()
        let source = repositories.userCandidateSource

        // reading = "じい" (2文字): input "じいじ" (3文字) → maxReadingLength=5 → reading.count=2 <= 5 ✓
        // reading = "じいじいじ" (5文字): input "じい" (2文字) → 2文字未満なので prefix 自体が空
        // reading = "じいじいじ" (5文字): input "じいじ" (3文字) → maxReadingLength=5 → 5 <= 5 ✓
        // reading = "じいじいじい" (6文字): input "じいじ" (3文字) → maxReadingLength=5 → 6 > 5 ✗
        try await repositories.userRepository.add(UserDictionaryEntry(
            id: UUID(), reading: "じいじいじい", word: "長い読み", score: 100,
            leftId: 1851, rightId: 1851, updatedAt: Date()
        ))
        try await repositories.userRepository.add(UserDictionaryEntry(
            id: UUID(), reading: "じいじいじ", word: "ちょうど", score: 100,
            leftId: 1851, rightId: 1851, updatedAt: Date()
        ))

        // input "じいじ" (3文字) → maxReadingLength = 3+2 = 5
        // "じいじいじ" (5文字) <= 5 → 返るべき
        // "じいじいじい" (6文字) > 5 → 返らないべき
        let results = source.searchCommonPrefix(inputReading: "じいじ", limit: 10)
        #expect(
            results.map(\.word).contains("ちょうど"),
            "reading.count=5 <= maxReadingLength=5 なので返るべきです"
        )
        #expect(
            results.map(\.word).contains("長い読み") == false,
            "reading.count=6 > maxReadingLength=5 なので返らないべきです"
        )
    }

    // MARK: - Learning dictionary predictive search tests

    /// 学習辞書: predictiveConversionStartLength = 3 のとき 1〜2文字では prefix が出ない。
    @Test func learningDictionaryCandidateSourceRespectsStartLengthDefault() async throws {
        let repositories = try makeRepositories()
        try await repositories.learningRepository.recordCommittedSelection(CommittedSelection(
            inputReading: "じい",
            candidateReading: "じい",
            word: "自維",
            sourceKind: .systemMain,
            lexicalInfo: CandidateLexicalInfo(score: 100, leftId: 1851, rightId: 1851),
            committedAt: Date()
        ))
        let source = repositories.learningCandidateSource

        // startLength=3 に設定
        let key = KeyboardSettings.Keys.predictiveConversionStartLength
        let original = KeyboardSettings.defaults.object(forKey: key)
        defer {
            if let original {
                KeyboardSettings.defaults.set(original, forKey: key)
            } else {
                KeyboardSettings.defaults.removeObject(forKey: key)
            }
        }
        KeyboardSettings.predictiveConversionStartLength = 3

        // 1文字では出ない
        #expect(
            source.searchCommonPrefix(inputReading: "じ", limit: 10).map(\.word).contains("自維") == false,
            "startLength=3 のとき 1文字入力で学習辞書の prefix 候補が出てはいけません"
        )
        #expect(
            source.searchPredictive(prefix: "じ", limit: 10).map(\.word).contains("自維") == false,
            "startLength=3 のとき 1文字入力で学習辞書の predictive 候補が出てはいけません"
        )
        // exact は出る
        #expect(source.searchExact(reading: "じい", limit: 10).map(\.word) == ["自維"])
    }

    /// 学習辞書: predictiveConversionStartLength = 1 のとき 1文字から候補が出る。
    @Test func learningDictionaryCandidateSourceAllowsSearchWhenStartLengthIsOne() async throws {
        let repositories = try makeRepositories()
        try await repositories.learningRepository.recordCommittedSelection(CommittedSelection(
            inputReading: "じい",
            candidateReading: "じい",
            word: "自維",
            sourceKind: .systemMain,
            lexicalInfo: CandidateLexicalInfo(score: 100, leftId: 1851, rightId: 1851),
            committedAt: Date()
        ))
        let source = repositories.learningCandidateSource

        let key = KeyboardSettings.Keys.predictiveConversionStartLength
        let original = KeyboardSettings.defaults.object(forKey: key)
        defer {
            if let original {
                KeyboardSettings.defaults.set(original, forKey: key)
            } else {
                KeyboardSettings.defaults.removeObject(forKey: key)
            }
        }
        KeyboardSettings.predictiveConversionStartLength = 1

        // 1文字 "じ" で "じい" がヒット（maxReadingLength = 1+2=3、"じい".count=2 <= 3 ✓）
        #expect(
            source.searchCommonPrefix(inputReading: "じ", limit: 10).map(\.word).contains("自維"),
            "startLength=1 のとき 1文字入力で学習辞書の prefix 候補が出るべきです"
        )
    }

    /// 学習辞書: reading.count > input.count + 2 の候補は maxReadingLength 制限で返さない。
    @Test func learningDictionaryCandidateSourceFiltersLongReadingsByMaxLength() async throws {
        let repositories = try makeRepositories()
        // reading = "すみれいろ" (5文字) と "すみれいろのはな" (8文字) を学習エントリとして追加
        try await repositories.learningRepository.add(LearningDictionaryEntry(
            id: UUID(), reading: "すみれいろ", word: "菫色", score: 0,
            leftId: 1851, rightId: 1851, updatedAt: Date()
        ))
        try await repositories.learningRepository.add(LearningDictionaryEntry(
            id: UUID(), reading: "すみれいろのはな", word: "菫色の花", score: 0,
            leftId: 1851, rightId: 1851, updatedAt: Date()
        ))
        let source = repositories.learningCandidateSource

        let key = KeyboardSettings.Keys.predictiveConversionStartLength
        let original = KeyboardSettings.defaults.object(forKey: key)
        defer {
            if let original {
                KeyboardSettings.defaults.set(original, forKey: key)
            } else {
                KeyboardSettings.defaults.removeObject(forKey: key)
            }
        }
        KeyboardSettings.predictiveConversionStartLength = 3

        // input "すみれ" (3文字) → maxReadingLength = 3+2 = 5
        // "すみれいろ" (5文字) <= 5 → 返るべき
        // "すみれいろのはな" (8文字) > 5 → 返らないべき
        let results = source.searchCommonPrefix(inputReading: "すみれ", limit: 10)
        #expect(
            results.map(\.word).contains("菫色"),
            "reading.count=5 <= maxReadingLength=5 なので返るべきです"
        )
        #expect(
            results.map(\.word).contains("菫色の花") == false,
            "reading.count=8 > maxReadingLength=5 なので返らないべきです"
        )
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
