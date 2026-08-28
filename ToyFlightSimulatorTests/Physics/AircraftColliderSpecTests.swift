//
//  AircraftColliderSpecTests.swift
//  ToyFlightSimulatorTests
//
//  Step 0.8: pins the authored F-22 CGTrader compound spec — including the
//  0.5 units sanity anchor (fuselage nose→tail ≈ 18.9 m at scale 1.0) — so
//  the numbers the overlay visualizes and Phase A will consume can't rot.
//

import Testing
@testable import ToyFlightSimulator

@Suite("AircraftColliderSpec", .tags(.physics))
struct AircraftColliderSpecTests {

    @Test("f22_cgtrader: 3 enabled airframe colliders with unique expected names")
    func f22CGTraderSpecShape() {
        let spec = AircraftColliderSpec.spec(for: .f22_cgtrader)
        #expect(spec.count == 3)
        #expect(spec.map(\.name) == ["fuselage", "wings", "empennage"])
        #expect(Set(spec.map(\.name)).count == spec.count, "collider names must be unique")
        #expect(spec.allSatisfy { $0.isEnabled })
        #expect(spec.allSatisfy { $0.group == .airframe })
    }

    @Test("f22_cgtrader: every dimension finite and positive")
    func f22CGTraderDimensionsValid() {
        for collider in AircraftColliderSpec.spec(for: .f22_cgtrader) {
            #expect(collider.shape.hasFinitePositiveDimensions,
                    "collider '\(collider.name)' has invalid dimensions")
        }
    }

    @Test("sanity anchor: fuselage capsule spans 2·(8.1+1.35) = 18.9 m at scale 1.0")
    func fuselageSanityAnchor() throws {
        let spec = AircraftColliderSpec.spec(for: .f22_cgtrader)
        let fuselage = try #require(spec.first { $0.name == "fuselage" })

        guard case .capsule(let radius, let halfHeight) = fuselage.shape else {
            Issue.record("fuselage should be a capsule, got \(fuselage.shape)")
            return
        }
        // Real F-22: 18.92 m nose→tail. The capsule's cap-to-cap span is
        // 2·(halfHeight + radius) — the same formula the overlay's mesh
        // mapping and units log use.
        #expect(approxEqual(2 * (halfHeight + radius), 18.9))
    }

    @Test("unauthored aircraft types return an empty spec")
    func unauthoredTypesReturnEmpty() {
        // The switch is exhaustive with no `default` (compile-enforced);
        // this documents the current authored-or-empty decisions.
        for type in AircraftType.allCases where type != .f22_cgtrader {
            #expect(AircraftColliderSpec.spec(for: type).isEmpty,
                    "\(type) has no authored spec yet")
        }
    }
}
