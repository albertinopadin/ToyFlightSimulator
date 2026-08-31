//
//  NarrowPhase.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/30/26.
//

import simd

/// Pure narrow phase: WorldCollider geometry in, Contacts out. No body
/// mutation, no Metal — every function below is unit-testable per the
/// project's Metal-free rule (research §3.4: the Local/World split is what
/// makes this a pure function).
///
/// The sphere-sphere and sphere-plane paths are TRANSCRIPTIONS of the deleted
/// PhysicsWorld shape switches — operation-for-operation, so the A-routing
/// commit is bit-identical against the Phase 0 goldens. Do not "improve" the
/// arithmetic here without a deliberate, reviewed golden regeneration.
enum NarrowPhase {
    // MARK: - Body-level dispatch

    /// Appends EVERY contacting collider pair between the two bodies into
    /// `contacts` (combined doc D3 hybrid: events and classification need all
    /// of them — a wingtip and the belly can scrape simultaneously). Returns
    /// the ABSOLUTE index (into `contacts`) of the deepest appended contact —
    /// the linear-only response consumes exactly that one; Phase D's solver
    /// will consume them all and the return value disappears. nil ⇒ no
    /// intersection (nothing appended).
    @discardableResult
    static func generateContacts(_ a: RigidBody, _ b: RigidBody, into contacts: inout [Contact]) -> Int? {
        // Planes are infinite static world geometry, special-cased at body
        // level (research §3.5); always presented to the shape tests as the
        // B side, flipped back on exit if the plane arrived as A.
        if a is PlaneRigidBody {
            guard !(b is PlaneRigidBody) else { return nil }   // plane/plane: nothing to do
            let firstNew = contacts.count
            guard let deepest = generateContacts(b, a, into: &contacts) else { return nil }

            // The recursive call appended contacts expressed with the VOLUME
            // body as A (normal pointing plane → volume, metadata on the A
            // side), but our caller passed (A = plane, B = volume), and
            // Contact ties normal direction and metadata sides to the
            // caller's argument order — so rewrite each appended contact into
            // the caller's orientation. Skipping this flip would hand the
            // response a normal pointing INTO the dynamic body. The deepest
            // index survives untouched: flipping changes neither a contact's
            // position in the array nor its depth.
            for i in firstNew..<contacts.count {
                contacts[i] = contacts[i].flipped
            }

            return deepest
        }

        if let plane = b as? PlaneRigidBody {
            let planePoint = plane.getPosition()
            let planeNormal = plane.collisionNormal
            var deepest: Int? = nil
            for collider in a.worldColliders() {
                if let contact = shapeVsPlane(collider, planePoint: planePoint, planeNormal: planeNormal) {
                    contacts.append(contact)
                    if deepest == nil || contact.depth > contacts[deepest!].depth {
                        deepest = contacts.count - 1
                    }
                }
            }
            
            return deepest
        }
        
        // Volume vs volume: children × children. A legacy SphereRigidBody's
        // "children" are its one synthesized view, so this loop IS the
        // sphere-sphere, sphere-compound, and compound-compound path at once.
        var deepest: Int? = nil
        for colliderA in a.worldColliders() {
            for colliderB in b.worldColliders() {
                if let contact = shapeVsShape(colliderA, colliderB) {
                    contacts.append(contact)
                    if deepest == nil || contact.depth > contacts[deepest!].depth {
                        deepest = contacts.count - 1
                    }
                }
            }
        }
        
        return deepest
    }
    
    // MARK: - Shape vs plane

