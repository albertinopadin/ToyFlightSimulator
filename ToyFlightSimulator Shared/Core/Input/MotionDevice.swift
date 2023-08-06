//
//  MotionDevice.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/6/23.
//

import CoreMotion

enum MotionContinuousState {
    case MotionPitch
    case MotionRoll
    case MotionYaw
}

class MotionDevice {
    let motionManager: CMMotionManager
    var timer: Timer? = nil
    var present: Bool = false
    
    var motionContinuousStateMapping: [MotionContinuousState: Float] = [
        .MotionPitch: 0.0,
        .MotionRoll: 0.0,
        .MotionYaw: 0.0
    ]
    
    init() {
        motionManager = CMMotionManager()
        
        if motionManager.isDeviceMotionAvailable {
            present = true
            let updateInterval = 1.0 / 60.0  // TODO: Perhaps use fps as the divisor
            motionManager.deviceMotionUpdateInterval = updateInterval
            motionManager.showsDeviceMovementDisplay = true
            motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
            
            timer = Timer(fire: Date(), interval: updateInterval, repeats: true, block: { (timer) in
                if let data = self.motionManager.deviceMotion {
//                    let pitch = data.attitude.pitch
//                    let roll = data.attitude.roll
//                    let yaw = data.attitude.yaw
//
//                    self.motionContinuousStateMapping[.MotionPitch] = Float(pitch)
//                    self.motionContinuousStateMapping[.MotionRoll] = Float(roll)
//                    self.motionContinuousStateMapping[.MotionYaw] = Float(yaw)
                    
                    // Axis are different, because device seems to be assuming portrait orientation:
                    let pitch = -data.attitude.roll
                    let roll = data.attitude.pitch
                    let yaw = data.attitude.yaw
                    
                    self.motionContinuousStateMapping[.MotionPitch] = Float(pitch)
                    self.motionContinuousStateMapping[.MotionRoll] = Float(roll)
                    self.motionContinuousStateMapping[.MotionYaw] = Float(yaw)
                }
            })
            
            RunLoop.current.add(timer!, forMode: .default)
        }
    }
}
