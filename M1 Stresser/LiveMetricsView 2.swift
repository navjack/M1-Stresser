// LiveMetricsView.swift
// Placeholder for future live metrics functionality.

import SwiftUI

struct LiveMetricsView: View {
    var body: some View {
        VStack {
            Text("Live Metrics")
                .font(.largeTitle)
                .padding(.bottom, 20)
            Text("Live power and thermal metrics will appear here.")
                .foregroundColor(.secondary)
        }
        .padding(40)
    }
}

#Preview {
    LiveMetricsView()
}
