//
//  F22.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/20/24.
//

import MetalKit

struct LiftData {
    let worldVelocity: float3
    let liftForceVector: float3
    let liftVelocityVector: float3
    let liftVelocitySquared: Float
    let liftCoefficient: Float
}

class F22: Aircraft {
    static let NAME: String = "F-22"
    
    let afterburnerLeft = Afterburner(name: "F-22 Left Afterburner")
    let afterburnerRight = Afterburner(name: "F-22 Right Afterburner")
    
    let mass: Float = 30_000  // 30,000 kg, ~66,000 lbs
    let engineMaxThrust: Float = 31_751  // 31,751 kg,  70,000 lbs of thrust
    let liftPower: Float = 50.0
    let liftCoefficientCurve = ValueCurve.smooth([
                                    (input: -30, output: -1.0),
                                    (input:   0, output:  0.2),
                                    (input:  30, output:  1.2)  // 30 degrees + AOA
                                ])
    let inducedDragPower: Float = 1.0
    let inducedDragCurve = AeroCurve(min: (-1, 0), zero: (0, 0), max: (360, 1))  // 700 knots, 360 m/s
    
    override var cameraOffset: float3 {
        [0, 55, -150]
    }
    
    override var rigidBody: RigidBody? {
        didSet {
            rigidBody?.restitution = 0.1
            rigidBody?.mass = self.mass
        }
    }
    
    init(scale: Float = 1.0, shouldUpdateOnPlayerInput: Bool = true) {
        super.init(name: Self.NAME,
                   modelType: .Sketchfab_F22,
                   scale: scale,
                   shouldUpdateOnPlayerInput: shouldUpdateOnPlayerInput)
        
        afterburnerLeft.off()
        afterburnerLeft.setPosition(-7, 1, -30)
        addChild(afterburnerLeft)

        afterburnerRight.off()
        afterburnerRight.setPosition(7, 1, -30)
        addChild(afterburnerRight)
    }
    
    override func doUpdate() {
        // Hack so jet doesn't go thru ground:
        if getPositionY() < 0 {
            setPositionY(0.0)
        }
        
        if let rigidBody, shouldUpdateOnPlayerInput && hasFocus {
            applyForces(rigidBody: rigidBody)

            let deltaTurn = Float(GameTime.DeltaTime) * _turnSpeed
            let deltaMove = Float(GameTime.DeltaTime) * _moveSpeed
            applyPlayerAttitudeInput(deltaTurn: deltaTurn)
            applyPlayerSideMove(deltaMove: deltaMove)
            handleGearToggle()

            animator?.update(deltaTime: Float(GameTime.DeltaTime))
        } else {
            super.doUpdate()
        }

        if hasFocus {
            let fwdValue = InputManager.ContinuousCommand(.MoveFwd)

            if fwdValue > 0.8 {
                afterburnerLeft.on()
                afterburnerRight.on()
            } else {
                afterburnerLeft.off()
                afterburnerRight.off()
            }
        }
    }

//    private func applyForces(rigidBody: RigidBody) {
//        let fwd = getFwdVector()
//        let velocity = rigidBody.velocity
//        let fwdVelocity = max(0, dot(velocity, fwd))
//        let fwdVeloSq = pow(fwdVelocity, 2)
//        let angleOfAttack: Float = 2.0  // Constant for now; in degrees
//        let engineForce = fwd * engineThrust * InputManager.ContinuousCommand(.MoveFwd) * 10.0
//        let lift = fwdVeloSq * getLiftCoefficient(aoa: angleOfAttack) * liftPower
//        let liftForceVector = getUpVector() * lift
//        let dragForceVector = fwdVeloSq * getDragCoefficient() * -fwd
//        rigidBody.force += engineForce + liftForceVector + dragForceVector
//    }
    
