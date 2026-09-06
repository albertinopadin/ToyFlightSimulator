//
//  ColliderDebugOverlay.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/27/26.
//

import Foundation

/// Maps ColliderShape (meters) onto the engine's debug meshes.
/// Child transforms are in the PARENT's model space — the parent's uniform
/// scale (1.0 for meterized aircraft) composes via the normal matrix
/// hierarchy, so the mesh-facing functions never see the scale.
/// (worldDimensions reports WORLD sizes for the 0.5 units log, so it alone
/// takes the parent scale as a parameter.)
enum ColliderOverlayMapping {
    /// ModelType.Sphere is ObjModel("sphere"), radius exactly 1.0. Not
    /// SphereMesh, whose MDLMesh(sphereWithExtent:) call is radius-semantics
    /// and builds twice the requested size (pinned by MeshBoundsTests).
    static let sphereMeshRadius: Float = 1.0

    /// ModelType.Cube wraps CubeMesh(size: 1.0) = MDLMesh(boxWithExtent: [1,1,1]);
    /// box extent IS full extent (measured) → side 1.0, half-extent 0.5.
    static let cubeMeshSize: Float = 1.0

    /// Scale for a volume built from the unit meshes above. Capsules return
    /// .one: their mesh is built bespoke at exact dimensions and must never
    /// be scaled (non-uniform scale distorts the hemispherical caps).
    static func childScale(for shape: ColliderShape) -> float3 {
        switch shape {
            case .sphere(radius: let r):
                return float3(repeating: r / sphereMeshRadius)
            case .box(halfExtents: let he):
                // Per-axis; non-uniform is fine for render-only children.
                return (2.0 * he) / cubeMeshSize
            case .capsule:
                return .one
        }
    }

    /// MDLMesh(capsuleWithExtent: [x, y, z]) takes x/z as the radius and y as
    /// the total cap-to-cap length (measured; pinned by MeshBoundsTests), so
    /// CapsuleMesh(radius:length:) builds exactly radius r, total length L,
    /// and a collider capsule (halfHeight = half the segment) maps as:
    static func capsuleMeshParams(radius: Float, halfHeight: Float) -> (radius: Float, length: Float) {
        (radius, 2 * (halfHeight + radius))
    }

    /// Axis-aligned local dimensions of a collider × the parent's uniform
    /// scale, for the units log. Rotation and translation are ignored, so it
    /// reports sizes, not extents. longestAxisMeters is the sanity anchor
    /// (fuselage capsule → 18.9).
    static func worldDimensions(of collider: LocalCollider, parentScale: Float) -> (dims: String, longestAxisMeters: Float) {
        switch collider.shape.scaled(by: parentScale) {
            case .sphere(radius: let r):
                return ("sphere ø \(formatMeters(2 * r))", 2 * r)
            case .capsule(radius: let r, halfHeight: let hh):
                let total = 2 * (hh + r)   // the same cap-to-cap span capsuleMeshParams renders
                return ("capsule ø \(formatMeters(2 * r)) × \(formatMeters(total)) end-to-end", total)
            case .box(halfExtents: let he):
                let full = 2 * he
                return ("box \(formatMeters(full.x)) × \(formatMeters(full.y)) × \(formatMeters(full.z))",
                        max(full.x, full.y, full.z))
        }
    }

    /// Strut overlay line in the aircraft's local space (the Line is a child,
    /// so the parent's scale composes): attach point to the uncompressed
    /// wheel's contact patch along body −Y. With the gear down, the lower end
    /// should sit at the modeled wheel's contact patch.
    static func strutLineEndpoints(for strut: SuspensionStrut) -> (start: float3, end: float3) {
        (strut.attachLocal, strut.attachLocal - float3(0, strut.reach, 0))
    }

    private static func formatMeters(_ value: Float) -> String {
        String(format: "%.2f m", value)
    }
}


