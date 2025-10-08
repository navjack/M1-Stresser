import Foundation
import SwiftUI

@MainActor
class MetricsModel: ObservableObject {
    @Published var cpuPower_mW: Double? = nil
    @Published var gpuPower_mW: Double? = nil
    @Published var dieTemp_C: Double? = nil
    @Published var thermalPressure: String? = nil
    @Published var lastUpdated: Date? = nil

    private var powermetricsHelper: Process?
    private var isRunning = false
    
    init() { start() }
    
    func start() {
        Task.detached {
            print("Launching powermetrics process")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["powermetrics", "--show-process-gpu"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
            } catch {
                print("Failed to launch powermetrics process: \(error)")
                await MainActor.run {
                    self.isRunning = false
                }
                return
            }
            
            print("Process launched, waiting for output")
            await MainActor.run {
                self.powermetricsHelper = process
            }
            await MainActor.run {
                self.isRunning = true
            }
            
            let handle = pipe.fileHandleForReading
            
            func makeLineSequence(from handle: FileHandle) -> AsyncThrowingStream<String, Error> {
                AsyncThrowingStream { continuation in
                    Task {
                        var buffer = Data()
                        do {
                            for try await byte in handle.bytes {
                                if byte == 0x0A { // newline
                                    if let line = String(data: buffer, encoding: .utf8) {
                                        continuation.yield(line)
                                    }
                                    buffer.removeAll()
                                } else {
                                    buffer.append(byte)
                                }
                            }
                            if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
                                continuation.yield(line)
                            }
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
                }
            }
            
            func withTimeout<T>(_ seconds: UInt64, operation: @escaping () async throws -> T) async throws -> T {
                try await withThrowingTaskGroup(of: T.self) { group in
                    group.addTask {
                        return try await operation()
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                        throw NSError(domain: "Timeout", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timeout after \(seconds) seconds"])
                    }
                    let result = try await group.next()!
                    group.cancelAll()
                    return result
                }
            }
            
            do {
                let lineSequence = makeLineSequence(from: handle)
                // Wait for first line with timeout 5 seconds
                let firstLine = try await withTimeout(5) {
                    var iterator = lineSequence.makeAsyncIterator()
                    guard let line = try await iterator.next() else {
                        throw NSError(domain: "NoOutput", code: 2, userInfo: [NSLocalizedDescriptionKey: "No output received"])
                    }
                    return line
                }
                print("Received first line: \(firstLine)")
                
                // Process lines with per-line timeout 5 seconds
                var iterator = lineSequence.makeAsyncIterator()
                // Yield first line that we already got above
                await self.processLine(firstLine)
                
                while true {
                    let line = try await withTimeout(5) {
                        guard let nextLine = try await iterator.next() else {
                            throw NSError(domain: "StreamEnded", code: 3, userInfo: [NSLocalizedDescriptionKey: "Stream ended"])
                        }
                        return nextLine
                    }
                    print("Received line: \(line)")
                    await self.processLine(line)
                }
            } catch {
                print("Timeout or error occurred: \(error.localizedDescription)")
                process.terminate()
                print("Process terminated due to error or timeout")
                await MainActor.run {
                    self.isRunning = false
                }
            }
        }
    }
    
    private func processLine(_ line: String) async {
        guard let data = line.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        var didUpdate = false
        if let cpu = dict["cpu_power_mw"] as? Double { self.cpuPower_mW = cpu; didUpdate = true }
        if let gpu = dict["gpu_power_mw"] as? Double { self.gpuPower_mW = gpu; didUpdate = true }
        if let temp = dict["die_temp_c"] as? Double { self.dieTemp_C = temp; didUpdate = true }
        if let pressure = dict["thermal_pressure"] as? String { self.thermalPressure = pressure; didUpdate = true }
        if didUpdate {
            self.lastUpdated = Date()
        }
    }
}
