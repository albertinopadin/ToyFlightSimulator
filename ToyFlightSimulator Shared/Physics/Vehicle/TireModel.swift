//
//  TireModel.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/13/26.
//

/// Tangent forces of the loaded wheels for one substep, solved together,
/// pure. Holding Coulomb friction as sequential impulses (Catto, GDC 2006):
/// each wheel in turn applies the impulse that brings its patch's tangent
/// velocity — predicted to the end of the substep from the body's other
/// forces and torques — to rest, clamped to what the tire can carry, and
/// the prediction is updated as each impulse lands; a few sweeps converge.
/// At rest that is exactly the force needed to stay at rest, so a parked
/// aircraft holds at idle on rolling resistance and holds against thrust up
/// to the brake limit, then slides; a wheel at its limit leaves the rest of
/// the demand to the wheels after it. (A force proportional to slip speed,
/// the first draft, is zero at rest and creeps under any push: 0.2 m/s from
/// the parked stance alone. A fixed per-wheel share of the demand, the
/// second, left the unbraked nose wheel's unmet share to nobody: 1.6 cm of
/// creep in 5 s under 100 kN with the brakes on.) There is no wheel spin
/// state: a free wheel rolls, resisting along its rolling direction only
/// with rolling resistance; braking raises that limit. Lateral and
/// longitudinal parts together are clamped to the friction circle.
enum TireModel {
    static let lateralFriction: Float = 0.8       // cornering grip, dry runway
    static let brakeFriction: Float = 0.5         // fully braked wheel, dry
    static let rollingResistance: Float = 0.02
    /// Sweeps over the wheels. With infinite inertia the first sweep is
    /// exact (every patch shares the body's velocity). With the F-22's
    /// tensor the patches couple through pitch, roll, and yaw, and a sweep
    /// removes about three quarters of what is left: eight leave under 0.1%
    /// of a 1 mm/s or 1 mrad/s disturbance at any patch (four leave 3%),
    /// and the next substep sees the rest as velocity.
    static let sweeps = 8
    /// The per-solve scratch is fixed-size; no aircraft has more struts.
    static let maxWheels = 8
    
    /// One wheel on the ground.
    struct Wheel {
        /// Contact patch on the ground, world space.
        var patch: float3
        /// Unit ground normal at the patch.
        var groundNormal: float3
        /// The wheel's forward axis (body forward, steered or not); any
        /// length, projected onto the ground plane here.
        var rollingDirection: float3
        /// Normal load, N. Zero for a strut off the ground: the wheel is
        /// skipped and its force is zero.
        var normalLoad: Float
        /// Brake command 0…1 on this wheel (0 for struts without brakes).
        var brake: Float
    }
    
    /// The body as the solve sees it: the point its velocities refer to, and
    /// what an impulse does to them.
    struct Body {
        var origin: float3
        var inverseMass: Float
        /// Zero for infinite inertia (RigidBody.infiniteInertia).
        var inverseInertiaWorld: float3x3
    }
    
    /// Solves `wheels` together. `velocity` and `angularVelocity` are the
    /// body's predicted end-of-substep velocities if no wheel acted; on
    /// return they carry the wheels' impulses (the solve's bookkeeping, not
    /// applied to any body here). `forces[i]` receives wheel i's force — its
    /// impulse over the substep — and zero for an unloaded wheel or one
    /// whose rolling axis is normal to the ground.
    static func solve(wheels: [Wheel],
                      body: Body,
                      velocity: inout float3,
                      angularVelocity: inout float3,
                      substepDelta h: Float,
                      forces: inout [float3]) {
        assert(wheels.count <= maxWheels && forces.count == wheels.count)
        // Accumulated impulses per wheel, N·s, along the wheel's forward and
        // side directions (Catto's accumulated clamping, in two dimensions).
        var longitudinal: SIMD8<Float> = .zero
        var lateral: SIMD8<Float> = .zero
        
        for _ in 0..<sweeps {
            for (i, wheel) in wheels.enumerated() {
                guard let frame = groundFrame(of: wheel) else { continue }
                let lever = wheel.patch - body.origin
                let patchVelocity = velocity + cross(angularVelocity, lever)
                
                // The impulse that stops the patch along each direction, on
                // top of what this wheel has already applied; then the
                // Coulomb limits as impulses — rolling resistance raised by
                // the brake along, cornering grip across, the circle over
                // both.
                let alongLimit = (rollingResistance + wheel.brake * brakeFriction) * wheel.normalLoad * h
                let acrossLimit = lateralFriction * wheel.normalLoad * h
                var along = longitudinal[i] - effectiveMass(body, lever: lever, along: frame.forward) * dot(patchVelocity, frame.forward)
                var across = lateral[i] - effectiveMass(body, lever: lever, along: frame.side) * dot(patchVelocity, frame.side)
                along = max(-alongLimit, min(alongLimit, along))
                let magnitude = (along * along + across * across).squareRoot()
                if magnitude > acrossLimit {
                    let scale = acrossLimit / magnitude
                    along *= scale
                    across *= scale
                }
                
                let impulse = frame.forward * (along - longitudinal[i]) + frame.side * (across - lateral[i])
                longitudinal[i] = along
                lateral[i] = across
                velocity += impulse * body.inverseMass
                angularVelocity += body.inverseInertiaWorld * cross(lever, impulse)
            }
        }
        
        for (i, wheel) in wheels.enumerated() {
            if let frame = groundFrame(of: wheel) {
                forces[i] = (frame.forward * longitudinal[i] + frame.side * lateral[i]) / h
            } else {
                forces[i] = .zero
            }
        }
    }
    
    /// The wheel's rolling direction projected onto the ground and the side
    /// direction across it, or nil for an unloaded wheel or a rolling axis
    /// normal to the ground.
    private static func groundFrame(of wheel: Wheel) -> (forward: float3, side: float3)? {
        guard wheel.normalLoad > 0 else { return nil }
        let n = wheel.groundNormal
        let inPlane = wheel.rollingDirection - n * dot(wheel.rollingDirection, n)
        // For a unit rolling direction the squared length is sin² of its
        // angle from the normal: 1e-4 rejects an axis within 0.57° of it.
        guard simd_length_squared(inPlane) > 1e-4 else { return nil }
        let forward = simd_normalize(inPlane)
        return (forward, cross(n, forward))
    }
    
    /// Effective mass at a lever arm along a unit direction,
    /// 1 / (1/m + (r × d) · I⁻¹ (r × d)): the mass an impulse there along d
    /// sees. The mass itself for infinite inertia.
    private static func effectiveMass(_ body: Body, lever r: float3, along d: float3) -> Float {
        let arm = cross(r, d)
        return 1 / (body.inverseMass + dot(body.inverseInertiaWorld * arm, arm))
    }
}
