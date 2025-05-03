# M1 Stresser

A macOS application designed to stress test Apple Silicon (M1, M2, etc.) processors. This tool acts as a "power virus," intentionally maximizing CPU, GPU, and neural engine utilization to test thermal performance and stability under heavy load.

## Features

The application provides several stress patterns targeting different processor components:

### CPU Stress Modes
*   **Vector sqrt (FP/NEON):** Saturates the floating-point and NEON vector units using repeated square root calculations.
*   **Integer ALU (Hashing):** Uses CommonCrypto for SHA256 hashing operations to stress integer ALU.
*   **L1 Cache Thrash (R/W):** Generates high L1 data cache activity through patterned reads and writes.
*   **L2 Cache Thrash (R/W):** Stresses L2 cache with larger memory patterns.
*   **Mem Bandwidth (Stream):** Stresses the memory controller and DRAM bandwidth using large, streaming memory copy operations.
*   **Mixed CPU Load:** Combines FP, integer, and memory operations across all cores.

### Accelerator Modes (can run concurrently)
*   **GPU Compute (Metal):** Uses Metal to stress the GPU with compute shaders.
*   **ANE Proxy (BLAS):** Uses Accelerate framework's vDSP for matrix operations (may utilize ANE).

## How to Use

1.  Launch the application.
2.  Select the desired stress pattern from the segmented control.
3.  Optionally enable concurrent GPU and/or ANE stress testing using the toggles.
4.  Click "Start" to begin the stress test.
5.  The test will run on all available CPU cores except one (to keep the UI responsive).
6.  Click "Stop" to end the test.

## Building

This is a standard SwiftUI application. Open the `M1 Stresser.xcodeproj` file in Xcode and build/run.

**Build Requirements:**
- macOS 15.0 or later
- Xcode 16.4 beta or later
- Swift 5.0
- Metal support

**Note:** This project was developed using Xcode Version 16.4 beta (16F1t) on macOS 15.5 beta. Compatibility issues may arise if you're using different versions.
