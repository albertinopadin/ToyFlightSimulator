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
    
    case MotionPitchRaw
    case MotionRollRaw
    case MotionYawRaw
}

class MotionDevice {
    let motionManager: CMMotionManager
    var timer: Timer? = nil
    var present: Bool = false
    
    private let dQueue: DispatchQueue
    private var pitchZero: Float = 0.0
    private var rollZero: Float = 0.0
    private var yawZero: Float = 0.0
    
    var motionContinuousStateMapping: [MotionContinuousState: Float] = [
        .MotionPitch: 0.0,
        .MotionRoll: 0.0,
        .MotionYaw: 0.0,
        .MotionPitchRaw: 0.0,
        .MotionRollRaw: 0.0,
        .MotionYawRaw: 0.0
    ]
    
    init(pitchAxisFlipped: Bool = true) {
        dQueue = DispatchQueue(label: "motion_device_queue")
        motionManager = CMMotionManager()
        
        if motionManager.isDeviceMotionAvailable {
            present = true
            let updateInterval = 1.0 / 60.0  // TODO: Perhaps use fps as the divisor
            motionManager.deviceMotionUpdateInterval = updateInterval
            motionManager.showsDeviceMovementDisplay = true
            motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
            
            timer = Timer(fire: Date(), interval: updateInterval, repeats: true, block: { [weak self] (timer) in
                if let data = self!.motionManager.deviceMotion {
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
                    
                    self!.dQueue.sync {
                        self!.motionContinuousStateMapping[.MotionPitchRaw] = Float(pitch)
                        self!.motionContinuousStateMapping[.MotionRollRaw] = Float(roll)
                        self!.motionContinuousStateMapping[.MotionYawRaw] = Float(yaw)
                        
                        self!.motionContinuousStateMapping[.MotionPitch] = Float(pitch) - self!.pitchZero
                        self!.motionContinuousStateMapping[.MotionRoll] = Float(roll) - self!.rollZero
                        self!.motionContinuousStateMapping[.MotionYaw] = Float(yaw) - self!.yawZero
                    }
                }
            })
            
            RunLoop.current.add(timer!, forMode: .default)
        }
    }
    
    func zeroDevice() {
        pitchZero = motionContinuousStateMapping[.MotionPitchRaw]!
        rollZero = motionContinuousStateMapping[.MotionRollRaw]!
        yawZero = motionContinuousStateMapping[.MotionYawRaw]!
    }
}
