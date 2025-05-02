# M1 Stresser

A macOS application designed to stress test the CPU on Apple Silicon (M1, M2, etc.) Macs. This tool acts as a "power virus," intentionally maximizing CPU utilization and power draw to test thermal performance and stability under heavy load.

## Features

The application provides several stress patterns targeting different CPU components:

*   **Vector FP/NEON:** Saturates the floating-point and NEON vector units using repeated square root calculations.
*   **L1 Cache Thrash:** Generates high L1 data cache activity through patterned reads and writes.
*   **Memory Bandwidth:** Stresses the memory controller and DRAM bandwidth using large, streaming memory copy operations.

## How to Use

1.  Launch the application.
2.  Select the desired stress pattern from the segmented control.
3.  Click "Start" to begin the stress test.
4.  The test will run on all available CPU cores except one (to keep the UI responsive).
5.  Click "Stop" to end the test.

## Building

This is a standard SwiftUI application. Open the `M1 Stresser.xcodeproj` file in Xcode and build/run.

**Build Requirements:**
- macOS 15.0 or later
- Xcode 16.4 beta or later
- Swift 5.0

**Note:** This project was developed using Xcode Version 16.4 beta (16F1t) on macOS 15.5 beta. Compatibility issues may arise if you're using different versions.

**Note:** This project includes profiling instrumentation and may require adjusting the DEVELOPMENT_TEAM setting in the Xcode project for your own development team.

*(Note: The project includes a simple `Item` data model using SwiftData, which doesn't appear to be used by the core stress-testing functionality.)*
