//
//  AircraftLandingGearSpecTests.swift
//  ToyFlightSimulatorTests
//
//  B.4 (B-suspension): pins the authored F-22 CGTrader gear spec — names,
//  sane dimensions, the shared 2.05 m reach that makes a level jet touch all
//  three wheels together, and the static stance the in-app settle (B.5) must
//  reproduce. The numbers were accepted in-app unchanged on 2026-09-06
//  (Phase B criterion 3); retune these pins with the spec if it is ever tuned.
//

import Testing
import simd
@testable import ToyFlightSimulator

@Suite("AircraftLandingGearSpec", .tags(.physics))
struct AircraftLandingGearSpecTests {

    private static let f22 = AircraftLandingGearSpec.spec(for: .f22_cgtrader)

    @Test("f22_cgtrader: nose + two mains with unique names and finite positive dimensions")
    func f22CGTraderSpecShape() {
        let spec = Self.f22
        #expect(spec.map(\.name) == ["noseGear", "mainGearLeft", "mainGearRight"])
        #expect(Set(spec.map(\.name)).count == spec.count, "strut names must be unique")
        for strut in spec {
            #expect(allFinite(strut.attachLocal), "\(strut.name): attach point must be finite")
            let dimensions: [(String, Float)] = [("restLength", strut.restLength),
                                                 ("maxTravel", strut.maxTravel),
                                                 ("wheelRadius", strut.wheelRadius),
                                                 ("springRate", strut.springRate),
                                                 ("compressionDamping", strut.compressionDamping),
                                                 ("reboundDamping", strut.reboundDamping),
                                                 ("maxSupportForce", strut.maxSupportForce)]
            for (label, value) in dimensions {
                #expect(value.isFinite && value > 0, "\(strut.name).\(label) must be finite and positive")
            }
            #expect(strut.maxTravel < strut.restLength, "\(strut.name): travel within the strut")
        }
    }

    @Test("unauthored aircraft types return an empty spec")
    func unauthoredTypesReturnEmpty() {
        // The switch is exhaustive with no `default` (compile-enforced);
        // this documents the current authored-or-empty decisions.
        for type in AircraftType.allCases where type != .f22_cgtrader {
            #expect(AircraftLandingGearSpec.spec(for: type).isEmpty, "\(type) has no authored gear yet")
        }
    }

    @Test("all three struts share one reach below the origin, 2.05 m")
    func equalReachBelowOrigin() {
        for strut in Self.f22 {
            #expect(approxEqual(strut.reachBelowOrigin, 2.05), "\(strut.name) reachBelowOrigin")
        }
    }

    @Test("geometry anchors: 3.24 m track, 6.1 m wheelbase, mirrored mains")
    func geometryAnchors() throws {
        let nose = try #require(Self.f22.first { $0.name == "noseGear" })
        let left = try #require(Self.f22.first { $0.name == "mainGearLeft" })
        let right = try #require(Self.f22.first { $0.name == "mainGearRight" })
        #expect(approxEqual(right.attachLocal.x - left.attachLocal.x, 3.24))
        #expect(approxEqual(nose.attachLocal.z - left.attachLocal.z, 6.1))
        #expect(nose.attachLocal.x == 0, "nose gear on the centerline")
        #expect(approxEqual(left.attachLocal, right.attachLocal * float3(-1, 1, 1)))
        // The same leg on both sides.
        #expect(left.restLength == right.restLength)
        #expect(left.maxTravel == right.maxTravel)
        #expect(left.wheelRadius == right.wheelRadius)
        #expect(left.springRate == right.springRate)
        #expect(left.compressionDamping == right.compressionDamping)
        #expect(left.reboundDamping == right.reboundDamping)
        #expect(left.maxSupportForce == right.maxSupportForce)
    }

    @Test("static stance at 30 t: compression ≈ 0.119 m, ride height ≈ 1.93 m")
    func staticStanceAt30Tonnes() throws {
        let stance = try #require(AircraftLandingGearSpec.staticStance(struts: Self.f22, mass: 30_000))
        // x = m·g / Σk = 294 300 / 2 468 000; ride height = 2.05 − x.
        let totalRate = Self.f22.reduce(0) { $0 + $1.springRate }
        #expect(approxEqual(totalRate, 2_468_000))
        #expect(approxEqual(stance.compression, 30_000 * PhysicsWorld.standardGravity / totalRate))
        #expect(approxEqual(stance.compression, 0.119, tolerance: 0.001))
        #expect(approxEqual(stance.rideHeight, 2.05 - stance.compression))
        #expect(approxEqual(stance.rideHeight, 1.93, tolerance: 0.002))
    }

    @Test("static stance edges: nil for an empty or rate-less spec; the default gravity is the world's")
    func staticStanceEdges() {
        #expect(AircraftLandingGearSpec.staticStance(struts: [], mass: 30_000) == nil)
        var limp = Self.f22[0]
        limp.springRate = 0
        #expect(AircraftLandingGearSpec.staticStance(struts: [limp], mass: 1) == nil)

        let implicit = AircraftLandingGearSpec.staticStance(struts: Self.f22, mass: 30_000)
        let explicit = AircraftLandingGearSpec.staticStance(struts: Self.f22, mass: 30_000,
                                                            gravity: -PhysicsWorld.gravity.y)
        #expect(implicit?.compression == explicit?.compression)
        #expect(implicit?.rideHeight == explicit?.rideHeight)
    }
}