    /// Sphere/capsule/box vs the infinite plane through planePoint. The
    /// sphere case is the legacy sphere-plane test in general-plane form —
    /// bit-identical for every plane that exists today (they all sit at the
    /// origin with a +Y normal; equivalence argued in the A.5 notes), and
    /// CORRECT for tilted/translated planes, which the deleted
    /// getPenetrationDepth(ball:plane:) y=0 hardcode never was.
    /// Gates are inclusive (depth >= 0), matching the legacy `<=` boundaries.
    static func shapeVsPlane(_ collider: WorldCollider, planePoint: float3, planeNormal n: float3) -> Contact? {
        switch collider.shape {
            case .sphere(radius: let r):
                let signedDistance = dot(collider.position - planePoint, n)
                let depth = r - signedDistance
                guard depth >= 0 else { return nil }
                return Contact(normal: n,
                               depth: depth,
                               point: collider.position - n * signedDistance,
                               collider: collider)

            case .capsule(radius: let r, halfHeight: let hh):
                // Deeper end-cap center decides. A capsule lying flat on the
                // plane picks one end — adequate for the linear response
                // (co-normal contacts resolve with one impulse); Phase D's
                // manifold work refines this.
                let axis = collider.rotation.columns.1
                let p0 = collider.position - axis * hh
                let p1 = collider.position + axis * hh
                let d0 = dot(p0 - planePoint, n)
                let d1 = dot(p1 - planePoint, n)
                let (endCenter, signedDistance) = d0 < d1 ? (p0, d0) : (p1, d1)
                let depth = r - signedDistance
                guard depth >= 0 else { return nil }
                return Contact(normal: n,
                               depth: depth,
                               point: endCenter - n * signedDistance,
                               collider: collider)
            
            case .box(halfExtents: let he):
                let c0 = collider.rotation.columns.0
                let c1 = collider.rotation.columns.1
                let c2 = collider.rotation.columns.2
                // Projection radius of the OBB onto the plane normal: how far
                // the box extends from its center along n, worst corner.
                let projectionRadius = he.x * abs(dot(c0, n))
                                     + he.y * abs(dot(c1, n))
                                     + he.z * abs(dot(c2, n))
                let signedDistance = dot(collider.position - planePoint, n)
                let depth = projectionRadius - signedDistance
                guard depth >= 0 else { return nil }
                func axisSign(_ x: Float) -> Float { x >= 0 ? 1 : -1 }
                // The deepest-penetrating corner (the box's support point in
                // direction −n): every corner is center ± he.x·c0 ± he.y·c1
                // ± he.z·c2, and stepping each axis AGAINST the plane normal
                // — minus the axis if it points along n, plus if it points
                // away — picks, per axis, the choice that lowers the
                // projection onto n. Summed, that's the corner closest to
                // (or furthest through) the plane, the natural
                // representative contact point.
                let corner = collider.position
                           - c0 * (he.x * axisSign(dot(c0, n)))
                           - c1 * (he.y * axisSign(dot(c1, n)))
                           - c2 * (he.z * axisSign(dot(c2, n)))
                return Contact(normal: n,
                               depth: depth,
                               point: corner,
                               collider: collider)
        }
    }
    
    // MARK: - Shape vs shape

    static func shapeVsShape(_ a: WorldCollider, _ b: WorldCollider) -> Contact? {
        switch (a.shape, b.shape) {
            case (.sphere(radius: let ra), .sphere(radius: let rb)):
                return sphereVsSphere(centerA: a.position,
                                      radiusA: ra,
                                      centerB: b.position,
                                      radiusB: rb,
                                      a: a,
                                      b: b)

            case (.sphere(radius: let r), .capsule):
                // Closest point on B's segment to A's center → sphere-sphere.
                let (pB, rB) = capsuleAsSphere(b, towards: a.position)
                return sphereVsSphere(centerA: a.position,
                                      radiusA: r,
                                      centerB: pB,
                                      radiusB: rB,
                                      a: a,
                                      b: b)
                
            case (.capsule, .sphere):
                return shapeVsShape(b, a)?.flipped
                
            case (.capsule, .capsule):
                let (segA0, segA1, rA) = capsuleSegment(a)
                let (segB0, segB1, rB) = capsuleSegment(b)
                let (pA, pB) = closestPointsOnSegments(segA0, segA1, segB0, segB1)
                return sphereVsSphere(centerA: pA, radiusA: rA, centerB: pB, radiusB: rB, a: a, b: b)
                
            case (.sphere(radius: let r), .box(halfExtents: let he)):
                return sphereVsBox(center: a.position,
                                   radius: r,
                                   box: b,
                                   halfExtents: he,
                                   a: a,
                                   b: b)
                
            case (.box, .sphere):
                return shapeVsShape(b, a)?.flipped
                
            case (.capsule, .box(halfExtents: let he)):
                // Approximation: nearest point of the capsule segment to the
                // box CENTER, then sphere-vs-box. Adequate for crash
                // detection; exact segment-OBB (or GJK) is the Phase C/D
                // upgrade path (combined doc §4.4).
                let (p, r) = capsuleAsSphere(a, towards: b.position)
                return sphereVsBox(center: p, radius: r, box: b, halfExtents: he, a: a, b: b)

            case (.box, .capsule):
                return shapeVsShape(b, a)?.flipped

            case (.box, .box):
                // Not needed while structures are static and vehicle compounds
                // are capsule/box-vs-sphere/plane dominated. Upgrade path:
                // SAT (15 axes) or GJK/EPA — Phase C decides if it's ever hit.
                return nil
        }
    }

