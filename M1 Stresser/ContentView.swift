//  ContentView.swift
//  M1 Stresser — Apple‑silicon power‑virus demo
//  Revised 2025‑05‑01
import SwiftUI
import Foundation
import Darwin   // for sqrt() and memcpy()
import Dispatch
import simd

struct ContentView: View {
    
    // MARK: – Stress modes ----------------------------------------------------
    enum StressMode: String, CaseIterable, Identifiable {
        case sqrtFPU        = "Vector sqrt (FP/NEON)"
        case l1CacheThrash  = "L1 Cache Thrash (R/W)"
        case memBandwidth   = "Mem Bandwidth (Stream copy)"
        
        var id: String { rawValue }
    }
    
    // MARK: – View‑state -------------------------------------------------------
    @State private var selectedMode: StressMode = .sqrtFPU
    @State private var isRunning = false
    @State private var workItems: [DispatchWorkItem] = []
    
    // MARK: – UI ---------------------------------------------------------------
    var body: some View {
        VStack(spacing: 24) {
            Text("M1 CPU Stresser").font(.title.bold())
            
            Picker("Stress pattern", selection: $selectedMode) {
                ForEach(StressMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            
            HStack(spacing: 40) {
                Button("Start", action: startStress).disabled(isRunning)
                Button("Stop",  action: stopStress).disabled(!isRunning)
            }
        }
        .padding(40)
        .frame(minWidth: 380)
    }
    
    // MARK: – Stress control ---------------------------------------------------
    private func startStress() {
        guard !isRunning else { return }
        isRunning = true
        
        // Leave one logical core free for the UI thread
        let logicalCores = ProcessInfo.processInfo.activeProcessorCount
        let workerCores  = max(1, logicalCores - 1)
        
        var items: [DispatchWorkItem] = []
        for _ in 0..<workerCores {
            // Capture mode and choose QoS: use .userInteractive to ensure
            // Firestorm cores for the heavy FPU path, otherwise .userInitiated.
            let mode = selectedMode
            let qosClass: DispatchQoS.QoSClass = (mode == .sqrtFPU) ? .userInteractive : .userInitiated
            var workItem: DispatchWorkItem!
            workItem = DispatchWorkItem(qos: DispatchQoS(qosClass: qosClass, relativePriority: 0)) {
                switch mode {
                // —— Vector FPU saturation: keeps both scalar + SIMD pipes busy.
                case .sqrtFPU:
                    // Vectorised FP loop to light up both scalar and SIMD FP pipes.
                    // 4‑wide SIMD produces 4 results per sqrt instruction.
                    let v = SIMD4<Double>(12345.6789, 98765.4321, 67890.1234, 54321.9876)
                    var accVec = SIMD4<Double>(repeating: 0)
                    var iterations: UInt64 = 0
                    
                    while !workItem.isCancelled {
                        // ~32 sqrt/cycle per loop trip (4‑wide * 8 unroll).
                        accVec += v.squareRoot();  accVec += v.squareRoot()
                        accVec += v.squareRoot();  accVec += v.squareRoot()
                        accVec += v.squareRoot();  accVec += v.squareRoot()
                        accVec += v.squareRoot();  accVec += v.squareRoot()
                        iterations &+= 1
                        
                        // Avoid overflow / dead‑code elimination.
                        if iterations & 0xFFFF_FFFF == 0 {
                            if accVec.x > 1e12 { accVec = SIMD4<Double>(repeating: 0) }
                        }
                    }
                    
                // —— L1 cache thrash: 64 B stride writes across a 32 KB buffer.
                case .l1CacheThrash:
                    let size = 32 * 1024
                    var buf  = [UInt8](repeating: 0, count: size)
                    var idx  = 0
                    while !workItem.isCancelled {
                        buf[idx] &+= 1
                        idx = (idx + 64) & (size - 1)
                    }
                    
                // —— Memory‑bandwidth saturator: 256 MB stream copy.
                case .memBandwidth:
                    // 256 MB streaming copy to saturate the SLC → DRAM path.
                    // We split it into 64 MB chunks to minimise cache pollution
                    // while keeping the inner loop tight.
                    let chunk    = 64 * 1024 * 1024     // 64 MB
                    let size     = 256 * 1024 * 1024    // 256 MB total
                    let src      = [UInt8](repeating: 1, count: size)
                    var dst      = [UInt8](repeating: 0, count: size)

                    src.withUnsafeBytes  { srcBuf in
                        dst.withUnsafeMutableBytes { dstBuf in
                            let srcBase = srcBuf.baseAddress!
                            let dstBase = dstBuf.baseAddress!
                            while !workItem.isCancelled {
                                // Copy 4×64 MB per iteration: 256 MB total.
                                memcpy(dstBase,                           srcBase,                           chunk)
                                memcpy(dstBase.advanced(by: chunk),       srcBase.advanced(by: chunk),       chunk)
                                memcpy(dstBase.advanced(by: chunk * 2),   srcBase.advanced(by: chunk * 2),   chunk)
                                memcpy(dstBase.advanced(by: chunk * 3),   srcBase.advanced(by: chunk * 3),   chunk)
                            }
                        }
                    }
                }
            }
            items.append(workItem)
            DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
        }
        workItems = items
    }
    
    private func stopStress() {
        workItems.forEach { $0.cancel() }
        workItems.removeAll()
        isRunning = false
    }
    
    /*
    // MARK: – Stress payloads --------------------------------------------------
    @inline(never)
    private func stressLoop(_ mode: StressMode) {
        var spin = 0
        switch mode {
        case .sqrtFPU:
            // Hot‑loop FP square‑roots; keep the value mutable so optimizer
            // can’t remove the work.
            var x = 12345.6789
            while !Task.isCancelled {
                x = sqrt(x)
                if x < 1.0 { x += 12345.6789 }
                
                spin &+= 1
                if spin & 0x3FFF == 0 { sched_yield() }
            }
            withUnsafePointer(to: &x) { _ = $0 }
            
        case .l1CacheThrash:
            // Hammer every cache line of a 32 KB array.
            let size = 32 * 1024
            var buf  = [UInt8](repeating: 0, count: size)
            var idx  = 0
            while !Task.isCancelled {
                buf[idx] &+= 1
                idx = (idx + 64) & (size - 1)
                
                spin &+= 1
                if spin & 0x3FFF == 0 { sched_yield() }
            }
            _ = buf[0]
            
        case .memBandwidth:
            // Continuous memcpy of a 64 MB buffer to flood SLC/DRAM.
            let size = 64 * 1024 * 1024
            var src  = [UInt8](repeating: 1, count: size)
            var dst  = [UInt8](repeating: 0, count: size)
            
            while !Task.isCancelled {
                src.withUnsafeBytes { sPtr in
                    dst.withUnsafeMutableBytes { dPtr in
                        memcpy(dPtr.baseAddress, sPtr.baseAddress, size)
                    }
                }
                
                spin &+= 1
                if spin & 0x3FFF == 0 { sched_yield() }
            }
        }
    }
    */
}

#Preview {
    ContentView()
}
