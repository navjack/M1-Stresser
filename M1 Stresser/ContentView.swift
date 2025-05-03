//  ContentView.swift
//  M1 Stresser — Apple‑silicon power‑virus demo
//  Revised 2025-05-02

import SwiftUI
import Foundation
import Darwin     // For sqrt(), memcpy()
import Dispatch
import simd
import Metal        // For GPU stress
import Accelerate   // For BLAS (proxy for ANE/heavy compute)
import CommonCrypto // For Integer ALU Hashing stress

// MARK: - GPU Stress Helper
class MetalStressor {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipelineState: MTLComputePipelineState
    let bufferA: MTLBuffer
    let bufferB: MTLBuffer
    let bufferResult: MTLBuffer

    let arrayLength = 1 << 24 // ~16 million elements
    let bufferSize: Int

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            print("Metal is not supported on this device.")
            return nil
        }
        self.device = device
        self.commandQueue = commandQueue

        // Simple compute kernel performing element-wise addition
        let kernelSource = """
        #include <metal_stdlib>
        using namespace metal;

        kernel void add_arrays(device const float *inA,
                               device const float *inB,
                               device float *result,
                               uint index [[thread_position_in_grid]]) {
            result[index] = inA[index] + inB[index] * 1.2345; // Some arbitrary work
        }
        """

        do {
            let library = try device.makeLibrary(source: kernelSource, options: nil)
            guard let addFunction = library.makeFunction(name: "add_arrays") else {
                print("Failed to create Metal function.")
                return nil
            }
            self.pipelineState = try device.makeComputePipelineState(function: addFunction)
        } catch {
            print("Failed to create Metal pipeline state: \(error)")
            return nil
        }

        // Allocate buffers
        bufferSize = arrayLength * MemoryLayout<Float>.size
        guard let bufA = device.makeBuffer(length: bufferSize, options: .storageModeShared),
              let bufB = device.makeBuffer(length: bufferSize, options: .storageModeShared),
              let bufRes = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
            print("Failed to create Metal buffers.")
            return nil
        }
        self.bufferA = bufA
        self.bufferB = bufB
        self.bufferResult = bufRes

        // Optional: Initialize buffers with some data
        // let ptrA = bufA.contents().bindMemory(to: Float.self, capacity: arrayLength)
        // let ptrB = bufB.contents().bindMemory(to: Float.self, capacity: arrayLength)
        // for i in 0..<arrayLength { ptrA[i] = Float(i); ptrB[i] = Float(arrayLength - i) }
    }

    func runStressIteration() {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeCommandEncoder = commandBuffer.makeComputeCommandEncoder() else { return }

        computeCommandEncoder.setComputePipelineState(pipelineState)
        computeCommandEncoder.setBuffer(bufferA, offset: 0, index: 0)
        computeCommandEncoder.setBuffer(bufferB, offset: 0, index: 1)
        computeCommandEncoder.setBuffer(bufferResult, offset: 0, index: 2)

        let gridSize = MTLSize(width: arrayLength, height: 1, depth: 1)
        let threadGroupSize = MTLSize(width: min(arrayLength, pipelineState.maxTotalThreadsPerThreadgroup), height: 1, depth: 1)
        computeCommandEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)

        computeCommandEncoder.endEncoding()
        commandBuffer.commit()
        // Don't wait for completion to allow continuous dispatching
        // commandBuffer.waitUntilCompleted() // <-- Remove or comment out for stress testing
    }
}


struct ContentView: View {

    // MARK: – Stress modes ----------------------------------------------------
    enum StressMode: String, CaseIterable, Identifiable {
        // CPU Modes
        case sqrtFPU        = "Vector sqrt (FP/NEON)"
        case integerALU     = "Integer ALU (Hashing)" // New
        case l1CacheThrash  = "L1 Cache Thrash (R/W)"
        case l2CacheThrash  = "L2 Cache Thrash (R/W)" // New
        case memBandwidth   = "Mem Bandwidth (Stream)"
        case mixedCPU       = "Mixed CPU Load"        // New
        // Accelerator Modes (can also be run concurrently)
        case gpuCompute     = "GPU Compute (Metal)"   // New
        case aneProxyBlas   = "ANE Proxy (BLAS)"      // New (Using BLAS as proxy)

