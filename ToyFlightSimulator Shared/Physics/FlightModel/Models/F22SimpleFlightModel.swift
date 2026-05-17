//
//  F22SimpleFlightModel.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/17/26.
//

public final class F22SimpleFlightModel: FlightModel {
    public let mass: Float = 30_000  // 30,000 kg, ~66,000 lbs
    let engineMaxThrust: Float = 31_751  // 31,751 kgf, 70,000 lbf, real F-22 afterburning thrust
    let throttlePower: Float = 10.0
    let liftPower: Float = 50.0
    let liftCoefficientCurve = ValueCurve.smooth([
                                    (input: -30, output: -1.0),
                                    (input:   0, output:  0.2),
                                    (input:  30, output:  1.2),  // 30 degrees + AOA
                                    (input:  90, output:  0.4),
                                    (input: 120, output:  0.0)
                                ])
    let inducedDragPower: Float = 1.0

    // Low-speed suppression ramp for induced drag.
    //
    // Induced drag in calculateInducedDrag is already proportional to
    // v² · Cl² (via liftVelocitySquared * dragForce), which matches the
    // physical formula D_i = ½·ρ·v²·S·(Cl²/(π·AR·e)) up to a constant. This
    // curve is *purely* a numerical fudge: at near-zero airspeed Cl is
    // noisy (atan2 of tiny components, divided through small magnitudes)
    // and we don't want any induced-drag contribution at all until the
    // aircraft is actually moving. Ramps 0 → 1 across 0..5 m/s (~0..10
    // knots, taxi speed), then clamps to 1.0 above. Above the ramp the
    // pure v²·Cl² physics carries the term.
    //
    // To tune: raise the max input (e.g. (10, 1)) to extend the suppression
    // further into the low-speed regime; lower it (e.g. (2, 1)) to engage
    // induced drag sooner. Set to a constant curve (min: (-1, 1), max: (1, 1))
    // to disable the fudge entirely and rely on v²·Cl² alone.
    let inducedDragCurve = SymmetricSigmoidCurve(min: (-1, 0), zero: (0, 0), max: (5, 1))
    
    public init() {}

    public func computeForce(state: RigidBody.State, input: ControlInput) -> float3 {
        let engineForce = state.worldForward * engineMaxThrust * input.throttle * throttlePower
        let worldVelocity = state.velocity
        let localVelo = getLocalVelocity(worldVelocity: worldVelocity, rotationMatrix: state.rotationMatrix)
        let (pitchAOA, _) = calculateAnglesOfAttack(localVelocity: localVelo)
        let liftData = calculateLiftData(angleOfAttack: pitchAOA,
                                         worldVelocity: worldVelocity,
                                         planeNormal: state.worldRight)
        let inducedDrag = calculateInducedDrag(liftData: liftData,
                                               worldVelocity: worldVelocity,
                                               worldForward: state.worldForward)
        let drag = getDragCoefficient() * liftData.liftVelocitySquared * -worldVelocity.normalize()

        DebugLog("[computeForce]\n  engine force: \(engineForce)\n  lift vector: \(liftData.liftForceVector)\n  induced drag + drag: \(inducedDrag + drag)", DEBUG_FORCES)
        let force = engineForce + liftData.liftForceVector + inducedDrag + drag
        return force
    }
    
    private func getLocalVelocity(worldVelocity: float3, rotationMatrix: matrix_float4x4) -> float3 {
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

    // Alternative implementation kept here for reference. Mathematically
    // equivalent to projectOnPlane above but requires a sqrt via normalize().
    // The form above avoids the sqrt by using dot(n, n) directly:
    //
    //     private func projectOnPlaneGoog(vector: float3, planeNormal: float3) -> float3 {
    //         let normal = planeNormal.normalize()
    //         let dotProduct = dot(vector, normal)
    //         return vector - (normal * dotProduct)
    //     }

    private func calculateLiftData(angleOfAttack: Float,
                                   worldVelocity: float3,
                                   planeNormal: float3) -> LiftData {
        let liftVelo = projectOnPlane(vector: worldVelocity, planeNormal: planeNormal)
        let v2 = dot(liftVelo, liftVelo)  // equivalent to pow(liftVelo.magnitude, 2), without sqrt
        let liftCoefficient = getLiftCoefficient(aoa: angleOfAttack)
        let liftForce = v2 * liftCoefficient * liftPower

        let liftDirection = cross(liftVelo.normalize(), planeNormal)
        let liftForceVector = liftDirection * liftForce

        DebugLog("[calculateLiftData] \n  world velocity: \(worldVelocity)\n  lv2: \(v2)\n  lift coeff: \(liftCoefficient)", DEBUG_LIFT)

        return LiftData(liftForceVector: liftForceVector,
                        liftVelocityVector: liftVelo,
                        liftVelocitySquared: v2,
                        liftCoefficient: liftCoefficient)
    }
    
    private func getLiftCoefficient(aoa: Float) -> Float {
        return liftCoefficientCurve.evaluate(at: aoa)
    }
    
    private func calculateInducedDrag(liftData: LiftData, worldVelocity: float3, worldForward: float3) -> float3 {
        let dragForce = pow(liftData.liftCoefficient, 2)
        let dragDirection = -liftData.liftVelocityVector.normalize()
        let inducedDrag = dragDirection *
                          liftData.liftVelocitySquared *
                          dragForce *
                          inducedDragPower *
                          getInducedDragCoefficient(worldVelocity: worldVelocity,
                                                    worldForward: worldForward)
        return inducedDrag
    }
    
    private func getInducedDragCoefficient(worldVelocity: float3, worldForward: float3) -> Float {
        let fwdAirspeed = dot(worldVelocity, worldForward)
        return inducedDragCurve.evaluate(at: max(0, fwdAirspeed))
    }
    
    // Just return constant for now; will implement fully later:
    private func getDragCoefficient() -> Float {
        return 0.2
    }
}
