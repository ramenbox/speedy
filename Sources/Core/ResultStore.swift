import Foundation
import SQLite3

let storeSchemaVersion: Int32 = 1
let storeBusyTimeoutMilliseconds: Int32 = 2_000
/// The column order that `decodeRow` reads.
private let storeResultColumns = "started_at, computer_name, status, download_mbps, upload_mbps, responsiveness_rpm, base_rtt_ms, interface_type, interface_name, test_endpoint, error"
/// SQLite copies bound text before the statement runs.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum StoreError: Error, Equatable {
    case couldNotCreateFolder(path: String, detail: String)
    case sqlite(action: String, detail: String)
    case newerSchema(found: Int32, supported: Int32)
    case tooManyRecords(limit: Int)
    case invalidRow(detail: String)

    var message: String {
        switch self {
        case .couldNotCreateFolder(let path, let detail):
            return "Could not create the folder \(path): \(detail)"
        case .sqlite(let action, let detail):
            return "Database error while \(action): \(detail)"
        case .newerSchema(let found, let supported):
            return "The database is from a newer Speedy (schema \(found), this version reads \(supported))"
        case .tooManyRecords(let limit):
            return "More than \(limit) results in this range"
        case .invalidRow(let detail):
            return "A stored result is invalid: \(detail)"
        }
    }
}

enum StoreFlag: String {
    case legacyResultsImported = "legacy_results_imported"
}

/// The test history in one SQLite file. Use it from one thread only.
final class ResultStore {
    private let database: OpaquePointer

    private init(database: OpaquePointer) {
        self.database = database
    }

    deinit {
        sqlite3_close(database)
    }

    /// Opens the database. Creates the folder, the file, and the tables when they do not exist.
    static func open(fileURL: URL) -> Result<ResultStore, StoreError> {
        let folderURL = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch {
            return .failure(.couldNotCreateFolder(path: folderURL.path, detail: error.localizedDescription))
        }
        var openedDatabase: OpaquePointer?
        let openFlags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let openCode = sqlite3_open_v2(fileURL.path, &openedDatabase, openFlags, nil)
        guard let database = openedDatabase else {
            return .failure(.sqlite(action: "opening \(fileURL.path)", detail: String(cString: sqlite3_errstr(openCode))))
        }
        let store = ResultStore(database: database)
        guard openCode == SQLITE_OK else {
            return .failure(store.lastError(action: "opening \(fileURL.path)"))
        }
        sqlite3_busy_timeout(database, storeBusyTimeoutMilliseconds)
        return store.migrate().map { store }
    }

    // MARK: Schema

    private func migrate() -> Result<Void, StoreError> {
        return readSchemaVersion().flatMap { version in
            switch version {
            case 0:
                return createSchema()
            case storeSchemaVersion:
                return .success(())
            default:
                return .failure(.newerSchema(found: version, supported: storeSchemaVersion))
            }
        }
    }

    private func readSchemaVersion() -> Result<Int32, StoreError> {
        return prepare("PRAGMA user_version", action: "reading the schema version").flatMap { statement in
            guard sqlite3_step(statement.pointer) == SQLITE_ROW else {
                return .failure(lastError(action: "reading the schema version"))
            }
            return .success(sqlite3_column_int(statement.pointer, 0))
        }
    }

    private func createSchema() -> Result<Void, StoreError> {
        let schema = """
            CREATE TABLE test_results (
                id INTEGER PRIMARY KEY,
                started_at REAL NOT NULL,
                computer_name TEXT NOT NULL,
                status TEXT NOT NULL CHECK (status IN ('ok', 'failed')),
                download_mbps REAL,
                upload_mbps REAL,
                responsiveness_rpm REAL,
                base_rtt_ms REAL,
                interface_type TEXT,
                interface_name TEXT,
                test_endpoint TEXT,
                error TEXT,
                UNIQUE (started_at, computer_name)
            );
            CREATE TABLE flags (name TEXT PRIMARY KEY);
            PRAGMA user_version = \(storeSchemaVersion);
            """
        return inTransaction(action: "creating the tables") {
            execute(schema, action: "creating the tables")
        }
    }

    // MARK: Writing

    /// Inserts the records in one transaction. A record with the same start time and computer is skipped.
    /// On failure nothing is inserted. Returns the number of inserted records.
    func insert(_ records: [TestRecord]) -> Result<Int, StoreError> {
        return inTransaction(action: "saving the results") {
            insertEach(records)
        }
    }

