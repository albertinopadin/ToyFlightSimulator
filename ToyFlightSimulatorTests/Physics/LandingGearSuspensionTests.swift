//
//  LandingGearSuspensionTests.swift
//  ToyFlightSimulatorTests
//
//  B.4 (B-suspension): the per-aircraft suspension state machine and the
//  world query it raycasts through, at the unit level — the deploy gate, the
//  event edges, and the body-axis ray. Metal-free: detached bodies, a posed
//  test double for rotation, and real PhysicsWorlds that are only queried,
//  never stepped (the stepped end-to-end settle is B.5's
//  GearSuspensionWorldTests).
//

import Foundation
import Testing
import simd
@testable import ToyFlightSimulator

/// Detached body with a settable pose. RigidBody.pose() gives detached bodies
/// the identity rotation, so tilting the strut axis needs the override.
private final class PosedTestRigidBody: RigidBody {
    var rotation: float3x3 = matrix_identity_float3x3
    var uniformScale: Float = 1

    init(position: float3) {
        super.init(gameObject: nil, standalonePosition: position)
    }

    override func pose() -> (position: float3, rotation: float3x3, uniformScale: Float) {
        (getPosition(), rotation, uniformScale)
    }
}

@Suite("LandingGearSuspension", .tags(.physics))
struct LandingGearSuspensionTests {

    /// Substep for the hand math (rate = Δx·10); the class takes whatever the
    /// world passes.
    private static let h: Float = 0.1

    /// One strut at the body origin: reach 1 m (rest 1, no wheel), travel
    /// 0.5 m, k 100 N/m, c 10 / 20 N·s/m, clamp 1 kN.
    private static let softStrut = SuspensionStrut(name: "single",
                                                   attachLocal: .zero,
                                                   restLength: 1,
                                                   maxTravel: 0.5,
                                                   wheelRadius: 0,
                                                   springRate: 100,
                                                   compressionDamping: 10,
                                                   reboundDamping: 20,
                                                   maxSupportForce: 1_000)

    /// A static ground plane at y = 0 in a world used only for raycasts.
    private func groundWorld() -> PhysicsWorld {
        let ground = PlaneRigidBody(detachedAt: .zero)
        ground.isStatic = true
        return PhysicsWorld(entities: [ground])
    }

    // MARK: - Contact, force direction, and the touchdown edge

    @Test("a level body compresses, pushes up along +Y, and reports touchdown once with the incoming sink and every strut's compression")
    func touchdownPushesUpAndFiresOnce() {
        // "single" at the origin and "high" 0.0625 m above it: at body height
        // 0.875 they compress 0.125 and 0.0625. First contact from rest is
        // this substep's whole penetration as rate (1.25 and 0.625 m/s):
        // F = 12.5 + 12.5 and 6.25 + 6.25 → 37.5 N along +Y.
        var high = Self.softStrut
        high.name = "high"
        high.attachLocal = [0, 0.0625, 0]
        let body = PosedTestRigidBody(position: [0, 0.875, 0])
        body.velocity = [0, -2, 0]
        let suspension = LandingGearSuspension(struts: [Self.softStrut, high])
        var events: [LandingGearEvent] = []
        suspension.onLandingGearEvent = { events.append($0) }
        let world = groundWorld()

        suspension.accumulateForces(body: body, gearDeployed: true, world: world, substepDelta: Self.h)

        #expect(approxEqual(body.force, [0, 37.5, 0]))
        #expect(suspension.compressions == [0.125, 0.0625])
        #expect(suspension.weightOnWheels)
        #expect(events.count == 1)
        if case .touchdown(let sinkRate, let compressions)? = events.first {
            #expect(sinkRate == 2, "the incoming velocity, before the strut forces act")
            #expect(compressions == [0.125, 0.0625],
                    "fired after ALL struts updated: the second strut's compression is already in")
        } else {
            Issue.record("expected a touchdown event, got \(events)")
        }

