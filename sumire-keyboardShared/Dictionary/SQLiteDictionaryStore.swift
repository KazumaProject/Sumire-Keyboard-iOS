import Foundation

final class SQLiteDictionaryStore: @unchecked Sendable {
    private let database: SQLiteDatabase

    init(databaseURL: URL) throws {
        database = try SQLiteDatabase(url: databaseURL)
        try migrate()
    }

    init(database: SQLiteDatabase) throws {
        self.database = database
        try migrate()
    }

    func recordCommittedSelection(_ selection: CommittedSelection) throws {
        guard selection.candidateReading.count == selection.inputReading.count else {
            return
        }

        let lexicalInfo = selection.lexicalInfo.resolvedForDictionarySave
        try recordLearningEntry(
            reading: selection.candidateReading,
            word: selection.word,
            score: lexicalInfo.score,
            leftId: lexicalInfo.leftId,
            rightId: lexicalInfo.rightId,
            updatedAt: selection.committedAt
        )
    }

    func addLearning(_ entry: LearningDictionaryEntry) throws {
        try upsertLearning(entry)
    }

    func updateLearning(_ entry: LearningDictionaryEntry) throws {
        try updateLearningEntry(entry)
    }

    func deleteLearning(id: LearningDictionaryEntryID) throws {
        try database.execute(
            "DELETE FROM learning_dictionary_entries WHERE id = ?",
            bindings: [.text(id.uuidString)]
        )
    }

    func deleteAllLearning() throws {
        try database.execute("DELETE FROM learning_dictionary_entries")
    }

    func addUser(_ entry: UserDictionaryEntry) throws {
        try upsertUser(entry)
    }

    func updateUser(_ entry: UserDictionaryEntry) throws {
        try updateUserEntry(entry)
    }

    func deleteUser(id: UserDictionaryEntryID) throws {
        try database.execute(
            "DELETE FROM user_dictionary_entries WHERE id = ?",
            bindings: [.text(id.uuidString)]
        )
    }

    func deleteAllUser() throws {
        try database.execute("DELETE FROM user_dictionary_entries")
    }

    func searchLearningExact(reading: String, limit: Int) throws -> [LearningDictionaryEntry] {
        guard reading.isEmpty == false, limit > 0 else {
            return []
        }
        return try database.query(
            """
            SELECT id, reading, word, score, left_id, right_id, updated_at
            FROM learning_dictionary_entries
            WHERE reading = ?
            ORDER BY score ASC, updated_at DESC
            LIMIT ?
            """,
            bindings: [.text(reading), .int(limit)],
            map: Self.learningEntry(from:)
        )
    }

    func searchLearningPrefix(
        prefix: String,
        limit: Int,
        maxReadingLength: Int? = nil
    ) throws -> [LearningDictionaryEntry] {
        guard prefix.isEmpty == false, limit > 0 else {
            return []
        }
        if let maxReadingLength {
            return try database.query(
                """
                SELECT id, reading, word, score, left_id, right_id, updated_at
                FROM learning_dictionary_entries
                WHERE reading LIKE ? ESCAPE '\\'
                  AND length(reading) <= ?
                ORDER BY score ASC, updated_at DESC
                LIMIT ?
                """,
                bindings: [.text(Self.likePrefixPattern(prefix)), .int(maxReadingLength), .int(limit)],
                map: Self.learningEntry(from:)
            )
        } else {
            return try database.query(
                """
                SELECT id, reading, word, score, left_id, right_id, updated_at
                FROM learning_dictionary_entries
                WHERE reading LIKE ? ESCAPE '\\'
                ORDER BY score ASC, updated_at DESC
                LIMIT ?
                """,
                bindings: [.text(Self.likePrefixPattern(prefix)), .int(limit)],
                map: Self.learningEntry(from:)
            )
        }
    }

    func searchLearningForManagementUI(query: String, limit: Int, offset: Int) throws -> [LearningDictionaryEntry] {
        let safeLimit = max(limit, 1)
        let safeOffset = max(offset, 0)
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try database.query(
                """
                SELECT id, reading, word, score, left_id, right_id, updated_at
                FROM learning_dictionary_entries
                ORDER BY updated_at DESC
                LIMIT ? OFFSET ?
                """,
                bindings: [.int(safeLimit), .int(safeOffset)],
                map: Self.learningEntry(from:)
            )
        }

