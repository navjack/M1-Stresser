// ExtremeStressView.swift
// Additional, more intense system stress options for "Extreme" tab

import SwiftUI
import Metal
import Accelerate
import Foundation
import Dispatch

struct ExtremeStressView: View {
    enum ExtremeMode: String, CaseIterable, Identifiable {
        case maxThreads = "Max Thread Saturation"
        case heavyMetal = "Heavy GPU Kernel"
        case ioStress = "Disk I/O Hammer"
        var id: String { rawValue }
    }

    @State private var selectedMode: ExtremeMode = .maxThreads
    @State private var isRunning = false
    @State private var workItems: [DispatchWorkItem] = []

    // For Metal
    @State private var metalStressor: HeavyMetalStressor? = HeavyMetalStressor()

    var body: some View {
        VStack(spacing: 18) {
            Text("Extreme System Stress").font(.title.bold())
            Picker("Test Mode", selection: $selectedMode) {
                ForEach(ExtremeMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.bottom)
            HStack(spacing: 36) {
                Button("Start", action: startExtremeStress).disabled(isRunning)
                Button("Stop", action: stopExtremeStress).disabled(!isRunning)
            }
            .padding(.bottom, 6)
            Text(selectedMode == .maxThreads ? "All logical cores are saturated; may impact UI responsiveness!" : selectedMode == .heavyMetal ? "Heavy Metal: Aggressive GPU compute kernel (longer per-thread work)" : "Disk I/O: Writes/reads 1GB temp files in a loop.")
                .font(.footnote).foregroundColor(.secondary)
            if selectedMode == .heavyMetal && metalStressor == nil {
                Text("Error: Metal setup failed. Heavy GPU test unavailable.").foregroundColor(.red)
            }
        }
        .padding(40)
        .frame(minWidth: 420)
    }

    private func startExtremeStress() {
        guard !isRunning else { return }
        isRunning = true
        switch selectedMode {
        case .maxThreads:
            startMaxThreadSaturation()
        case .heavyMetal:
            if metalStressor == nil { isRunning = false; return }
            let work = DispatchWorkItem {
                while isRunning {
                    metalStressor?.runExtremeKernel()
                }
            }
            workItems = [work]
            DispatchQueue.global(qos: .userInteractive).async(execute: work)
        case .ioStress:
            startDiskIOStress()
        }
    }

    private func stopExtremeStress() {
        isRunning = false
        workItems.forEach { $0.cancel() }
        workItems.removeAll()
    }

    private func startMaxThreadSaturation() {
        // Use all logical cores, possibly 2x for oversubscription
        let logicalCores = ProcessInfo.processInfo.activeProcessorCount
        let totalWorkers = logicalCores * 2
        var items: [DispatchWorkItem] = []
        for _ in 0..<totalWorkers {
            let work = DispatchWorkItem(qos: .userInitiated) {
                var x = 1.23
                while isRunning {
                    x = sqrt(x * 1.00034 + 9.1)
                    if x.isNaN { x = 1.23 }
                }
            }
            items.append(work)
            DispatchQueue.global(qos: .userInitiated).async(execute: work)
        }
        workItems = items
    }
    
    private func startDiskIOStress() {
        // Repeatedly write and read a large temp file (1GB)
        let work = DispatchWorkItem(qos: .utility) {
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent("extreme_stress_temp.bin")
            let bufferSize = 1024 * 1024 * 16 // 16MB buffer
            let totalSize = 1024 * 1024 * 1024 // 1GB
            let buffer = Data(repeating: 0xE3, count: bufferSize)
            while isRunning {
                // --- Write ---
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try? FileManager.default.removeItem(at: fileURL)
                }
                FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
                guard let handle = try? FileHandle(forWritingTo: fileURL) else { continue }
                var written = 0
                while written < totalSize && isRunning {
                    handle.write(buffer)
                    written += bufferSize
                }
                try? handle.close()
                // --- Read ---
                if let handleR = try? FileHandle(forReadingFrom: fileURL) {
                    while handleR.offsetInFile < UInt64(totalSize) && isRunning {
                        _ = try? handleR.read(upToCount: bufferSize)
                    }
                    try? handleR.close()
                }
            }
            // Cleanup
            try? FileManager.default.removeItem(at: fileURL)
        }
        workItems = [work]
        DispatchQueue.global(qos: .utility).async(execute: work)
    }
}

// HeavyMetalStressor: more aggressive Metal kernel
class HeavyMetalStressor {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipelineState: MTLComputePipelineState
    let bufferA: MTLBuffer
    let bufferB: MTLBuffer
    let bufferResult: MTLBuffer
    let arrayLength = 1 << 24 // 16m elements
    let bufferSize: Int

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue()
        else { return nil }
        self.device = device
        self.commandQueue = commandQueue
        let kernelSource = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void heavy_compute(device float *inA, device float *inB, device float *result, uint index [[thread_position_in_grid]]) {
            float acc = inA[index];
            for (int i = 0; i < 128; ++i) {
                acc = sqrt(acc * 1.73205f + inB[index]) * 1.2345f;
            }
            result[index] = acc;
        }
        """
        do {
            let library = try device.makeLibrary(source: kernelSource, options: nil)
            guard let function = library.makeFunction(name: "heavy_compute") else { return nil }
            pipelineState = try device.makeComputePipelineState(function: function)
        } catch {
            return nil
        }
        bufferSize = arrayLength * MemoryLayout<Float>.size
        guard let bufA = device.makeBuffer(length: bufferSize, options: .storageModeShared),
              let bufB = device.makeBuffer(length: bufferSize, options: .storageModeShared),
              let bufRes = device.makeBuffer(length: bufferSize, options: .storageModeShared)
        else { return nil }
        bufferA = bufA
        bufferB = bufB
        bufferResult = bufRes
    }

    func runExtremeKernel() {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipelineState)
        encoder.setBuffer(bufferA, offset: 0, index: 0)
        encoder.setBuffer(bufferB, offset: 0, index: 1)
        encoder.setBuffer(bufferResult, offset: 0, index: 2)
        let gridSize = MTLSize(width: arrayLength, height: 1, depth: 1)
        let threadGroupSize = MTLSize(width: min(arrayLength, pipelineState.maxTotalThreadsPerThreadgroup), height: 1, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        commandBuffer.commit()
    }
}

#Preview {
    ExtremeStressView()
}
