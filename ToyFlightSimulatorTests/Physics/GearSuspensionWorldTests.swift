//
//  GearSuspensionWorldTests.swift
//  ToyFlightSimulatorTests
//
//  B.5 (B-suspension, part 2): the B-phase counterpart of CompoundBodyTests —
//  the real LandingGearSuspension driving the live F-22 gear spec through the
//  body's force hook, over the compound colliders and corrected response, end
//  to end and Metal-free (detached bodies, plan rule 3).
//

import Foundation
import Testing
import simd
@testable import ToyFlightSimulator

@Suite("Gear suspension (world)", .tags(.physics))
struct GearSuspensionWorldTests {
    private static let dt: Float = 1.0 / 60.0

    /// Body-origin height at which the F-22's struts first touch level ground:
    /// every authored strut reaches 2.05 m below the origin.
    private static let strutContactHeight: Float =
        AircraftLandingGearSpec.spec(for: .f22_cgtrader)[0].reachBelowOrigin

    /// Metal-free stand-in for Aircraft: drives the real LandingGearSuspension
    /// from the body's force hook. A detached body's pose has the identity
    /// rotation, i.e. a level aircraft. Node rotation and the animator gate
    /// are B.5's in-app checks.
    private final class GearRig {
        let body: RigidBody
        let suspension: LandingGearSuspension
        var gearDeployed = true

        init(body: RigidBody, struts: [SuspensionStrut]) {
            self.body = body
            self.suspension = LandingGearSuspension(struts: struts)
            body.forceGenerator = { [weak self] body, substepDelta, world in
                guard let self else { return }
                self.suspension.accumulateForces(body: body,
                                                 gearDeployed: self.gearDeployed,
                                                 world: world,
                                                 substepDelta: substepDelta)
            }
        }
    }

    private func makeF22OnGear(startY: Float, velocityY: Float = 0)
        -> (world: PhysicsWorld, body: RigidBody, rig: GearRig) {
        let body = RigidBody(detachedAt: [0, startY, 0])
        body.mass = 30_000                                    // the flight model's mass
        body.restitution = 0.2
        body.velocity = [0, velocityY, 0]
        body.colliders = AircraftColliderSpec.spec(for: .f22_cgtrader)
        let rig = GearRig(body: body, struts: AircraftLandingGearSpec.spec(for: .f22_cgtrader))
        let plane = PlaneRigidBody(detachedAt: .zero)
        plane.isStatic = true
        let world = PhysicsWorld(entities: [body, plane], updateType: .HeckerVerlet)
        world.useBroadPhase = false
        return (world, body, rig)
    }

    @Test("the F-22 settles on its struts at ride height, gravity on, fuselage clear")
    func settlesOnStruts() {
        let (world, body, rig) = makeF22OnGear(startY: 2.5)
        var airframeTouched = false
        body.onContact = { _, _ in airframeTouched = true }

        for _ in 0..<600 { world.update(deltaTime: Self.dt) }   // 10 s

        #expect(body.shouldApplyGravity)
        #expect(rig.suspension.weightOnWheels)
        #expect(abs(body.getPosition().y - 1.93) <= 0.02,
                "Σk·x = W gives x ≈ 0.119, ride height = 2.05 − x ≈ 1.93")
        #expect(abs(rig.suspension.compressions[0] - 0.119) <= 0.01,
                "equal-reach struts share the static compression")
        #expect(simd_length(body.velocity) <= 0.05)
        #expect(!airframeTouched,
                "on its wheels the fuselage capsule (bottom −1.05) stays about 0.88 m clear")
    }

    @Test("gear up: the same body falls through the struts to the Phase A belly rest")
    func gearUpFallsToBelly() {
        let (world, body, rig) = makeF22OnGear(startY: 2.5)
        rig.gearDeployed = false
        var contactNames: Set<String> = []
        body.onContact = { contact, _ in
            if let name = contact.colliderNameA { contactNames.insert(name) }
        }

        for _ in 0..<600 { world.update(deltaTime: Self.dt) }

        #expect(abs(body.getPosition().y - 1.05) <= 0.05,
                "CompoundBodyTests' settle, with the suspension present but retracted")
        #expect(contactNames == ["fuselage"])
        #expect(!rig.suspension.weightOnWheels)
    }

    @Test("touchdown reports the incoming sink; a firm arrival overloads, a gentle one does not")
    func touchdownAndOverloadEvents() {
        // Start 1 cm above strut contact so the commanded velocity IS the
        // arrival velocity, one substep of gravity (0.08 m/s) aside. From
        // higher up the free fall before contact adds to it: 2.2 m arrives at
        // 4.4 m/s, not 4.
        let start = Self.strutContactHeight + 0.01

        // 4 m/s sink: the mains' damper alone gives 146 kN·s/m · 4 ≈ 584 kN,
        // past the 400 kN clamp, so the overload event fires on the rising edge.
        let firm = makeF22OnGear(startY: start, velocityY: -4)
        var firstSink: Float? = nil
        var overloadedStruts: Set<String> = []
        firm.rig.suspension.onLandingGearEvent = { event in
            switch event {
                case .touchdown(let sinkRate, _):
                    if firstSink == nil { firstSink = sinkRate }
                case .gearOverload(let strutName, _, _):
                    overloadedStruts.insert(strutName)
                case .liftoff:
                    break
            }
        }
        for _ in 0..<300 { firm.world.update(deltaTime: Self.dt) }
        #expect(firstSink != nil && abs(firstSink! - 4.0) <= 0.15)
        #expect(overloadedStruts.contains("mainGearLeft") && overloadedStruts.contains("mainGearRight"))

        // 0.5 m/s: damper under 110 kN and the spring peaks well under the clamp.
        let gentle = makeF22OnGear(startY: start, velocityY: -0.5)
        var gentleOverloads = 0
        gentle.rig.suspension.onLandingGearEvent = { if case .gearOverload = $0 { gentleOverloads += 1 } }
        for _ in 0..<300 { gentle.world.update(deltaTime: Self.dt) }
        #expect(gentleOverloads == 0)
        #expect(gentle.rig.suspension.weightOnWheels)
    }

    @Test("a body pushed upward leaves cleanly: struts push, never pull")
    func strutsNeverPull() {
        let (world, body, rig) = makeF22OnGear(startY: 2.5)
        for _ in 0..<600 { world.update(deltaTime: Self.dt) }   // settle first
        var sawLiftoff = false
        rig.suspension.onLandingGearEvent = { if case .liftoff = $0 { sawLiftoff = true } }

        body.velocity = [0, 4, 0]
        var maxY: Float = 0
        for _ in 0..<240 {
            world.update(deltaTime: Self.dt)
            maxY = max(maxY, body.getPosition().y)
        }

        #expect(sawLiftoff)
        // Ballistic apex from 4 m/s is about 0.82 m above launch; rebound
        // damping acts only across the first ~0.12 m of strut extension. A
        // strut that pulled would remove most of the apex.
        #expect(maxY - 1.93 >= 0.5)
    }
}
