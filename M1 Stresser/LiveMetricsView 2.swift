import Foundation

@MainActor
class MetricsModel: ObservableObject {
    @Published var cpuPower_mW: Double? = nil
    @Published var gpuPower_mW: Double? = nil
    @Published var dieTemp_C: Double? = nil
    @Published var thermalPressure: String? = nil
    @Published var lastUpdated: Date? = nil

    private var powermetricsHelper: Process?
    private var readHandle: FileHandle?

    init() {
        startPowermetricsHelper()
    }

    deinit {
        stopPowermetricsHelper()
    }

    private func startPowermetricsHelper() {
        let helper = Process()
        let pipe = Pipe()
        helper.standardOutput = pipe
        helper.standardError = nil
        helper.standardInput = nil
        
        // Use the bundled helper in Resources if present, else fallback to /usr/local/bin
        let bundlePath = Bundle.main.path(forResource: "PowermetricsHelper", ofType: nil)
        if let path = bundlePath {
            helper.executableURL = URL(fileURLWithPath: path)
        } else {
            helper.executableURL = URL(fileURLWithPath: "/usr/local/bin/PowermetricsHelper")
        }
        
        do {
            try helper.run()
        } catch {
            print("Failed to start PowermetricsHelper process: \(error)")
            return
        }
        
        self.powermetricsHelper = helper
        self.readHandle = pipe.fileHandleForReading
        Task {
            await self.readLines()
        }
    }

    private func stopPowermetricsHelper() {
        readHandle = nil
        powermetricsHelper?.terminate()
        powermetricsHelper = nil
    }

    private func readLines() async {
        guard let handle = readHandle else { return }
        
        for try await line in handle.bytes.lines {
            await updateFromLine(String(line))
        }
    }

    private func updateFromLine(_ line: String) async {
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

// LiveMetricsView.swift
// Placeholder for future live metrics functionality.

import SwiftUI

struct LiveMetricsView: View {
    @ObservedObject var model = MetricsModel()
    
    var body: some View {
        if model.cpuPower_mW == nil &&
            model.gpuPower_mW == nil &&
            model.dieTemp_C == nil &&
            model.thermalPressure == nil {
            ProgressView("Awaiting powermetrics data...")
                .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
                .scaleEffect(1.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Form {
                Section(header: Text("Power Metrics")) {
                    if let cpu = model.cpuPower_mW {
                        HStack {
                            Label("CPU Power", systemImage: "cpu")
                            Spacer()
                            Text("\(cpu, specifier: "%.1f") mW")
                                .monospacedDigit()
                        }
                    }
                    if let gpu = model.gpuPower_mW {
                        HStack {
                            Label("GPU Power", systemImage: "gpu")
                            Spacer()
                            Text("\(gpu, specifier: "%.1f") mW")
                                .monospacedDigit()
                        }
                    }
                }
                
                Section(header: Text("Thermal Metrics")) {
                    if let temp = model.dieTemp_C {
                        HStack {
                            Label("Die Temp", systemImage: "thermometer")
                            Spacer()
                            Text("\(temp, specifier: "%.1f") °C")
                                .monospacedDigit()
                                .foregroundColor(color(for: temp))
                        }
                    }
                    if let pressure = model.thermalPressure {
                        HStack {
                            Label("Thermal Pressure", systemImage: "gauge")
                            Spacer()
                            Text(pressure)
                                .monospacedDigit()
                        }
                    }
                }
                
                if let last = model.lastUpdated {
                    Section {
                        HStack {
                            Spacer()
                            Text("Last update: \(last, formatter: dateFormatter)")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
    
    private func color(for temp: Double) -> Color {
        if temp > 85 {
            return .red
        } else if temp > 70 {
            return .orange
        } else {
            return .primary
        }
    }
    
    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .medium
        return f
    }
}

#Preview {
    LiveMetricsView()
}
