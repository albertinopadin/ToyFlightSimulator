//
//  ColliderShapeTests.swift
//  ToyFlightSimulatorTests
//
//  Step 0.8: the collider vocabulary (0.1) is data-only and Metal-free —
//  these pin scaled(by:), the dimension validator, and LocalCollider defaults.
//

import Testing
import simd
@testable import ToyFlightSimulator

@Suite("ColliderShape vocabulary", .tags(.physics))
struct ColliderShapeTests {

    // MARK: - scaled(by:)

    @Test("scaled(by:) multiplies every dimension, per shape")
    func scaledByScalesAllDimensions() {
        #expect(ColliderShape.sphere(radius: 2).scaled(by: 3) == .sphere(radius: 6))
        #expect(ColliderShape.capsule(radius: 1.5, halfHeight: 4).scaled(by: 2)
                == .capsule(radius: 3, halfHeight: 8))
        #expect(ColliderShape.box(halfExtents: [1, 2, 3]).scaled(by: 2)
                == .box(halfExtents: [2, 4, 6]))
    }

    @Test("scaled(by: 1) is the identity")
    func scaledByOneIsIdentity() {
        let shapes: [ColliderShape] = [.sphere(radius: 1.35),
                                       .capsule(radius: 1.35, halfHeight: 8.1),
                                       .box(halfExtents: [6.6, 0.18, 2.7])]
        for shape in shapes {
            #expect(shape.scaled(by: 1) == shape)
        }
    }

    // MARK: - hasFinitePositiveDimensions

    @Test("valid dimensions accepted, including capsule halfHeight 0 (sphere-equivalent)")
    func validDimensionsAccepted() {
        #expect(ColliderShape.sphere(radius: 0.001).hasFinitePositiveDimensions)
        #expect(ColliderShape.capsule(radius: 1.35, halfHeight: 8.1).hasFinitePositiveDimensions)
        #expect(ColliderShape.capsule(radius: 1, halfHeight: 0).hasFinitePositiveDimensions)
        #expect(ColliderShape.box(halfExtents: [6.6, 0.18, 2.7]).hasFinitePositiveDimensions)
    }

    @Test("NaN, infinity, zero, and negative dimensions rejected")
    func invalidDimensionsRejected() {
        #expect(!ColliderShape.sphere(radius: .nan).hasFinitePositiveDimensions)
        #expect(!ColliderShape.sphere(radius: .infinity).hasFinitePositiveDimensions)
        #expect(!ColliderShape.sphere(radius: 0).hasFinitePositiveDimensions)
        #expect(!ColliderShape.sphere(radius: -1).hasFinitePositiveDimensions)

        #expect(!ColliderShape.capsule(radius: .nan, halfHeight: 1).hasFinitePositiveDimensions)
        #expect(!ColliderShape.capsule(radius: 0, halfHeight: 1).hasFinitePositiveDimensions)
        #expect(!ColliderShape.capsule(radius: 1, halfHeight: -0.1).hasFinitePositiveDimensions)
        #expect(!ColliderShape.capsule(radius: 1, halfHeight: .infinity).hasFinitePositiveDimensions)

        #expect(!ColliderShape.box(halfExtents: [1, .nan, 1]).hasFinitePositiveDimensions)
        #expect(!ColliderShape.box(halfExtents: [1, 0, 1]).hasFinitePositiveDimensions)
        #expect(!ColliderShape.box(halfExtents: [1, 1, -1]).hasFinitePositiveDimensions)
        #expect(!ColliderShape.box(halfExtents: [.infinity, 1, 1]).hasFinitePositiveDimensions)
    }

    // MARK: - LocalCollider defaults

    @Test("LocalCollider defaults: origin, identity rotation, .airframe, enabled")
    func localColliderDefaults() {
        let collider = LocalCollider(name: "test", shape: .sphere(radius: 1))
        #expect(collider.name == "test")
        #expect(approxEqual(collider.localPosition, .zero))
        #expect(approxEqual(collider.localRotation.vector, simd_quatf.identity.vector))
        #expect(collider.group == .airframe)
        #expect(collider.isEnabled)
    }
}
