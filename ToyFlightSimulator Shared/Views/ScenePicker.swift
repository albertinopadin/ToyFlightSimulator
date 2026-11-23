//
//  ScenePicker.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 11/23/26.
//

import SwiftUI

struct ScenePicker: View {
    @Binding var sceneType: SceneType

    var body: some View {
        HStack {
            Text("Scene:")

            // Picker labels only render on macOS; the HStack Text is the visible
            // cross-platform title and labelsHidden() keeps the VoiceOver label.
            Picker("Scene:", selection: $sceneType) {
                ForEach(SceneType.allCases) { sceneType in
                    Text("\(sceneType.rawValue)").tag(sceneType).padding()
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }
}

#Preview {
    ScenePicker(sceneType: .constant(.BallPhysics))
        .padding()
}
