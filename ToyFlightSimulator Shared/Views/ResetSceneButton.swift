//
//  ResetSceneButton.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 7/10/26.
//

import SwiftUI

struct ResetSceneButton: View {
    var body: some View {
        Button("Reset Scene", role: .destructive) {
            print("Pressed SwiftUI Reset Scene button")
            SceneManager.RequestResetScene()
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
    }
}

#Preview {
    ResetSceneButton()
}
