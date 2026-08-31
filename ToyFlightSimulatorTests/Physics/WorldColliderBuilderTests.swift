//
//  WorldColliderBuilderTests.swift
//  ToyFlightSimulatorTests
//
//  A.8 (A-routing track): the pure LocalCollider × body-pose → WorldCollider
//  transform, pinned against hand-computed poses. Metal-free by construction —
//  WorldColliderBuilder takes plain values, no Node/GameObject involved.
//

import Foundation
import Testing
import simd
@testable import ToyFlightSimulator

@Suite("WorldColliderBuilder", .tags(.physics))
struct WorldColliderBuilderTests {

    private func rotation(_ angle: Float, about axis: float3) -> float3x3 {
        float3x3(simd_quatf(angle: angle, axis: axis))
    }

    @Test("offset × rotation × scale compose in that order (rotate the scaled local offset)")
    func poseComposition() throws {
        // Body at [10,0,0], rotated 90° about Z (x̂→ŷ), scale 2. A collider
        // 1 m down local +X must land 2 m up world +Y from the body:
        // position = body + R·(localPosition · s) = [10,0,0] + R_z90·[2,0,0].
        let colliders = [LocalCollider(name: "probe",
                                       shape: .sphere(radius: 1),
                                       localPosition: [1, 0, 0])]
        var out: [WorldCollider] = []
        WorldColliderBuilder.build(colliders,
                                   bodyPosition: [10, 0, 0],
                                   bodyRotation: rotation(.halfPi, about: Z_AXIS),
                                   uniformScale: 2.0,
                                   into: &out)

        try #require(out.count == 1)
        #expect(approxEqual(out[0].position, [10, 2, 0]))
        #expect(out[0].shape == .sphere(radius: 2))          // dimensions × scale
        #expect(approxEqual(out[0].rotation, rotation(.halfPi, about: Z_AXIS)))
        #expect(out[0].sourceIndex == 0)
        #expect(out[0].name == "probe")
        #expect(out[0].group == .airframe)                    // LocalCollider default
    }

    @Test("the fuselage Y→Z local rotation points the world capsule axis along +Z")
    func fuselageCapsuleAxisMapsYToZ() throws {
        // The F-22 spec's fuselage trick: .capsule is defined along local Y,
        // rotated π/2 about X so it runs nose–tail. The world capsule axis is
        // rotation.columns.1 (the world image of local Y) — must be ≈ +Z.
        let colliders = [LocalCollider(name: "fuselage",
                                       shape: .capsule(radius: 1, halfHeight: 2),
                                       localRotation: simd_quatf(angle: .halfPi, axis: X_AXIS))]
        var out: [WorldCollider] = []
        WorldColliderBuilder.build(colliders,
                                   bodyPosition: .zero,
                                   bodyRotation: matrix_identity_float3x3,
                                   uniformScale: 1.0,
                                   into: &out)

        try #require(out.count == 1)
        #expect(approxEqual(out[0].rotation.columns.1, [0, 0, 1]))
    }

    @Test("disabled colliders are omitted; survivors keep their ORIGINAL source indices")
    func disabledChildOmission() {
        let colliders = [
            LocalCollider(name: "a", shape: .sphere(radius: 1)),
            LocalCollider(name: "b", shape: .sphere(radius: 1), isEnabled: false),
            LocalCollider(name: "c", shape: .sphere(radius: 1)),
        ]
        var out: [WorldCollider] = []
        WorldColliderBuilder.build(colliders,
                                   bodyPosition: .zero,
                                   bodyRotation: matrix_identity_float3x3,
                                   uniformScale: 1.0,
                                   into: &out)

        #expect(out.map(\.name) == ["a", "c"])
        // sourceIndex must index into the AUTHORED list (identity for the
        // overlay/spec round trip), not the compacted output.
        #expect(out.map(\.sourceIndex) == [0, 2])
    }

    @Test("uniform scale flows into every shape's dimensions via scaled(by:)")
    func scaleFlowsIntoShapes() {
        let colliders = [
            LocalCollider(name: "cap", shape: .capsule(radius: 1, halfHeight: 2)),
            LocalCollider(name: "box", shape: .box(halfExtents: [1, 2, 3])),
        ]
        var out: [WorldCollider] = []
        WorldColliderBuilder.build(colliders,
                                   bodyPosition: .zero,
                                   bodyRotation: matrix_identity_float3x3,
                                   uniformScale: 3.0,
                                   into: &out)

        #expect(out[0].shape == .capsule(radius: 3, halfHeight: 6))
        #expect(out[1].shape == .box(halfExtents: [3, 6, 9]))
    }

    @Test("rotated capsule AABB: segment reach per world axis + radius inflation")
    func rotatedCapsuleAABB() {
        // Capsule r 0.5, hh 2, axis rotated Y→Z, centered at [1,2,3]:
        // endpoints at [1,2,1] and [1,2,5], so bounds are ±0.5 around the
        // segment in X/Y and ±2.5 in Z.
        let c = WorldCollider(shape: .capsule(radius: 0.5, halfHeight: 2),
                              position: [1, 2, 3],
                              rotation: rotation(.halfPi, about: X_AXIS),
                              sourceIndex: nil, name: nil, group: nil)
        #expect(approxEqual(c.aabb.min, [0.5, 1.5, 0.5]))
        #expect(approxEqual(c.aabb.max, [1.5, 2.5, 5.5]))
    }

    @Test("rotated box AABB: |R|·he world extents")
    func rotatedBoxAABB() {
        // he [1,2,3] rotated 90° about Z: local X (reach 1) now spans world Y,
        // local Y (reach 2) spans world X, Z unchanged → extents [2,1,3].
        let c = WorldCollider(shape: .box(halfExtents: [1, 2, 3]),
                              position: .zero,
                              rotation: rotation(.halfPi, about: Z_AXIS),
                              sourceIndex: nil, name: nil, group: nil)
        #expect(approxEqual(c.aabb.min, [-2, -1, -3]))
        #expect(approxEqual(c.aabb.max, [2, 1, 3]))
    }

    @Test("empty collider list produces empty output and clears stale scratch")
    func emptyListClearsScratch() {
        var out = [WorldCollider(shape: .sphere(radius: 1),
                                 position: .zero,
                                 rotation: matrix_identity_float3x3,
                                 sourceIndex: nil, name: "stale", group: nil)]
        WorldColliderBuilder.build([],
                                   bodyPosition: .zero,
                                   bodyRotation: matrix_identity_float3x3,
                                   uniformScale: 1.0,
                                   into: &out)
        #expect(out.isEmpty)
    }
}
