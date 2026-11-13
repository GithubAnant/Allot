import Foundation

// Run short, read-only CLI queries off the UI thread; never start a model turn.
enum Command {
    static func executable(_ name: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        return paths.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    static func run(_ executable: String, _ arguments: [String], input: String? = nil,
                    environment: [String: String] = [:], responseID: Int? = nil, allowFailureOutput: Bool = false, timeout seconds: Double = 30) async throws -> Data {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
            let output = Pipe(), stdin = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.standardInput = stdin
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            try process.run()
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: timeout)
            defer {
                timeout.cancel()
                if process.isRunning { process.terminate() }
                try? stdin.fileHandleForWriting.close()
                try? output.fileHandleForReading.close()
            }
            if let input { try stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8)) }
            else { try stdin.fileHandleForWriting.close() }
            var collected = Data(), line = Data()
            while true {
                let chunk = output.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                if let responseID {
                    for byte in chunk {
                        if byte == 10 {
                            if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                               object["id"] as? Int == responseID { return line }
                            line.removeAll(keepingCapacity: true)
                        } else { line.append(byte) }
                        guard line.count < 8_000_000 else { throw UsageFailure("CLI response exceeded safety limit.") }
                    }
                } else {
                    collected.append(chunk)
                    guard collected.count < 8_000_000 else { throw UsageFailure("CLI response exceeded safety limit.") }
                }
            }
            process.waitUntilExit()
            guard responseID == nil, process.terminationStatus == 0 || (allowFailureOutput && !collected.isEmpty) else {
                throw UsageFailure("CLI query failed or timed out. Check that the CLI is signed in and up to date.")
            }
            return collected
        }.value
    }
}
