import Foundation
import SQLite3

enum SQLiteDatabaseError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
    case invalidColumn(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            return "SQLite open failed: \(message)"
        case .prepareFailed(let message):
            return "SQLite prepare failed: \(message)"
        case .stepFailed(let message):
            return "SQLite step failed: \(message)"
        case .bindFailed(let message):
            return "SQLite bind failed: \(message)"
        case .invalidColumn(let message):
            return "SQLite invalid column: \(message)"
        }
    }
}

enum SQLiteValue: Sendable {
    case text(String)
    case int(Int)
    case double(Double)
    case null
}

final class SQLiteStatement {
    fileprivate let statement: OpaquePointer

    fileprivate init(statement: OpaquePointer) {
        self.statement = statement
    }

    func text(at index: Int32) throws -> String {
        guard let cString = sqlite3_column_text(statement, index) else {
            throw SQLiteDatabaseError.invalidColumn("Expected TEXT at column \(index).")
        }
        return String(cString: cString)
    }

    func int(at index: Int32) -> Int {
        Int(sqlite3_column_int64(statement, index))
    }

    func double(at index: Int32) -> Double {
        sqlite3_column_double(statement, index)
    }
}

final class SQLiteDatabase: @unchecked Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "com.kazumaproject.sumire-keyboard.sqlite")
    private let queueKey = DispatchSpecificKey<Void>()
    private var connection: OpaquePointer?

    init(url: URL) throws {
        self.url = url
        queue.setSpecific(key: queueKey, value: ())
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let status = sqlite3_open_v2(url.path, &database, flags, nil)
        guard status == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            if let database {
                sqlite3_close(database)
            }
            throw SQLiteDatabaseError.openFailed(message)
        }
        connection = database
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA foreign_keys = ON")
    }

    deinit {
        if let connection {
            sqlite3_close(connection)
        }
    }

    func execute(_ sql: String, bindings: [SQLiteValue] = []) throws {
        try syncOnQueue {
            let statement = try prepare(sql)
            defer {
                sqlite3_finalize(statement)
            }
            try bind(bindings, to: statement)
            let status = sqlite3_step(statement)
            guard status == SQLITE_DONE || status == SQLITE_ROW else {
                throw SQLiteDatabaseError.stepFailed(lastErrorMessage())
            }
        }
    }

    func query<T>(
        _ sql: String,
        bindings: [SQLiteValue] = [],
        map: (SQLiteStatement) throws -> T
    ) throws -> [T] {
        try syncOnQueue {
            let statement = try prepare(sql)
            defer {
                sqlite3_finalize(statement)
            }
            try bind(bindings, to: statement)

            var results: [T] = []
            while true {
                let status = sqlite3_step(statement)
                if status == SQLITE_ROW {
                    results.append(try map(SQLiteStatement(statement: statement)))
                } else if status == SQLITE_DONE {
                    return results
                } else {
                    throw SQLiteDatabaseError.stepFailed(lastErrorMessage())
                }
            }
        }
    }

    func transaction(_ work: () throws -> Void) throws {
        try syncOnQueue {
            try executeWithoutQueue("BEGIN IMMEDIATE")
            do {
                try work()
                try executeWithoutQueue("COMMIT")
            } catch {
                try? executeWithoutQueue("ROLLBACK")
                throw error
            }
        }
    }

    private func syncOnQueue<T>(_ work: () throws -> T) throws -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return try work()
        }
        return try queue.sync(execute: work)
    }

    private func executeWithoutQueue(_ sql: String, bindings: [SQLiteValue] = []) throws {
        let statement = try prepare(sql)
        defer {
            sqlite3_finalize(statement)
        }
        try bind(bindings, to: statement)
        let status = sqlite3_step(statement)
        guard status == SQLITE_DONE || status == SQLITE_ROW else {
            throw SQLiteDatabaseError.stepFailed(lastErrorMessage())
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let connection else {
            throw SQLiteDatabaseError.openFailed("Database is closed.")
        }

        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard status == SQLITE_OK, let statement else {
            throw SQLiteDatabaseError.prepareFailed(lastErrorMessage())
        }
        return statement
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32
            switch value {
            case .text(let text):
                status = sqlite3_bind_text(statement, index, text, -1, SQLiteDatabase.transientDestructor)
            case .int(let int):
                status = sqlite3_bind_int64(statement, index, sqlite3_int64(int))
            case .double(let double):
                status = sqlite3_bind_double(statement, index, double)
            case .null:
                status = sqlite3_bind_null(statement, index)
            }

            guard status == SQLITE_OK else {
                throw SQLiteDatabaseError.bindFailed(lastErrorMessage())
            }
        }
    }

    private func lastErrorMessage() -> String {
        guard let connection else {
            return "Database is closed."
        }
        return String(cString: sqlite3_errmsg(connection))
    }

    private static let transientDestructor = unsafeBitCast(
        -1,
        to: sqlite3_destructor_type.self
    )
}
