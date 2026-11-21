//
//  TravelDistanceLimitTests.swift
//  ToyFlightSimulatorTests
//
//  Missile and Droppable reap themselves on the distance they have traveled, which
//  TravelDistanceLimit counts. It is a plain struct, so these tests need no Metal; the
//  weapons themselves need a model and are not built here. Only their static limits (the
//  AircraftStore default) are read, which does not construct a weapon.
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
        // multiple of 0.5 well below 2^53, so the Double total is exact.
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
        // 0.5 m is exact in Float and Double, and every partial sum is a multiple of 0.5 below
        // 2^53, so the Double total is exact and the count is exactly limit / 0.5 (200,000).
        let maxDistance = Missile.MAX_DISTANCE_BEFORE_REAP
        let expectedTicks = Int((maxDistance / 0.5).rounded(.up))
        var limit = TravelDistanceLimit(maxDistance: maxDistance)
        for _ in 0..<(expectedTicks - 1) { limit.move(by: [0, 0, 0.5]) }
        #expect(!limit.reachedLimit)
        limit.move(by: [0, 0, 0.5])
        #expect(limit.reachedLimit)
    }

    @Test("a dropped store reaches its limit on the exact tick")
    func droppedStoreReachesItsLimitOnTheExactTick() {
        // Droppable's step: gravity / 60 down (the fall speed stays at that value) and the
        // GBU-16's forward 0.02 m per tick, |step| = 0.1647 m. Its length is not a whole
        // number of Double gaps, so each sum rounds, by at most half a gap (7.3e-12 m at
        // 100 km): under 4.5e-6 m over all 607,096 steps. The exact ratio is 607,095.6, so
        // the limit lies 0.4 of a step (0.065 m) from the nearest tick boundary, far more
        // than that error. The old Float total took 609,051 ticks (+0.32%).
        let dropStep = float3(0, -PhysicsWorld.standardGravity / 60, -0.02)
        let maxDistance = Droppable.MAX_DISTANCE_BEFORE_REAP
        // Same Float length move(by:) adds, widened to Double.
        let exactTicks = Int((maxDistance / Double(dropStep.magnitude)).rounded(.up))

        var limit = TravelDistanceLimit(maxDistance: maxDistance)
        var ticks = 0
        while !limit.reachedLimit && ticks < 2 * exactTicks {
            limit.move(by: dropStep)
            ticks += 1
        }
        #expect(limit.reachedLimit)
        #expect(ticks == exactTicks)
    }

    @Test("1.95 mm steps still count past 65,536 m, where a Float total stopped")
    func smallStepsStillCountPastWhereAFloatTotalStopped() {
        // 2^-9 m = 1.953125 mm is exact in Float and Double. A Float total at 65,536 m has a
        // gap of 7.8 mm, and 65,536 + 1.95 mm rounds back to 65,536, so the old Float total
        // stayed there and never reached this limit. Every Double sum here is exact: 512
        // steps add exactly 1 m.
        var limit = TravelDistanceLimit(maxDistance: 65_537)
        limit.move(by: [0, 0, 65_536])
        let smallStep: float3 = [0, 0, 0.001953125]
        for _ in 0..<511 { limit.move(by: smallStep) }
        #expect(limit.distanceTraveled == 65_536.998046875)
        #expect(!limit.reachedLimit)

        limit.move(by: smallStep)
        #expect(limit.distanceTraveled == 65_537)
        #expect(limit.reachedLimit)
    }
}
