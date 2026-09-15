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
                let before = contacts.count
                shapeVsPlane(collider, planePoint: planePoint, planeNormal: planeNormal, into: &contacts)
                for index in before..<contacts.count {
                    noteDeepest(index, in: contacts, deepest: &deepest)
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
    
    /// Keeps `deepest` at the index of the deepest contact of this pair seen
    /// so far; `candidateIndex` is a contact already in the array. The
    /// comparison half of `append`, split out so the plane branch can note
    /// the one or two contacts `shapeVsPlane` appends per collider. Ties keep
    /// the earlier contact, as before. (Written against the inout parameter
    /// directly: a `guard var deepest` here shadows it with a copy, and a
    /// deeper later contact is never recorded — found at the D.3 review.)
    private static func noteDeepest(_ candidateIndex: Int, in contacts: [Contact], deepest: inout Int?) {
        if let current = deepest, contacts[current].depth >= contacts[candidateIndex].depth { return }
        deepest = candidateIndex
    }
    
    /// Appends `contact` and keeps `deepest` at the index of the deepest
    /// contact appended so far. Ties keep the earlier contact, as before.
    private static func append(_ contact: Contact, to contacts: inout [Contact], deepest: inout Int?) {
        contacts.append(contact)
        noteDeepest(contacts.count - 1, in: contacts, deepest: &deepest)
    }
    
    // MARK: - Shape vs plane

    /// Appends the contacts of one collider against the infinite plane
    /// through planePoint: none, one, or two (a capsule's end caps). Gates are
    /// inclusive (depth >= 0).
    static func shapeVsPlane(_ collider: WorldCollider,
                             planePoint: float3,
                             planeNormal n: float3,
                             into contacts: inout [Contact]) {
        switch collider.shape {
            case .sphere(radius: let r):
                let signedDistance = dot(collider.position - planePoint, n)
                let depth = r - signedDistance
                guard depth >= 0 else { return }
                contacts.append(Contact(normal: n,
                                        depth: depth,
                                        point: collider.position - n * signedDistance,
                                        collider: collider))

            case .capsule(radius: let r, halfHeight: let hh):
                // Both end caps, deeper first. A capsule lying along the
                // ground gets two points, so a body with pitch freedom rests
                // on both ends instead of rocking between them (D.3). The
                // first contact is the one the single-contact form produced.
                let axis = collider.rotation.columns.1
                let p0 = collider.position - axis * hh
                let p1 = collider.position + axis * hh
                let d0 = dot(p0 - planePoint, n)
                let d1 = dot(p1 - planePoint, n)
                let (near, nearDistance, far, farDistance) = d0 < d1 ? (p0, d0, p1, d1) : (p1, d1, p0, d0)
                guard r - nearDistance >= 0 else { return }
                contacts.append(Contact(normal: n,
                                        depth: r - nearDistance,
                                        point: near - n * nearDistance,
                                        collider: collider))
                if r - farDistance >= 0 {
                    contacts.append(Contact(normal: n,
                                            depth: r - farDistance,
                                            point: far - n * farDistance,
                                            collider: collider))
                }
            
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
                guard depth >= 0 else { return }
                func axisSign(_ x: Float) -> Float { x >= 0 ? 1 : -1 }
                // Deepest corner: the box's support point in direction −n,
                // stepping each axis against the plane normal.
                let corner = collider.position
                           - c0 * (he.x * axisSign(dot(c0, n)))
                           - c1 * (he.y * axisSign(dot(c1, n)))
                           - c2 * (he.z * axisSign(dot(c2, n)))
                contacts.append(Contact(normal: n,
                                        depth: depth,
                                        point: corner,
                                        collider: collider))
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
                return capsuleVsBox(a, b, halfExtents: he)

            case (.box, .capsule):
                return shapeVsShape(b, a)?.flipped

            case (.box(halfExtents: let ha), .box(halfExtents: let hb)):
                return boxVsBox(a, halfExtentsA: ha, b, halfExtentsB: hb)
        }
    }

    // MARK: - Primitive helpers (pure — unit-testable without Metal)

    // MARK: - Tolerances
    //
    // Angles are compared as cosines or squared sines of unit vectors, so
    // they do not scale with the scene; the one length is a division guard.

    /// Ray vs plane: the cosine between the unit ray and the plane normal
    /// must lie at least this far below zero. Grazing and receding rays
    /// (an inverted aircraft's struts) hit nothing.
    static let grazingRayCosine: Float = 1e-6

    /// Separating axes from cross products: two unit directions whose cross
    /// product is shorter than this (|sin θ| < 1e-3, 0.057°) are parallel
    /// and give no new axis. Box edges against box edges in boxVsBox, the
    /// core direction against box axes in capsuleVsBox.
    static let parallelAxisSineSquared: Float = 1e-6

    /// Support point: a box axis whose cosine against the direction is
    /// within this of zero (0.006°) has no single farthest point and
    /// contributes its center.
    static let perpendicularAxisCosine: Float = 1e-4

    /// Capsule-box contact point: a core whose cosine against the contact
    /// normal is within this of zero runs across the normal, and the
    /// clipped span's midpoint is the point rather than an end. The
    /// cross-product normals are perpendicular to the core exactly; in
    /// float32 their cosine carries up to 6e-8 of rounding (300 000 random
    /// pose-axis samples of the F-22's 16.2 m core), so this is a 170×
    /// margin. The absolute 1e-6 m band it replaces was within 5% of that
    /// rounding at 16.2 m.
    static let coreAcrossNormalCosine: Float = 1e-5

    /// Segment vs slab: a segment whose extent along a box axis is under
    /// this (meters) is parallel to the slab, which keeps 1 / extent
    /// finite and the 0 × inf NaN out of the crossing parameters.
    static let parallelSlabExtent: Float = 1e-8

    /// Ray vs infinite plane: distance t ≥ 0 along `direction` (unit length)
    /// to the plane through planePoint, or nil. Front face only: the ray must
    /// approach against the normal, so an inverted aircraft's struts hit
    /// nothing.
    static func rayVsPlane(origin: float3, direction: float3,
                           planePoint: float3, planeNormal n: float3) -> Float? {
        let denominator = dot(direction, n)
        guard denominator < -grazingRayCosine else { return nil }   // parallel, or facing away
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
    
    /// Capsule vs oriented box, exact. A core that touches or enters the box
    /// (the slab test) gets the least translation that frees the capsule, by
    /// separating axes over the twelve directions a segment and a box can
    /// separate along. Otherwise the core's distance to the box is the least
    /// of its two ends' distances (sphereVsBox: a face, an edge, or a corner)
    /// and its distance to each of the twelve box edges
    /// (closestPointsOnSegments): a core interior point nearest a face
    /// interior means the core runs parallel to the face, and then an end or
    /// a boundary edge is as close. The three sphere probes this replaces
    /// (both caps and the point nearest the box center) missed a core
    /// crossing a box between them, about one true hit in ten; a sphere
    /// probed at the clipped span's midpoint (the second draft) reported that
    /// sphere's depth, not the capsule's.
    private static func capsuleVsBox(_ a: WorldCollider, _ b: WorldCollider, halfExtents he: float3) -> Contact? {
        let (capsuleCoreStart, capsuleCoreEnd, capsuleRadius) = capsuleSegment(a)

        // Capsule core in box-local space (R orthonormal: inverse = transpose).
        let localCapsuleCoreStart = b.rotation.transpose * (capsuleCoreStart - b.position)
        let localCapsuleCoreEnd = b.rotation.transpose * (capsuleCoreEnd - b.position)
        if let span = segmentSpanInsideBox(localCapsuleCoreStart, localCapsuleCoreEnd, halfExtents: he) {
            // Penetration depth of a segment in a box: the least, over the
            // Minkowski difference's face normals — the three face normals
            // and the core's cross product with each, in both senses — of
            // the box's reach along the direction, plus the radius, minus the
            // nearer end's projection: how far the capsule must move along it
            // to be clear. Face axes first, strict compares: ties go to the
            // face and to the earlier sense. A shallow nose-first strike
            // comes out through the face at any yaw; a deep crossing slides
            // out past the nearest edge, as box-box would.
            // The core's unit direction: its cross products with the box
            // axes are then sines and its run along the normal a cosine, so
            // both tolerances are angles and neither scales with the core.
            // A zero-length core (a sphere) has no direction: no
            // cross-product axes, and the point is the span's midpoint.
            let localCapsuleCoreDelta = localCapsuleCoreEnd - localCapsuleCoreStart
            let coreLength = simd_length(localCapsuleCoreDelta)
            let localCapsuleCoreDirection = coreLength > 0 ? localCapsuleCoreDelta / coreLength : .zero
            var leastDepth = Float.infinity
            var localNormal = float3.zero
            func considerAxis(_ candidate: float3) {
                let lengthSquared = simd_length_squared(candidate)
                guard lengthSquared > parallelAxisSineSquared else { return }   // core parallel to the axis: no new direction
                let axis = candidate / lengthSquared.squareRoot()
                let reach = he.x * abs(axis.x) + he.y * abs(axis.y) + he.z * abs(axis.z)
                for sense in 0..<2 {
                    let signedAxis = sense == 0 ? axis : -axis
                    let nearerEndProjection = min(dot(localCapsuleCoreStart, signedAxis),
                                                  dot(localCapsuleCoreEnd, signedAxis))
                    let depth = reach + capsuleRadius - nearerEndProjection
                    if depth < leastDepth {
                        leastDepth = depth
                        localNormal = signedAxis
                    }
                }
            }
            for i in 0..<3 {
                var axis = float3.zero
                axis[i] = 1
                considerAxis(axis)
            }
            for i in 0..<3 {
                var axis = float3.zero
                axis[i] = 1
                considerAxis(cross(localCapsuleCoreDirection, axis))
            }

            // The point: the clipped span's deepest point against the normal
            // (an end inside the box), or the span's midpoint when the core
            // runs across the normal (a core through the box, or past an
            // edge). Inside both shapes, as sphereVsBox's inside branch
            // reports the center.
            let coreAlongNormal = dot(localCapsuleCoreDirection, localNormal)   // a cosine
            let contactPointParameter: Float   // along the core: 0 at capsuleCoreStart, 1 at capsuleCoreEnd
            if coreAlongNormal > coreAcrossNormalCosine {
                contactPointParameter = span.enter
            } else if coreAlongNormal < -coreAcrossNormalCosine {
                contactPointParameter = span.exit
            } else {
                contactPointParameter = 0.5 * (span.enter + span.exit)
            }
            return Contact(normal: b.rotation * localNormal,
                           depth: leastDepth,
                           point: capsuleCoreStart + (capsuleCoreEnd - capsuleCoreStart) * contactPointParameter,
                           collider: a,
                           against: b)
        }

        // Outside the box: the nearer end cap, then the twelve edges. Ties
        // keep the earlier candidate, as everywhere else.
        var best: Contact? = nil
        func consider(_ candidate: Contact?) {
            guard let candidate else { return }
            if let current = best, current.depth >= candidate.depth { return }
            best = candidate
        }
        consider(sphereVsBox(center: capsuleCoreStart, radius: capsuleRadius, box: b, halfExtents: he, a: a, b: b))
        consider(sphereVsBox(center: capsuleCoreEnd, radius: capsuleRadius, box: b, halfExtents: he, a: a, b: b))

        for axis in 0..<3 {
            // The four edges parallel to this axis, one per corner of the
            // face it is normal to.
            let u = (axis + 1) % 3
            let v = (axis + 2) % 3
            let halfEdge = b.rotation[axis] * he[axis]
            for cornerU in 0..<2 {
                for cornerV in 0..<2 {
                    let signU: Float = cornerU == 0 ? -1 : 1
                    let signV: Float = cornerV == 0 ? -1 : 1
                    let middle = b.position + b.rotation[u] * (signU * he[u]) + b.rotation[v] * (signV * he[v])
                    let (onCapsuleCore, onEdge) = closestPointsOnSegments(capsuleCoreStart, capsuleCoreEnd,
                                                                          middle - halfEdge, middle + halfEdge)
                    let delta = onCapsuleCore - onEdge
                    let distance = simd_length(delta)
                    guard distance <= capsuleRadius, distance > 0 else { continue }   // 0 cannot happen: the slab test took it
                    consider(Contact(normal: delta / distance,
                                     depth: capsuleRadius - distance,
                                     point: onEdge,
                                     collider: a,
                                     against: b))
                }
            }
        }

        return best
    }
    
    /// Oriented box vs oriented box by separating axes: the six face normals
    /// and the nine edge-edge cross products (Ericson §4.4.1 gives the test;
    /// this keeps each axis's overlap). The contact normal is the axis of
    /// least overlap, pointed from B toward A, and the depth is that overlap.
    /// One contact point where the boxes meet: for a face axis, the centroid
    /// of the incident face clipped to the reference face (Box2D's manifold,
    /// reduced to one point); for an edge-edge axis the midpoint of the two
    /// edges' closest points. Right for a strike; a box resting flat on
    /// another box's face would rock on one point, and no aircraft box does
    /// (the fuselage capsule sits below the wings and empennage).
    private static func boxVsBox(_ a: WorldCollider, halfExtentsA ha: float3,
                                 _ b: WorldCollider, halfExtentsB hb: float3) -> Contact? {
        enum Feature { case faceOfA(Int), faceOfB(Int), edges(Int, Int) }
        let centerOffset = a.position - b.position
        var leastOverlap: Float = .infinity
        var normal: float3 = .zero
        var feature: Feature = .faceOfA(0)
        
        /// False when `candidate` separates the boxes. Near-parallel edges
        /// give a near-zero cross product and no new axis.
        func overlaps(along candidate: float3, _ candidateFeature: Feature) -> Bool {
            let lengthSquared = simd_length_squared(candidate)
            guard lengthSquared > parallelAxisSineSquared else { return true }
            let axis = candidate / lengthSquared.squareRoot()
            let reachA = ha.x * abs(dot(a.rotation[0], axis)) +
                         ha.y * abs(dot(a.rotation[1], axis)) +
                         ha.z * abs(dot(a.rotation[2], axis))
            let reachB = hb.x * abs(dot(b.rotation[0], axis)) +
                         hb.y * abs(dot(b.rotation[1], axis)) +
                         hb.z * abs(dot(b.rotation[2], axis))
            let distance = dot(centerOffset, axis)
            let overlap = reachA + reachB - abs(distance)
            guard overlap >= 0 else { return false }              // inclusive, like every other gate
            if overlap < leastOverlap {                           // strict: face axes win ties over edge axes
                leastOverlap = overlap
                normal = distance >= 0 ? axis : -axis             // from B toward A
                feature = candidateFeature
            }
            
            return true
        }
        
        for i in 0..<3 {
            guard overlaps(along: a.rotation[i], .faceOfA(i)), overlaps(along: b.rotation[i], .faceOfB(i)) else {
                return nil
            }
        }
        
        for i in 0..<3 {
            for j in 0..<3 {
                guard overlaps(along: cross(a.rotation[i], b.rotation[j]), .edges(i, j)) else { return nil }
            }
        }
        
        /// The box's farthest point in `direction`. An axis at right angles to
        /// the direction has no single farthest point (a face or an edge), so
        /// that axis contributes its center: a face gives its center, an edge
        /// its midpoint, a corner itself.
        func support(_ box: WorldCollider, _ h: float3, _ direction: float3) -> float3 {
            var point = box.position
            for i in 0..<3 {
                let alignment = dot(box.rotation[i], direction)
                if abs(alignment) > perpendicularAxisCosine {
                    point += box.rotation[i] * (h[i] * (alignment > 0 ? 1 : -1))
                }
            }
            return point
        }
        
        /// One point where the boxes meet, for a face axis of `reference`
        /// (Box2D's contact points, Catto GDC 2006, reduced to one): the
        /// incident face — the other box's face most opposed to the
        /// reference face — is clipped by the reference face's four side
        /// planes (Sutherland–Hodgman), and the clipped vertices at or below
        /// the face are averaged. Inside both boxes for any strike. The
        /// second draft's projected-overlap midpoint was inside both
        /// projections but not both boxes: a unit cube at 45° shifted 0.5 m
        /// along the face got a point 0.46 m outside the cube, and a wing
        /// yawed 20° with its tip 0.3 m into a wall got one 5.3 m from the
        /// tip on the wing's centerline, a yaw lever arm of zero. A quad
        /// clipped by four planes has at most eight vertices; the buffer is
        /// on the stack. `fallback` (the support point) covers a clip that
        /// keeps nothing, which no overlapping pair has produced.
        func clippedPoint(reference: WorldCollider,
                          _ hRef: float3,
                          referenceAxis: Int,
                          faceNormal: float3,
                          incident: WorldCollider,
                          _ hInc: float3,
                          fallback: float3) -> float3 {
            // The incident face: the incident axis most opposed to the
            // reference face's outward normal, on that side.
            var incidentAxis = 0
            var incidentSign: Float = 1
            var mostOpposed: Float = .infinity
            for j in 0..<3 {
                let alignment = dot(incident.rotation[j], faceNormal)
                let sign: Float = alignment > 0 ? -1 : 1
                if sign * alignment < mostOpposed {
                    mostOpposed = sign * alignment
                    incidentAxis = j
                    incidentSign = sign
                }
            }
            
            let u = (incidentAxis + 1) % 3
            let v = (incidentAxis + 2) % 3
            let faceCenter = incident.position + incident.rotation[incidentAxis] * (incidentSign * hInc[incidentAxis])
            let du = incident.rotation[u] * hInc[u]
            let dv = incident.rotation[v] * hInc[v]
            
            return withUnsafeTemporaryAllocation(of: float3.self, capacity: 16) { buffer -> float3 in
                // Two eight-slot halves, swapped after each clip plane.
                var input = UnsafeMutableBufferPointer(rebasing: buffer[0..<8])
                var output = UnsafeMutableBufferPointer(rebasing: buffer[8..<16])
                input[0] = faceCenter + du + dv
                input[1] = faceCenter + du - dv
                input[2] = faceCenter - du - dv
                input[3] = faceCenter - du + dv
                var count = 4
                
                for sideAxis in 0..<3 where sideAxis != referenceAxis {
                    for side in 0..<2 {
                        // Keep what lies within this side plane of the
                        // reference face: dot(p, n) ≤ dot(center, n) + h.
                        let planeNormal = reference.rotation[sideAxis] * (side == 0 ? -1 : 1)
                        let planeOffset = dot(reference.position, planeNormal) + hRef[sideAxis]
                        var kept = 0
                        for k in 0..<count {
                            let p = input[k]
                            let q = input[(k + 1) % count]
                            let dp = dot(p, planeNormal) - planeOffset
                            let dq = dot(q, planeNormal) - planeOffset
                            if dp <= 0 {
                                output[kept] = p
                                kept += 1
                            }
                            if (dp < 0 && dq > 0) || (dp > 0 && dq < 0) {
                                output[kept] = p + (q - p) * (dp / (dp - dq))
                                kept += 1
                            }
                        }
                        
                        count = kept
                        guard count > 0 else { return fallback }
                        swap(&input, &output)
                    }
                }
                
                // The clipped vertices at or below the reference face.
                let facePlane = dot(reference.position, faceNormal) + hRef[referenceAxis]
                var sum: float3 = .zero
                var below = 0
                for k in 0..<count where dot(input[k], faceNormal) - facePlane <= 0 {
                    sum += input[k]
                    below += 1
                }
                
                return below > 0 ? sum / Float(below) : fallback
            }
        }
        
        let point: float3
        switch feature {
            case .faceOfA(let i):
                // The reference face is A's face toward B: its outward normal
                // is −normal (the normal points from B toward A).
                point = clippedPoint(reference: a,
                                     ha,
                                     referenceAxis: i,
                                     faceNormal: -normal,
                                     incident: b,
                                     hb,
                                     fallback: support(b, hb, normal))
            case .faceOfB(let i):
                point = clippedPoint(reference: b,
                                     hb,
                                     referenceAxis: i,
                                     faceNormal: normal,
                                     incident: a,
                                     ha,
                                     fallback: support(a, ha, -normal))
            case .edges(let i, let j):
                let midA = support(a, ha, -normal)
                let midB = support(b, hb, normal)
                let (pA, pB) = closestPointsOnSegments(midA - a.rotation[i] * ha[i],
                                                       midA + a.rotation[i] * ha[i],
                                                       midB - b.rotation[j] * hb[j],
                                                       midB + b.rotation[j] * hb[j])
                point = 0.5 * (pA + pB)
        }
        
        return Contact(normal: normal, depth: leastOverlap, point: point, collider: a, against: b)
    }

    /// The parameter span of the segment segmentStart→segmentEnd (t = 0 at
    /// the start, 1 at the end; both ends box-local) inside the axis-aligned
    /// box of the given half extents, or nil where it passes by. Ericson
    /// §5.3.3 (segment vs AABB by slabs); inclusive at the boundary like
    /// every other gate, so a segment touching a face is inside.
    static func segmentSpanInsideBox(_ segmentStart: float3, _ segmentEnd: float3,
                                     halfExtents he: float3) -> (enter: Float, exit: Float)? {
        let segmentDelta = segmentEnd - segmentStart
        var enter: Float = 0
        var exit: Float = 1
        for i in 0..<3 {
            if abs(segmentDelta[i]) < parallelSlabExtent {
                // Parallel to this slab: inside it or not at all.
                guard abs(segmentStart[i]) <= he[i] else { return nil }
            } else {
                let inverseDelta = 1 / segmentDelta[i]
                var slabEnter = (-he[i] - segmentStart[i]) * inverseDelta
                var slabExit = (he[i] - segmentStart[i]) * inverseDelta
                if slabEnter > slabExit { swap(&slabEnter, &slabExit) }
                enter = max(enter, slabEnter)
                exit = min(exit, slabExit)
                guard enter <= exit else { return nil }
            }
        }
        return (enter, exit)
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
