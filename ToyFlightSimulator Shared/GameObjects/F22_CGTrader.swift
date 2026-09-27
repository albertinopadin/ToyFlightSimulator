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
                   aircraftType: .f22_cgtrader,
                   modelType: .CGTrader_F22,
                   scale: scale,
                   shouldUpdateOnPlayerInput: shouldUpdateOnPlayerInput)
        setupAnimator(F22Animator.init)
        // Eye point chosen so this jet's canopy crown sits within 1 cm of the Sketchfab one above
        // the eye (0.304 vs 0.301 m). The cockpit's canopy glass pokes a few cm outside this
        // narrower canopy near its aft end; hide `Canopy_Glass` here if it shows from outside.
        self.attachCockpit(named: "F22_Cockpit", modelType: .F22_Cockpit, eyePointInBodyFrame: [0, 1.08, 5.50])
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
