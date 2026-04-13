# Plan: Switch to Left-Handed Metal-Native Coordinate Conventions

## Problem

The 3D rendering pipeline mixes OpenGL right-handed conventions (from `Math.swift`) with
Apple's left-handed Metal conventions (from `Transform.swift`, ported from Apple's deferred
lighting sample). This causes:

1. **Wrong projection depth range**: `Math.perspective()` maps z to [-1, 1] (OpenGL), but Metal
   clips to [0, 1]. Half the depth buffer is wasted and the effective near plane shifts from
   `near` to `~2*near*far/(near+far)`.
2. **Broken light culling (latent)**: The tile frustum planes in `LightCulling.metal` assume
   left-handed view space (+z forward), but the right-handed view matrix puts visible objects
   at negative z. Point/spot lights will be incorrectly culled once enabled.
3. **Camera3D view matrix bug**: Uses `R * T(-pos)` instead of the correct `R^T * T(-pos)`.
   Currently masked because `DebugCamera3D` overrides with `modelMatrix.inverse`.
4. **depthUnproject / screenToViewSpace formulas**: Derived for the right-handed projection;
   they happen to give correct values in isolation, but the frustum reconstruction in the
   shader mixes those values with left-handed plane normals -> wrong culling volumes.

## Goal

Adopt Metal's native left-handed conventions throughout:

- Camera looks down **+z**
- Projection maps depth to **[0, 1]** with `w_clip = +z_eye`
- `Transform.perspectiveProjection` (already in the codebase) becomes the single source of truth
- Light culling, depth unprojection, and screen-to-view all work as Apple's sample intended

## Scope

### Files to change

| File                  | Change                                                                       |
| --------------------- | ---------------------------------------------------------------------------- |
| `Camera3D.swift`      | Use `Transform.perspectiveProjection`; fix view matrix                       |
| `DebugCamera3D.swift` | Flip scroll-zoom sign                                                        |
| `Node.swift`          | `getFwdVector()`: return column 2 directly (no negation)                     |
| `Renderer3D.swift`    | No winding change needed (see Step 2 note)                                   |
| `GameScene.swift`     | Update `depthUnproject` formula for left-handed projection                   |
| `Math.swift`          | Fix projection and lookAt functions to left-handed; add comments             |
| `LightManager.swift`  | Fix `lightEyeDirection` sign                                                 |

### Files that need NO changes

| File                 | Why                                                           |
| -------------------- | ------------------------------------------------------------- |
| `Transform.swift`    | Already left-handed -- this is what we're switching TO        |
| `LightCulling.metal` | Already written for left-handed (from Apple sample)           |
| `ForwardPass.metal`  | Uses world-space positions for lighting -- convention-agnostic |
| `DepthPass.metal`    | Just `P * V * M * position` -- works with any convention      |
| `Cube.swift`         | MDLMesh geometry is convention-agnostic                       |
| `Shaders2D.metal`    | 2D pipeline is unaffected                                     |

---

## Step-by-step Changes

### Step 1: Projection -- `Camera3D.swift` and `Math.swift`

Replace both calls to `matrix_float4x4.perspective(...)` with
`Transform.perspectiveProjection(...)`. Note the Apple function takes **radians**, not degrees.

**Camera3D.swift -- Before:**

```swift
self.projectionMatrix = matrix_float4x4.perspective(degreesFov: fieldOfView,
                                                    aspectRatio: aspectRatio,
                                                    near: near,
                                                    far: far)
```

**Camera3D.swift -- After:**

```swift
self.projectionMatrix = Transform.perspectiveProjection(fieldOfView.toRadians,
                                                        aspectRatio,
                                                        near,
                                                        far)
```

Apply this in both `init` (line 27) and `setAspectRatio` (line 34).

Also fix the `Math.swift` `perspective()` function itself so it produces a correct
left-handed Metal projection (in case anything else calls it or it's used in
ToyFlightSimulator). Add a comment pointing to `Transform.perspectiveProjection` as the
canonical version.