        var id: String { rawValue }

        // Helper to identify CPU-primary modes
        var isCPUMode: Bool {
            switch self {
            case .sqrtFPU, .integerALU, .l1CacheThrash, .l2CacheThrash, .memBandwidth, .mixedCPU:
                return true
            case .gpuCompute, .aneProxyBlas:
                return false
            }
        }
    }

    // MARK: – View‑state -------------------------------------------------------
    @State private var selectedMode: StressMode = .sqrtFPU
    @State private var isRunning = false
    @State private var cpuWorkItems: [DispatchWorkItem] = []
    @State private var gpuWorkItem: DispatchWorkItem? = nil // For dedicated GPU mode or concurrent
    @State private var aneWorkItem: DispatchWorkItem? = nil // For dedicated ANE mode or concurrent

    // Concurrency Toggles
    @State private var runGpuConcurrently = false
    @State private var runAneConcurrently = false

    // Metal helper instance
    @State private var metalStressor: MetalStressor? = nil

    // MARK: – UI ---------------------------------------------------------------
    var body: some View {
        VStack(spacing: 20) { // Reduced spacing slightly
            Text("M1 Stresser").font(.title.bold())

            Picker("Primary Stress Mode", selection: $selectedMode) {
                ForEach(StressMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu) // Changed picker style for more options
            .padding(.bottom)

            // Concurrency Options Box
            GroupBox("Run Concurrently") {
                VStack {
                    Toggle("GPU Compute (Metal)", isOn: $runGpuConcurrently)
                        .disabled(isRunning) // Disable toggles while running
                    Toggle("ANE Proxy (BLAS)", isOn: $runAneConcurrently)
                        .disabled(isRunning)
                }
                .padding(.vertical, 5)
            }
            .padding(.bottom)


            HStack(spacing: 40) {
                Button("Start", action: startStress).disabled(isRunning)
                Button("Stop", action: stopStress).disabled(!isRunning)
            }
            .onAppear {
                // Attempt to initialize Metal helper on view appear
                if metalStressor == nil {
                    metalStressor = MetalStressor()
                }
            }
            // Display error if Metal setup failed
            if metalStressor == nil {
                Text("Error: Metal setup failed. GPU test unavailable.")
                    .foregroundColor(.red)
                    .padding(.top)
            }
        }
        .padding(40)
        .frame(minWidth: 420) // Increased width slightly
    }

    // MARK: – Stress Control ---------------------------------------------------
    private func startStress() {
        guard !isRunning else { return }
        isRunning = true

        // --- Start Primary Stress ---
        switch selectedMode {
        case .gpuCompute:
             startGpuStress(concurrent: false) // Start GPU as primary
        case .aneProxyBlas:
             startAneStress(concurrent: false) // Start ANE as primary
        default: // All CPU modes
            startCPUStress(mode: selectedMode)
        }

        // --- Start Concurrent Stress (if toggled) ---
        if runGpuConcurrently && selectedMode != .gpuCompute { // Don't run twice if primary is GPU
            startGpuStress(concurrent: true)
        }
        if runAneConcurrently && selectedMode != .aneProxyBlas { // Don't run twice if primary is ANE
            startAneStress(concurrent: true)
        }
    }

    private func stopStress() {
        // Cancel CPU workers
        cpuWorkItems.forEach { $0.cancel() }
        cpuWorkItems.removeAll()

        // Cancel GPU worker (primary or concurrent)
        gpuWorkItem?.cancel()
        gpuWorkItem = nil

        // Cancel ANE worker (primary or concurrent)
        aneWorkItem?.cancel()
        aneWorkItem = nil

        isRunning = false
        // Reset toggles if desired? Optional.
        // runGpuConcurrently = false
        // runAneConcurrently = false
    }

    // MARK: - CPU Stress Launchers ---------------------------------------------
    private func startCPUStress(mode: StressMode) {
        // Leave one logical core free for the UI/System unless only 1 core exists
        let logicalCores = ProcessInfo.processInfo.activeProcessorCount
        let workerCores = max(1, logicalCores - 1)

        var items: [DispatchWorkItem] = []
        for i in 0..<workerCores {
            // Choose QoS based on mode - example: high QoS for FP/NEON
            let qosClass: DispatchQoS.QoSClass = (mode == .sqrtFPU || mode == .mixedCPU) ? .userInteractive : .userInitiated
            var workItem: DispatchWorkItem!
            workItem = DispatchWorkItem(qos: DispatchQoS(qosClass: qosClass, relativePriority: 0)) {
                 // Select the stress function based on the mode
                switch mode {
                case .sqrtFPU:        stressSqrtFPU(workItem: workItem)
                case .integerALU:     stressIntegerALU(workItem: workItem)
                case .l1CacheThrash:  stressL1CacheThrash(workItem: workItem)
                case .l2CacheThrash:  stressL2CacheThrash(workItem: workItem)
                case .memBandwidth:   stressMemBandwidth(workItem: workItem)
                case .mixedCPU:       stressMixedCPU(workItem: workItem, coreIndex: i) // Pass index for variation
                default: break // Should not happen for CPU modes
                }
            }
            items.append(workItem)
            DispatchQueue.global(qos: qosClass).async(execute: workItem) // Use QoS on queue too
        }
        cpuWorkItems = items
    }


    // MARK: - Accelerator Stress Launchers --------------------------------------
    private func startGpuStress(concurrent: Bool) {
         guard metalStressor != nil else {
             print("GPU Stress skipped: Metal setup failed.")
             if !concurrent { isRunning = false } // Stop if it was primary
             return
         }

         let workItem = DispatchWorkItem(qos: .userInitiated) { [weak metalStressor] in
             while !(gpuWorkItem?.isCancelled ?? true) {
                 metalStressor?.runStressIteration()
                 // Maybe add a tiny sleep if it overloads the system *too* much,
                 // but for a power virus, usually run flat out.
                 // Thread.sleep(forTimeInterval: 0.001)
             }
         }
         gpuWorkItem = workItem
         DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
    }

    private func startAneStress(concurrent: Bool) {
        let workItem = DispatchWorkItem(qos: .userInitiated) {
            // Use Accelerate vDSP matrix multiplication as a proxy for heavy compute
            // Setup for a matrix multiplication C = A * B
            let n: vDSP_Length = 1024 // Matrix dimension (use vDSP_Length which is UInt)
            let size = Int(n * n)
            let matrixA = [Float](repeating: 0.5, count: size)
            let matrixB = [Float](repeating: 0.8, count: size)
            var matrixC = [Float](repeating: 0.0, count: size)

            while !(aneWorkItem?.isCancelled ?? true) {
                // Perform C = A * B using vDSP
                // vDSP.matrixMultiply requires pointers and dimensions as vDSP_Length (UInt)
                // Note: vDSP_mmul assumes column-major order by default, matching standard BLAS.
                // If matrices were conceptually row-major, we'd transpose A and B inputs
                // and swap matrix dimensions M and N in the call.
                // Since A, B, C are NxN, M=N=K=n.
                // For C = A * B, vDSP_mmul calculates C = A*B + C_initial, so we ensure C starts at 0.
                // Alternatively, for C = A * B, we can call vDSP_mmul with separate output buffer
                // or overwrite C. Let's overwrite C.

                 vDSP_mmul(matrixA, 1,       // Input A, stride A
                           matrixB, 1,       // Input B, stride B
                           &matrixC, 1,      // Output C, stride C
                           n, n, n)          // M (rows in A), N (cols in B), K (cols in A / rows in B)

                // Prevent compiler optimizing away the calculation entirely
                // (Read from the result buffer)
                if matrixC[0] > Float.infinity { print("Overflow guard") }
                 // Add a tiny bit of work to ensure the loop variable is used within the condition
                 if matrixC[Int(n-1)] == Float.infinity && (aneWorkItem?.isCancelled ?? true) { print("Never happens guard")}
            }
        }
        aneWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
    }


    // MARK: - Core Stress Logic Functions ---------------------------------------

    // --- Vector FP/NEON ---
    private func stressSqrtFPU(workItem: DispatchWorkItem) {
        let v = SIMD4<Double>(12345.6789, 98765.4321, 67890.1234, 54321.9876)
        var accVec = SIMD4<Double>(repeating: 0)
        var iterations: UInt64 = 0

        while !workItem.isCancelled {
            // ~32 sqrt/cycle per loop trip (4‑wide * 8 unroll).
            accVec += v.squareRoot(); accVec += v.squareRoot()
            accVec += v.squareRoot(); accVec += v.squareRoot()
            accVec += v.squareRoot(); accVec += v.squareRoot()
            accVec += v.squareRoot(); accVec += v.squareRoot()
            iterations &+= 1

            // Avoid overflow / dead‑code elimination.
            if iterations & 0xFFFF_FFFF == 0 {
                if accVec.x > 1e12 { accVec = SIMD4<Double>(repeating: 0) }
            }
        }
        // Ensure accumulator isn't optimized away completely if loop finishes instantly
         if accVec.x < 0 { print("FP Accumulator: \(accVec.x)") }
    }

    // --- Integer ALU (Hashing) ---
    private func stressIntegerALU(workItem: DispatchWorkItem) {
        // Use CommonCrypto for SHA256 hashing
        let dataSize = 1024 * 64 // 64 KB of data to hash repeatedly
        var dataToHash = Data(repeating: 0xAA, count: dataSize)
        var hashOutput = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        var iterations: UInt64 = 0

        while !workItem.isCancelled {
            dataToHash.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Void in
                 _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hashOutput)
            }
            iterations &+= 1

            // Modify input slightly to prevent potential caching/optimization? Unlikely needed for SHA256.
             if iterations & 0xFFF == 0 {
                 dataToHash[0] = dataToHash[0] &+ 1
                 // Prevent hashOutput being optimized away
                 if hashOutput[0] > 255 { print("Hash guard") }
             }
        }
    }

    // --- L1 Cache Thrash ---
    private func stressL1CacheThrash(workItem: DispatchWorkItem) {
        let size = 32 * 1024         // 32 KB - Target L1d
        let stride = 64              // Typical cache line size
        var buf = [UInt8](repeating: 0, count: size)
        var idx = 0
        let mask = size - 1          // Works because size is power of 2

        while !workItem.isCancelled {
            buf[idx] &+= 1           // Read-modify-write
            idx = (idx + stride) & mask
        }
        // Ensure buffer isn't optimized away
        if buf[0] > 255 { print("L1 Thrash guard") }
    }

    // --- L2 Cache Thrash ---
        private func stressL2CacheThrash(workItem: DispatchWorkItem) {
            let size = 8 * 1024 * 1024   // 8 MB - Target L2 (P-core L2 is 12MB)
            let stride = 128             // Try 128 byte stride (reported M1 line size)
            
            // This line allocates and initializes the buffer to zeros.
            var buf = [UInt8](repeating: 0, count: size)
            
            var idx = 0
            let mask = size - 1          // Works because size is power of 2

            // The redundant initialization block has been removed.

            while !workItem.isCancelled {
                buf[idx] &+= 1           // Read-modify-write
                idx = (idx + stride) & mask
            }
             // Ensure buffer isn't optimized away
             if buf[0] > 255 { print("L2 Thrash guard") }
        }

    // --- Memory Bandwidth ---
    private func stressMemBandwidth(workItem: DispatchWorkItem) {
        let chunk = 64 * 1024 * 1024     // 64 MB chunk
        let totalSize = chunk * 4        // 256 MB total
        guard let src = malloc(totalSize)?.bindMemory(to: UInt8.self, capacity: totalSize),
              let dst = malloc(totalSize)?.bindMemory(to: UInt8.self, capacity: totalSize) else {
            print("Failed to allocate memory for bandwidth test.")
            return // Exit work item if allocation fails
        }
        // Initialize src buffer - can skip for pure copy test if desired
         memset(src, 1, totalSize)

        while !workItem.isCancelled {
            // Copy 4x64 MB per iteration: 256 MB total.
            memcpy(dst,                           src,                           chunk)
            memcpy(dst.advanced(by: chunk),       src.advanced(by: chunk),       chunk)
            memcpy(dst.advanced(by: chunk * 2),   src.advanced(by: chunk * 2),   chunk)
            memcpy(dst.advanced(by: chunk * 3),   src.advanced(by: chunk * 3),   chunk)
        }

        free(src)
        free(dst)
    }

    // --- Mixed CPU Load ---
         private func stressMixedCPU(workItem: DispatchWorkItem, coreIndex: Int) {
             // Combine FP, Integer, and some memory access
             let v = SIMD4<Double>(123.45, 678.90, 123.45, 678.90)
             var accVec = SIMD4<Double>(repeating: Double(coreIndex)) // Vary initial state slightly

             let dataSize = 1024 * 8 // 8 KB buffer for light memory work
             var dataBuffer = Data(repeating: UInt8(coreIndex & 0xFF), count: dataSize)
             var hashOutput = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH)) // SHA1 is faster than SHA256

             var iterations: UInt64 = 0
             let memMask = dataSize - 1

             while !workItem.isCancelled {
                 // 1. FP Work
                 accVec += v.squareRoot()
                 accVec *= SIMD4<Double>(1.0001, 0.9998, 1.0002, 0.9997) // Add multiply

                 // 2. Integer Work (SHA1 hash part of the buffer)
                 let hashLen = min(dataSize, 1024) // Hash 1KB chunks
                 let hashStart = Int(iterations * 64) & memMask // Move hash window
                 let rangeEnd = min(dataSize, hashStart + hashLen)
                 let count = max(0, rangeEnd - hashStart)

                 if count > 0 {
                     dataBuffer.withUnsafeBytes { buffer -> Void in
                         if let baseAddress = buffer.baseAddress {
                             _ = CC_SHA1(baseAddress.advanced(by: hashStart), CC_LONG(count), &hashOutput)
                         }
                     }
                 }

                 // 3. Memory Access (Simple read/write pattern within the buffer)
                 let memIdx = Int(iterations * 128) & memMask

                 // --- FIX IS HERE ---
                 // Get the raw 64-bit pattern of the Double, then truncate to UInt8.
                 // This avoids numeric conversion issues with NaN, infinity, or out-of-range values.
                 let accVecXBits = accVec.x.bitPattern // This is a UInt64
                 let safeAccXAsUInt8 = UInt8(truncatingIfNeeded: accVecXBits)

                 // Now use the safely truncated value in the wrapping addition
                 dataBuffer[memIdx] = dataBuffer[memIdx] &+ hashOutput[Int(iterations % UInt64(CC_SHA1_DIGEST_LENGTH))] &+ safeAccXAsUInt8
                 // --- END FIX ---

                 iterations &+= 1

                 // Avoid overflow / dead code elimination - More robust check needed?
                 // Consider checking isFinite as well, though using bitPattern bypasses the crash.
                 if iterations & 0xFFFFF == 0 {
                     // Reset if non-finite or excessively large/small magnitude
                     if !accVec.x.isFinite || abs(accVec.x) > 1e12 {
                         accVec = SIMD4<Double>(repeating: Double(coreIndex))
                     }
                     if dataBuffer[0] > 250 { dataBuffer[0] = UInt8(coreIndex & 0xFF) }
                 }
             }
             // Ensure results aren't optimized away
             if accVec.x < -1e15 || dataBuffer[0] > 255 { print("Mixed guard: \(accVec.x), \(dataBuffer[0])") } // Adjusted guard print condition
         }
}


#Preview {
    ContentView()
}
