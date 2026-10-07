import Foundation

enum LegacyImportOutcome: Equatable {
    case alreadyImported
    case noLegacyFile
    case imported(insertedCount: Int, skippedRowCount: Int)
}

enum LegacyImportFailure: Error, Equatable {
    case couldNotRead(path: String, detail: String)
    case fileProblem(path: String, LegacyFileProblem)
    case store(StoreError)

    var message: String {
        switch self {
        case .couldNotRead(let path, let detail):
            return "Could not read the old results in \(path): \(detail)"
        case .fileProblem(let path, .headerMismatch(let found)):
            return "The old results in \(path) have unknown columns: \(found)"
        case .fileProblem(let path, .tooManyLines(let limit)):
            return "The old results in \(path) have more than \(limit) lines"
        case .store(let storeError):
            return storeError.message
        }
    }
}

/// Imports an Office Speedtest results.csv one time. It does not change or delete the file.
/// After a failure nothing is imported and the next call tries again.
func importLegacyResults(fileURL: URL, into store: ResultStore) -> Result<LegacyImportOutcome, LegacyImportFailure> {
    switch store.isFlagSet(.legacyResultsImported) {
    case .failure(let storeError):
        return .failure(.store(storeError))
    case .success(true):
        return .success(.alreadyImported)
    case .success(false):
        break
    }
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
        return store.setFlag(.legacyResultsImported).map { .noLegacyFile }.mapError(LegacyImportFailure.store)
    }
    let text: String
    do {
        text = try String(contentsOf: fileURL, encoding: .utf8)
    } catch {
        return .failure(.couldNotRead(path: fileURL.path, detail: error.localizedDescription))
    }
    let report: LegacyParseReport
    switch parseLegacyResultsCsv(text) {
    case .success(let parseReport):
        report = parseReport
    case .failure(let fileProblem):
        return .failure(.fileProblem(path: fileURL.path, fileProblem))
    }
    return store.insert(report.records)
        .flatMap { insertedCount in
            store.setFlag(.legacyResultsImported).map {
                LegacyImportOutcome.imported(insertedCount: insertedCount, skippedRowCount: report.rowErrors.count)
            }
        }
        .mapError(LegacyImportFailure.store)
}
