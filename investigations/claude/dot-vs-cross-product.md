# Dot Product vs Cross Product

Quick reference for when to reach for which in flight-model / 3D math code.

## At a glance

|                            | `dot(a, b)`                                                | `cross(a, b)`                                                  |
| -------------------------- | ---------------------------------------------------------- | -------------------------------------------------------------- |
| **Returns**                | Scalar (`Float`)                                           | Vector (`float3`)                                              |
| **Formula**                | `a.x*b.x + a.y*b.y + a.z*b.z`                              | `(a.y*b.z - a.z*b.y, a.z*b.x - a.x*b.z, a.x*b.y - a.y*b.x)`    |
| **Geometry**               | `|a| |b| cos(θ)` — projection-like                         | `|a| |b| sin(θ) * n̂` — perpendicular to both                   |
| **Commutative?**           | Yes: `dot(a, b) == dot(b, a)`                              | No: `cross(a, b) == -cross(b, a)`                              |
| **Defined in any dim?**    | Yes (2D, 3D, N-D)                                          | 3D only (in this form)                                         |
| **Swift `simd` function**  | `dot(a, b)`                                                | `cross(a, b)`                                                  |

## What they tell you

### `dot` — *"how aligned are these two vectors?"*

- `> 0` → pointing roughly the same way
- `== 0` → perpendicular
- `< 0` → pointing opposite
- `dot(v, v)` = squared length of `v` (cheap — no `sqrt`)

### `cross` — *"give me an axis perpendicular to both."*

- Magnitude equals the area of the parallelogram spanned by `a` and `b`
- `== zero` → inputs are parallel (or one is the zero vector)
- Direction follows handedness convention (left-handed in this project)

## Typical flight-model / engine uses

```swift
// Forward airspeed: how much of the velocity is along the nose
let fwdSpeed = dot(velocity, fwd)

// Project velocity onto the forward axis (the "vector form" of fwdSpeed)
let projVelo = dot(velocity, fwd) / dot(fwd, fwd) * fwd

// Right vector from forward + up
let right = cross(fwd, up)

// Torque axis from a lifting surface (wing × airflow)
let torqueAxis = cross(wing, airflow)

// sin(angle between a and b) — useful for stall / sideslip detection
let sinTheta = length(cross(a, b)) / (length(a) * length(b))

// Plane normal from three points
let n = normalize(cross(p1 - p0, p2 - p0))
```

## Rule of thumb

- Reach for **`dot`** when you want *"how much of this is in that direction"* — projections, angles, alignment, scalar magnitudes.
- Reach for **`cross`** when you want *"an axis perpendicular to these two"* — torque axes, normals, right vectors, area.

## Handedness note

Cross-product *math* is the same regardless of coordinate convention — the components fall out of the formula identically. Handedness only affects *which direction in world space* the result points. This project is left-handed Metal-native (see `CLAUDE.md` → "Coordinate Conventions"), so `cross(fwd, up)` gives the **right** vector in pilot frame.

## Related

- `Float3+Extensions.swift` — project-local helpers
- `Math/Transform.swift` — canonical projection/view math
- See also: `projectOnPlane` helper in `F22.swift` (uses `dot` twice, no `cross`)
