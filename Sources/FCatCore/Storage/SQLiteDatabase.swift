import Foundation
import SQLite3

public final class SQLiteDatabase {
    private var db: OpaquePointer?

    public init(url: URL) throws {
        if sqlite3_open(url.path, &db) != SQLITE_OK {
            throw SQLiteError.open(message)
        }
    }

    deinit { sqlite3_close(db) }

    public func execute(_ sql: String, bindings: [SQLiteBinding] = []) throws {
        let statement = try prepare(sql, bindings: bindings)
        defer { sqlite3_finalize(statement) }
        if sqlite3_step(statement) != SQLITE_DONE {
            throw SQLiteError.step(message)
        }
    }

    public func query(_ sql: String, bindings: [SQLiteBinding] = []) throws -> [[String: SQLiteValue]] {
        let statement = try prepare(sql, bindings: bindings)
        defer { sqlite3_finalize(statement) }
        var rows: [[String: SQLiteValue]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: SQLiteValue] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER:
                    row[name] = .integer(sqlite3_column_int64(statement, index))
                case SQLITE_TEXT:
                    if let text = sqlite3_column_text(statement, index) {
                        row[name] = .text(String(cString: text))
                    } else {
                        row[name] = .null
                    }
                default:
                    row[name] = .null
                }
            }
            rows.append(row)
        }
        return rows
    }

    private func prepare(_ sql: String, bindings: [SQLiteBinding]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            throw SQLiteError.prepare(message)
        }
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            switch binding {
            case .text(let value): sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
            case .int(let value): sqlite3_bind_int64(statement, index, value)
            case .null: sqlite3_bind_null(statement, index)
            }
        }
        return statement
    }

    private var message: String { String(cString: sqlite3_errmsg(db)) }
}

public enum SQLiteBinding {
    case text(String)
    case int(Int64)
    case null
}

public enum SQLiteValue: Equatable {
    case text(String)
    case integer(Int64)
    case null

    public var string: String? {
        if case .text(let value) = self { return value }
        return nil
    }

    public var int64: Int64? {
        if case .integer(let value) = self { return value }
        return nil
    }
}

public enum SQLiteError: Error, Equatable {
    case open(String)
    case prepare(String)
    case step(String)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
