//
//  CameraPicker.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/27/26.
//

import SwiftUI

struct CameraPicker: View {
    @Binding var cameraType: CameraType

    var body: some View {
        HStack {
            Text("Camera:")

            // Picker labels only render on macOS; the HStack Text is the visible
            // cross-platform title and labelsHidden() keeps the VoiceOver label.
            Picker("Camera:", selection: $cameraType) {
                ForEach(CameraType.allCases) { cam in
                    Text("\(cam.rawValue)").tag(cam).padding()
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: cameraType) { old, new in
                SceneManager.SetCamera(new)
            }
        }
    }
}

#Preview {
    CameraPicker(cameraType: .constant(.Attached))
        .padding()
}
