//
//  RendererPicker.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 7/10/26.
//

import SwiftUI

struct RendererPicker: View {
    @Binding var rendererType: RendererType

    var body: some View {
        HStack {
            Text("Renderer:")

            // Picker labels only render on macOS; the HStack Text is the visible
            // cross-platform title and labelsHidden() keeps the VoiceOver label.
            Picker("Renderer:", selection: $rendererType) {
                ForEach(RendererType.allCases) { rendererType in
                    Text("\(rendererType.rawValue)").tag(rendererType).padding()
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }
}

#Preview {
    RendererPicker(rendererType: .constant(.TiledDeferred))
        .padding()
}