        // Same pose again: rate 0, spring only (12.5 + 6.25); still on wheels,
        // no new transition event.
        body.force = .zero
        suspension.accumulateForces(body: body, gearDeployed: true, world: world, substepDelta: Self.h)
        #expect(approxEqual(body.force, [0, 18.75, 0]))
        #expect(events.count == 1)
    }

    @Test("the strut ray follows the body's up axis: a rolled body measures the slant distance and pushes along its own up")
    func rayAndForceFollowBodyUp() {
        // 60° roll about Z: up = R·ŷ with up.y = cos 60° = 0.5. Attach at
        // height 0.375 → slant distance to the ground 0.375 / 0.5 = 0.75 →
        // compression 0.25 → F = 100·0.25 + 10·2.5 = 50 N along up.
        let body = PosedTestRigidBody(position: [0, 0.375, 0])
        body.rotation = float3x3(simd_quatf(angle: .pi / 3, axis: Z_AXIS))
        let up = body.rotation.up
        #expect(approxEqual(up.y, 0.5))
        #expect(approxEqual(up, body.rotation * Y_AXIS))

        let suspension = LandingGearSuspension(struts: [Self.softStrut])
        suspension.accumulateForces(body: body, gearDeployed: true, world: groundWorld(), substepDelta: Self.h)

        #expect(approxEqual(suspension.compressions[0], 0.25))
        #expect(approxEqual(body.force, up * 50))
        #expect(!approxEqual(body.force, [0, 50, 0]), "not world up")
    }

    @Test("an inverted or knife-edge body's struts hit nothing: back-facing or parallel rays")
    func invertedBodyHasNoContact() {
        let suspension = LandingGearSuspension(struts: [Self.softStrut])
        var events = 0
        suspension.onLandingGearEvent = { _ in events += 1 }
        let world = groundWorld()

        // Level, this height would compress the strut by 0.5 m.
        let body = PosedTestRigidBody(position: [0, 0.5, 0])
        body.rotation = float3x3(simd_quatf(angle: .pi, axis: Z_AXIS))   // up = −ŷ: the ray goes up
        suspension.accumulateForces(body: body, gearDeployed: true, world: world, substepDelta: Self.h)
        #expect(body.force == .zero)
        #expect(suspension.compressions == [0])
        #expect(!suspension.weightOnWheels)

        body.rotation = float3x3(simd_quatf(angle: .halfPi, axis: Z_AXIS))   // up = ±x̂: the ray is parallel
        suspension.accumulateForces(body: body, gearDeployed: true, world: world, substepDelta: Self.h)
        #expect(body.force == .zero)
        #expect(!suspension.weightOnWheels)
        #expect(events == 0)
    }

    // MARK: - The deploy gate

    @Test("gear up: no force, compressions zeroed, one liftoff if there was weight on wheels; redeploying starts from rest")
    func retractedGearResetsAndFiresLiftoff() {
        let body = PosedTestRigidBody(position: [0, 0.875, 0])   // 0.125 m below reach
        let suspension = LandingGearSuspension(struts: [Self.softStrut])
        let world = groundWorld()
        suspension.accumulateForces(body: body, gearDeployed: true, world: world, substepDelta: Self.h)
        #expect(suspension.weightOnWheels)
        #expect(approxEqual(body.force, [0, 25, 0]))   // 12.5 spring + 12.5 damper

        var events: [LandingGearEvent] = []
        suspension.onLandingGearEvent = { events.append($0) }
        body.force = .zero
        suspension.accumulateForces(body: body, gearDeployed: false, world: world, substepDelta: Self.h)
        #expect(body.force == .zero, "retracted gear produces no force even below reach")
        #expect(suspension.compressions == [0])
        #expect(!suspension.weightOnWheels)
        #expect(events.count == 1)
        if case .liftoff? = events.first {} else {
            Issue.record("expected liftoff, got \(events)")
        }

        // Staying retracted is quiet.
        suspension.accumulateForces(body: body, gearDeployed: false, world: world, substepDelta: Self.h)
        #expect(events.count == 1)

        // Redeploying: the finite differences restart from 0, so the first
        // substep back reads the whole 0.125 m as this substep's penetration
        // (the documented quirk) and it is a fresh touchdown.
        suspension.accumulateForces(body: body, gearDeployed: true, world: world, substepDelta: Self.h)
        #expect(approxEqual(body.force, [0, 25, 0]))
        #expect(events.count == 2)
        if case .touchdown? = events.last {} else {
            Issue.record("expected a touchdown on redeploy, got \(events)")
        }
    }

    // MARK: - Overload edges

    @Test("gear overload fires once per exceedance, per strut, on the clamp or on bottoming out")
    func overloadFiresOnRisingEdgePerStrut() {
        // Three struts side by side: "weak" clamps at 5 N (any contact
        // overloads it), "strong" never does, "stubby" bottoms out at 0.0625 m.
        var weak = Self.softStrut
        weak.name = "weak"
        weak.maxSupportForce = 5
        var strong = Self.softStrut
        strong.name = "strong"
        strong.attachLocal = [1, 0, 0]
        var stubby = Self.softStrut
        stubby.name = "stubby"
        stubby.attachLocal = [-1, 0, 0]
        stubby.maxTravel = 0.0625

        let body = PosedTestRigidBody(position: [0, 0.875, 0])
        let suspension = LandingGearSuspension(struts: [weak, strong, stubby])
        var overloads: [(name: String, force: Float, bottomedOut: Bool)] = []
        suspension.onLandingGearEvent = {
            if case .gearOverload(let name, let force, let bottomedOut) = $0 {
                overloads.append((name, force, bottomedOut))
            }
        }
        let world = groundWorld()

        // Press: weak 25 N unclamped → clamped 5, event; strong 25 N, fine;
        // stubby raw 0.125 → capped 0.0625, rate 0.625 → 12.5 N, bottomed, event.
        suspension.accumulateForces(body: body, gearDeployed: true, world: world, substepDelta: Self.h)
        #expect(overloads.map { $0.name } == ["weak", "stubby"])
        #expect(overloads.map { $0.bottomedOut } == [false, true])
        #expect(overloads.count == 2
                && approxEqual(overloads[0].force, 5)
                && approxEqual(overloads[1].force, 12.5), "the event carries the clamped force")
        #expect(approxEqual(body.force, [0, 5 + 25 + 12.5, 0]))

        // Held: both exceedances continue (weak's spring-only 12.5 N ≥ 5 N,
        // stubby still bottomed) — no new events.
        body.force = .zero
        suspension.accumulateForces(body: body, gearDeployed: true, world: world, substepDelta: Self.h)
        #expect(overloads.count == 2)

        // Lift to 0.03125 m compression: weak and stubby both rebound to a
        // floored 0 N and stubby is off its stop, so every exceedance ends.
        body.setPosition([0, 0.96875, 0])
        body.force = .zero
        suspension.accumulateForces(body: body, gearDeployed: true, world: world, substepDelta: Self.h)
        #expect(overloads.count == 2)
        #expect(suspension.weightOnWheels)

        // Press again: new exceedances, new events, same order.
        body.setPosition([0, 0.875, 0])
        body.force = .zero
        suspension.accumulateForces(body: body, gearDeployed: true, world: world, substepDelta: Self.h)
        #expect(overloads.map { $0.name } == ["weak", "stubby", "weak", "stubby"])
        #expect(overloads.map { $0.bottomedOut } == [false, true, false, true])
    }

    // MARK: - PhysicsWorld.raycastStaticPlanes, the query the struts use

    @Test("nearest static plane ahead of the ray wins; dynamic planes, non-planes, and planes behind are ignored")
    func raycastStaticPlanes() {
        let low = PlaneRigidBody(detachedAt: .zero)
        low.isStatic = true
        let high = PlaneRigidBody(detachedAt: [0, 1, 0])
        high.isStatic = true
        let moving = PlaneRigidBody(detachedAt: [0, 3, 0])                        // dynamic: not ground
        let ball = SphereRigidBody(detachedAt: [0, 4, 0], collisionRadius: 1)     // not a plane
        let world = PhysicsWorld(entities: [ball, moving, low, high])

        #expect(world.raycastStaticPlanes(from: [0, 5, 0], direction: [0, -1, 0]) == 4, "the y = 1 plane")
        #expect(world.raycastStaticPlanes(from: [0, 0.5, 0], direction: [0, -1, 0]) == 0.5,
                "between the planes only y = 0 is ahead and front-facing")
        #expect(world.raycastStaticPlanes(from: [0, 5, 0], direction: [0, 1, 0]) == nil, "away from every plane")
        #expect(PhysicsWorld(entities: [ball]).raycastStaticPlanes(from: [0, 5, 0], direction: [0, -1, 0]) == nil,
                "no planes at all")
    }
}
