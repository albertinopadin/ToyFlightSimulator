//
//  WeaponTravelLimitTests.swift
//  ToyFlightSimulatorTests
//
//  Missile and Droppable count the step they apply each update with travelLimit.move(by:)
//  and remove themselves once the count reaches their limit. These tests build real
//  weapons and run their doUpdate, so a missing or wrong call fails here.
//  TravelDistanceLimitTests covers the counter itself.
//
//  App-hosted: a weapon's init reaches Assets.Models and Assets.SingleSMMeshes, which cut
//  the store's submesh out of the FA-18F model and need the Metal device. Nothing here
//  touches Engine.renderer, so the host-app launch race does not apply. Each test builds a
//  different weapon type, because a weapon's init writes into the cached vertex buffer of
//  its submesh, which every weapon of that type shares; the suite is also serialized.
//
//  The tests call doUpdate(), not update(): the scene traversal calls doUpdate first, and
//  update() would also run model.update() on the shared model.
//

import Testing
import simd
@testable import ToyFlightSimulator

@Suite("Weapons count the steps they move", .tags(.gameObjects), .serialized)
struct WeaponTravelLimitTests {

    @Test("a missile counts every step it flies")
    func missileCountsEveryStep() {
        // The F-18 fires with a unit direction and 0.5 m per update. Without fire() the
        // speed is 0 and every count below would be trivially 0.
        let missile = Sidewinder()
        missile.fire(direction: [0.6, 0, 0.8], speed: 0.5)
        let step = missile.direction * missile.speed
        let startPosition = missile.getPosition()

        // The same Float step through the same counter gives the same Double sum, exactly.
        var expected = TravelDistanceLimit(maxDistance: Missile.MAX_DISTANCE_BEFORE_REAP)
        let updateCount = 100
        for _ in 0..<updateCount {
            missile.doUpdate()
            expected.move(by: step)
        }

        #expect(missile.travelLimit.distanceTraveled == expected.distanceTraveled)
        #expect(abs(missile.travelLimit.distanceTraveled - 50) < 1e-4)  // 100 × 0.5 m
        #expect(!missile.travelLimit.reachedLimit)
        // Position sums round in Float (about 2e-6 m per update below 64 m), so allow 1 mm.
        #expect(approxEqual(missile.getPosition(), startPosition + Float(updateCount) * step,
                            tolerance: 1e-3))
    }

    @Test("a missile 50 km from the origin still flies and counts")
    func missileFarFromTheOriginKeepsFlying() {
        // A stored position is relative to the floating origin, so it can be anywhere.
        // Under the old rule (reap once any coordinate passed 1,000 m) this missile was
        // removed on its first update without moving.
        let sceneStandIn = Node(name: "scene stand-in")
        let missile = AIM120()
        sceneStandIn.addChild(missile)
        let startPosition: float3 = [-30_000, 500, 40_000]
        missile.setPosition(startPosition)
        missile.fire(direction: [0, 0, 1], speed: 0.5)

        missile.doUpdate()

        #expect(missile.parent === sceneStandIn)
        #expect(missile.travelLimit.distanceTraveled == 0.5)
        // The Float gap at 40,000 m is 3.9 mm, so the new z rounds by up to 2 mm.
        #expect(approxEqual(missile.getPosition(), startPosition + [0, 0, 0.5], tolerance: 0.01))
    }

    @Test("a dropped store counts every step it falls")
    func droppedStoreCountsEveryStep() {
        // The F-18 drops a GBU-16 with 0.02 m per update forward. The fall speed is
        // gravity / 60 per update from the first update on, so every step is the same.
        let bomb = GBU16()
        bomb.drop(forwardComponent: 0.02)
        let startPosition = bomb.getPosition()

        var expected = TravelDistanceLimit(maxDistance: Droppable.MAX_DISTANCE_BEFORE_REAP)
        let updateCount = 100
        for _ in 0..<updateCount {
            bomb.doUpdate()
            // velocityVector is the step doUpdate just applied.
            expected.move(by: bomb.velocityVector)
        }

        let step = float3(0, -PhysicsWorld.standardGravity / 60, -0.02)
        #expect(bomb.velocityVector == step)
        #expect(bomb.travelLimit.distanceTraveled == expected.distanceTraveled)
        // 100 × |step| = 100 × 0.164719 m
        #expect(abs(bomb.travelLimit.distanceTraveled - 16.4719) < 1e-3)
        #expect(approxEqual(bomb.getPosition(), startPosition + Float(updateCount) * step,
                            tolerance: 1e-3))
    }

    @Test("a store removes itself on the update after its count reaches the limit")
    func storeRemovesItselfAtItsLimit() {
        // A short limit stands in for the 100 km one. The fuel tank falls 0.1635 m per
        // update, so the count is 0.1635 after one update and 0.327 (past 0.3) after two.
        let sceneStandIn = Node(name: "scene stand-in")
        let tank = FuelTank()
        sceneStandIn.addChild(tank)
        tank.travelLimit = TravelDistanceLimit(maxDistance: 0.3)
        tank.drop(forwardComponent: 0)

        tank.doUpdate()
        #expect(!tank.travelLimit.reachedLimit)
        tank.doUpdate()
        #expect(tank.travelLimit.reachedLimit)
        #expect(tank.parent === sceneStandIn)  // checked at the start of the next update

        let positionAtLimit = tank.getPosition()
        let distanceAtLimit = tank.travelLimit.distanceTraveled
        tank.doUpdate()

        #expect(tank.parent == nil)
        #expect(!sceneStandIn.children.contains { $0 === tank })
        #expect(tank.getPosition() == positionAtLimit)
        #expect(tank.travelLimit.distanceTraveled == distanceAtLimit)
    }
}
