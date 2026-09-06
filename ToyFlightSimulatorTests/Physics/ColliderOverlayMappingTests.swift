//
//  ColliderOverlayMappingTests.swift
//  ToyFlightSimulatorTests
//
//  Step 0.8: ColliderOverlayMapping is the pure, Metal-free half of the X-key
//  overlay (the overlay class itself constructs GameObjects → not unit-
//  testable per the project's Metal-free rule). These pin the shape → debug-
//  mesh mapping and the 0.5 units log arithmetic.
//

import Testing
import simd
@testable import ToyFlightSimulator

@Suite("ColliderOverlayMapping", .tags(.physics))
struct ColliderOverlayMappingTests {

    // MARK: - childScale

    @Test("sphere child scale = radius (unit OBJ sphere, radius exactly 1)")
    func sphereChildScale() {
        #expect(approxEqual(ColliderOverlayMapping.childScale(for: .sphere(radius: 2)),
                            [2, 2, 2]))
    }

    @Test("box child scale = full extents (unit cube, side 1) — non-uniform allowed")
    func boxChildScale() {
        #expect(approxEqual(ColliderOverlayMapping.childScale(for: .box(halfExtents: [1, 0.5, 3])),
                            [2, 1, 6]))
    }

    @Test("capsule child scale = 1 (bespoke mesh at exact dimensions, never scaled)")
    func capsuleChildScale() {
        #expect(approxEqual(ColliderOverlayMapping.childScale(for: .capsule(radius: 1.35, halfHeight: 8.1)),
                            .one))
    }

    // MARK: - capsuleMeshParams (the measured MDLMesh mapping)

    @Test("capsule mesh params: radius passes through, length = 2·(halfHeight + radius)")
    func capsuleMeshParams() {
        let p = ColliderOverlayMapping.capsuleMeshParams(radius: 1.35, halfHeight: 8.1)
        #expect(approxEqual(p.radius, 1.35))
        #expect(approxEqual(p.length, 18.9))

        // halfHeight 0 degenerates to a sphere of diameter 2r.
        let sphereLike = ColliderOverlayMapping.capsuleMeshParams(radius: 1, halfHeight: 0)
        #expect(approxEqual(sphereLike.length, 2))
    }

    // MARK: - worldDimensions (the 0.5 units log)

    @Test("worldDimensions: fuselage capsule reads the 18.9 m sanity anchor at scale 1")
    func worldDimensionsCapsuleAnchor() {
        let fuselage = LocalCollider(name: "fuselage",
                                     shape: .capsule(radius: 1.35, halfHeight: 8.1))
        let (dims, longest) = ColliderOverlayMapping.worldDimensions(of: fuselage, parentScale: 1)
        #expect(approxEqual(longest, 18.9))
        #expect(dims == "capsule ø 2.70 m × 18.90 m end-to-end")
    }

    @Test("worldDimensions: box reports full extents, longest axis wins")
    func worldDimensionsBox() {
        let wings = LocalCollider(name: "wings",
                                  shape: .box(halfExtents: [6.6, 0.18, 2.7]))
        let (dims, longest) = ColliderOverlayMapping.worldDimensions(of: wings, parentScale: 1)
        #expect(approxEqual(longest, 13.2))
        #expect(dims == "box 13.20 m × 0.36 m × 5.40 m")
    }

    @Test("worldDimensions: sphere reports diameter")
    func worldDimensionsSphere() {
        let ball = LocalCollider(name: "ball", shape: .sphere(radius: 2))
        let (dims, longest) = ColliderOverlayMapping.worldDimensions(of: ball, parentScale: 1)
        #expect(approxEqual(longest, 4))
        #expect(dims == "sphere ø 4.00 m")
    }

    @Test("worldDimensions: parent scale multiplies every reported size")
    func worldDimensionsHonorParentScale() {
        let fuselage = LocalCollider(name: "fuselage",
                                     shape: .capsule(radius: 1.35, halfHeight: 8.1))
        let (dims, longest) = ColliderOverlayMapping.worldDimensions(of: fuselage, parentScale: 2)
        #expect(approxEqual(longest, 37.8))
        #expect(dims == "capsule ø 5.40 m × 37.80 m end-to-end")
    }

    // MARK: - strutLineEndpoints (B.5: the cyan gear lines)

    @Test("strut line runs from the attach point down body −Y by the strut's reach")
    func strutLineEndpoints() {
        let strut = SuspensionStrut(name: "test",
                                    attachLocal: [1, -0.5, 2],
                                    restLength: 1.0,
                                    maxTravel: 0.4,
                                    wheelRadius: 0.25,
                                    springRate: 1,
                                    compressionDamping: 1,
                                    reboundDamping: 1,
                                    maxSupportForce: 1)
        let (start, end) = ColliderOverlayMapping.strutLineEndpoints(for: strut)
        #expect(approxEqual(start, float3(1, -0.5, 2)))
        #expect(approxEqual(end, float3(1, -1.75, 2)))     // reach = 1.0 + 0.25
        // The lower end sits reachBelowOrigin under the body origin — the
        // number the units log prints and the modeled wheel should touch.
        #expect(approxEqual(end.y, -strut.reachBelowOrigin))
    }

    @Test("F-22 strut lines all end 2.05 m below the origin, straight under their attach points")
    func f22StrutLinesShareTheReach() {
        let struts = AircraftLandingGearSpec.spec(for: .f22_cgtrader)
        #expect(struts.count == 3)
        for strut in struts {
            let (start, end) = ColliderOverlayMapping.strutLineEndpoints(for: strut)
            #expect(approxEqual(start, strut.attachLocal))
            #expect(approxEqual(end.y, -2.05))
            #expect(approxEqual(end.x, start.x) && approxEqual(end.z, start.z))
        }
    }
}
