//
//  F22_CGTrader.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2/23/26.
//

class F22_CGTrader: Aircraft {
    static let NAME: String = "F-22_CGTrader"

    override var cameraOffset: float3 {
        [0, 7, -20]
    }

    init(scale: Float = 1.0, shouldUpdateOnPlayerInput: Bool = true) {
        super.init(name: Self.NAME,
                   modelType: .CGTrader_F22,
                   scale: scale,
                   shouldUpdateOnPlayerInput: shouldUpdateOnPlayerInput)
        setupAnimator(F22Animator.init)
    }

    override func doUpdate() {
        super.doUpdate()

        if shouldUpdateOnPlayerInput && hasFocus {
            let pitchValue = InputManager.ContinuousCommand(.Pitch)
            let rollValue = InputManager.ContinuousCommand(.Roll)
            self.animator?.deflectHorizontalStabilizers(pitchInput: pitchValue, rollInput: rollValue)
            self.animator?.rollAilerons(value: rollValue)
            self.animator?.rollFlaperons(value: rollValue)

            let yawValue = InputManager.ContinuousCommand(.Yaw)
            self.animator?.yawRudders(value: yawValue)
        }
    }
}
