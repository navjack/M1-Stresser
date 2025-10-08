//
//  M1_StresserApp.swift
//  M1 Stresser
//
//  Created by Jack Mangano on 5/1/25.
//

import SwiftUI

@main
struct M1_StresserApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .tabItem {
                        Label("General", systemImage: "cpu")
                    }
                ExtremeStressView()
                    .tabItem {
                        Label("Extreme", systemImage: "flame.fill")
                    }
                LiveMetricsView()
                    .tabItem {
                        Label("Live Metrics", systemImage: "waveform.path.ecg")
                    }
            }
        }
    }
}