**Math.swift `perspective()` -- Before (lines 114-132):**

```swift
static func perspective(degreesFov: Float, aspectRatio: Float, near: Float, far: Float) -> matrix_float4x4 {
    let fov = degreesFov.toRadians

    let t: Float = tan(fov / 2)

    let x: Float = 1 / (aspectRatio * t)
    let y: Float = 1 / t
    let z: Float = -((far + near) / (far - near))
    let w: Float = -((2 * far * near) / (far - near))

    var result = matrix_identity_float4x4
    result.columns = (
        float4(x,  0,  0,  0),
        float4(0,  y,  0,  0),
        float4(0,  0,  z, -1),
        float4(0,  0,  w,  0)
    )
    return result
}
```

**Math.swift `perspective()` -- After:**

```swift
/// Left-handed perspective projection for Metal (z maps to [0, 1], w_clip = +z_eye).
/// See also: Transform.perspectiveProjection (canonical version, takes radians).
static func perspective(degreesFov: Float, aspectRatio: Float, near: Float, far: Float) -> matrix_float4x4 {
    let fov = degreesFov.toRadians

    let t: Float = tan(fov / 2)

    let x: Float = 1 / (aspectRatio * t)
    let y: Float = 1 / t
    let z: Float = far / (far - near)
    let w: Float = -(near * far) / (far - near)

    var result = matrix_identity_float4x4
    result.columns = (
        float4(x, 0, 0, 0),
        float4(0, y, 0, 0),
        float4(0, 0, z, 1),
        float4(0, 0, w, 0)
    )
    return result
}
```

---

### Step 2: Front-face winding -- `Renderer3D.swift`

**No change needed.** Metal's default front-facing winding (`.clockwise`) is correct.

During implementation, we initially added `setFrontFacing(.counterClockwise)` based on
the assumption that ModelIO generates CCW-wound triangles. Testing showed this caused
front faces to be culled instead of back faces. The reason:

- **Imported mesh files** (`.obj`, `.usd`) from external tools use CCW winding (OpenGL
  convention) and DO need `setFrontFacing(.counterClockwise)`.
- **Programmatically generated meshes** via `MDLMesh(boxWithExtent:)` and similar
  ModelIO constructors produce CW-wound triangles that match Metal's default convention.

Since this project uses programmatic `MDLMesh` constructors (not imported files), Metal's
default `.clockwise` winding is already correct. If external model files are loaded in the
future, winding may need to be set per-draw-call or the mesh data re-wound at load time.

#### Background: Metal's winding conventions

Metal's default front-facing winding is `.clockwise`, matching DirectX conventions. This
makes Metal a natural porting target for DirectX content and game engines (Unity, Unreal).
When loading `.obj` or other OpenGL-convention mesh files via ModelIO, developers must
explicitly set `.counterClockwise` winding. Apple's own deferred lighting sample does this
because it loads asset files rather than generating meshes programmatically.

**Sources consulted:**

