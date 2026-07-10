//
//  RefreshRatePicker.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 7/10/26.
//

import SwiftUI

struct RefreshRatePicker: View {
    @Binding var framesPerSecond: FPS

    var body: some View {
        HStack {
            Text("Refresh Rate:")

            // Picker labels only render on macOS; the HStack Text is the visible
            // cross-platform title and labelsHidden() keeps the VoiceOver label.
            Picker("Refresh Rate:", selection: $framesPerSecond) {
                ForEach(FPS.allCases) { fps in
                    Text("\(fps.rawValue)").tag(fps).padding()
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

#Preview {
    RefreshRatePicker(framesPerSecond: .constant(.FPS_120))
        .padding()
}
