//
//  SuspensionStrut.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/4/26.
//

/// One landing-gear strut: a raycast spring-damper on the aircraft body. The
/// gear is not made of bodies; Bullet's raycast vehicle, Unity's
/// WheelCollider, Jolt's VehicleConstraint, and JSBSim's FGLGear all model it
/// this way.
///
/// Units: attachLocal, restLength, maxTravel, and wheelRadius are post-import
/// body-local meters, multiplied by the body's uniformScale when world
/// quantities are computed (the LocalCollider contract). springRate, the
/// dampings, and maxSupportForce are absolute SI values sized against the
/// aircraft's mass and do not scale: scaling a model does not change its mass.
struct SuspensionStrut {
    var name: String
    /// Strut attach point on the airframe, body-local meters (Y up, +Z nose).
    var attachLocal: float3
    /// Uncompressed strut length below the attach point, meters.
    var restLength: Float
    /// Compression at which the strut bottoms out, meters.
    var maxTravel: Float
    var wheelRadius: Float
    /// N/m. Sized as static load / target static compression.
    var springRate: Float
    /// N·s/m while compressing.
    var compressionDamping: Float
    /// N·s/m while extending. Oleo struts damp rebound harder than
    /// compression; this is also what lets a bounced aircraft leave the ground
    /// cleanly instead of oscillating.
    var reboundDamping: Float
    /// Clamp on the strut force, N, and the gear-overload threshold (B.6).
    var maxSupportForce: Float

    /// Attach point to the uncompressed wheel's contact patch, along body −Y.
    var reach: Float { restLength + wheelRadius }
    /// Body origin to the uncompressed wheel's contact patch for a level
    /// aircraft (attachLocal.y is negative below the origin).
    var reachBelowOrigin: Float { reach - attachLocal.y }
}

/// Pure per-strut math, testable without bodies or a world.
enum SuspensionSolver {
    struct StrutStep: Equatable {
        let compression: Float        // meters, 0...maxTravel·scale
        let compressionRate: Float    // m/s, positive while compressing
        let force: Float              // N along body up, never negative
        let bottomedOut: Bool
        let overloaded: Bool          // unclamped force ≥ maxSupportForce, or bottomed out

        static let noContact = StrutStep(compression: 0,
                                         compressionRate: 0,
                                         force: 0,
                                         bottomedOut: false,
                                         overloaded: false)
    }

    /// `distanceToGround` is the raycast distance along −up from the attach
    /// point; nil or beyond reach means the wheel is in the air.
    static func solve(strut: SuspensionStrut,
                      uniformScale: Float,
                      distanceToGround: Float?,
                      previousCompression: Float,
                      substepDelta: Float) -> StrutStep {
        let reach = strut.reach * uniformScale
        guard let distance = distanceToGround, distance <= reach else { return .noContact }

        // How far the uncompressed wheel would sit below the surface is how
        // far the strut must compress to keep it on the surface.
        let maxTravel = strut.maxTravel * uniformScale
        let rawCompression = reach - distance
        let bottomedOut = rawCompression >= maxTravel
        let compression = min(rawCompression, maxTravel)

        // Finite-difference rate. At touchdown the previous compression is 0
        // and this substep's penetration is sink·dt, so the rate is the sink
        // speed with no special case. Stays correct when Phase D rotates the
        // strut.
        let rate = (compression - previousCompression) / substepDelta
        let damping = rate >= 0 ? strut.compressionDamping : strut.reboundDamping

        // A strut pushes, never pulls. Without the floor, a fast rebound's
        // damper term exceeds the spring term and pulls the aircraft back down.
        let unclamped = strut.springRate * compression + damping * rate
        let force = max(0, min(unclamped, strut.maxSupportForce))
        let overloaded = unclamped >= strut.maxSupportForce || bottomedOut

        return StrutStep(compression: compression,
                         compressionRate: rate,
                         force: force,
                         bottomedOut: bottomedOut,
                         overloaded: overloaded)
    }
}
