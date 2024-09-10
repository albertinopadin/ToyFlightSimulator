//
//  TFSTouchThrottle.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/9/24.
//

import SwiftUI

struct TFSTouchThrottle: View {
    var viewSize: CGSize
    
    @State private var throttle: Float = 0.0
    
    var body: some View {
        Slider(value: $throttle, label: {
            Label("Throttle", systemImage: "airplane")
        }, minimumValueLabel: {
            Text("Idle")
                .rotationEffect(Angle(degrees: 90))
        }, maximumValueLabel: {
            Text("Max")
                .rotationEffect(Angle(degrees: 90))
        })
        .gesture(
            DragGesture().onChanged { gesture in
                throttle = Float(gesture.translation.width / 200).clamped(to: 0...1)
            }
        )
        .background(.gray.opacity(0.25))
        .rotationEffect(Angle(degrees: -90))
        .frame(width: 200, height: 100)
        .position(x: 120, y: viewSize.height - 100)
        .onChange(of: throttle) { newValue in
            print("Throttle changed: \(newValue)")
            InputManager.SetContinuous(command: .MoveFwd, value: throttle)
        }
    }
}

#Preview {
    TFSTouchThrottle(viewSize: CGSize(width: 1920, height: 1080))
}
