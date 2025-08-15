//
//  TFSTouchJoystick.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/9/24.
//

import SwiftUI

struct TFSTouchJoystick: View {
    var viewSize: CGSize
    
    @GestureState private var joystickPosition: CGSize = .zero
    
    var body: some View {
        Circle()
            .fill(.gray.opacity(0.5))
            .frame(width: 50, height: 50)
            .position(x: viewSize.width - 120, y: viewSize.height - 100)
            .offset(joystickPosition)
            .gesture(
                DragGesture().updating($joystickPosition) { value, state, transaction in
                    state = value.translation
                }
            )
            .onChange(of: joystickPosition) { oldValue, newValue in
                print("Joystick position changed: \(newValue)")
                // Height / Width are flipped as we're in landscape:
                InputManager.SetContinuous(command: .Pitch, value: Float(newValue.height / 100).clamped(to: -1...1))
                InputManager.SetContinuous(command: .Roll, value: Float(newValue.width / 100).clamped(to: -1...1))
            }
    }
}

#Preview {
    TFSTouchJoystick(viewSize: CGSize(width: 1920, height: 1080))
}
