import Foundation

let networkQualityPath = "/usr/bin/networkQuality"
let testMaximumSeconds = 30
/// networkQuality can hang when the network is not usable, also with -M. Speedy stops it after this time.
let testHardLimitSeconds = 60
let forcedKillDelaySeconds = 5

enum NetworkQualityRunOutcome {
    case finished(Result<SpeedMeasurement, NetworkQualityFailure>)
    /// `cancel()` stopped the test. Nothing is recorded.
    case cancelled
}

/// Runs one networkQuality test. Use one runner per test.
final class NetworkQualityRunner {
    private let lock = NSLock()
    private var runningProcess: Process?
    private var cancelRequested = false
    private var timedOut = false

    /// Starts the test on a background queue. Calls completion on the main queue.
    func start(completion: @escaping (NetworkQualityRunOutcome) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let outcome = self.runUntilFinished()
            DispatchQueue.main.async {
                completion(outcome)
            }
        }
    }

    /// Stops a running test. Its completion receives `.cancelled`.
    func cancel() {
        lock.lock()
        cancelRequested = true
        let process = runningProcess
        lock.unlock()
        process?.terminate()
    }

    private func runUntilFinished() -> NetworkQualityRunOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: networkQualityPath)
        process.arguments = ["-c", "-M", String(testMaximumSeconds)]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = FileHandle.nullDevice

        lock.lock()
        guard !cancelRequested else {
            lock.unlock()
            return .cancelled
        }
        do {
            try process.run()
        } catch {
            lock.unlock()
            return .finished(.failure(.couldNotStart(detail: error.localizedDescription)))
        }
        runningProcess = process
        lock.unlock()

        // Both pipes are read at the same time, so a full pipe buffer cannot block networkQuality.
        let readGroup = DispatchGroup()
        var outputData = Data()
        var errorData = Data()
        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            readGroup.leave()
        }
        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            readGroup.leave()
        }
        scheduleHardLimit(for: process)

        process.waitUntilExit()
        readGroup.wait()
        return classifyExit(of: process, outputData: outputData, errorData: errorData)
    }

    private func classifyExit(of process: Process, outputData: Data, errorData: Data) -> NetworkQualityRunOutcome {
        lock.lock()
        runningProcess = nil
        let wasCancelled = cancelRequested
        let wasTimedOut = timedOut
        lock.unlock()

        guard !wasCancelled else {
            return .cancelled
        }
        guard !wasTimedOut else {
            return .finished(.failure(.timedOut(limitSeconds: testHardLimitSeconds)))
        }
        // The error output explains a failure better than the normal output.
        let detail = errorData.isEmpty ? describeOutput(outputData) : describeOutput(errorData)
        switch (process.terminationReason, process.terminationStatus) {
        case (.exit, 0):
            return .finished(parseNetworkQualityOutput(outputData))
        case (.exit, let exitCode):
            return .finished(.failure(.exitedWithCode(exitCode, detail: detail)))
        case (.uncaughtSignal, let signalNumber):
            return .finished(.failure(.stoppedBySignal(signalNumber, detail: detail)))
        @unknown default:
            return .finished(.failure(.endedInUnknownWay(detail: detail)))
        }
    }

    /// Stops the process after testHardLimitSeconds. If it ignores the stop signal, it is killed.
    private func scheduleHardLimit(for process: Process) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .seconds(testHardLimitSeconds)) {
            self.lock.lock()
            guard self.runningProcess === process else {
                self.lock.unlock()
                return
            }
            self.timedOut = true
            self.lock.unlock()
            process.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .seconds(forcedKillDelaySeconds)) {
                self.lock.lock()
                let processIsStillRunning = self.runningProcess === process && process.isRunning
                self.lock.unlock()
                if processIsStillRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }
    }
}
