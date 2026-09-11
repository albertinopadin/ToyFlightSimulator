//
//  StaticStructure.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/11/26.
//

/// Static scenery with collision: one box or one vertical capsule, rendered
/// at exactly its collider's size (the mesh is the collider, so there is
/// nothing to overlay) and carried by a static RigidBody it creates itself.
/// Build a hangar from several. Static bodies never pair with each other in
/// the broad phase; each part costs one AABB test per dynamic body per
/// substep over a compound, and contacts name the part ("Hangar_roof").
final class StaticStructure: GameObject {
    enum Shape {
        /// Full extents in meters: a 40 × 12 × 3 m wall is [40, 12, 3].
        case box(size: float3)
        /// Vertical (axis +Y), `height` cap to cap.
        case capsule(radius: Float, height: Float)
        
        /// The same solid as a collider. Pure, tested. A capsule no taller
        /// than its diameter has no core: halfHeight clamps to 0, the
        /// sphere-equivalent LocalCollider accepts, never negative.
        var collider: ColliderShape {
            switch self {
                case .box(let size):
                    return .box(halfExtents: size / 2)
                case .capsule(let radius, let height):
                    return .capsule(radius: radius, halfHeight: max(0, height / 2 - radius))
            }
        }
    }
    
    init(name: String, shape: Shape, color: float4) {
        super.init(name: name, model: Model(name: name, mesh: Self.makeMesh(shape)))
        setColor(color)
        
        // RigidBody.init registers itself as this object's rigidBody. Scenes
        // still add it to their PhysicsWorld (GameScene.addChild registers
        // renderables, not bodies).
        let body = RigidBody(gameObject: self)
        body.colliders = [LocalCollider(name: name, shape: shape.collider, group: .structure)]
        body.isStatic = true
        body.shouldApplyGravity = false
        body.restitution = 0.3            // min() with the aircraft's 0.2 keeps 0.2; debris (1.0) stops bouncing
        body.categoryMask = CollisionCategory.structure
    }
    
    /// Bespoke mesh at the shape's size, so the node stays at scale 1 (the
    /// units contract for a body's node). Built wherever buildScene runs (the
    /// update thread on a scene reset), like the overlay's capsule volumes:
    /// MTKMesh creation does not need the main thread.
    private static func makeMesh(_ shape: Shape) -> Mesh {
        switch shape {
            case .box(size: let size):
                return CubeMesh(extent: size)
            case .capsule(radius: let radius, height: let height):
                return CapsuleMesh(radius: radius, length: height)
        }
    }
}
