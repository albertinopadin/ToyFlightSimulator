//
//  VolumeSlider.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 7/10/26.
//

// SwiftUI Slider is unavailable on tvOS.
#if !os(tvOS)

import SwiftUI

struct VolumeSlider: View {
    @Binding var volume: Float

    var body: some View {
        HStack {
            Text("Game Volume:")

            // The label closure is accessibility-only on iOS and rendered on macOS;
            // labelsHidden() keeps it for VoiceOver without doubling the visible title.
            Slider(value: $volume, in: 0...100) {
                Text("Game Volume:")
            }
            .labelsHidden()
            .onChange(of: volume) {
                AudioManager.SetVolume(volume / 100.0)
            }
            .frame(height: 40.0)

            Text("\(String(format: "%.0f", volume))")
                .frame(minWidth: 25)
                .monospacedDigit()
        }
    }
}

#Preview {
    VolumeSlider(volume: .constant(15.0))
        .padding()
}

#endif
