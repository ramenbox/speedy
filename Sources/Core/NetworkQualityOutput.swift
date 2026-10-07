import Foundation

let failureDetailMaximumCharacters = 300

/// Every way a networkQuality test can end without a measurement.
enum NetworkQualityFailure: Error, Equatable {
    case couldNotStart(detail: String)
    case timedOut(limitSeconds: Int)
    case exitedWithCode(Int32, detail: String)
    case stoppedBySignal(Int32, detail: String)
    case endedInUnknownWay(detail: String)
    /// networkQuality ran but reported a network error, for example -1009 when there is no internet connection.
    case networkError(domain: String, code: Int)
    case outputUnreadable(problem: String, detail: String)
    case invalidField(name: String, problem: String)

    var message: String {
        switch self {
        case .couldNotStart(let detail):
            return "Could not start networkQuality: \(detail)"
        case .timedOut(let limitSeconds):
            return "networkQuality did not finish within \(limitSeconds) seconds and was stopped"
        case .exitedWithCode(let exitCode, let detail):
            return "networkQuality exit code \(exitCode): \(detail)"
        case .stoppedBySignal(let signalNumber, let detail):
            return "networkQuality was stopped by signal \(signalNumber): \(detail)"
        case .endedInUnknownWay(let detail):
            return "networkQuality ended in an unknown way: \(detail)"
        case .networkError(let domain, let code):
            return describeNetworkError(domain: domain, code: code)
        case .outputUnreadable(let problem, let detail):
            return "\(problem): \(detail)"
        case .invalidField(let name, let problem):
            return "Field \(name) \(problem)"
        }
    }
}

func describeNetworkError(domain: String, code: Int) -> String {
    switch (domain, code) {
    case ("NSURLErrorDomain", -1009):
        return "No internet connection"
    case ("NSURLErrorDomain", -1001):
        return "The test server did not answer in time"
    case ("NSURLErrorDomain", -1003):
        return "The test server name could not be found (DNS)"
    case ("NSURLErrorDomain", -1004):
        return "Could not connect to the test server"
    case ("NSURLErrorDomain", -1005):
        return "The network connection was lost during the test"
    default:
        return "Network error \(domain) \(code)"
    }
}

/// The JSON that networkQuality `-c` prints when the test could not run.
private struct NetworkQualityErrorOutput: Decodable {
    let errorCode: Int
    let errorDomain: String

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case errorDomain = "error_domain"
    }
}

/// The fields of the networkQuality `-c` JSON output that Speedy records.
private struct NetworkQualityMeasurementOutput: Decodable {
    struct Other: Decodable {
        /// Sample count per interface type, for example ["wifi": 188].
        let interfaceType: [String: Double]

        enum CodingKeys: String, CodingKey {
            case interfaceType = "interface-type"
        }
    }

    let downloadBitsPerSecond: Double
    let uploadBitsPerSecond: Double
    let responsiveness: Double
    let baseRoundTripTimeMilliseconds: Double
    let interfaceName: String
    let testEndpoint: String
    let other: Other

    enum CodingKeys: String, CodingKey {
        case downloadBitsPerSecond = "dl_throughput"
        case uploadBitsPerSecond = "ul_throughput"
        case responsiveness = "responsiveness"
        case baseRoundTripTimeMilliseconds = "base_rtt"
        case interfaceName = "interface_name"
        case testEndpoint = "test_endpoint"
        case other = "other"
    }
}

/// Converts the output of a networkQuality run that exited with code 0. Pure: no I/O.
func parseNetworkQualityOutput(_ outputData: Data) -> Result<SpeedMeasurement, NetworkQualityFailure> {
    // networkQuality exits with code 0 also when the network is not usable. It then prints only an error code.
    if let errorOutput = try? JSONDecoder().decode(NetworkQualityErrorOutput.self, from: outputData) {
        return .failure(.networkError(domain: errorOutput.errorDomain, code: errorOutput.errorCode))
    }
    let decodedOutput: NetworkQualityMeasurementOutput
    do {
        decodedOutput = try JSONDecoder().decode(NetworkQualityMeasurementOutput.self, from: outputData)
    } catch let decodingError as DecodingError {
        return .failure(.outputUnreadable(problem: describeDecodingError(decodingError), detail: describeOutput(outputData)))
    } catch {
        return .failure(.outputUnreadable(problem: "networkQuality output could not be read", detail: error.localizedDescription))
    }
    return validateMeasurement(decodedOutput)
}

private func validateMeasurement(_ decodedOutput: NetworkQualityMeasurementOutput) -> Result<SpeedMeasurement, NetworkQualityFailure> {
    let numberFields: [(name: String, value: Double)] = [
        ("dl_throughput", decodedOutput.downloadBitsPerSecond),
        ("ul_throughput", decodedOutput.uploadBitsPerSecond),
        ("responsiveness", decodedOutput.responsiveness),
        ("base_rtt", decodedOutput.baseRoundTripTimeMilliseconds),
    ]
    if let invalidNumberField = numberFields.first(where: { !$0.value.isFinite || $0.value < 0 }) {
        return .failure(.invalidField(name: invalidNumberField.name, problem: "has an unexpected value: \(invalidNumberField.value)"))
    }
    let interfaceType = decodedOutput.other.interfaceType.keys.sorted().joined(separator: "+")
    let textFields: [(name: String, value: String)] = [
        ("other.interface-type", interfaceType),
        ("interface_name", decodedOutput.interfaceName),
        ("test_endpoint", decodedOutput.testEndpoint),
    ]
    if let emptyTextField = textFields.first(where: { $0.value.isEmpty }) {
        return .failure(.invalidField(name: emptyTextField.name, problem: "is empty"))
    }
    return .success(SpeedMeasurement(
        downloadMegabitsPerSecond: decodedOutput.downloadBitsPerSecond / 1_000_000,
        uploadMegabitsPerSecond: decodedOutput.uploadBitsPerSecond / 1_000_000,
        responsivenessRoundTripsPerMinute: decodedOutput.responsiveness,
        baseRoundTripTimeMilliseconds: decodedOutput.baseRoundTripTimeMilliseconds,
        interfaceType: interfaceType,
        interfaceName: decodedOutput.interfaceName,
        testEndpoint: decodedOutput.testEndpoint,
    ))
}

func describeDecodingError(_ decodingError: DecodingError) -> String {
    switch decodingError {
    case .keyNotFound(let key, let context):
        return "Field \(describeCodingPath(context.codingPath + [key])) is missing"
    case .valueNotFound(_, let context):
        return "Field \(describeCodingPath(context.codingPath)) is empty"
    case .typeMismatch(_, let context):
        return "Field \(describeCodingPath(context.codingPath)) has an unexpected type"
    case .dataCorrupted:
        return "networkQuality output is not valid JSON"
    @unknown default:
        return "networkQuality output has an unknown problem"
    }
}

private func describeCodingPath(_ codingPath: [CodingKey]) -> String {
    return codingPath.map(\.stringValue).joined(separator: ".")
}

/// The printed output, on one line and shortened, for a failure message.
func describeOutput(_ data: Data) -> String {
    let text = collapseWhitespace(String(decoding: data, as: UTF8.self))
    guard !text.isEmpty else {
        return "no output"
    }
    return String(text.prefix(failureDetailMaximumCharacters))
}
