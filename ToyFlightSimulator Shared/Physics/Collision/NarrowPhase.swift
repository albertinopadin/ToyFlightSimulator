//
//  NarrowPhase.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/30/26.
//

import simd

/// Pure narrow phase: WorldCollider geometry in, Contacts out. No body
/// mutation, no Metal. The sphere-sphere and sphere-plane paths reproduce the
/// pre-Phase-A arithmetic operation for operation; changing them requires a
/// reviewed golden regeneration.
enum NarrowPhase {
    // MARK: - Body-level dispatch

    /// Appends every contacting collider pair between the two bodies and
    /// returns the index into `contacts` of the deepest one, or nil. The
    /// linear response uses only the deepest; events use all.
    @discardableResult
    static func generateContacts(_ a: RigidBody, _ b: RigidBody, into contacts: inout [Contact]) -> Int? {
        // Planes are handled at body level: always presented to the shape
        // tests as the B side, flipped back on exit if the plane arrived as A.
        if a is PlaneRigidBody {
            guard !(b is PlaneRigidBody) else { return nil }   // plane/plane: nothing to do
            let firstNew = contacts.count
            guard let deepest = generateContacts(b, a, into: &contacts) else { return nil }

            // The recursive call built contacts with the volume body as A;
            // flip them so the caller's order (A = plane, B = volume) holds.
            // Flipping keeps each index and depth, so `deepest` stays valid.
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
                    append(contact, to: &contacts, deepest: &deepest)
                }
            }
            
            return deepest
        }
        
        // Volume vs volume: every collider of A against every collider of B.
        // A SphereRigidBody contributes its one-sphere view, so this is also
        // the sphere-sphere path.
        var deepest: Int? = nil
        for colliderA in a.worldColliders() {
            for colliderB in b.worldColliders() {
                if let contact = shapeVsShape(colliderA, colliderB) {
                    append(contact, to: &contacts, deepest: &deepest)
                }
            }
        }
        
        return deepest
    }
    
    /// Appends `contact` and keeps `deepest` at the index of the deepest
    /// contact appended so far. Ties keep the earlier contact, as before.
    private static func append(_ contact: Contact, to contacts: inout [Contact], deepest: inout Int?) {
        contacts.append(contact)
        if let current = deepest, contacts[current].depth >= contact.depth { return }
        deepest = contacts.count - 1
    }
    
    // MARK: - Shape vs plane

    /// Sphere, capsule, or box against the infinite plane through planePoint.
    /// Gates are inclusive (depth >= 0).
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
                // The deeper end-cap center decides. A capsule lying flat picks
                // one end, which is enough for the linear response.
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
                // Deepest corner: the box's support point in direction −n,
                // stepping each axis against the plane normal.
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
                // Approximation: the capsule reduced to the sphere nearest the
                // box center, then sphere-vs-box. Exact segment-OBB or GJK can
                // replace it later.
                let (p, r) = capsuleAsSphere(a, towards: b.position)
                return sphereVsBox(center: p, radius: r, box: b, halfExtents: he, a: a, b: b)

            case (.box, .capsule):
                return shapeVsShape(b, a)?.flipped

            case (.box, .box):
                // Not implemented: no box-box pair exists yet. SAT or GJK/EPA
                // when one does.
                return nil
        }
    }

    // MARK: - Primitive helpers (pure — unit-testable without Metal)

    /// Ray vs infinite plane: distance t ≥ 0 along `direction` (unit length)
    /// to the plane through planePoint, or nil. Front face only: the ray must
    /// approach against the normal, so an inverted aircraft's struts hit
    /// nothing.
    static func rayVsPlane(origin: float3, direction: float3,
                           planePoint: float3, planeNormal n: float3) -> Float? {
        let denominator = dot(direction, n)
        guard denominator < -1e-6 else { return nil }   // parallel, or facing away
        let t = dot(planePoint - origin, n) / denominator
        return t >= 0 ? t : nil                          // plane behind the origin
    }

    /// Squared compare: no sqrt on the reject path, and the same form as the
    /// legacy test, which the goldens cover. Coincident centers give a zero
    /// normal, as before.
    private static func sphereVsSphere(centerA: float3, radiusA: Float,
                                       centerB: float3, radiusB: Float,
                                       a: WorldCollider, b: WorldCollider) -> Contact? {
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

        // The capsule axis is local +Y, so the rotation's second column is
        // the axis in world space.
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
        // Clamped projection onto the segment: t = 0 at p0, t = 1 at p1.
        let t = max(0, min(1, dot(point - p0, segment) / lengthSquared))
        return p0 + segment * t
    }

    /// Closest points between two segments: Ericson, Real-Time Collision
    /// Detection §5.1.9 (ClosestPtSegmentSegment), with the book's variable
    /// names. The .ulpOfOne branches handle segments degenerated to points.
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
