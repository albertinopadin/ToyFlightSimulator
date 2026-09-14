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
    
    /// Per-strut scratch for the tire solve, index-aligned with `struts` and
    /// reused every substep so the two passes allocate nothing. An entry with
    /// normalLoad 0 is a strut off the ground: TireModel skips it and its
    /// force is zero. Pass 1 rewrites every entry before pass 2 reads them,
    /// so nothing carries over between substeps and resetToAirborne need
    /// not clear it.
    private var wheels: [TireModel.Wheel]
    private var tireForces: [float3]
    
    /// True while any strut carries compression (the avionics WoW signal).
    private(set) var weightOnWheels = false

    var onLandingGearEvent: ((LandingGearEvent) -> Void)?

    init(struts: [SuspensionStrut]) {
        self.struts = struts
        self.compressions = Array(repeating: 0, count: struts.count)
        self.wasOverloaded = Array(repeating: false, count: struts.count)
        
        // Placeholders: normalLoad 0 reads as "off the ground" until pass 1
        // writes the real wheel.
        self.wheels = Array(repeating: TireModel.Wheel(patch: .zero,
                                                       groundNormal: .zero,
                                                       rollingDirection: .zero,
                                                       normalLoad: 0,
                                                       brake: 0),
                            count: struts.count)
        self.tireForces = Array(repeating: .zero, count: struts.count)
    }

    /// One substep. `gearDeployed` is the animation gate (Aircraft.isGearDown):
    /// retracted or moving gear produces no force and holds zero compression.
    /// `brake` is 0…1 and acts on the struts that have brakes.
    func accumulateForces(body: RigidBody, gearDeployed: Bool, brake: Float, world: PhysicsWorld, substepDelta: Float) {
        guard gearDeployed else {
            resetToAirborne()
            return
        }

        let pose = body.pose()
        // Body up, the strut axis: rays go down −up. Not float3.up, which is
        // world up — a rolled aircraft's struts roll with it.
        let up = pose.rotation.up
        // Wheels roll along body forward; TireModel projects it onto the ground.
        let forward = pose.rotation.forward

        // Pass 1: every strut's spring-damper step, its overload edge, and
        // its load — applied now, along the ground normal at the contact
        // patch (Bullet's raycast vehicle applies its suspension impulse the
        // same way), so a pitched or rolled stance pushes nothing along the
        // runway and the load's torque is in the tire solve's prediction.
        // The compression is still measured along the strut. A braking
        // force at ground level pitches the nose down once the body can
        // pitch (D.3).
        for (i, strut) in struts.enumerated() {
            let attachWorld = pose.position + pose.rotation * (strut.attachLocal * pose.uniformScale)
            let hit = world.raycastStaticPlanes(from: attachWorld, direction: -up)
            let step = SuspensionSolver.solve(strut: strut,
                                              uniformScale: pose.uniformScale,
                                              distanceToGround: hit?.distance,
                                              previousCompression: compressions[i],
                                              substepDelta: substepDelta)
            compressions[i] = step.compression

            // Rising edge only: one event per exceedance, per strut.
            if step.overloaded && !wasOverloaded[i] {
                onLandingGearEvent?(.gearOverload(strutName: strut.name,
                                                  force: step.force,
                                                  bottomedOut: step.bottomedOut))
            }

            wasOverloaded[i] = step.overloaded
            
            if let hit, step.force > 0 {
                let patch = attachWorld - up * hit.distance
                body.addForce(hit.normal * step.force, atWorldPoint: patch)
                wheels[i] = TireModel.Wheel(patch: patch,
                                            groundNormal: hit.normal,
                                            rollingDirection: forward,
                                            normalLoad: step.force,
                                            brake: strut.hasBrakes ? brake : 0)
            } else {
                wheels[i].normalLoad = 0
            }
        }
        
        // Pass 2: the tires, solved together against the body's velocities
        // as this substep's other forces and torques would leave them — the
        // flight model's force (Aircraft.generateForces adds it first), the
        // strut loads above, and the solver's gravity. Their impulses come
        // back as forces at the patches. I⁻¹ in world axes is read once and
        // shared by the prediction and the solve.
        let gravity: float3 = body.shouldApplyGravity ? PhysicsWorld.gravity : .zero
        var velocity = body.velocity + (body.force / body.mass + gravity) * substepDelta
        let bodyInverseInertiaWorld = body.inverseInertiaWorld()
        var angularVelocity = body.angularVelocity + bodyInverseInertiaWorld * body.torque * substepDelta
        TireModel.solve(wheels: wheels,
                        body: TireModel.Body(origin: pose.position,
                                             inverseMass: 1 / body.mass,
                                             inverseInertiaWorld: bodyInverseInertiaWorld),
                        velocity: &velocity,
                        angularVelocity: &angularVelocity,
                        substepDelta: substepDelta,
                        forces: &tireForces)
        for i in struts.indices where wheels[i].normalLoad > 0 {
            body.addForce(tireForces[i], atWorldPoint: wheels[i].patch)
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
