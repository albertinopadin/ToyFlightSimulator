//
//  TravelDistanceLimitTests.swift
//  ToyFlightSimulatorTests
//
//  Missile and Droppable reap themselves on the distance they have traveled, which
//  TravelDistanceLimit counts. It is a plain struct, so these tests need no Metal; the
//  weapons themselves need a model and are not built here. Only their static limits are
//  read, which does not construct a weapon.
//

import Testing
import simd
@testable import ToyFlightSimulator

@Suite("TravelDistanceLimit", .tags(.gameObjects))
struct TravelDistanceLimitTests {

    @Test("a new limit has traveled nothing and is not reached")
    func newLimitIsNotReached() {
        let limit = TravelDistanceLimit(maxDistance: 1_000)
        #expect(limit.distanceTraveled == 0)
        #expect(!limit.reachedLimit)
    }

    @Test("1,999 steps of 0.5 m stay under 1,000 m; the 2,000th reaches it")
    func reachedExactlyAtTheLimit() {
        // 0.5 m per tick is the speed the F-18 gives its missiles. Every partial sum is a
        // multiple of 0.5 well below 2^23, so the Float total is exact.
        var limit = TravelDistanceLimit(maxDistance: 1_000)
        for _ in 0..<1_999 { limit.move(by: [0, 0, 0.5]) }
        #expect(limit.distanceTraveled == 999.5)
        #expect(!limit.reachedLimit)

        limit.move(by: [0, 0, 0.5])
        #expect(limit.distanceTraveled == 1_000)
        #expect(limit.reachedLimit)
    }

    @Test("a step counts its length, whatever its direction")
    func stepCountsItsLength() {
        // 3-4-5 triangles, so every length is exact. Opposite directions add, not cancel:
        // the count is distance traveled, not displacement.
        var limit = TravelDistanceLimit(maxDistance: 1_000)
        limit.move(by: [3, 0, 4])
        #expect(limit.distanceTraveled == 5)
        limit.move(by: [-3, 0, -4])
        #expect(limit.distanceTraveled == 10)
        limit.move(by: [0, -3, 4])
        #expect(limit.distanceTraveled == 15)
    }

    @Test("a missile at the F-18's release speed reaches its limit after limit / 0.5 ticks")
    func missileReachesItsLimitOnTime() {
        // The Float total must not stall below Missile.MAX_DISTANCE_BEFORE_REAP: 0.5 m is a
        // whole number of Float gaps at every total up to 2^23 m, so each sum is exact.
        let maxDistance = Missile.MAX_DISTANCE_BEFORE_REAP
        let expectedTicks = Int((maxDistance / 0.5).rounded(.up))
        var limit = TravelDistanceLimit(maxDistance: maxDistance)
        for _ in 0..<(expectedTicks - 1) { limit.move(by: [0, 0, 0.5]) }
        #expect(!limit.reachedLimit)
        limit.move(by: [0, 0, 0.5])
        #expect(limit.reachedLimit)
    }

    @Test("a dropped store's Float total stays within 1% of the exact tick count")
    func droppedStoreReachesItsLimitWithinOnePercent() {
        // Droppable's step: gravity / 60 down (the fall speed stays at that value) and the
        // GBU-16's forward 0.02 m per tick, |step| = 0.1647 m. Its length is not a whole
        // number of Float gaps, so each sum rounds; the scratch run gave 609,051 ticks
        // against an exact 607,096 (+0.32%).
        let dropStep = float3(0, -PhysicsWorld.standardGravity / 60, -0.02)
        let maxDistance = Droppable.MAX_DISTANCE_BEFORE_REAP
        let exactTicks = (Double(maxDistance) / Double(simd_length(dropStep))).rounded(.up)

        var limit = TravelDistanceLimit(maxDistance: maxDistance)
        var ticks = 0
        while !limit.reachedLimit && Double(ticks) < 2 * exactTicks {
            limit.move(by: dropStep)
            ticks += 1
        }
        #expect(limit.reachedLimit)
        #expect(abs(Double(ticks) - exactTicks) / exactTicks < 0.01)
    }
}