/// Render-only volumes visualizing an aircraft's collider spec (red), its
/// legacy physics sphere (yellow), and its gear struts (cyan lines). Owns no
/// physics state; update-thread only (all scene-graph mutation happens in
/// doUpdate — same rule as CycleCamera).
///
/// X cycles: off → volumesOverHull (translucent, catches OVERFIT via
/// protrusion) → volumesOnly (hull hidden, catches UNDERFIT — end caps and
/// silhouettes visible; A/B against volumesOverHull for placement) → off.
final class ColliderDebugOverlay {
    enum Mode {
        case off
        case volumesOverHull
        case volumesOnly

        var next: Mode {
            switch self {
                case .off:             return .volumesOverHull
                case .volumesOverHull: return .volumesOnly
                case .volumesOnly:     return .off
            }
        }
    }

    /// Alpha < 1 makes isTransparent true, which routes the volumes into the
    /// transparent collection at registration, so setColor comes before
    /// Register.
    static let specColor: float4    = [1, 0, 0, 0.3]
    static let legacyColor: float4  = [1, 1, 0, 0.25]
    /// Opaque cyan: Line renders through the .lines collection, so the alpha
    /// rule above does not apply.
    static let strutColor: float4   = [0, 1, 1, 1]

    private(set) var mode: Mode = .off
    private var volumes: [GameObject] = []
    private weak var host: GameObject?

    /// X-key entry point (GameScene.doUpdate): advance the mode on `target`.
    /// The assert pins the wiring invariant: a host change while visible must
    /// arrive via hostWasReplaced, never via cycle — otherwise volumes would
    /// attach to a second aircraft while the first still holds the old set.
    func cycle(on target: GameObject, type: AircraftType) {
        assert(mode == .off || host === target,
               "[ColliderDebugOverlay] host changed without hostWasReplaced - swap wiring is missing")
        apply(mode.next, on: target, type: type)
    }

    /// Aircraft swap: SceneManager.RemoveObject already detached and
    /// unregistered the old subtree, volumes included. Drop the stale
    /// references (removeFromScene on them would be redundant) and re-apply
    /// the mode to the new host.
    func hostWasReplaced(by newTarget: GameObject?, type: AircraftType) {
        let previousMode = mode
        reset()
        if previousMode != .off, let newTarget {
            apply(previousMode, on: newTarget, type: type)
        }
    }

    /// Bookkeeping-only clear — no scene-graph calls. Callers guarantee the
    /// volumes' subtree is already gone (swap) or being torn down wholesale
    /// (teardownScene).
    func reset() {
        volumes.removeAll()
        host = nil
        mode = .off
    }

    /// Single mutation point for mode transitions. Hull hidden-ness is
    /// applied LAST on the way in and FIRST on the way out, so no partial
    /// transition can strand a hidden aircraft.
    private func apply(_ newMode: Mode, on target: GameObject, type: AircraftType) {
        guard newMode != mode else { return }

        if newMode == .off {
            SceneManager.SetRenderableHidden(target, false)   // un-hide FIRST
            for volume in volumes {
                // Per the scene-graph rule: removeChild + Unregister. A bare
                // removeChild would leave frozen ghost renderables.
                volume.removeFromScene()
            }

            reset()
            return
        }

        if mode == .off {   // entering: build, attach, register, log
            host = target
            let acSpec = AircraftColliderSpec.spec(for: type)
            let gearSpec = AircraftLandingGearSpec.spec(for: type)
            buildVolumes(on: target, spec: acSpec, gearSpec: gearSpec)
            logWorldDimensions(acSpec, gearSpec: gearSpec, on: target)
        }

        mode = newMode

        // LAST (see doc comment above):
        SceneManager.SetRenderableHidden(target, newMode == .volumesOnly)
    }