        let pattern = Self.likeContainsPattern(query)
        return try database.query(
            """
            SELECT id, reading, word, score, left_id, right_id, updated_at
            FROM learning_dictionary_entries
            WHERE reading LIKE ? ESCAPE '\\' OR word LIKE ? ESCAPE '\\'
            ORDER BY updated_at DESC
            LIMIT ? OFFSET ?
            """,
            bindings: [.text(pattern), .text(pattern), .int(safeLimit), .int(safeOffset)],
            map: Self.learningEntry(from:)
        )
    }

    func searchUserExact(reading: String, limit: Int) throws -> [UserDictionaryEntry] {
        guard reading.isEmpty == false, limit > 0 else {
            return []
        }
        return try database.query(
            """
            SELECT id, reading, word, score, left_id, right_id, updated_at
            FROM user_dictionary_entries
            WHERE reading = ?
            ORDER BY score ASC, updated_at DESC
            LIMIT ?
            """,
            bindings: [.text(reading), .int(limit)],
            map: Self.userEntry(from:)
        )
    }

    func searchUserPrefix(
        prefix: String,
        limit: Int,
        maxReadingLength: Int? = nil
    ) throws -> [UserDictionaryEntry] {
        guard prefix.isEmpty == false, limit > 0 else {
            return []
        }
        if let maxReadingLength {
            return try database.query(
                """
                SELECT id, reading, word, score, left_id, right_id, updated_at
                FROM user_dictionary_entries
                WHERE reading LIKE ? ESCAPE '\\'
                  AND length(reading) <= ?
                ORDER BY score ASC, updated_at DESC
                LIMIT ?
                """,
                bindings: [.text(Self.likePrefixPattern(prefix)), .int(maxReadingLength), .int(limit)],
                map: Self.userEntry(from:)
            )
        } else {
            return try database.query(
                """
                SELECT id, reading, word, score, left_id, right_id, updated_at
                FROM user_dictionary_entries
                WHERE reading LIKE ? ESCAPE '\\'
                ORDER BY score ASC, updated_at DESC
                LIMIT ?
                """,
                bindings: [.text(Self.likePrefixPattern(prefix)), .int(limit)],
                map: Self.userEntry(from:)
            )
        }
    }

    func searchUserForManagementUI(query: String, limit: Int, offset: Int) throws -> [UserDictionaryEntry] {
        let safeLimit = max(limit, 1)
        let safeOffset = max(offset, 0)
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try database.query(
                """
                SELECT id, reading, word, score, left_id, right_id, updated_at
                FROM user_dictionary_entries
                ORDER BY updated_at DESC
                LIMIT ? OFFSET ?
                """,
                bindings: [.int(safeLimit), .int(safeOffset)],
                map: Self.userEntry(from:)
            )
        }

        let pattern = Self.likeContainsPattern(query)
        return try database.query(
            """
            SELECT id, reading, word, score, left_id, right_id, updated_at
            FROM user_dictionary_entries
            WHERE reading LIKE ? ESCAPE '\\' OR word LIKE ? ESCAPE '\\'
            ORDER BY updated_at DESC
            LIMIT ? OFFSET ?
            """,
            bindings: [.text(pattern), .text(pattern), .int(safeLimit), .int(safeOffset)],
            map: Self.userEntry(from:)
        )
    }

    func allUserEntries() throws -> [UserDictionaryEntry] {
        try database.query(
            """
            SELECT id, reading, word, score, left_id, right_id, updated_at
            FROM user_dictionary_entries
            ORDER BY reading ASC, score ASC, updated_at DESC
            """,
            map: Self.userEntry(from:)
        )
    }

    func countUserEntries(query: String) throws -> Int {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try database.query(
                "SELECT COUNT(*) FROM user_dictionary_entries",
                map: { $0.int(at: 0) }
            ).first ?? 0
        }

        let pattern = Self.likeContainsPattern(query)
        return try database.query(
            """
            SELECT COUNT(*)
            FROM user_dictionary_entries
            WHERE reading LIKE ? ESCAPE '\\' OR word LIKE ? ESCAPE '\\'
            """,
            bindings: [.text(pattern), .text(pattern)],
            map: { $0.int(at: 0) }
        ).first ?? 0
    }

    private func migrate() throws {
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS learning_dictionary_entries (
                id TEXT PRIMARY KEY,
                reading TEXT NOT NULL,
                word TEXT NOT NULL,
                score INTEGER NOT NULL,
                left_id INTEGER NOT NULL,
                right_id INTEGER NOT NULL,
                updated_at REAL NOT NULL
            )
            """
        )
        try database.execute(
            """
            CREATE INDEX IF NOT EXISTS learning_dictionary_entries_reading_idx
            ON learning_dictionary_entries(reading)
            """
        )
        try database.execute(
            """
            CREATE UNIQUE INDEX IF NOT EXISTS learning_dictionary_entries_unique_logical_idx
            ON learning_dictionary_entries(reading, word, left_id, right_id)
            """
        )
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS user_dictionary_entries (
                id TEXT PRIMARY KEY,
                reading TEXT NOT NULL,
                word TEXT NOT NULL,
                score INTEGER NOT NULL,
                left_id INTEGER NOT NULL,
                right_id INTEGER NOT NULL,
                updated_at REAL NOT NULL
            )
            """
        )
        try database.execute(
            """
            CREATE INDEX IF NOT EXISTS user_dictionary_entries_reading_idx
            ON user_dictionary_entries(reading)
            """
        )
        try database.execute(
            """
            CREATE UNIQUE INDEX IF NOT EXISTS user_dictionary_entries_unique_logical_idx
            ON user_dictionary_entries(reading, word, left_id, right_id)
            """
        )
    }

    private func recordLearningEntry(
        reading: String,
        word: String,
        score: Int,
        leftId: Int,
        rightId: Int,
        updatedAt: Date
    ) throws {
        let existing = try database.query(
            """
            SELECT id, score
            FROM learning_dictionary_entries
            WHERE reading = ? AND word = ? AND left_id = ? AND right_id = ?
            LIMIT 1
            """,
            bindings: [.text(reading), .text(word), .int(leftId), .int(rightId)]
        ) { statement in
            (id: try statement.text(at: 0), score: statement.int(at: 1))
        }.first

        if let existing {
            try database.execute(
                """
                UPDATE learning_dictionary_entries
                SET score = ?, updated_at = ?
                WHERE id = ?
                """,
                bindings: [
                    .int(existing.score - 500),
                    .double(updatedAt.timeIntervalSince1970),
                    .text(existing.id)
                ]
            )
        } else {
            try database.execute(
                """
                INSERT INTO learning_dictionary_entries
                    (id, reading, word, score, left_id, right_id, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: [
                    .text(UUID().uuidString),
                    .text(reading),
                    .text(word),
                    .int(score),
                    .int(leftId),
                    .int(rightId),
                    .double(updatedAt.timeIntervalSince1970)
                ]
            )
        }
    }

    private func upsertLearning(_ entry: LearningDictionaryEntry) throws {
        try database.execute(
            """
            INSERT INTO learning_dictionary_entries
                (id, reading, word, score, left_id, right_id, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                reading = excluded.reading,
                word = excluded.word,
                score = excluded.score,
                left_id = excluded.left_id,
                right_id = excluded.right_id,
                updated_at = excluded.updated_at
            """,
            bindings: Self.bindings(for: entry)
        )
    }

    private func updateLearningEntry(_ entry: LearningDictionaryEntry) throws {
        try database.execute(
            """
            UPDATE learning_dictionary_entries
            SET reading = ?, word = ?, score = ?, left_id = ?, right_id = ?, updated_at = ?
            WHERE id = ?
            """,
            bindings: [
                .text(entry.reading),
                .text(entry.word),
                .int(entry.score),
                .int(entry.leftId),
                .int(entry.rightId),
                .double(entry.updatedAt.timeIntervalSince1970),
                .text(entry.id.uuidString)
            ]
        )
    }

    private func upsertUser(_ entry: UserDictionaryEntry) throws {
        try database.execute(
            """
            INSERT INTO user_dictionary_entries
                (id, reading, word, score, left_id, right_id, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                reading = excluded.reading,
                word = excluded.word,
                score = excluded.score,
                left_id = excluded.left_id,
                right_id = excluded.right_id,
                updated_at = excluded.updated_at
            """,
            bindings: Self.bindings(for: entry)
        )
    }

    private func updateUserEntry(_ entry: UserDictionaryEntry) throws {
        try database.execute(
            """
            UPDATE user_dictionary_entries
            SET reading = ?, word = ?, score = ?, left_id = ?, right_id = ?, updated_at = ?
            WHERE id = ?
            """,
            bindings: [
                .text(entry.reading),
                .text(entry.word),
                .int(entry.score),
                .int(entry.leftId),
                .int(entry.rightId),
                .double(entry.updatedAt.timeIntervalSince1970),
                .text(entry.id.uuidString)
            ]
        )
    }

    private static func learningEntry(from statement: SQLiteStatement) throws -> LearningDictionaryEntry {
        LearningDictionaryEntry(
            id: UUID(uuidString: try statement.text(at: 0)) ?? UUID(),
            reading: try statement.text(at: 1),
            word: try statement.text(at: 2),
            score: statement.int(at: 3),
            leftId: statement.int(at: 4),
            rightId: statement.int(at: 5),
            updatedAt: Date(timeIntervalSince1970: statement.double(at: 6))
        )
    }

    private static func userEntry(from statement: SQLiteStatement) throws -> UserDictionaryEntry {
        UserDictionaryEntry(
            id: UUID(uuidString: try statement.text(at: 0)) ?? UUID(),
            reading: try statement.text(at: 1),
            word: try statement.text(at: 2),
            score: statement.int(at: 3),
            leftId: statement.int(at: 4),
            rightId: statement.int(at: 5),
            updatedAt: Date(timeIntervalSince1970: statement.double(at: 6))
        )
    }

    private static func bindings(for entry: LearningDictionaryEntry) -> [SQLiteValue] {
        [
            .text(entry.id.uuidString),
            .text(entry.reading),
            .text(entry.word),
            .int(entry.score),
            .int(entry.leftId),
            .int(entry.rightId),
            .double(entry.updatedAt.timeIntervalSince1970)
        ]
    }

    private static func bindings(for entry: UserDictionaryEntry) -> [SQLiteValue] {
        [
            .text(entry.id.uuidString),
            .text(entry.reading),
            .text(entry.word),
            .int(entry.score),
            .int(entry.leftId),
            .int(entry.rightId),
            .double(entry.updatedAt.timeIntervalSince1970)
        ]
    }

    private static func likePrefixPattern(_ value: String) -> String {
        escapeLike(value) + "%"
    }

    private static func likeContainsPattern(_ value: String) -> String {
        "%" + escapeLike(value) + "%"
    }

    private static func escapeLike(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