    // MARK: - Primitive helpers (pure — unit-testable without Metal)

    /// LEGACY-EXACT transcription of the deleted PhysicsWorld sphere-sphere
    /// pair: squared-distance gate, INCLUSIVE boundary, one sqrt on the hit
    /// path, and the degenerate coincident-centers case yields a ZERO normal
    /// (as before — reachable via perfect overlap and therefore pinned;
    /// changing it to an arbitrary up-vector is a behavior change requiring a
    /// golden regen of its own).
    private static func sphereVsSphere(centerA: float3, radiusA: Float,
                                       centerB: float3, radiusB: Float,
                                       a: WorldCollider, b: WorldCollider) -> Contact? {
        // Deliberately NOT `distance(centerA, centerB) <= radiusSum`, for two
        // reasons. (1) Rejection needs no sqrt: comparing squared quantities
        // decides overlap just as well (both sides non-negative, squaring is
        // monotonic), and rejection is the overwhelmingly common outcome for
        // broad-phase candidates — the sqrt below runs only on actual hits.
        // (2) The legacy pair test used exactly this squared form, and
        // sqrt-then-compare can disagree with it at the boundary by one
        // rounding step — the bit-for-bit golden gate pins the squared form.
        let radiusSum = radiusA + radiusB
        let delta = centerA - centerB
        let distanceSquared = simd_length_squared(delta)
        guard distanceSquared <= radiusSum * radiusSum else { return nil }
        let distance = simd_length(delta)
        let normal: float3 = distance > 0 ? delta / distance : .zero
        return Contact(normal: normal,
                       depth: radiusSum - distance,
                       point: centerB + normal * radiusB,
                       collider: a,
                       against: b)
    }
    
    private static func sphereVsBox(center: float3,
                                    radius: Float,
                                    box: WorldCollider,
                                    halfExtents he: float3,
                                    a: WorldCollider,
                                    b: WorldCollider) -> Contact? {
        // Sphere center in box-local space (R orthonormal: inverse = transpose).
        let local = box.rotation.transpose * (center - box.position)
        let clamped = simd_clamp(local, -he, he)

        if local.x == clamped.x && local.y == clamped.y && local.z == clamped.z {
            // Center inside the box — always a hit regardless of radius: push
            // out along the axis of least penetration (depth = face distance
            // + radius). Ties resolve toward x→y→z, deterministically.
            let distances = he - abs(local)
            var axis = 0
            if distances.y < distances.x { axis = 1 }
            if distances.z < distances[axis] { axis = 2 }
            var localNormal = float3.zero
            localNormal[axis] = local[axis] >= 0 ? 1 : -1
            return Contact(normal: box.rotation * localNormal,
                           depth: distances[axis] + radius,
                           point: center,
                           collider: a,
                           against: b)
        }
        
        let closest = box.position + box.rotation * clamped
        let delta = center - closest
        let distance = simd_length(delta)
        guard distance <= radius else { return nil }
        let normal: float3 = distance > 0 ? delta / distance : [0, 1, 0]
        return Contact(normal: normal,
                       depth: radius - distance,
                       point: closest,
                       collider: a,
                       against: b)
    }
    
