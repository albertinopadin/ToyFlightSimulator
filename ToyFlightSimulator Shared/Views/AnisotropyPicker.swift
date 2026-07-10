//
//  AnisotropyPicker.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 7/10/26.
//

import SwiftUI

struct AnisotropyPicker: View {
    @Binding var maxAnisotropy: MaxAnisotropy

    var body: some View {
        HStack {
            Text("Anisotropic Filtering:")

            // Picker labels only render on macOS; the HStack Text is the visible
            // cross-platform title and labelsHidden() keeps the VoiceOver label.
            Picker("Anisotropic Filtering:", selection: $maxAnisotropy) {
                ForEach(MaxAnisotropy.allCases) { level in
                    Text(level.label).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: maxAnisotropy) { _, newValue in
                Preferences.SelectedMaxAnisotropy = newValue
                Graphics.SamplerStates.setLinearMaxAnisotropy(newValue)
            }
        }
    }
}

#Preview {
    AnisotropyPicker(maxAnisotropy: .constant(.x8))
        .padding()
}
