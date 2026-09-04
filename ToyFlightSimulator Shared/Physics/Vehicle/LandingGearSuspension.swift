//
//  LandingGearSuspension.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/4/26.
//

/// Gear/ground events. Fired on the UpdateThread inside the physics step;
/// handlers must be cheap and must not change physics state (the onContact
/// rule). Nobody is registered until B.6.
enum LandingGearEvent {
    /// Weight on wheels went false → true. sinkRate is the body's downward
    /// speed at that substep, before the strut forces act on it (level-runway
    /// vertical rate).
    case touchdown(sinkRate: Float, compressions: [Float])
    /// Weight on wheels went true → false (bounce, or takeoff).
    case liftoff
    /// A strut's unclamped force crossed maxSupportForce, or it bottomed out.
    /// Fires once per exceedance, per strut.
    case gearOverload(strutName: String, force: Float, bottomedOut: Bool)
}

/// Per-aircraft suspension state. Owned by Aircraft and driven from its
/// generateForces every substep, outside the input guard, because a parked
/// aircraft must be held up. Per-instance state only; UpdateThread only.
final class LandingGearSuspension {
    let struts: [SuspensionStrut]
    /// Current compression per strut, meters; index-aligned with `struts`.
    private(set) var compressions: [Float]
    private var wasOverloaded: [Bool]
    /// True while any strut carries compression (the avionics WoW signal).
    private(set) var weightOnWheels = false

    var onLandingGearEvent: ((LandingGearEvent) -> Void)?

    init(struts: [SuspensionStrut]) {
        self.struts = struts
        self.compressions = Array(repeating: 0, count: struts.count)
        self.wasOverloaded = Array(repeating: false, count: struts.count)
    }

    /// One substep. `gearDeployed` is the animation gate (Aircraft.isGearDown):
    /// retracted or moving gear produces no force and holds zero compression.
    func accumulateForces(body: RigidBody, gearDeployed: Bool, world: PhysicsWorld, substepDelta: Float) {
        guard gearDeployed else {
            resetToAirborne()
            return
        }

        let pose = body.pose()
        // Body up, the strut axis: rays go down −up, force pushes +up. Not
        // float3.up, which is world up — a rolled aircraft's struts roll with it.
        let up = pose.rotation.up

        for (i, strut) in struts.enumerated() {
            let attachWorld = pose.position + pose.rotation * (strut.attachLocal * pose.uniformScale)
            let distance = world.raycastStaticPlanes(from: attachWorld, direction: -up)
            let step = SuspensionSolver.solve(strut: strut,
                                              uniformScale: pose.uniformScale,
                                              distanceToGround: distance,
                                              previousCompression: compressions[i],
                                              substepDelta: substepDelta)
            compressions[i] = step.compression
            body.force += up * step.force

            // Rising edge only: one event per exceedance, per strut.
            if step.overloaded && !wasOverloaded[i] {
                onLandingGearEvent?(.gearOverload(strutName: strut.name,
                                                  force: step.force,
                                                  bottomedOut: step.bottomedOut))
            }

            wasOverloaded[i] = step.overloaded
        }

        // Weight-on-wheels transitions after all struts updated, so a
        // touchdown event carries this substep's complete compressions. The
        // force phase runs before the collision response, so body.velocity is
        // still the incoming velocity here.
        let anyContact = compressions.contains { $0 > 0 }
        if anyContact != weightOnWheels {
            weightOnWheels = anyContact
            if anyContact {
                let sinkRate = max(0, -body.velocity.y)
                onLandingGearEvent?(.touchdown(sinkRate: sinkRate, compressions: compressions))
            } else {
                onLandingGearEvent?(.liftoff)
            }
        }
    }

    /// Gear retracted or in transit: no force, compressions zeroed so the
    /// next deployment's finite differences start from rest. Known quirk,
    /// accepted: deploying the gear while resting on the fuselage reads a
    /// large compression on the first substep and lifts the aircraft onto its
    /// wheels. Bounded by maxSupportForce, and an aircraft on its fuselage is
    /// already a crash.
    private func resetToAirborne() {
        for i in compressions.indices {
            compressions[i] = 0
            wasOverloaded[i] = false
        }

        if weightOnWheels {
            weightOnWheels = false
            onLandingGearEvent?(.liftoff)
        }
    }
}