    /// The capsule's core segment endpoints and radius, in world space.
    private static func capsuleSegment(_ c: WorldCollider) -> (p0: float3, p1: float3, radius: Float) {
        guard case .capsule(radius: let r, halfHeight: let hh) = c.shape else {
            fatalError("capsuleSegment on non-capsule collider")
        }

        // ColliderShape defines .capsule as a segment along LOCAL +Y (see its
        // doc comment), and a rotation matrix's columns are the world images
        // of the local basis vectors — R·[0,1,0] IS columns.1 — so columns.1
        // is the capsule axis in world space.
        let axis = c.rotation.columns.1
        return (c.position - axis * hh, c.position + axis * hh, r)
    }

    /// The capsule reduced to the sphere nearest `target`: (center, radius).
    private static func capsuleAsSphere(_ c: WorldCollider, towards target: float3) -> (center: float3, radius: Float) {
        let (p0, p1, r) = capsuleSegment(c)
        return (closestPointOnSegment(p0, p1, to: target), r)
    }

    static func closestPointOnSegment(_ p0: float3, _ p1: float3, to point: float3) -> float3 {
        let segment = p1 - p0
        let lengthSquared = simd_length_squared(segment)
        guard lengthSquared > .ulpOfOne else { return p0 }   // degenerate: both ends coincide
        // Textbook point-onto-segment projection: dot(point − p0, segment)
        // is |point − p0|·|segment|·cos θ — dividing by |segment|² leaves the
        // parameter t of the perpendicular foot along p0→p1 measured in
        // segment lengths (t = 0 at p0, t = 1 at p1). Clamping t to [0, 1]
        // keeps the result on the segment rather than the infinite line, so
        // beyond either end the nearest END point wins.
        let t = max(0, min(1, dot(point - p0, segment) / lengthSquared))
        return p0 + segment * t
    }

    /// Closest points between two segments — the clamped-parameter algorithm
    /// from Christer Ericson, "Real-Time Collision Detection" §5.1.9
    /// (ClosestPtSegmentSegment), transcribed with the book's variable names
    /// (d1/d2 directions, s/t parameters, a/b/c/e/f dot products):
    /// minimize |(p1 + s·d1) − (p2 + t·d2)| over s,t ∈ [0,1] — solve the
    /// unconstrained closest points of the two LINES, then clamp s and t
    /// against each other's segment bounds (each clamp re-solves the other
    /// parameter). The .ulpOfOne branches handle segments degenerated to
    /// points. Book site: https://realtimecollisiondetection.net/books/rtcd/
    static func closestPointsOnSegments(_ p1: float3, _ q1: float3, _ p2: float3, _ q2: float3) -> (float3, float3) {
        let d1 = q1 - p1
        let d2 = q2 - p2
        let r = p1 - p2
        let a = dot(d1, d1)
        let e = dot(d2, d2)
        let f = dot(d2, r)
        var s: Float = 0, t: Float = 0
        if a <= .ulpOfOne && e <= .ulpOfOne { return (p1, p2) }
        if a <= .ulpOfOne {
            t = max(0, min(1, f / e))
        } else {
            let c = dot(d1, r)
            if e <= .ulpOfOne {
                s = max(0, min(1, -c / a))
            } else {
                let b = dot(d1, d2)
                let denominator = a * e - b * b
                s = denominator > .ulpOfOne ? max(0, min(1, (b * f - c * e) / denominator)) : 0
                t = (b * s + f) / e
                if t < 0 {
                    t = 0
                    s = max(0, min(1, -c / a))
                } else if t > 1 {
                    t = 1
                    s = max(0, min(1, (b - c) / a))
                }
            }
        }
        
        return (p1 + d1 * s, p2 + d2 * t)
    }
}