- [Metal Programming Guide: Render Command Encoder](https://developer.apple.com/library/archive/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/Render-Ctx/Render-Ctx.html) -- confirms Metal default is `MTLWindingClockwise`
- [MTLWinding -- Apple Developer Documentation](https://developer.apple.com/documentation/metal/mtlwinding)
- [DirectX Coordinate Systems (Microsoft Learn)](https://learn.microsoft.com/en-us/windows/win32/direct3d9/coordinate-systems) -- explains DirectX left-handed + CW convention
- [Metal by Tutorials, Chapter 2: 3D Models (Kodeco)](https://www.kodeco.com/books/metal-by-tutorials/v3.0/chapters/2-3d-models) -- confirms imported .obj files use CCW winding

---

### Step 3: Forward vector -- `Node.swift`

In left-handed convention, +z is forward. The model matrix's column 2 already points in the
local z direction -- stop negating it.

**Before (lines 155-158):**

```swift
func getFwdVector() -> float3 {
    let forward = modelMatrix.columns.2
    return normalize([-forward.x, -forward.y, -forward.z])
}
```

**After:**

```swift
func getFwdVector() -> float3 {
    return normalize(float3(modelMatrix.columns.2.x,
                            modelMatrix.columns.2.y,
                            modelMatrix.columns.2.z))
}
```

---

### Step 4: Camera view matrix -- `Camera3D.swift`

The current implementation has two problems: it uses `R` instead of `R^T`, and it builds a
right-handed view matrix. The simplest and most efficient fix is to use `modelMatrix.inverse`
-- exactly what `DebugCamera3D` already does.

`modelMatrix.inverse` is better here than manually computing `R^T * T(-pos)` with three dot
products because:

- It's a single SIMD operation (4x4 matrix inverse is well-optimized by simd)
- It's simpler code with no room for sign errors
- It's consistent with `DebugCamera3D`, avoiding two different view-matrix code paths
- It automatically handles any future changes to model matrix construction (e.g. if scale
  or parent transforms are added)

**Before (lines 40-45):**

```swift
override func updateModelMatrix() {
    super.updateModelMatrix()
    viewMatrix = matrix_identity_float4x4
    viewMatrix = matrix_multiply(viewMatrix, rotationMatrix)
    viewMatrix.translate(direction: -self.getPosition())
}
```

**After:**

```swift
override func updateModelMatrix() {
    super.updateModelMatrix()
    viewMatrix = modelMatrix.inverse
}
```

> **Note:** This is now identical to what `DebugCamera3D` does, which means
> `DebugCamera3D.updateModelMatrix()` no longer needs its own override for this line.
> However, `DebugCamera3D` still needs its override because it calls `super.updateModelMatrix()`
> to get the Camera3D behavior first. No change needed in `DebugCamera3D.updateModelMatrix()`.

---

### Step 5: Debug camera scroll direction -- `DebugCamera3D.swift`

With +z now being forward (into the screen), scrolling to zoom in should move in +z.

**Before (line 64):**

```swift
self.moveZ(-Mouse.GetDWheel() * 0.1)
```

**After:**

```swift
self.moveZ(Mouse.GetDWheel() * 0.1)
```

---

### Step 6: Scene initial camera positions

Camera at `(0, 0, 5)` looking down +z now faces AWAY from objects at the origin. Move
cameras to negative z so they look toward the origin.

**`TestScene3D.swift` (line 25):**

```swift
// Before:
camera.setPosition(0, 0, 5)
// After:
camera.setPosition(0, 0, -5)
```

**`ConwaysGameOfLife3DScene.swift` (line 32):**

```swift
// Before:
camera.setPosition(0, 0, 5)
// After:
camera.setPosition(0, 0, -5)
```

---

### Step 7: Depth unprojection -- `GameScene.swift`

The formula changes for the left-handed projection. Derive:

```
Left-handed projection:
  P[2][2] = far / (far - near)          (= zs)
  P[3][2] = -near * far / (far - near)  (= -near * zs)

  z_ndc = (z_eye * zs - near * zs) / z_eye = zs - near*zs/z_eye
  depth = zs - near*zs / z_eye
  z_eye = near * zs / (zs - depth)
        = -P[3][2] / (P[2][2] - depth)
        = P[3][2] / (depth - P[2][2])
```

So `depthUnproject = (P[2][2], P[3][2])` and the shader formula
`depthUnproject.y / (depth - depthUnproject.x)` works WITHOUT changes to
`LightCulling.metal`.

**Before (lines 116-118):**

```swift
// Depth unprojection: derives view-space Z from depth buffer value
// z_view = -P32 / (depth + P22), so depthUnproject = (-P22, -P32)
_sceneConstants.depthUnproject = float2(-camera.projectionMatrix[2][2],
                                         -camera.projectionMatrix[3][2])
```

**After:**

```swift
// Depth unprojection (left-handed): z_view = P32 / (depth - P22)
// Ship as depthUnproject = (P22, P32) so shader computes depthUnproject.y / (depth - depthUnproject.x)
_sceneConstants.depthUnproject = float2(camera.projectionMatrix[2][2],
                                         camera.projectionMatrix[3][2])
```

The `screenToViewSpace` calculation (lines 120-125) does NOT need to change -- `P00` and
`P11` have the same values in both conventions.

---

### Step 8: Light eye direction -- `LightManager.swift`

The negation of the light position was a right-handed convention artifact (forward = -z, so
negate to get direction toward origin). In left-handed convention, direction toward origin
from a positive-z light is just `normalize(origin - lightPos)`.

**Before (line 45):**

```swift
data.lightEyeDirection = normalize(viewMatrix * float4(-obj.getPosition(), 1)).xyz
```

**After:**

```swift
data.lightEyeDirection = normalize(viewMatrix * float4(obj.getPosition(), 1)).xyz
```

> **Note:** `lightEyeDirection` isn't currently used in any shader -- the forward pass
> computes light direction per-fragment from `worldPosition`. But this fixes it for future use.

---

### Step 9: Fix remaining `Math.swift` functions

Fix the other OpenGL-style right-handed functions to use left-handed Metal conventions.
Add comments pointing to the equivalent `Transform` functions for potential future
deprecation.

**`perspectiveProjectionFoVY` (lines 249-263) -- Before:**

```swift
init(perspectiveProjectionFoVY fovYRadians: Float,
     aspectRatio: Float,
     near: Float,
     far: Float)
{
    let sy = 1 / tan(fovYRadians * 0.5)
    let sx = sy / aspectRatio
    let zRange = far - near
    let sz = -(far + near) / zRange
    let tz = -2 * far * near / zRange
    self.init(SIMD4<Float>(sx, 0,  0,  0),
              SIMD4<Float>(0, sy,  0,  0),
              SIMD4<Float>(0,  0, sz, -1),
              SIMD4<Float>(0,  0, tz,  0))
}
```

**After:**

```swift
/// Left-handed perspective projection for Metal (z maps to [0, 1], w_clip = +z_eye).
/// See also: Transform.perspectiveProjection (canonical version).
init(perspectiveProjectionFoVY fovYRadians: Float,
     aspectRatio: Float,
     near: Float,
     far: Float)
{
    let sy = 1 / tan(fovYRadians * 0.5)
    let sx = sy / aspectRatio
    let sz = far / (far - near)
    let tz = -(near * far) / (far - near)
    self.init(SIMD4<Float>(sx, 0,  0, 0),
              SIMD4<Float>(0, sy,  0, 0),
              SIMD4<Float>(0,  0, sz, 1),
              SIMD4<Float>(0,  0, tz, 0))
}
```

**`lookAt` (lines 224-232) -- Before:**

```swift
init(lookAt at: SIMD3<Float>, from: SIMD3<Float>, up: SIMD3<Float>) {
    let zNeg = normalize(at - from)
    let x = normalize(cross(zNeg, up))
    let y = normalize(cross(x, zNeg))
    self.init(SIMD4<Float>(x, 0),
              SIMD4<Float>(y, 0),
              SIMD4<Float>(-zNeg, 0),
              SIMD4<Float>(from, 1))
}
```

**After:**

```swift
/// Left-handed look-at: builds a model matrix placing the camera at `from`, looking toward `at`.
/// See also: Transform.look(eye:target:up:) (canonical version, returns a view matrix directly).
init(lookAt at: SIMD3<Float>, from: SIMD3<Float>, up: SIMD3<Float>) {
    let z = normalize(at - from)
    let x = normalize(cross(up, z))
    let y = cross(z, x)
    self.init(SIMD4<Float>(x, 0),
              SIMD4<Float>(y, 0),
              SIMD4<Float>(z, 0),
              SIMD4<Float>(from, 1))
}
```

Key changes to `lookAt`:
- Cross product order flips from `cross(zNeg, up)` to `cross(up, z)` for left-handed
- Column 2 stores `z` directly instead of `-zNeg` (forward = +z in left-handed)
- The `y` axis uses `cross(z, x)` to maintain left-handed orthogonal frame

---

## Verification Checklist

After all changes, verify:

- [ ] Build succeeds for macOS, iOS, tvOS targets
- [ ] Cubes render with correct perspective (near face larger than far face)
- [ ] DebugCamera3D: scroll wheel zooms in/out correctly
- [ ] DebugCamera3D: mouse drag rotates view correctly
- [ ] DebugCamera3D: middle-mouse pans correctly
- [ ] Depth buffer spans full [0, 1] range (not [-1, 1] clamped)
- [ ] Back-face culling works (only 3 faces of cube visible at a time, not 6)
- [ ] Lighting looks correct (directional light shading, ambient contribution)
- [ ] 3D Game of Life grid renders with cubes visible and properly spaced
- [ ] No z-fighting or near-plane clipping artifacts at normal viewing distances

---

## Porting Guide for ToyFlightSimulator

The same Math.swift / Transform.swift / Camera code is shared between Automata and
ToyFlightSimulator. Here's what to look for when applying this fix there:

### Shared code to find and fix

1. **`matrix_float4x4.perspective()`** -- Search for all callers. Replace with
   `Transform.perspectiveProjection()` (radians, not degrees). Also fix the function itself
   to left-handed conventions (see Step 1). If ToyFlightSimulator doesn't have
   `Transform.swift` from Apple's sample, copy in the `perspectiveProjection` function.

2. **`getFwdVector()`** -- Search in Node.swift or equivalent base class. If it negates column
   2, remove the negation. This is the single most impactful change for left-handed.

3. **`setCullMode(.back)`** -- If using imported mesh files (`.obj`, `.usd`), add
   `setFrontFacing(.counterClockwise)` before it. If using programmatic `MDLMesh`
   constructors, Metal's default `.clockwise` winding is already correct.

4. **Camera view matrix** -- Search for `matrix_multiply(viewMatrix, rotationMatrix)` followed
   by `translate(direction: -self.getPosition())`. Replace with `modelMatrix.inverse`.

5. **Scroll/zoom sign** -- Search for `moveZ(-` patterns. The sign may need to flip.

6. **Scene camera positions** -- Search for `camera.setPosition(...)`. If the camera was
   placed at positive z looking toward -z, flip to negative z.

7. **`depthUnproject`** -- Search for `-camera.projectionMatrix[2][2]`. Remove the negations:
   pass `P[2][2]` and `P[3][2]` directly.

8. **Light direction negation** -- Search for `float4(-obj.getPosition()`. Remove the negation.

9. **OpenGL-style functions in Math.swift** -- Search for `perspectiveProjectionFoVY`,
   `lookAt at:from:up:` (the one with `-zNeg` in column 2). Fix these to left-handed
   conventions (see Steps 1 and 9).

### Quick grep patterns for ToyFlightSimulator

```bash
# Find the OpenGL projection:
grep -rn "perspective(degreesFov\|perspectiveProjectionFoVY" --include="*.swift"

# Find forward vector negation:
grep -rn "\-forward\.\|forward\.x, -forward" --include="*.swift"

# Find right-handed camera setup:
grep -rn "translate(direction: -self" --include="*.swift"

# Find scroll zoom sign:
grep -rn "moveZ(-" --include="*.swift"

# Find depth unprojection:
grep -rn "depthUnproject\|projectionMatrix\[2\]\[2\]" --include="*.swift"

# Find light direction negation:
grep -rn "float4(-obj\|float4(-.*getPosition" --include="*.swift"

# Find winding/culling:
grep -rn "setCullMode\|setFrontFacing" --include="*.swift"
```

### Key principle

The fix is **convention-consistent**, not piecemeal. All of these changes must be applied
together. Changing just the projection without the winding flag will make all geometry
invisible. Changing just the forward vector without the camera position will point cameras
the wrong way. Apply all steps as a unit and verify with the checklist.
