//
//  ControlInput.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/17/26.
//

public struct ControlInput {
    public let throttle: Float  //  0...1
    public let pitch: Float     // -1...1
    public let roll: Float      // -1...1
    public let yaw: Float       // -1...1

    public init(throttle: Float, pitch: Float, roll: Float, yaw: Float) {
        self.throttle = throttle
        self.pitch = pitch
        self.roll = roll
        self.yaw = yaw
    }
}