    /// Runs the work in one transaction. Commits on success, rolls back on failure.
    private func inTransaction<Value>(action: String, work: () -> Result<Value, StoreError>) -> Result<Value, StoreError> {
        return execute("BEGIN", action: action).flatMap {
            switch work() {
            case .success(let value):
                return execute("COMMIT", action: action).map { value }
            case .failure(let error):
                // The first error is the one to report. A failed rollback also ends the transaction.
                _ = execute("ROLLBACK", action: action)
                return .failure(error)
            }
        }
    }

    private func insertEach(_ records: [TestRecord]) -> Result<Int, StoreError> {
        let sql = """
            INSERT OR IGNORE INTO test_results
            (started_at, computer_name, status, download_mbps, upload_mbps, responsiveness_rpm, base_rtt_ms,
             interface_type, interface_name, test_endpoint, error)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        return prepare(sql, action: "saving a result").flatMap { statement in
            var insertedCount = 0
            for record in records {
                bind(record, to: statement)
                guard sqlite3_step(statement.pointer) == SQLITE_DONE else {
                    return .failure(lastError(action: "saving a result"))
                }
                insertedCount += Int(sqlite3_changes(database))
                sqlite3_reset(statement.pointer)
                sqlite3_clear_bindings(statement.pointer)
            }
            return .success(insertedCount)
        }
    }

    private func bind(_ record: TestRecord, to statement: PreparedStatement) {
        let pointer = statement.pointer
        sqlite3_bind_double(pointer, 1, record.startedAt.timeIntervalSince1970)
        sqlite3_bind_text(pointer, 2, record.computerName, -1, sqliteTransient)
        switch record.result {
        case .measured(let measurement):
            sqlite3_bind_text(pointer, 3, csvStatusMeasured, -1, sqliteTransient)
            sqlite3_bind_double(pointer, 4, measurement.downloadMegabitsPerSecond)
            sqlite3_bind_double(pointer, 5, measurement.uploadMegabitsPerSecond)
            sqlite3_bind_double(pointer, 6, measurement.responsivenessRoundTripsPerMinute)
            sqlite3_bind_double(pointer, 7, measurement.baseRoundTripTimeMilliseconds)
            sqlite3_bind_text(pointer, 8, measurement.interfaceType, -1, sqliteTransient)
            sqlite3_bind_text(pointer, 9, measurement.interfaceName, -1, sqliteTransient)
            sqlite3_bind_text(pointer, 10, measurement.testEndpoint, -1, sqliteTransient)
        case .failed(let message):
            sqlite3_bind_text(pointer, 3, csvStatusFailed, -1, sqliteTransient)
            sqlite3_bind_text(pointer, 11, message, -1, sqliteTransient)
        }
    }

    /// Deletes all results. Flags stay, so the old results.csv is not imported again.
    func deleteAllResults() -> Result<Void, StoreError> {
        return execute("DELETE FROM test_results", action: "deleting the history")
    }

    func isFlagSet(_ flag: StoreFlag) -> Result<Bool, StoreError> {
        return prepare("SELECT 1 FROM flags WHERE name = ?", action: "reading a flag").flatMap { statement in
            sqlite3_bind_text(statement.pointer, 1, flag.rawValue, -1, sqliteTransient)
            switch sqlite3_step(statement.pointer) {
            case SQLITE_ROW:
                return .success(true)
            case SQLITE_DONE:
                return .success(false)
            default:
                return .failure(lastError(action: "reading a flag"))
            }
        }
    }

    func setFlag(_ flag: StoreFlag) -> Result<Void, StoreError> {
        return prepare("INSERT OR IGNORE INTO flags (name) VALUES (?)", action: "saving a flag").flatMap { statement in
            sqlite3_bind_text(statement.pointer, 1, flag.rawValue, -1, sqliteTransient)
            guard sqlite3_step(statement.pointer) == SQLITE_DONE else {
                return .failure(lastError(action: "saving a flag"))
            }
            return .success(())
        }
    }

    // MARK: Reading

    /// Returns the records from the start on, oldest first.
    /// Fails with `tooManyRecords` when there are more than `maximumCount`.
    func records(from start: RangeStart, maximumCount: Int) -> Result<[TestRecord], StoreError> {
        let lowerBound: Double
        switch start {
        case .unbounded:
            lowerBound = -Double.greatestFiniteMagnitude
        case .from(let date):
            lowerBound = date.timeIntervalSince1970
        }
        let sql = "SELECT \(storeResultColumns) FROM test_results WHERE started_at >= ? ORDER BY started_at ASC LIMIT ?"
        return prepare(sql, action: "reading the history").flatMap { statement in
            sqlite3_bind_double(statement.pointer, 1, lowerBound)
            sqlite3_bind_int64(statement.pointer, 2, Int64(maximumCount) + 1)
            return readRows(statement, maximumCount: maximumCount)
        }
    }

    /// Returns up to `count` records, newest first.
    func newestRecords(count: Int) -> Result<[TestRecord], StoreError> {
        let sql = "SELECT \(storeResultColumns) FROM test_results ORDER BY started_at DESC LIMIT ?"
        return prepare(sql, action: "reading the newest results").flatMap { statement in
            sqlite3_bind_int64(statement.pointer, 1, Int64(count))
            return readRows(statement, maximumCount: count)
        }
    }

    private func readRows(_ statement: PreparedStatement, maximumCount: Int) -> Result<[TestRecord], StoreError> {
        var records: [TestRecord] = []
        while true {
            switch sqlite3_step(statement.pointer) {
            case SQLITE_ROW:
                guard records.count < maximumCount else {
                    return .failure(.tooManyRecords(limit: maximumCount))
                }
                switch decodeRow(statement.pointer) {
                case .success(let record):
                    records.append(record)
                case .failure(let error):
                    return .failure(error)
                }
            case SQLITE_DONE:
                return .success(records)
            default:
                return .failure(lastError(action: "reading the history"))
            }
        }
    }

    private func decodeRow(_ pointer: OpaquePointer) -> Result<TestRecord, StoreError> {
        let startedAt = Date(timeIntervalSince1970: sqlite3_column_double(pointer, 0))
        let computerName = readText(pointer, column: 1)
        let status = readText(pointer, column: 2)
        switch status {
        case csvStatusMeasured:
            let numberColumns: [Int32] = [3, 4, 5, 6]
            guard numberColumns.allSatisfy({ sqlite3_column_type(pointer, $0) != SQLITE_NULL }) else {
                return .failure(.invalidRow(detail: "result at \(csvTimestampFormatter.string(from: startedAt)) has status ok but misses a number"))
            }
            let measurement = SpeedMeasurement(
                downloadMegabitsPerSecond: sqlite3_column_double(pointer, 3),
                uploadMegabitsPerSecond: sqlite3_column_double(pointer, 4),
                responsivenessRoundTripsPerMinute: sqlite3_column_double(pointer, 5),
                baseRoundTripTimeMilliseconds: sqlite3_column_double(pointer, 6),
                interfaceType: readText(pointer, column: 7),
                interfaceName: readText(pointer, column: 8),
                testEndpoint: readText(pointer, column: 9),
            )
            return .success(TestRecord(startedAt: startedAt, computerName: computerName, result: .measured(measurement)))
        case csvStatusFailed:
            let message = readText(pointer, column: 10)
            return .success(TestRecord(startedAt: startedAt, computerName: computerName, result: .failed(message: message)))
        default:
            return .failure(.invalidRow(detail: "unknown status \(status)"))
        }
    }

    // MARK: SQLite helpers

    private func readText(_ pointer: OpaquePointer, column: Int32) -> String {
        guard let text = sqlite3_column_text(pointer, column) else {
            return ""
        }
        return String(cString: text)
    }

    private func prepare(_ sql: String, action: String) -> Result<PreparedStatement, StoreError> {
        var statementPointer: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statementPointer, nil) == SQLITE_OK, let pointer = statementPointer else {
            sqlite3_finalize(statementPointer)
            return .failure(lastError(action: action))
        }
        return .success(PreparedStatement(pointer: pointer))
    }

    private func execute(_ sql: String, action: String) -> Result<Void, StoreError> {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            return .failure(lastError(action: action))
        }
        return .success(())
    }

    private func lastError(action: String) -> StoreError {
        return .sqlite(action: action, detail: String(cString: sqlite3_errmsg(database)))
    }
}

/// Finalizes the statement when it goes out of scope.
private final class PreparedStatement {
    let pointer: OpaquePointer

    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        sqlite3_finalize(pointer)
    }
}