    /// One volume per enabled spec collider, a cyan line per strut, plus the
    /// yellow legacy-sphere ghost. Order: setColor before Register;
    /// target.addChild (plain Node reparenting, since only GameScene.addChild
    /// auto-registers and the volumes hang off the aircraft), then
    /// SceneManager.Register.
    private func buildVolumes(on target: GameObject, spec: [LocalCollider], gearSpec: [SuspensionStrut]) {
        if spec.isEmpty {
            print("[ColliderDebugOverlay] no compound spec for \(target.getName()) yet - legacy sphere only")
        }

        for collider in spec where collider.isEnabled {
            let volume = makeVolume(for: collider.shape, name: "ColliderOverlay_\(collider.name)")
            volume.setColor(Self.specColor)
            volume.setPosition(collider.localPosition)
            volume.setRotation(collider.localRotation)
            volume.setScale(ColliderOverlayMapping.childScale(for: collider.shape))
            attach(volume, to: target)
        }
        
        // Cyan strut lines. Line is a GameObject in the .lines collection, so
        // attach, register, and removeFromScene work as for the volumes. Line
        // builds its vertex buffer at init, on the update thread, like the
        // capsule mesh in makeVolume.
        for strut in gearSpec {
            let (start, end) = ColliderOverlayMapping.strutLineEndpoints(for: strut)
            attach(Line(startPoint: start, endPoint: end, color: Self.strutColor), to: target)
        }

        // The legacy sphere sits at the body origin. collisionRadius is world
        // meters and the ghost is a child, so divide by the parent's scale. A
        // compound aircraft has a plain RigidBody and gets no ghost; its red
        // volumes are the live colliders.
        if let sphereBody = target.rigidBody as? SphereRigidBody {
            let ghost = GameObject(name: "ColliderOverlay_legacySphere", modelType: .Sphere)
            ghost.setColor(Self.legacyColor)
            ghost.setScale(sphereBody.collisionRadius / (ColliderOverlayMapping.sphereMeshRadius * target.uniformScale))
            attach(ghost, to: target)
        }
    }

    private func attach(_ volume: GameObject, to target: GameObject) {
        target.addChild(volume)
        SceneManager.Register(volume)
        volumes.append(volume)
    }

    /// Sphere/box volumes reuse the unit library models; capsules get a
    /// bespoke mesh at exact dimensions through GameObject(name:model:).
    /// Mesh construction on the update thread is established practice: scene
    /// resets rebuild whole scenes there.
    private func makeVolume(for shape: ColliderShape, name: String) -> GameObject {
        switch shape {
            case .sphere:
                // OBJ sphere, radius exactly 1.0 — never SphereMesh (2× quirk).
                return GameObject(name: name, modelType: .Sphere)
            case .box:
                return GameObject(name: name, modelType: .Cube)
            case .capsule(radius: let radius, halfHeight: let halfHeight):
                let p = ColliderOverlayMapping.capsuleMeshParams(radius: radius, halfHeight: halfHeight)
                let mesh = CapsuleMesh(radius: p.radius, length: p.length)
                return GameObject(name: name, model: Model(name: name, mesh: mesh))
        }
    }

    /// Units log, printed on every overlay show. Sanity anchor: the fuselage
    /// capsule must read about 18.90 m at scale 1.0 (real F-22: 18.92 m).
    /// With a gear spec, also the strut geometry and the static stance the
    /// in-app settle must reproduce (F-22: compression 0.119 m, ride height
    /// 1.93 m at 30 t).
    private func logWorldDimensions(_ spec: [LocalCollider], gearSpec: [SuspensionStrut], on target: GameObject) {
        guard !spec.isEmpty else { return }

        let scale = target.uniformScale
        print("[ColliderDebugOverlay] \(target.getName()) collider world dimensions (uniformScale \(scale)):")

        for collider in spec where collider.isEnabled {
            let (dims, _) = ColliderOverlayMapping.worldDimensions(of: collider, parentScale: scale)
            print("  \(collider.name): \(dims)")
        }

        if let sphereBody = target.rigidBody as? SphereRigidBody {
            print("  legacy sphere: ø \(String(format: "%.2f m", 2 * sphereBody.collisionRadius)) (world)")
        }
        
        // Gear stance from the body's live mass (synced from the flight model).
        if !gearSpec.isEmpty,
           let mass = target.rigidBody?.mass,
           let stance = AircraftLandingGearSpec.staticStance(struts: gearSpec, mass: mass) {
            for strut in gearSpec {
                print("  \(strut.name): attach \(strut.attachLocal), reach below origin \(String(format: "%.2f m", strut.reachBelowOrigin))")
            }
            
            print("  gear stance: static compression \(String(format: "%.3f m", stance.compression)), "
                              + "ride height ≈ \(String(format: "%.2f m", stance.rideHeight))")
        }
    }
}
