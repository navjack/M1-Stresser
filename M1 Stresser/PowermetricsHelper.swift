// PowermetricsHelper.swift
// Helper program to run powermetrics, parse key stats, and write JSON lines to stdout.
// To be compiled as a command-line tool and bundled with the main app.

import Foundation

// Launch powermetrics as a child
let powermetricsPath = "/usr/bin/powermetrics"
let arguments = ["-i", "1000", "--samplers", "cpu_power,gpu_power,thermal", "--show-all"]

let task = Process()
task.launchPath = powermetricsPath
task.arguments = arguments

task.standardOutput = Pipe()
task.standardError = Pipe()
let output = task.standardOutput as! Pipe

task.launch()

// Regexes for parsing powermetrics output
let cpuPowerRegex = try! NSRegularExpression(pattern: #"CPU Power: *(\d+\.?\d*) mW"#)
let gpuPowerRegex = try! NSRegularExpression(pattern: #"GPU Power: *(\d+\.?\d*) mW"#)
let dieTempRegex = try! NSRegularExpression(pattern: #"Die temperature: *(\d+\.?\d*) C"#)
let thermalPressureRegex = try! NSRegularExpression(pattern: #"Thermal pressure: *(\w+)"#)

// Read powermetrics output line by line, extract key stats, and print as JSON
var currentStats: [String: Any] = [:]

func parseAndEmit(line: String) {
    if let match = cpuPowerRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
       let range = Range(match.range(at: 1), in: line) {
        currentStats["cpu_power_mw"] = Double(line[range]) ?? 0
    }
    if let match = gpuPowerRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
       let range = Range(match.range(at: 1), in: line) {
        currentStats["gpu_power_mw"] = Double(line[range]) ?? 0
    }
    if let match = dieTempRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
       let range = Range(match.range(at: 1), in: line) {
        currentStats["die_temp_c"] = Double(line[range]) ?? 0
    }
    if let match = thermalPressureRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
       let range = Range(match.range(at: 1), in: line) {
        currentStats["thermal_pressure"] = String(line[range])
    }
    
    // Emit JSON every time we have all key stats
    if currentStats["cpu_power_mw"] != nil && currentStats["gpu_power_mw"] != nil && currentStats["die_temp_c"] != nil && currentStats["thermal_pressure"] != nil {
        if let data = try? JSONSerialization.data(withJSONObject: currentStats, options: []) {
            if let asString = String(data: data, encoding: .utf8) {
                print(asString)
                fflush(stdout)
            }
        }
        currentStats.removeAll()
    }
}

// Read from powermetrics' stdout
let handle = output.fileHandleForReading
let buffer = NSMutableData()

while true {
    let chunk = handle.availableData
    if chunk.isEmpty { break }
    buffer.append(chunk)
    while let range = buffer.range(of: Data([0x0A]), options: [], in: NSRange(location: 0, length: buffer.length)) { // Newline
        let lineData = buffer.subdata(with: NSRange(location: 0, length: range.location))
        buffer.replaceBytes(in: NSRange(location: 0, length: range.location + 1), withBytes: nil, length: 0)
        if let line = String(data: lineData, encoding: .utf8) {
            parseAndEmit(line: line)
        }
    }
}
