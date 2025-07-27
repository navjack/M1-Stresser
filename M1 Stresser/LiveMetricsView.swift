// LiveMetricsView.swift
// SwiftUI dashboard for real-time power/thermal metrics from PowermetricsHelper

import SwiftUI
import Foundation

struct MetricSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let cpuPower: Double
    let gpuPower: Double
    let dieTemp: Double
    let thermalPressure: String
}

@Observable
final class MetricsModel: ObservableObject {
    @Published var current: MetricSample?
    @Published var history: [MetricSample] = []
    private var task: Task<Void, Never>?

    func start() {
        // Launch PowermetricsHelper and parse its stdout
        task = Task.detached(priority: .userInitiated) { [weak self] in
            let process = Process()
            let helperPath = Bundle.main.path(forResource: "PowermetricsHelper", ofType: nil) ?? "/usr/local/bin/PowermetricsHelper" // Adjust as needed
            process.launchPath = "/usr/bin/sudo"
            process.arguments = [helperPath]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = nil
            do {
                try process.run()
            } catch {
                print("Failed to launch helper: \(error)")
                return
            }
            let handle = pipe.fileHandleForReading
            while !Task.isCancelled {
                if let line = try? handle.readLine() {
                    guard let data = line.data(using: .utf8),
                        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                        let cpu = json["cpu_power_mw"] as? Double,
                        let gpu = json["gpu_power_mw"] as? Double,
                        let temp = json["die_temp_c"] as? Double,
                        let pressure = json["thermal_pressure"] as? String
                    else { continue }
                    let sample = MetricSample(timestamp: .now, cpuPower: cpu, gpuPower: gpu, dieTemp: temp, thermalPressure: pressure)
                    await MainActor.run {
                        self?.current = sample
                        self?.history.append(sample)
                        if self?.history.count ?? 0 > 60 { self?.history.removeFirst() }
                    }
                }
            }
            process.terminate()
        }
    }
    
    func stop() {
        task?.cancel()
        task = nil
    }
}

struct LiveMetricsView: View {
    @StateObject private var model = MetricsModel()
    
    var body: some View {
        VStack(spacing: 18) {
            Text("Live System Metrics").font(.title.bold())
            if let sample = model.current {
                HStack(spacing: 36) {
                    MetricCard(title: "CPU Power", value: String(format: "%.1f mW", sample.cpuPower), color: .blue)
                    MetricCard(title: "GPU Power", value: String(format: "%.1f mW", sample.gpuPower), color: .purple)
                    MetricCard(title: "Die Temp", value: String(format: "%.1f°C", sample.dieTemp), color: sample.dieTemp > 90 ? .red : .orange)
                    MetricCard(title: "Thermal", value: sample.thermalPressure, color: sample.thermalPressure == "nominal" ? .green : .red)
                }
                Divider().padding(.vertical, 8)
                MetricsHistoryChart(samples: model.history)
                    .frame(height: 120)
            } else {
                ProgressView("Waiting for data...")
            }
        }
        .padding(40)
        .frame(minWidth: 500)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let color: Color
    var body: some View {
        VStack {
            Text(title).font(.headline).foregroundColor(.secondary)
            Text(value).font(.system(size: 24, weight: .bold)).foregroundColor(color)
        }
        .frame(width: 100)
        .padding(8)
        .background(.thinMaterial)
        .cornerRadius(10)
    }
}

struct MetricsHistoryChart: View {
    let samples: [MetricSample]
    var body: some View {
        GeometryReader { geo in
            let points = samples.enumerated().map { (idx, s) in
                CGPoint(x: geo.size.width * CGFloat(idx) / CGFloat(max(1, samples.count-1)),
                        y: geo.size.height * (1 - CGFloat(s.cpuPower / (samples.map{ $0.cpuPower }.max() ?? 1))))
            }
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                points.dropFirst().forEach { path.addLine(to: $0) }
            }
            .stroke(.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            // Repeat for GPU and Temp as overlays:
            let gpuPoints = samples.enumerated().map { (idx, s) in
                CGPoint(x: geo.size.width * CGFloat(idx) / CGFloat(max(1, samples.count-1)),
                        y: geo.size.height * (1 - CGFloat(s.gpuPower / (samples.map{ $0.gpuPower }.max() ?? 1))))
            }
            Path { path in
                guard let first = gpuPoints.first else { return }
                path.move(to: first)
                gpuPoints.dropFirst().forEach { path.addLine(to: $0) }
            }
            .stroke(.purple.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [4]))
            let tempPoints = samples.enumerated().map { (idx, s) in
                CGPoint(x: geo.size.width * CGFloat(idx) / CGFloat(max(1, samples.count-1)),
                        y: geo.size.height * (1 - CGFloat(s.dieTemp / (samples.map{ $0.dieTemp }.max() ?? 1))))
            }
            Path { path in
                guard let first = tempPoints.first else { return }
                path.move(to: first)
                tempPoints.dropFirst().forEach { path.addLine(to: $0) }
            }
            .stroke(.orange.opacity(0.5), style: StrokeStyle(lineWidth: 2))
        }
    }
}

#Preview {
    LiveMetricsView()
}

// Utility for reading a line from FileHandle (simple, synchronous)
extension FileHandle {
    func readLine() throws -> String? {
        var data = Data()
        while true {
            let byte = try self.read(upToCount: 1)
            if byte == nil || byte!.isEmpty { return data.isEmpty ? nil : String(data: data, encoding: .utf8) }
            if byte![0] == 0x0A { break } // Newline
            data.append(byte!)
        }
        return String(data: data, encoding: .utf8)
    }
}