    private func applyForces(rigidBody: RigidBody) {
        let fwd = getFwdVector()
        let engineForce = fwd * engineMaxThrust * InputManager.ContinuousCommand(.MoveFwd) * 10.0
        let worldVelocity = rigidBody.velocity
        let localVelo = getLocalVelocity(worldVelocity: worldVelocity)
        let (pitchAOA, _) = calculateAnglesOfAttack(localVelocity: localVelo)
        let liftData = calculateLiftData(angleOfAttack: pitchAOA,
                                         worldVelocity: worldVelocity,
                                         planeNormal: getRightVector(),
                                         liftPower: liftPower)
        let inducedDrag = calculateInducedDrag(liftData: liftData)
        let drag = getDragCoefficient() * liftData.liftVelocitySquared * -worldVelocity.normalize()
        
        print("[applyForces]\n  engine force: \(engineForce)\n  lift vector: \(liftData.liftForceVector)\n  induced drag + drag: \(inducedDrag + drag)")
        rigidBody.force += engineForce + liftData.liftForceVector + inducedDrag + drag
    }
    
    private func getLocalVelocity(worldVelocity: float3) -> float3 {
        let rotationMatrix = getRotationMatrix()
        let rotationUpperLeft3 = rotationMatrix.upperLeft3x3
        let inverseRotation = rotationUpperLeft3.inverse
        let localVelo = inverseRotation * worldVelocity
        return localVelo
    }
    
    private func calculateAnglesOfAttack(localVelocity: float3) -> (pitchAngleOfAttack: Float, yawAngleOfAttack: Float) {
        if localVelocity.magnitude < 0.1 {
            return (0, 0)
        }
        
        let pitchAOA = atan2(-localVelocity.y, localVelocity.z).toDegrees
        let yawAOA = atan2(localVelocity.x, localVelocity.z).toDegrees
        return (pitchAOA, yawAOA)
    }
    
    private func projectOnPlane(vector: float3, planeNormal: float3) -> float3 {
        let sqMag = dot(planeNormal, planeNormal)
        guard sqMag > .ulpOfOne else { return vector }
        return vector - (dot(vector, planeNormal) / sqMag) * planeNormal
    }
    
    // Google's alternative implementation:
    private func projectOnPlaneGoog(vector: float3, planeNormal: float3) -> float3 {
        let normal = planeNormal.normalize()
        let dotProduct = dot(vector, normal)
        return vector - (normal * dotProduct)
    }
    
    private func calculateLiftData(angleOfAttack: Float,
                                   worldVelocity: float3,
                                   planeNormal: float3,
                                   liftPower: Float) -> LiftData {
        let liftVelo = projectOnPlane(vector: worldVelocity, planeNormal: planeNormal)
        let v2 = dot(liftVelo, liftVelo)  // equivalent to pow(liftVelo.magnitude, 2), without sqrt
        let liftCoefficient = getLiftCoefficient(aoa: angleOfAttack)
        let liftForce = v2 * liftCoefficient * liftPower
        
        let liftDirection = cross(liftVelo.normalize(), planeNormal)
        let liftForceVector = liftDirection * liftForce
        
        print("[calculateLiftData] \n  world velocity: \(worldVelocity)\n  lv2: \(v2)\n  lift coeff: \(liftCoefficient)")
        
        return LiftData(worldVelocity: worldVelocity,
                        liftForceVector: liftForceVector,
                        liftVelocityVector: liftVelo,
                        liftVelocitySquared: v2,
                        liftCoefficient: liftCoefficient)
    }
    
    private func getLiftCoefficient(aoa: Float) -> Float {
        return liftCoefficientCurve.evaluate(at: aoa)
    }
    
    private func calculateInducedDrag(liftData: LiftData) -> float3 {
        let dragForce = pow(liftData.liftCoefficient, 2)
        let dragDirection = -liftData.liftVelocityVector.normalize()
        let inducedDrag = dragDirection *
                          liftData.liftVelocitySquared *
                          dragForce *
                          inducedDragPower *
                          getInducedDragCoefficient(worldVelocity: liftData.worldVelocity)
        return inducedDrag
    }
    
    private func getInducedDragCoefficient(worldVelocity: float3) -> Float {
        let fwdAirspeed = dot(worldVelocity, getFwdVector())
        return inducedDragCurve.evaluate(at: max(0, fwdAirspeed))
    }
    
    // Just return constant for now; will implement fully later:
    private func getDragCoefficient() -> Float {
        return 0.2
    }
}
