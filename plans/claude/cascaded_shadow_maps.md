# Cascaded Shadow Maps (CSM) — Clean Implementation Plan

## Context

The repo currently runs the single-cascade sun-follow shadow camera from [`single_cascade_sun_following_shadow_camera.md`](single_cascade_sun_following_shadow_camera.md). One 8192² depth map is fit to a `2 * shadowRadius` square around the main camera each frame. That ships, but it has three structural problems:

1. **Uniform texel density across the entire covered region.** Shadows under the F-22 are at the same resolution as shadows at the radius edge. The visible compromise: pick a small radius (~500) → sharp under-jet shadows but distant casters fall off entirely; pick a large radius (~5000) → distant shadows appear but the F-22's silhouette becomes texel-aliased.
2. **Hard cutoff at `radius`.** Anything past it reads `1.0` (fully lit) by the sampler-edge guard. Distant casters cast no shadow at all.
3. **Texel swimming during steady flight.** No texel-aligned snap on the shadow projection.

CSM is the standard solution: split the camera frustum into N depth ranges and render a separate, tightly-fit shadow map per range. Sharp near, coverage far. That's Stage 1. Stage 2 attacks the swimming.

This plan does not start from scratch — there's a prior debugging journey on the `csm1` branch ([summary](../../debugging/claude/csm_journey_summary.md)) that landed a working implementation through several non-obvious diagnostic detours. This plan extracts the **minimal correct change set** from that journey, validates each load-bearing decision against external references, and adds a Stage 2 anti-swimming step the prior branch never reached. Old debugging notes, screenshots, and the prior plan should not be brought forward — they pollute history without helping the next reader.

Branch: `csm`, cut fresh from `main` (which already contains the working single-cascade sun-follow path that CSM extends).

---

## Outcome

After Stage 1 ships:

- 4 cascades, 4096² each (`depth32Float`, texture2DArray), total 256 MB — same as pre-CSM single 8192² map.
- F-22 self-shadow stays crisp at any reachable world coordinate (validated up to `cam_world ≈ (10K, 5.9, 22K)` on the `csm1` branch).
- F-22 cast-shadow on ground stays sharp at the same coords.
- Static-geometry shadow edges don't visibly swim during steady flight (texel snap working).
- Distant casters out to ~500 world units produce visible shadows (Microsoft "Practical Split Scheme" with lambda=0.5).
- All four renderers continue to work (TiledDeferred, TiledMultisample, TiledMSAATessellated, SinglePassDeferredLighting).

After Stage 2 ships:

- Animated-geometry edge swim (currently visible on the F-22 control surfaces during steady flight) is reduced to below the eye's discrimination threshold via wider PCF + cascade blending.
- Cascade-boundary seams (visible resolution-change lines) eliminated by 10% cascade-blend band.
- Optional: EVSM-based path is offered as a follow-on for users who want filterable shadows (out of scope for this plan but architecturally enabled).

---

## Critical Files

### Created

- **NEW** `ToyFlightSimulator Shared/Shadows/ShadowCascadeFitting.swift` — PSSM splits + bounding-sphere fit + world-space texel snap.

### Moved

- `ToyFlightSimulator Shared/GameObjects/ShadowCamera.swift` → `ToyFlightSimulator Shared/Shadows/ShadowCamera.swift` (and extended with the cascade-fit initializer).

### Modified

- `ToyFlightSimulator Shared/GameObjects/LightObject.swift` — replace `updateShadowCamera` with `updateShadowCascades`; add cascade knobs.
- `ToyFlightSimulator Shared/Graphics/Shaders/TFSCommon.h` — `TFS_MAX_SHADOW_CASCADES`, `TFSBufferIndexShadowCascadeVP`, cascade arrays on `LightData`.
- `ToyFlightSimulator Shared/Graphics/Shaders/Lighting.metal` — cascade-aware `CalculateShadow` / `CalculateShadowMSAA`, plus `SelectCascade`, `SlopeScaledWorldBias`, `NDCShadowEpsilon`, 3×3 hardware-PCF kernel.
- `ToyFlightSimulator Shared/Graphics/Shaders/Shadow.metal` — both shadow vertex functions consume per-pass cascade VP at the new push-constant slot.
- `ToyFlightSimulator Shared/Graphics/Shaders/ShaderDefinitions.h` — `VertexOut` loses `shadowPosition` (the fragment now computes shadow position from the cascade-selected matrix).
- `ToyFlightSimulator Shared/Graphics/Shaders/TiledDeferredGBuffer.metal` — fragment binds `SceneConstants`, recomputes `fragViewSpaceDepth` per-fragment.
- `ToyFlightSimulator Shared/Graphics/Shaders/TiledMSAAGBuffer.metal` — same per-fragment recomputation pattern.
- `ToyFlightSimulator Shared/Graphics/Shaders/GBuffer.metal` — same per-fragment recomputation pattern (both `gbuffer_fragment_base` and `gbuffer_fragment_material`).
- `ToyFlightSimulator Shared/Graphics/Shaders/TiledDeferredTransparency.metal` — vertex shader drops `shadowPosition` write.
- `ToyFlightSimulator Shared/Graphics/Shaders/SinglePassDeferredTransparency.metal` — same.
- `ToyFlightSimulator Shared/Scenes/GameScene.swift` — `setSceneConstants` binds both vertex AND fragment.
- `ToyFlightSimulator Shared/Display/Protocols/ShadowRendering.swift` — `shadowMap` becomes `texture2DArray`; descriptor becomes an array; pass encoders iterate over cascades and bind the per-pass cascade VP.
- All four renderers conforming to `ShadowRendering` (`TiledDeferredRenderer`, `TiledMultisampleRenderer`, `TiledMSAATessellatedRenderer`, `SinglePassDeferredLightingRenderer`) — adopt the new texture/descriptor shape and pass binding.

---

## Reused Existing Infrastructure

- `Transform.orthographicProjection` — left-handed, forward-Z. Suitable for ortho shadow projections; reverse-Z is not pursued (see § Investigation > Reverse-Z).
- `Transform.look(eye:target:up:)` — used as-is for light-view construction.
- `Y_AXIS` — `up` for light view, with a documented fallback when `lightDirection` is parallel to Y.
- `CameraManager.CurrentCamera` — optional; guarded everywhere.
- `Camera.viewMatrix.inverse` — used to derive frustum-corner world positions per slice.
- `SceneConstants.cameraPosition` — already populated each frame; bound to fragments in this plan.
- Existing `Lighting::CalculateDirectionalLighting` (uses `light.direction`) — unchanged.

---

# Investigation Summary — What the Two-Day Detour Validated

Before laying out the diffs, here's what the prior journey conclusively proved (and the external references that corroborate each point). These shape the Stage 1 design.

| Finding | Why it's load-bearing | External validation |
|---|---|---|
| **Bounding-sphere fit, not AABB-of-corners** | AABB-of-corners has a rotation-dependent extent — a camera spin alone changes texel size 60% frame-to-frame. Texel snap can't stabilize on top of that. | Valient's Killzone 2 algorithm via [Long Forgotten Blog: Stable CSM](http://longforgottenblog.blogspot.com/2014/12/rendering-post-stable-cascaded-shadow.html); endorsed by [Theomader's Stable CSM](https://dev.theomader.com/stable-csm/) and MJP. |
| **Texel snap in world space, not light-view space** | The light-view basis is *derived from* the value being snapped, so `floor(0/texelSize) * texelSize = 0` — the snap is a no-op if done in light view. World-space snap operates on a frame-independent basis. | MS DX docs ["Moving the light in texel sized increments"](https://learn.microsoft.com/en-us/windows/win32/dxtecharts/common-techniques-to-improve-shadow-depth-maps): "snap the projection bounds in light space to shadow map texel sized increments." The math works in either space *provided the basis itself is stable*; world-axis projection is the simplest stable basis. |
| **Per-fragment `viewSpaceDepth = distance(worldPos, cameraPos)`** (not per-vertex) | Per-vertex `fabs(eyePos.z)` loses sign across near-plane straddling triangles → mixed-sign-clip.w pathology in perspective-correct interpolation → ground fragments under camera report 200K instead of ~5. Per-vertex `distance(worldPos, cameraPos)` is non-linear in eye space → rasterizer interpolates incorrectly. Per-fragment compute uses already-linearly-interpolated `worldPosition`, then a Sterbenz-exact subtraction for visible fragments. | Standard perspective-correct interpolation theory (see [Outerra: Depth Buffer Range](https://outerra.blogspot.com/2012/11/maximizing-depth-buffer-range-and.html), [CornellU "Tightening Precision"](https://www.cs.cornell.edu/~paulu/tightening.pdf)). The journey doc's iteration sequence reads as a textbook proof that this is the only correct shape of the fix. |
| **Cap shadow-fitting far at `_shadowMaxDistance`, not `cam.far`** | Flight-sim cameras need huge `cam.far` (1M+) for horizon rendering. Naive PSSM splits over [near, 1M] produce cascade-0 widths in the hundreds of thousands of world units → individual texels cover hundreds of world units → F-22 (~30 world units) is smaller than one texel → no F-22 shadow. | MS CSM docs note: "When most of the geometry is clumped into a small section (such as an overhead view or a flight simulator) of the view frustum, fewer cascades are necessary" — and explicitly recommend tight near/far for the *shadow* sub-frusta independently of the main camera. |
| **Account for camera scale in cascade radius** | The default `AttachedCamera` is parented to an aircraft with `setScale(3.0)`, so the camera's view matrix has 1/3 scale baked in. Cascade radius computed from view-space slice dimensions is in *scaled* units; cascade center from `cameraInverse * eyePoint` is in *world* units. Mixing them makes the cascade ortho 3× too small for the area it's centered on. | Confirmed by direct test on `csm1`: F-22 disappears from its own cascade without the scale fix. Not surfaced in any external CSM reference I found because most engines normalize camera scale to 1.0 — the bug is specific to attached-camera flight-sim setups. |
| **PSSM "Practical Split Scheme" with λ=0.5** | Pure logarithmic splits collapse cascade 0 to near-zero width near `near=0.01`; pure uniform splits waste resolution near the eye. The hybrid `splitFar_i = uniform_i * (1-λ) + log_i * λ` with λ=0.5 hits the sweet spot. | [Microsoft CSM docs](https://learn.microsoft.com/en-us/windows/win32/dxtecharts/cascaded-shadow-maps), originally proposed by Engel in ShaderX5 (2006) and standardized by Microsoft's CSM sample. |
| **Interval-based cascade selection (vs map-based)** | Direct view-space-depth comparison against precomputed split depths. Faster than map-based (which intersects texcoord with cascade bounds). | [Microsoft CSM docs](https://learn.microsoft.com/en-us/windows/win32/dxtecharts/cascaded-shadow-maps): "Interval-based selection is slightly faster than map-based selection because the cascade selection can be done directly." |
| **3×3 hardware-PCF kernel** | 9 calls to `sample_compare` with `filter::linear` on a `depth2d_array`. Each call uses the hardware bilinear filter to interpolate the depth-compare result across a 2×2 texel quad, so the effective kernel is closer to 4×4 weighted. Smooths sub-texel rasterization changes (the main lever for animated-geometry swim mitigation). | [MJP "Shadow Techniques"](https://therealmjp.github.io/posts/shadow-maps/): "going from 2x2 PCF to 7x7 PCF only adds about 0.4ms" on modern GPUs via `GatherCmp`. Apple Metal's `sample_compare` with `filter::linear` is the equivalent path. |
| **Slope-scaled world-space bias** | A single flat slack tuned for ground gets acne on F-22 rudders (nearly parallel to overhead sun). Slope-scaled bias gives ground low slack, near-vertical surfaces up to ~21× more. | MS ["Common Techniques to Improve Shadow Depth Maps"](https://learn.microsoft.com/en-us/windows/win32/dxtecharts/common-techniques-to-improve-shadow-depth-maps) "Slope-Scale Depth Bias." Confirmed by direct test on `csm1`. |

### Investigation > Reverse-Z

The `csm1` plan considered but rejected reverse-Z for shadows. Reverse-Z is dramatically beneficial for **perspective** depth buffers because it pairs the non-uniform 1/z distribution with the non-uniform float exponent distribution — concentrating precision where it's actually needed. **Orthographic** depth is already linear in view-space z; the float exponent doesn't buy you anything orthographic. [Outerra](https://outerra.blogspot.com/2012/11/maximizing-depth-buffer-range-and.html) explicitly notes the technique only addresses perspective projections. Skip it.

### Investigation > SDSM / Sample Distribution Shadow Maps

[SDSM](https://dl.acm.org/doi/10.1145/1944745.1944761) (Lauritzen et al., 2011) auto-fits cascade splits by reading the main depth buffer's min/max and partitioning *that* range, instead of using fixed PSSM splits over `[near, far]`. Higher quality for the same texel budget — especially at oblique angles where the depth distribution is skewed. **Decision: out of scope for Stage 1.** It requires a GPU min/max depth reduction pass before shadow generation, which doesn't fit cleanly into the existing render pipeline. Listed as a future enhancement.

### Investigation > VSM / EVSM / MSM (filterable shadow maps)

[EVSM](https://lousodrome.net/blog/light/tag/evsm/) and [Moment Shadow Maps](https://github.com/timurson/MomentShadowMapping) store summary statistics (e.g., depth and depth²) instead of raw depth, and use Chebyshev's inequality to estimate occlusion. The shadow map can then be linearly filtered (bilinear, anisotropic, mipmaps) which dramatically reduces swim for animated geometry. **Decision: out of scope for Stage 1.** They change the shadow-gen pipeline substantially (different render target format, blur passes, light bleeding mitigation). Listed as a future Stage-3 enhancement worth pursuing if Stage 2's PCF widening isn't enough.

### Investigation > PCSS (Percentage Closer Soft Shadows)

[PCSS](https://developer.download.nvidia.com/shaderlibrary/docs/shadow_PCSS.pdf) varies the PCF kernel size based on a blocker-search step that approximates penumbra width. Physically-plausible soft shadows but expensive: ~25 blocker-search taps + ~25 PCF taps per fragment. **Decision: out of scope.** Stage 1's directional sun barely justifies PCSS; better suited to local lights.

### Investigation > Camera-relative rendering / floating origin

The journey doc validated that for the current flight extent (jets fly to ~22K world units from origin, ground spans ±500K), per-fragment `distance(worldPos, cameraPos)` is sufficient — the Sterbenz-exact subtraction at the visible-fragment scale eliminates the precision problem. **Camera-relative rendering** ([Babylon.js docs](https://doc.babylonjs.com/features/featuresDeepDive/scene/floating_origin/), [Flax Large Worlds](https://docs.flaxengine.com/manual/editor/large-worlds/index.html)) becomes necessary at planetary scale (millions to billions of world units), where even per-fragment world coordinates lose precision. **Decision: out of scope** — TFS's scales don't require it. Document it as an enhancement *only if* the simulator grows toward planetary coordinates.

### Investigation > Animated geometry swimming (the unsolved problem)

This is the remaining swim the `csm1` branch acknowledged as the final outstanding artifact, and it's what Stage 2 targets. [MJP](https://therealmjp.github.io/posts/shadow-maps/) is explicit: "Standard 'stabilization' techniques for cascade shadow maps only fix flickering for completely static geometry." The mechanism: skinning + per-frame F-22 animator updates → vertex positions move sub-pixel from frame to frame → those vertices rasterize into different shadow texels → the comparison threshold flips → shadow edges shimmer. Three independent levers (in order of cost/reward):

1. **Wider PCF kernel** (cheap, ~1 ms): from 3×3 to 5×5 or 7×7 hardware-PCF. Hardware filter sub-texel-averages the comparison result, smoothing the threshold flip below the eye's discrimination threshold. MJP measured 7×7 PCF at +0.4ms on a 2013 GPU; modern Apple Silicon should be sub-half-ms.
2. **Cascade blending at boundaries** (moderate, ~0.3 ms): blend cascade i and i+1 in the last 10% of each cascade's range. Eliminates the visible resolution-change seam that magnifies swim perception.
3. **Pre-filtering (EVSM/MSM)** (substantial rewrite): hardware-filterable shadows. Highest quality, biggest implementation cost. Not in this plan.

Stage 2 implements (1) and (2). Stage 3 (out of scope here) would be EVSM if (1)+(2) prove insufficient.

---

# Stage 1 — Minimal Correct CSM Implementation

## 1. Create the `Shadows/` folder

New folder `ToyFlightSimulator Shared/Shadows/`. Both `ShadowCamera.swift` (moved from `GameObjects/`) and `ShadowCascadeFitting.swift` (new) live here. The Xcode project file needs the new group/folder entry under the `ToyFlightSimulator Shared` group; both the macOS and iOS targets need the two files added to their `Sources` build phase.

## 2. `Shadows/ShadowCamera.swift` (moved from `GameObjects/`, extended)

Keep the existing legacy initializer (single-cascade sun-follow fast path) so the cascade refactor is opt-in per `LightObject`. Add a cascade-fit initializer that takes the pre-computed light view and ortho bounds directly.

```swift
//
//  ShadowCamera.swift
//  ToyFlightSimulator
//

import MetalKit

/// Per-frame "synthesis camera" used to render a directional light's shadow map.
/// Generalized to either single-cascade sun-follow (legacy) or per-cascade CSM
/// (new). The cascade-fit initializer accepts the lightView and ortho bounds
/// already computed by `ShadowCascadeFitting`.
struct ShadowCamera {
    let viewMatrix:       float4x4
    let projectionMatrix: float4x4
    /// Far − near of the ortho frustum, in world units. Used by the shader's
    /// depth-compare epsilon: NDC epsilon = worldSlack / depthRange.
    let depthRange:       Float

    var viewProjectionMatrix: float4x4 { projectionMatrix * viewMatrix }

    /// Legacy single-cascade sun-follow constructor (existing call sites).
    init(direction: float3, focus: float3, radius: Float, lift: Float) {
        let eye = focus + direction * lift
        self.viewMatrix = Transform.look(eye: eye, target: focus, up: Y_AXIS)
        let near: Float = 1
        let far:  Float = 2 * lift
        self.projectionMatrix = Transform.orthographicProjection(-radius, radius,
                                                                 -radius, radius,
                                                                 near, far)
        self.depthRange = far - near
    }

    /// Cascade-fit constructor (CSM). lightView and ortho bounds come from
    /// `ShadowCascadeFitting.fitCascades`.
    init(lightView: float4x4,
         orthoMinX: Float, orthoMaxX: Float,
         orthoMinY: Float, orthoMaxY: Float,
         orthoNearZ: Float, orthoFarZ: Float) {
        self.viewMatrix = lightView
        self.projectionMatrix = Transform.orthographicProjection(
            orthoMinX, orthoMaxX,
            orthoMinY, orthoMaxY,
            orthoNearZ, orthoFarZ)
        self.depthRange = orthoFarZ - orthoNearZ
    }
}
```

## 3. `Shadows/ShadowCascadeFitting.swift` (new)

The PSSM split scheme, the bounding-sphere fit, and the world-space texel snap, all in one file. Each is small and benefits from being read top-to-bottom.

```swift
//
//  ShadowCascadeFitting.swift
//  ToyFlightSimulator
//

import simd

enum ShadowCascadeFitting {

    // MARK: - PSSM "Practical Split Scheme" (Microsoft / Engel ShaderX5)
    //
    // splitFar_i = uniform_i * (1 - λ) + log_i * λ
    //   uniform_i = near + (far - near) * (i + 1) / N
    //   log_i     = near * (far / near) ^ ((i + 1) / N)
    //
    // λ=0 → uniform (waste near, good far); λ=1 → logarithmic (degenerate near 0
    // when `near` is very small); λ=0.5 hits the sweet spot for typical scenes.
    //
    // Returns N split *far* depths, with split 0's near being the camera's near.
    static func computeSplits(near: Float, far: Float,
                              cascadeCount: Int, lambda: Float) -> [Float] {
        precondition(cascadeCount >= 1)
        precondition(near > 0 && far > near)
        let n = Float(cascadeCount)
        var splits: [Float] = []
        splits.reserveCapacity(cascadeCount)
        for i in 0..<cascadeCount {
            let p = Float(i + 1) / n
            let uniform = near + (far - near) * p
            let log     = near * powf(far / near, p)
            splits.append(uniform * (1 - lambda) + log * lambda)
        }
        return splits
    }

    // MARK: - Bounding sphere of a frustum slice
    //
    // Why a sphere, not an AABB of the 8 frustum corners: the sphere's radius
    // depends only on FOV/aspect/slice-near/slice-far — *not* on the camera's
    // rotation. As the camera spins, AABB extents change because the corners
    // rotate through the AABB; a sphere is rotation-invariant. Without this,
    // texel snap can't hold a stable edge (Valient / Killzone 2; see
    // longforgottenblog "Stable CSM").
    //
    // The center is the midpoint of the slice along the camera's forward axis,
    // transformed to world by the camera's inverse view matrix. The radius is
    // computed in view space then scaled by the camera's world scale (the
    // `AttachedCamera` is parented to a scale-3 aircraft, so view-space units
    // are 1/3 of world units — see csm_journey_summary.md Fix 2).
    static func boundingSphereForSlice(cameraInverse: float4x4,
                                       fovYRadians: Float,
                                       aspect: Float,
                                       sliceNear: Float,
                                       sliceFar: Float)
                                       -> (centerWorld: float3, radius: Float) {
        let midZ        = (sliceNear + sliceFar) * 0.5
        let halfRangeZ  = (sliceFar  - sliceNear) * 0.5
        let tanHalfFov  = tanf(fovYRadians * 0.5)
        let farHalfH    = sliceFar * tanHalfFov
        let farHalfW    = farHalfH * aspect

        let radiusView  = sqrtf(halfRangeZ * halfRangeZ
                              + farHalfH   * farHalfH
                              + farHalfW   * farHalfW)

        // Pull world scale from the first column of the inverse view matrix.
        // Inverse-view's columns are the world-space camera basis vectors;
        // their length equals the parent node chain's accumulated scale.
        let c0 = cameraInverse.columns.0
        let cameraScale = simd_length(simd_float3(c0.x, c0.y, c0.z))
        let radius = radiusView * cameraScale

        let centerWorld4 = cameraInverse * float4(0, 0, midZ, 1)
        return (float3(centerWorld4.x, centerWorld4.y, centerWorld4.z), radius)
    }

    // MARK: - Per-cascade fit (sphere + world-space snap)
    //
    // Returns N ShadowCameras (one per cascade) plus the per-cascade split
    // far-depths in world units (for the shader's interval-based cascade
    // selection).
    struct CascadeFit {
        let cascades:   [ShadowCamera]
        let splitFars:  [Float]   // world-space depth per cascade (far)
    }

    static func fitCascades(camera: CameraSnapshot,
                            lightDirection: float3,
                            shadowMapResolution: Int,
                            cascadeCount: Int,
                            lambda: Float,
                            shadowMaxDistance: Float,
                            zPaddingWorldUnits: Float)
                            -> CascadeFit {
        precondition(cascadeCount >= 1)

        // Cap the cascade-fitting far. The flight-sim main camera has `far`
        // in the millions to render the horizon; running PSSM over [near, far]
        // collapses cascade 0 to hundreds of thousands of world units wide.
        // Decouple shadow reach from sky reach (see csm_journey_summary.md Fix 1).
        let near = camera.near
        let far  = min(camera.far, shadowMaxDistance)
        let splitFars = computeSplits(near: near, far: far,
                                      cascadeCount: cascadeCount,
                                      lambda: lambda)

        let cameraInverse = camera.viewMatrix.inverse

        var cascades: [ShadowCamera] = []
        cascades.reserveCapacity(cascadeCount)

        var prevFar = near
        for i in 0..<cascadeCount {
            let sliceFar = splitFars[i]
            let (sphereCenter, radius) = boundingSphereForSlice(
                cameraInverse: cameraInverse,
                fovYRadians:   camera.fovY,
                aspect:        camera.aspect,
                sliceNear:     prevFar,
                sliceFar:      sliceFar)
            prevFar = sliceFar

            // World-space light basis. Stable across frames because it depends
            // only on `lightDirection` (constant for the directional sun) and
            // the global `up = Y_AXIS`. Degenerate when light is exactly
            // overhead — fall back to world +X.
            let zWorld = -lightDirection // light looks toward focus along -direction
            var xCandidate = simd_cross(Y_AXIS, zWorld)
            if simd_length_squared(xCandidate) < 1e-6 {
                xCandidate = simd_cross(float3(1, 0, 0), zWorld)
            }
            let xWorld = simd_normalize(xCandidate)
            let yWorld = simd_cross(zWorld, xWorld)

            // World-space texel snap. World units per texel for this cascade.
            let texelSize = (2 * radius) / Float(shadowMapResolution)

            // Project sphereCenter onto (xWorld, yWorld); snap those scalar
            // projections to integer multiples of texelSize; reapply as a
            // world-space shift. Light view is built around the snapped center.
            // Snap MUST be in world space — doing it in light view evaluates
            // to a no-op because the snap's frame of reference is itself
            // derived from the value being snapped (csm_journey_summary.md Fix 4).
            let projX = simd_dot(xWorld, sphereCenter)
            let projY = simd_dot(yWorld, sphereCenter)
            let snappedProjX = floor(projX / texelSize) * texelSize
            let snappedProjY = floor(projY / texelSize) * texelSize
            let shift = (snappedProjX - projX) * xWorld
                      + (snappedProjY - projY) * yWorld
            let snappedCenter = sphereCenter + shift

            // Light view: eye at center + direction (so we look "down" toward
            // surfaces), target the snapped center.
            let eye = snappedCenter + lightDirection * radius
            let lightView = Transform.look(eye: eye,
                                           target: snappedCenter,
                                           up: Y_AXIS)

            // Ortho extents in light view: [-radius, +radius] on X/Y, with
            // additive z-padding so casters slightly outside the sphere still
            // fit. Multiplicative padding (the LearnOpenGL `zMult = 10` trick)
            // blows up when the AABB straddles 0; additive is bounded.
            let halfExtent = radius
            let nearZ: Float = 0 - zPaddingWorldUnits
            let farZ:  Float = 2 * radius + zPaddingWorldUnits

            cascades.append(ShadowCamera(
                lightView:  lightView,
                orthoMinX: -halfExtent, orthoMaxX: halfExtent,
                orthoMinY: -halfExtent, orthoMaxY: halfExtent,
                orthoNearZ: nearZ,      orthoFarZ: farZ))
        }

        return CascadeFit(cascades: cascades, splitFars: splitFars)
    }

    /// Minimal value-type snapshot of what `fitCascades` reads from the camera.
    /// Avoids passing the whole `Camera` class (which would create a coupling
    /// the Shadows folder doesn't deserve).
    struct CameraSnapshot {
        let viewMatrix: float4x4
        let near:       Float
        let far:        Float
        let fovY:       Float
        let aspect:     Float
    }
}
```

## 4. `Graphics/Shaders/TFSCommon.h` — `LightData` schema

### Before (relevant excerpt)

```c
typedef struct {
    LightType type;
    matrix_float4x4 modelMatrix;
    matrix_float4x4 viewProjectionMatrix;
    matrix_float4x4 shadowViewProjectionMatrix;
    matrix_float4x4 shadowTransformMatrix;
    simd_float3 direction;
    simd_float3 lightEyeDirection;
    simd_float3 position;
    simd_float3 color;
    float brightness;
    float radius;
    simd_float3 attenuation;
    float ambientIntensity;
    float diffuseIntensity;
    float specularIntensity;
    float shadowDepthRange;
    float shadowWorldSlack;
} LightData;

typedef enum {
    TFSBufferIndexMeshVertex                = 0,
    /* ... */
    TFSBufferIndexMaterialTextureTransforms = 12
} TFSBufferIndices;
```

### After

```c
#define TFS_MAX_SHADOW_CASCADES 4

typedef struct {
    LightType type;
    matrix_float4x4 modelMatrix;
    matrix_float4x4 viewProjectionMatrix;

    /// Legacy single-cascade alias of cascadeViewProjectionMatrices[0]. Kept
    /// during the transition so the legacy GBuffer.metal vertex path (which
    /// still consumes the precomputed shadow_coord) continues to build.
    /// Removed in a follow-up once that path is updated.
    matrix_float4x4 shadowViewProjectionMatrix;

    matrix_float4x4 shadowTransformMatrix;
    simd_float3     direction;
    simd_float3     lightEyeDirection;
    simd_float3     position;
    simd_float3     color;
    float           brightness;
    float           radius;
    simd_float3     attenuation;
    float           ambientIntensity;
    float           diffuseIntensity;
    float           specularIntensity;

    // Per-cascade depth slack (world units → NDC via shadowDepthRanges[i]).
    float           shadowWorldSlack;

    // Cascade data. cascadeCount = 0 means "no shadows" (renderers should
    // still allocate the texture array but the shader returns fully lit).
    uint            cascadeCount;

    // Each entry is `light_view_projection_matrix` for that cascade. The
    // shader transforms worldPosition by `cascadeViewProjectionMatrices[i]`
    // after `SelectCascade` picks i.
    matrix_float4x4 cascadeViewProjectionMatrices[TFS_MAX_SHADOW_CASCADES];

    // Per-cascade *far* depth threshold (world units). `SelectCascade` picks
    // the first i where fragViewSpaceDepth < cascadeSplitDepths[i].
    float           cascadeSplitDepths[TFS_MAX_SHADOW_CASCADES];

    // Per-cascade `far - near` of the ortho frustum (world units). Used by
    // the per-cascade epsilon: NDC epsilon = worldSlack / cascadeDepthRanges[i].
    float           cascadeDepthRanges[TFS_MAX_SHADOW_CASCADES];
} LightData;

typedef enum {
    TFSBufferIndexMeshVertex                = 0,
    TFSBufferIndexMeshGenerics              = 1,
    TFSBufferFrameData                      = 2,
    TFSBufferDirectionalLightsNum           = 3,
    TFSBufferDirectionalLightData           = 4,
    TFSBufferPointLightsData                = 5,
    TFSBufferPointLightsPosition            = 6,
    TFSBufferModelConstants                 = 7,
    TFSBufferIndexSceneConstants            = 8,
    TFSBufferIndexMaterial                  = 9,
    TFSBufferIndexTerrain                   = 10,
    TFSBufferIndexJointBuffer               = 11,
    TFSBufferIndexMaterialTextureTransforms = 12,

    // Per-shadow-gen-pass push constant: a single 4×4 matrix (the current
    // cascade's view-projection matrix). Separate from LightData because the
    // shadow gen pass runs N times per frame, and each pass needs a different
    // matrix without copying all of LightData.
    TFSBufferIndexShadowCascadeVP           = 13
} TFSBufferIndices;
```

Notes:
- Removed: `shadowDepthRange` (single Float). Replaced by `cascadeDepthRanges[N]`.
- Kept: `shadowViewProjectionMatrix`. It's now redundant with `cascadeViewProjectionMatrices[0]`, but several consumers (the legacy `GBuffer.metal` vertex path that precomputes `shadow_coord`) still read it during Stage 1. Stage 1 keeps it as an alias to defer the GBuffer.metal refactor; removed in a follow-up commit.
- `simd_float4x4 cascadeViewProjectionMatrices[4]` adds 256 B. `simd_float cascadeSplitDepths[4]` + `cascadeDepthRanges[4]` adds another 32 B. Total `LightData` growth ~290 B. All consumers use `LightData.stride`; no manual offsets.

## 5. `GameObjects/LightObject.swift` — refactor

### After (replace the body)

Keep the existing setters and the backward-compat `direction`/`setLightDirection` machinery. Replace `_shadowRadius`/`_shadowLift`/`updateShadowCamera` with cascade machinery.

```swift
import MetalKit

class LightObject: GameObject {
    var lightType: LightType
    var lightData = LightData()

    // CSM configuration.
    private var _cascadeCount:      Int   = 4         // 1...TFS_MAX_SHADOW_CASCADES
    private var _cascadeLambda:     Float = 0.5       // PSSM hybrid blend
    private var _shadowMapRes:      Int   = 4096      // MUST match ShadowRendering.ShadowMapSize
    private var _shadowMaxDistance: Float = 500       // decouple from cam.far
    private var _cascadeZPad:       Float = 100       // additive ortho z-padding (world units)
    private var _shadowWorldSlack:  Float = 0.25      // base slack; per-cascade scaled in shader

    // Shadow-coord transform from clip-space [-1,1] to UV [0,1] with Y flip.
    // Only used by the legacy `GBuffer.metal` path; tiled deferred derives the
    // transform inline in CalculateShadow.
    let shadowScale     = Transform.scaleMatrix(.init(0.5, -0.5, 1))
    let shadowTranslate = Transform.translationMatrix(.init(0.5, 0.5, 0))

    private var _explicitDirection: float3?
    private var _modelType: ModelType = .None

    var direction: float3 {
        if let d = _explicitDirection { return d }
        let p = self.getPosition()
        let lengthSq = simd_length_squared(p)
        return lengthSq > .ulpOfOne ? p / sqrt(lengthSq) : Y_AXIS
    }

    init(name: String, lightType: LightType = Directional) {
        self.lightType = lightType
        super.init(name: name, modelType: .None)
        self.lightData.shadowTransformMatrix = shadowTranslate * shadowScale
    }

    init(name: String, lightType: LightType = Directional, modelType: ModelType = .Sphere) {
        self.lightType = lightType
        self._modelType = modelType
        super.init(name: name, modelType: modelType)
        self.lightData.shadowTransformMatrix = shadowTranslate * shadowScale
    }

    func setLightDirection(_ dir: float3) { _explicitDirection = normalize(dir) }
    func setCascadeCount(_ n: Int)        { _cascadeCount = min(max(n, 1), Int(TFS_MAX_SHADOW_CASCADES)) }
    func setCascadeLambda(_ l: Float)     { _cascadeLambda = simd_clamp(l, 0, 1) }
    func setShadowMaxDistance(_ d: Float) { _shadowMaxDistance = max(d, 1) }
    func setShadowMapResolution(_ r: Int) { _shadowMapRes = r }
    func setCascadeZPad(_ pad: Float)     { _cascadeZPad = max(pad, 0) }
    func setShadowWorldSlack(_ s: Float)  { _shadowWorldSlack = max(s, 0) }

    override func update() {
        super.update()
        self.lightData.type        = self.lightType
        self.lightData.modelMatrix = self.modelMatrix
        self.lightData.position    = self.getPosition()
        self.lightData.direction   = self.direction
        self.lightData.shadowWorldSlack = _shadowWorldSlack

        if self.lightType == Directional {
            updateShadowCascades()
        }
    }

    private func updateShadowCascades() {
        guard let cam = CameraManager.CurrentCamera else { return }

        let snapshot = ShadowCascadeFitting.CameraSnapshot(
            viewMatrix: cam.viewMatrix,
            near:       cam.near,
            far:        cam.far,
            fovY:       cam.fieldOfView.toRadians,
            aspect:     cam.aspectRatio)

        let fit = ShadowCascadeFitting.fitCascades(
            camera:              snapshot,
            lightDirection:      self.direction,
            shadowMapResolution: _shadowMapRes,
            cascadeCount:        _cascadeCount,
            lambda:              _cascadeLambda,
            shadowMaxDistance:   _shadowMaxDistance,
            zPaddingWorldUnits:  _cascadeZPad)

        // Convert split-far depths from view-space (scaled if camera has a
        // scale-N parent) to world units for shader consumption. Same scale
        // extraction as in `boundingSphereForSlice`.
        let c0 = cam.viewMatrix.inverse.columns.0
        let cameraScale = simd_length(simd_float3(c0.x, c0.y, c0.z))

        lightData.cascadeCount = UInt32(_cascadeCount)
        writeCascadeMatrices(into: &lightData.cascadeViewProjectionMatrices,
                             from: fit.cascades.map { $0.viewProjectionMatrix })
        writeCascadeFloats(into: &lightData.cascadeSplitDepths,
                           from: fit.splitFars.map { $0 * cameraScale })
        writeCascadeFloats(into: &lightData.cascadeDepthRanges,
                           from: fit.cascades.map { $0.depthRange })

        // Legacy alias for the GBuffer.metal vertex path. Removed in follow-up.
        lightData.shadowViewProjectionMatrix = fit.cascades[0].viewProjectionMatrix
    }
}

// MARK: - Tuple-array writers
//
// LightData.cascadeViewProjectionMatrices is a C array, which Swift imports as
// a homogeneous tuple. `withUnsafeMutablePointer` gives us index access.
private func writeCascadeMatrices(into tuple: inout (float4x4, float4x4, float4x4, float4x4),
                                  from src: [float4x4]) {
    withUnsafeMutablePointer(to: &tuple) { tuplePtr in
        tuplePtr.withMemoryRebound(to: float4x4.self,
                                   capacity: Int(TFS_MAX_SHADOW_CASCADES)) { ptr in
            for i in 0..<min(src.count, Int(TFS_MAX_SHADOW_CASCADES)) {
                ptr[i] = src[i]
            }
        }
    }
}

private func writeCascadeFloats(into tuple: inout (Float, Float, Float, Float),
                                from src: [Float]) {
    withUnsafeMutablePointer(to: &tuple) { tuplePtr in
        tuplePtr.withMemoryRebound(to: Float.self,
                                   capacity: Int(TFS_MAX_SHADOW_CASCADES)) { ptr in
            for i in 0..<min(src.count, Int(TFS_MAX_SHADOW_CASCADES)) {
                ptr[i] = src[i]
            }
        }
    }
}

extension LightObject {
    // ... existing setLightColor / setLightBrightness / etc. unchanged ...
}
```

## 6. `Scenes/GameScene.swift` — bind SceneConstants to fragments

The fragment shaders need `sceneConstants.cameraPosition` to recompute view-space depth per-fragment.

### Before

```swift
func setSceneConstants(with renderEncoder: MTLRenderCommandEncoder) {
    renderEncoder.setVertexBytes(&_sceneConstants,
                                 length: SceneConstants.stride,
                                 index: TFSBufferIndexSceneConstants.index)
}
```

### After

```swift
func setSceneConstants(with renderEncoder: MTLRenderCommandEncoder) {
    renderEncoder.setVertexBytes(&_sceneConstants,
                                 length: SceneConstants.stride,
                                 index: TFSBufferIndexSceneConstants.index)
    renderEncoder.setFragmentBytes(&_sceneConstants,
                                   length: SceneConstants.stride,
                                   index: TFSBufferIndexSceneConstants.index)
}
```

## 7. `Graphics/Shaders/Lighting.metal` — cascade-aware shadow sampling

Three additions: `SelectCascade`, `SlopeScaledWorldBias`, and rewriting `CalculateShadow` / `CalculateShadowMSAA` to be cascade-aware (3×3 PCF, cascade fallthrough).

### After (relevant excerpt — replaces existing `NDCShadowEpsilon`/`CalculateShadow`/`CalculateShadowMSAA`)

```metal
static float NDCShadowEpsilon(float worldSlack, float depthRange) {
    return worldSlack / max(depthRange, 1.0);
}

// Slope-scaled bias: surfaces nearly parallel to light direction get up to
// SLOPE_BIAS_FACTOR× the base slack. Prevents acne on near-vertical surfaces
// (F-22 rudders, sphere sides) without Peter-panning the ground.
static float SlopeScaledWorldBias(float baseSlack, float3 normal, float3 lightDir) {
    float nDotL = saturate(dot(normalize(normal), lightDir));
    float slope = 1.0 - nDotL;
    constexpr float SLOPE_BIAS_FACTOR = 20.0;
    return baseSlack * (1.0 + slope * SLOPE_BIAS_FACTOR);
}

// Interval-based cascade selection. Returns the index of the first cascade
// whose far depth is greater than this fragment's view-space depth. Falls back
// to the last cascade if the fragment is beyond all of them (rather than 0,
// which would put the fragment in the smallest, sharpest cascade — wrong).
static uint SelectCascade(constant LightData &light, float viewSpaceDepth) {
    for (uint i = 0; i < light.cascadeCount; ++i) {
        if (viewSpaceDepth < light.cascadeSplitDepths[i]) return i;
    }
    return light.cascadeCount > 0 ? light.cascadeCount - 1 : 0;
}

// 3×3 hardware-PCF kernel. Each sample_compare with filter::linear performs
// a hardware 2×2 bilinear filter on the comparison result, so the effective
// kernel is ~4×4 weighted. Output mapped to [0.5, 1.0] so shadowed regions
// are dimmed 50% rather than fully black.
static float CalculateShadow(float3 worldPosition,
                             float  fragViewSpaceDepth,
                             float3 worldNormal,
                             constant LightData &light,
                             depth2d_array<float> shadowArray) {
    if (light.cascadeCount == 0) return 1.0;

    uint cascadeIdx = SelectCascade(light, fragViewSpaceDepth);
    float4 shadowPos = light.cascadeViewProjectionMatrices[cascadeIdx]
                     * float4(worldPosition, 1.0);
    float3 ndc = shadowPos.xyz / shadowPos.w;
    float2 xy  = ndc.xy * 0.5 + 0.5;
    xy.y = 1.0 - xy.y;

    // Cascade fallthrough: texel snap can shift a fragment slightly outside
    // the depth-selected cascade's XY box. Try the next cascade before
    // returning fully-lit. Cheap because the next cascade is usually empty
    // anyway (no occluder), so this resolves in one extra sample worst-case.
    if (any(xy < 0.0) || any(xy > 1.0) || ndc.z < 0.0 || ndc.z > 1.0) {
        if (cascadeIdx + 1 < light.cascadeCount) {
            cascadeIdx += 1;
            shadowPos = light.cascadeViewProjectionMatrices[cascadeIdx]
                      * float4(worldPosition, 1.0);
            ndc = shadowPos.xyz / shadowPos.w;
            xy  = ndc.xy * 0.5 + 0.5;
            xy.y = 1.0 - xy.y;
            if (any(xy < 0.0) || any(xy > 1.0) || ndc.z < 0.0 || ndc.z > 1.0) {
                return 1.0;
            }
        } else {
            return 1.0;
        }
    }

    float baseSlack = light.shadowWorldSlack;
    float biasWorld = SlopeScaledWorldBias(baseSlack, worldNormal, light.direction);
    float epsilon   = NDCShadowEpsilon(biasWorld, light.cascadeDepthRanges[cascadeIdx]);
    float refZ      = ndc.z - epsilon;

    constexpr sampler pcfSampler(coord::normalized,
                                 filter::linear,
                                 address::clamp_to_edge,
                                 compare_func::less);
    float invW = 1.0 / float(shadowArray.get_width());
    float invH = 1.0 / float(shadowArray.get_height());
    float litSum = 0.0;
    for (int dy = -1; dy <= 1; ++dy) {
        for (int dx = -1; dx <= 1; ++dx) {
            float2 offset = float2(float(dx) * invW, float(dy) * invH);
            litSum += shadowArray.sample_compare(pcfSampler,
                                                 xy + offset,
                                                 cascadeIdx,
                                                 refZ);
        }
    }
    // Map [0, 1] PCF result to [0.5, 1.0] shadow factor.
    return 0.5 + 0.5 * (litSum * (1.0 / 9.0));
}

// MSAA variant: same logic but reads from a depth2d_ms_array (manual averaging
// because sample_compare isn't available on MS textures). One sample per
// subpixel; no PCF kernel widening on this path (MSAA already softens edges
// implicitly).
static float CalculateShadowMSAA(float3 worldPosition,
                                 float  fragViewSpaceDepth,
                                 float3 worldNormal,
                                 constant LightData &light,
                                 depth2d_ms_array<float> shadowArray) {
    if (light.cascadeCount == 0) return 1.0;

    uint cascadeIdx = SelectCascade(light, fragViewSpaceDepth);
    float4 shadowPos = light.cascadeViewProjectionMatrices[cascadeIdx]
                     * float4(worldPosition, 1.0);
    float3 ndc = shadowPos.xyz / shadowPos.w;
    float2 xy  = ndc.xy * 0.5 + 0.5;
    xy.y = 1.0 - xy.y;
    if (any(xy < 0.0) || any(xy > 1.0) || ndc.z < 0.0 || ndc.z > 1.0) {
        return 1.0;
    }

    uint2 coords = uint2(uint(xy.x * shadowArray.get_width()),
                         uint(xy.y * shadowArray.get_height()));
    uint numSamples = shadowArray.get_num_samples();
    float shadow = 0.0;
    for (uint i = 0; i < numSamples; ++i) {
        shadow += shadowArray.read(coords, cascadeIdx, i);
    }
    shadow /= float(numSamples);

    float biasWorld = SlopeScaledWorldBias(light.shadowWorldSlack, worldNormal, light.direction);
    float epsilon   = NDCShadowEpsilon(biasWorld, light.cascadeDepthRanges[cascadeIdx]);
    return (ndc.z > shadow + epsilon) ? 0.5 : 1.0;
}
```

## 8. `Graphics/Shaders/Shadow.metal` — consume per-pass cascade VP

The shadow gen pass runs N times per frame (one per cascade). Each iteration binds the per-cascade VP at `TFSBufferIndexShadowCascadeVP = 13`. The vertex shader uses that instead of `lightData.shadowViewProjectionMatrix`.

### Before (relevant excerpt)

```metal
vertex ShadowOutput shadow_vertex(const     VertexIn        in              [[ stage_in ]],
                                  constant  LightData       &lightData      [[ buffer(TFSBufferDirectionalLightData) ]],
                                  constant  ModelConstants  *modelConstants [[ buffer(TFSBufferModelConstants) ]],
                                            uint            instanceId      [[ instance_id ]])
{
    ModelConstants modelInstance = modelConstants[instanceId];
    ShadowOutput out = {
        .position = lightData.shadowViewProjectionMatrix * modelInstance.modelMatrix * float4(in.position, 1.0)
    };
    return out;
}
```

### After

```metal
vertex ShadowOutput shadow_vertex(const     VertexIn        in              [[ stage_in ]],
                                  constant  float4x4        &cascadeVP      [[ buffer(TFSBufferIndexShadowCascadeVP) ]],
                                  constant  ModelConstants  *modelConstants [[ buffer(TFSBufferModelConstants) ]],
                                            uint            instanceId      [[ instance_id ]])
{
    ModelConstants modelInstance = modelConstants[instanceId];
    ShadowOutput out = {
        .position = cascadeVP * modelInstance.modelMatrix * float4(in.position, 1.0)
    };
    return out;
}
```

Identical change to `shadow_animated_vertex`. The `LightData` buffer is no longer needed by the shadow gen pass at all (drop the binding from `ShadowRendering` shadow-pass encoders; see §10).

## 9. `Graphics/Shaders/ShaderDefinitions.h` — `VertexOut` cleanup

### Before (relevant excerpt)

```c
struct VertexOut {
    float4 position [[ position ]];
    float3 normal;
    float2 uv;
    float3 worldPosition;
    float3 worldNormal;
    float3 worldTangent;
    float3 worldBitangent;
    float4 shadowPosition;
    uint   instanceId;
    float4 objectColor;
    bool   useObjectColor;
};
```

### After

```c
struct VertexOut {
    float4 position [[ position ]];
    float3 normal;
    float2 uv;
    float3 worldPosition;     // perspective-correctly interpolated; fragments derive viewSpaceDepth and shadowPos from this
    float3 worldNormal;
    float3 worldTangent;
    float3 worldBitangent;
    uint   instanceId;
    float4 objectColor;
    bool   useObjectColor;
};
```

`shadowPosition` removed: fragments now compute their own shadow position from `cascadeViewProjectionMatrices[SelectCascade(...)] * worldPosition` per-fragment. The vertex shader doesn't know which cascade a fragment belongs to (it varies across a triangle as fragments fall on different sides of a cascade boundary).

## 10. Tiled deferred GBuffer fragments — per-fragment recomputation

The vertex shaders (`tiled_deferred_gbuffer_vertex`, `tiled_deferred_gbuffer_animated_vertex`, `tiled_msaa_gbuffer_vertex`) drop the `shadowPosition` field from the returned `VertexOut`. The fragments bind `SceneConstants` and recompute `fragViewSpaceDepth` per-fragment from the already-interpolated `worldPosition`.

### Vertex change (one example; identical pattern for all)

```metal
// In tiled_deferred_gbuffer_vertex (and animated_vertex, tiled_msaa_gbuffer_vertex,
// the two transparency vertex shaders):
VertexOut out {
    .position       = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * worldPosition,
    .normal         = in.normal,
    .uv             = in.textureCoordinate,
    .worldPosition  = worldPosition.xyz / worldPosition.w,
    .worldNormal    = modelInstance.normalMatrix * in.normal,
    .worldTangent   = modelInstance.normalMatrix * in.tangent,
    .worldBitangent = modelInstance.normalMatrix * in.bitangent,
    .instanceId     = instanceId,
    .objectColor    = modelInstance.objectColor,
    .useObjectColor = modelInstance.useObjectColor
};
// `.shadowPosition` field removed.
// `LightData` binding can be dropped from this vertex shader entirely.
```

### Fragment change (`TiledDeferredGBuffer.metal`)

```metal
fragment GBufferOut
tiled_deferred_gbuffer_fragment(VertexOut                          in              [[ stage_in ]],
                                constant SceneConstants            &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
                                constant MaterialProperties        &material       [[ buffer(TFSBufferIndexMaterial) ]],
                                constant MaterialTextureTransforms &uvXforms       [[ buffer(TFSBufferIndexMaterialTextureTransforms) ]],
                                constant LightData                 &lightData      [[ buffer(TFSBufferDirectionalLightData) ]],
                                sampler                            sampler2d       [[ sampler(0) ]],
                                texture2d<half>                    baseColorTexture[[ texture(TFSTextureIndexBaseColor) ]],
                                texture2d<half>                    normalTexture   [[ texture(TFSTextureIndexNormal) ]],
                                depth2d_array<float>               shadowArray     [[ texture(TFSTextureIndexShadow) ]]) {
    /* ...UV sampling, color sampling, normal sampling unchanged... */

    // Per-fragment view-space depth. worldPosition was interpolated
    // perspective-correctly (it's linear in eye space, since view_inverse is
    // affine); the subtraction worldPos - cameraPos is Sterbenz-exact in float32
    // for visible fragments; length of a well-conditioned small vector is
    // well-conditioned. See csm_journey_summary.md D1 iteration 3.
    float fragViewSpaceDepth = distance(in.worldPosition, sceneConstants.cameraPosition);

    color.a = Lighting::CalculateShadow(in.worldPosition,
                                        fragViewSpaceDepth,
                                        in.worldNormal,
                                        lightData,
                                        shadowArray);
    /* ...rest unchanged... */
}
```

Identical pattern in:
- `TiledMSAAGBuffer.metal::tiled_msaa_gbuffer_fragment` (uses `depth2d_ms_array<float>` + `CalculateShadowMSAA`).
- `GBuffer.metal::gbuffer_fragment_base` and `gbuffer_fragment_material` (single-pass deferred path). These also need a fix because they currently use the precomputed `in.shadow_coord` from the `ColorInOut` vertex output — rewrite them to recompute the same way.

For `GBuffer.metal`, the vertex shader's `ColorInOut` loses `shadow_coord`, gains `worldPosition`. The fragments bind `SceneConstants` and `LightData` (currently only the vertex binds LightData) and call `Lighting::CalculateShadow` instead of doing a direct `sample_compare` on the `shadow_coord`.

## 11. Transparency vertex shaders — drop shadow position

`TiledDeferredTransparency.metal::tiled_deferred_transparency_vertex` and `SinglePassDeferredTransparency.metal` write `VertexOut.shadowPosition`. Both vertex shaders need the same treatment as the GBuffer vertex shaders: drop the `shadowPosition` field. The transparency fragments don't sample shadows currently (look at `tiled_deferred_transparency_fragment` — no shadow texture binding), so the fragments need no change.

## 12. `Display/Protocols/ShadowRendering.swift` — texture array + per-cascade pass

### After (replace the body)

```swift
import MetalKit

protocol ShadowRendering: RenderPassEncoding {
    static var ShadowMapSize: Int  { get }
    static var CascadeCount:  Int  { get }     // matches LightObject._cascadeCount

    var shadowMapArray:               MTLTexture { get set }
    var shadowResolveArray:           MTLTexture? { get set }
    var shadowRenderPassDescriptors:  [MTLRenderPassDescriptor] { get set }
}

extension ShadowRendering {
    static var ShadowMapSize: Int { 4096 }
    static var CascadeCount:  Int { 4 }

    public static func makeShadowMapArray(label: String, sampleCount: Int = 1) -> MTLTexture {
        let d = MTLTextureDescriptor()
        d.pixelFormat       = .depth32Float
        d.width             = Self.ShadowMapSize
        d.height            = Self.ShadowMapSize
        d.arrayLength       = Self.CascadeCount
        d.mipmapLevelCount  = 1
        d.textureType       = sampleCount > 1 ? .type2DMultisampleArray : .type2DArray
        d.sampleCount       = sampleCount
        d.resourceOptions   = .storageModePrivate
        d.usage             = [.renderTarget, .shaderRead]

        guard let tex = Engine.Device.makeTexture(descriptor: d) else {
            fatalError("[ShadowRendering makeShadowMapArray] failed")
        }
        tex.label = label
        return tex
    }

    public static func makeShadowRenderPassDescriptors(shadowArray: MTLTexture,
                                                       resolveArray: MTLTexture? = nil)
                                                       -> [MTLRenderPassDescriptor] {
        precondition(shadowArray.arrayLength == Self.CascadeCount)
        var descriptors: [MTLRenderPassDescriptor] = []
        descriptors.reserveCapacity(Self.CascadeCount)
        for i in 0..<Self.CascadeCount {
            let d = MTLRenderPassDescriptor()
            d.depthAttachment.texture     = shadowArray
            d.depthAttachment.slice       = i
            d.depthAttachment.loadAction  = .clear
            d.depthAttachment.clearDepth  = 1.0
            if let resolve = resolveArray {
                d.depthAttachment.resolveTexture = resolve
                d.depthAttachment.resolveSlice   = i
                d.depthAttachment.storeAction    = .multisampleResolve
            } else {
                d.depthAttachment.storeAction    = .store
            }
            descriptors.append(d)
        }
        return descriptors
    }

    /// Iterate over cascades. For each cascade, push the cascade VP at
    /// TFSBufferIndexShadowCascadeVP and draw all shadow-casting geometry.
    /// Replaces the old single-pass `encodeShadowMapPass`.
    func encodeShadowMapPasses(into commandBuffer: MTLCommandBuffer) {
        guard let light = LightManager.GetDirectionalLightData(viewMatrix: .identity).first
        else { return }
        // Reify the cascade VPs from the tuple.
        var vps: [float4x4] = withUnsafePointer(to: light.cascadeViewProjectionMatrices) { tuplePtr in
            tuplePtr.withMemoryRebound(to: float4x4.self,
                                       capacity: Int(TFS_MAX_SHADOW_CASCADES)) { ptr in
                (0..<Int(light.cascadeCount)).map { ptr[$0] }
            }
        }

        for i in 0..<Int(light.cascadeCount) {
            let descriptor = shadowRenderPassDescriptors[i]
            encodeRenderPass(into: commandBuffer,
                             using: descriptor,
                             label: "Shadow Map Pass [\(i)]") { renderEncoder in
                encodeRenderStage(using: renderEncoder, label: "Shadow Generation Stage") {
                    setRenderPipelineState(renderEncoder, state: .ShadowGeneration)
                    renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.ShadowGeneration])
                    renderEncoder.setVertexBytes(&vps[i],
                                                 length: float4x4.stride,
                                                 index: TFSBufferIndexShadowCascadeVP.index)
                    // NOTE: Removed `setDepthBias(0.1, slopeScale: 1, clamp: 0.0)`.
                    // The fixed-function bias destabilizes thin-aircraft shadows
                    // at the small cascade-0 ortho width (Peter Pans the wheels
                    // ~10cm off the ground). The shader-side per-cascade
                    // SlopeScaledWorldBias handles bias correctly without it.
                    DrawManager.DrawShadows(with: renderEncoder)
                }
            }
        }
    }

    // The other two encoders (`encodeShadowPassTiledDeferred`,
    // `encodeMSAAShadowPass`) collapse into `encodeShadowMapPasses` plus
    // per-renderer pipeline-state choice. Keep them as thin wrappers that just
    // pick the right RenderPipelineState before delegating.
    func encodeShadowPassesTiledDeferred(into commandBuffer: MTLCommandBuffer) {
        encodeShadowMapPasses(into: commandBuffer)  // identical logic for tiled deferred
    }
    func encodeShadowPassesMSAA(into commandBuffer: MTLCommandBuffer) {
        encodeShadowMapPasses(into: commandBuffer)  // identical logic for MSAA
    }
}
```

## 13. Each `Renderer` implementation — adopt new texture/descriptor shape

For each of the four renderers conforming to `ShadowRendering` (`TiledDeferredRenderer`, `SinglePassDeferredLightingRenderer`, `TiledMultisampleRenderer`, `TiledMSAATessellatedRenderer`):

1. Rename the `shadowMap` property to `shadowMapArray` (type unchanged: `MTLTexture`).
2. Rename `shadowResolveTexture` (if present) to `shadowResolveArray`.
3. Rename `shadowRenderPassDescriptor` to `shadowRenderPassDescriptors: [MTLRenderPassDescriptor]`.
4. Use `Self.makeShadowMapArray(...)` and `Self.makeShadowRenderPassDescriptors(...)` to allocate, in both `init` and `mtkView(_:drawableSizeWillChange:)`.
5. When binding the shadow texture for the lighting pass, bind `shadowMapArray` (the array) — the fragment shader's `depth2d_array<float>` consumes it directly.

Example (TiledDeferredRenderer):

```swift
// Was:
var shadowMap: MTLTexture
var shadowRenderPassDescriptor: MTLRenderPassDescriptor
var shadowResolveTexture: MTLTexture? = nil

// Becomes:
var shadowMapArray: MTLTexture
var shadowResolveArray: MTLTexture? = nil
var shadowRenderPassDescriptors: [MTLRenderPassDescriptor]
```

```swift
// init body:
shadowMapArray = Self.makeShadowMapArray(label: "Shadow Texture Array")
shadowRenderPassDescriptors = Self.makeShadowRenderPassDescriptors(shadowArray: shadowMapArray)
```

```swift
// Lighting-pass binding (unchanged conceptually, just renamed):
renderEncoder.setFragmentTexture(shadowMapArray, index: TFSTextureIndexShadow.index)
```

`encodeShadowMapPass(into:)` becomes `encodeShadowMapPasses(into:)` (or just the renamed protocol method). Same call site change in each renderer's render loop.

## 14. Stage 1 defaults

| Property | Default | Why |
|---|---|---|
| `_cascadeCount` | 4 | PSSM sweet spot for this scene scale. Each cascade halves the previous covered area roughly. |
| `_cascadeLambda` | 0.5 | Microsoft PSSM hybrid blend. Pure log degenerates near=0.01; pure uniform wastes resolution near camera. |
| `_shadowMapRes` | 4096 | Same total memory (256 MB) as the pre-CSM single 8192² map. |
| `_shadowMaxDistance` | 500 | Decouples shadow reach from camera far plane (huge for horizon rendering). |
| `_cascadeZPad` | 100 (world units, **additive**) | Avoids the multiplicative-padding blow-up when the AABB straddles 0. |
| `_shadowWorldSlack` | 0.25 | Per-cascade scaled by `worldSlack / cascadeDepthRanges[i]` in the shader's `NDCShadowEpsilon`. |
| `ShadowRendering.ShadowMapSize` | 4096 | MUST match `LightObject._shadowMapRes` (the former drives texel-snap math, the latter allocates the texture). |
| `ShadowRendering.CascadeCount`  | 4 | MUST match `LightObject._cascadeCount`. |

If `_cascadeCount` and `CascadeCount` ever drift (e.g., per-scene override), the `precondition` in `makeShadowRenderPassDescriptors` will trip at startup. Acceptable: this is a global tuning knob, not per-scene.

## 15. Stage 1 verification

Build/test:
- `xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug CODE_SIGNING_ALLOWED=NO` succeeds.
- `xcodebuild test ...` — all existing tests pass.

Functional (run on FlightboxWithPhysics; this is the screenshotted scene from the journey doc):
1. **F-22 self-shadow at spawn.** Sharp silhouette on the rudders, wings, fuselage. No fuzzy blob.
2. **F-22 cast-shadow on ground at spawn.** Visible silhouette with detail (wings, vertical stabs).
3. **Fly to `cam_world ≈ (10K, 5.9, 22K)`.** Both self-shadow and cast-shadow still sharp. **This is the critical test** — the journey doc proved cascade selection was broken at this distance in earlier iterations.
4. **Land near the ground.** Cascade selection still correct at oblique viewing angles; no fully-lit patches under the aircraft.
5. **Static-geometry edges.** Spheres, cubes — shadow edges should NOT visibly swim during steady flight (texel snap working). Animated F-22 edges may still swim — that's Stage 2.
6. **Switch renderers** via the macOS menu through each of TiledDeferred / TiledMultisample / TiledMSAATessellated / SinglePassDeferredLighting. All four should render shadows correctly.
7. **No console errors, no Metal validation layer complaints.**

If all 7 pass, Stage 1 is shippable. If (5) shows swim on static geometry, the snap is broken — debug `ShadowCascadeFitting.fitCascades` first. If (4) shows fully-lit patches under the aircraft, cascade fallthrough isn't covering — try increasing `_cascadeZPad`.

---

# Stage 2 — Anti-Swimming Improvements

Stage 1 fixes swim on static geometry (texel snap) but the F-22's animated control surfaces still cause sub-pixel edge motion. The eye picks this up as residual shimmer during steady flight. Stage 2 attacks this with two changes, neither of which requires schema changes — they're tunable extensions of Stage 1.

## 2.1 Widen PCF kernel from 3×3 to 5×5

The 3×3 kernel in `CalculateShadow` averages 9 hardware-bilinear depth comparisons. Widening to 5×5 averages 25, which sub-texel-smooths the comparison threshold below the eye's discrimination threshold for typical sub-texel rasterization changes. [MJP measured 7×7 PCF at +0.4ms](https://therealmjp.github.io/posts/shadow-maps/) on a 2013 GPU; on Apple Silicon (M-series unified memory, optimized `sample_compare` path) 5×5 should be sub-0.2ms.

### Change in `Lighting.metal::CalculateShadow`

```metal
// Replace the inner 3×3 loop with parameterized half-size.
constexpr int PCF_HALF = 2;  // 2 → 5×5; was 1 (3×3)
constexpr float PCF_DIVISOR = float((PCF_HALF * 2 + 1) * (PCF_HALF * 2 + 1));

float invW = 1.0 / float(shadowArray.get_width());
float invH = 1.0 / float(shadowArray.get_height());
float litSum = 0.0;
for (int dy = -PCF_HALF; dy <= PCF_HALF; ++dy) {
    for (int dx = -PCF_HALF; dx <= PCF_HALF; ++dx) {
        float2 offset = float2(float(dx) * invW, float(dy) * invH);
        litSum += shadowArray.sample_compare(pcfSampler, xy + offset, cascadeIdx, refZ);
    }
}
return 0.5 + 0.5 * (litSum * (1.0 / PCF_DIVISOR));
```

If 5×5 isn't enough, try `PCF_HALF = 3` (7×7). Watch for two failure modes:
- **Softness creep**: shadow edges become visibly blurry, which reads as "low-quality" rather than "stable." If users complain about loss of detail, fall back to 3×3 and pursue cascade blending alone (§2.2) or move to Stage 3 (EVSM).
- **Cascade-boundary seams**: widening the PCF kernel widens the visible seam between cascades. §2.2 directly addresses this.

## 2.2 Cascade blending at boundaries

When a fragment is in the last 10% of cascade i's depth range, sample BOTH cascade i and cascade i+1 and lerp by the blend weight. Eliminates the visible resolution-change seam at cascade boundaries — which is the single most distracting CSM artifact after edge swim.

### Change in `Lighting.metal::CalculateShadow`

Add after the cascade selection but before the main sampling loop:

```metal
constexpr float CASCADE_BLEND_FRACTION = 0.1;  // last 10% of cascade range blends to next

// Compute blend weight: 0 in the body of cascade i, ramping to 1 at the boundary.
float cascadeFar = light.cascadeSplitDepths[cascadeIdx];
float cascadeNear = (cascadeIdx > 0) ? light.cascadeSplitDepths[cascadeIdx - 1] : 0.0;
float cascadeSpan = max(cascadeFar - cascadeNear, 1.0);
float blendStart = cascadeFar - cascadeSpan * CASCADE_BLEND_FRACTION;
float blendWeight = saturate((fragViewSpaceDepth - blendStart) / (cascadeFar - blendStart));

bool canBlend = (cascadeIdx + 1 < light.cascadeCount) && (blendWeight > 0.0);

float litCurrent = computePcfShadow(worldPosition, worldNormal, light, shadowArray, cascadeIdx);
float litNext    = canBlend
    ? computePcfShadow(worldPosition, worldNormal, light, shadowArray, cascadeIdx + 1)
    : litCurrent;

float lit = mix(litCurrent, litNext, blendWeight);
return 0.5 + 0.5 * lit;
```

Where `computePcfShadow` is the 5×5 PCF loop refactored as a helper (so it's called once per cascade without code duplication).

Cost: the blend region's worth of fragments (~10% of screen for typical cascade configs) sample TWO cascades instead of one. Net ~10% extra shadow-sampling cost. Cheap.

## 2.3 (Optional) Skinning compute pass for shared shadow/color skinning

If §2.1 + §2.2 leave residual swim that's traceable specifically to F-22 animation, a more invasive fix is to do skeletal skinning once per frame in a compute pass, write to a transient vertex buffer, and have both the shadow generation pass and the GBuffer pass read from that buffer. This guarantees the F-22's vertex positions are bit-identical in both passes — eliminating one class of "shadow doesn't match silhouette" artifacts.

This is moderately invasive (~2 days of work) and arguably worth it independently for performance (skinning runs once per frame instead of N+1 times). Out of scope for this plan but listed as a defensible follow-on.

## Stage 2 verification

In addition to all Stage 1 functional checks:
1. **Steady-flight static-geometry swim**: zero visible swim on spheres, cubes, ground. (Should already pass Stage 1.)
2. **Steady-flight F-22 control surface swim**: ailerons, flaperons, rudders. Should be visibly reduced vs Stage 1. "Eliminated" is a higher bar — if eye can still see motion, that's diagnostic feedback (consider PCF_HALF=3 or Stage 3).
3. **Cascade boundaries**: fly the F-22 forward so that its shadow crosses a visible cascade boundary on the ground. Boundary should be smooth, not a visible step. Look in particular at where cascade 0 ends and cascade 1 begins (likely 60-120 world units from the camera, depending on splits).
4. **No new performance regression**: render time should stay within ~10% of Stage 1.

---

# Risks and Rollback

| Risk | Mitigation |
|---|---|
| `LightData` shift breaks shader struct layouts. | All consumers use `LightData.stride` or the `TFSCommon.h` typedef. No manual offsets. Recompile to verify. |
| `depth2d_array<float>` not supported on some target GPUs. | Apple Silicon and all macOS Metal-capable GPUs since 2017 support array depth textures. The minimum-supported macOS in this repo (per CLAUDE.md targeting macos-26) is well above the cutoff. |
| `texture_2DMultisampleArray` for MSAA shadow path may have validation issues. | The MSAA shadow path already uses a multisample shadow texture today; extending to MSAA array texture should work on every Apple Silicon GPU. If it doesn't, fall back to a single MSAA `texture2d` per cascade (N separate textures). Plan for this only if Metal validation complains. |
| Cascade-config drift between `LightObject._cascadeCount` and `ShadowRendering.CascadeCount`. | `precondition(shadowArray.arrayLength == Self.CascadeCount)` in `makeShadowRenderPassDescriptors`. Crashes at startup; visible immediately. |
| First-frame race (LightObject runs before camera is set). | `updateShadowCascades` early-returns if no current camera; existing matrices stay zero-init (renderer wouldn't be drawing yet anyway). |
| Stage 2 wider PCF causes shadow-edge softness complaints. | Roll back PCF_HALF to 1 (3×3) and rely on §2.2 cascade blending alone. |
| Stage 2 cascade blending causes the "double-sample" branch to slow down on integrated GPUs. | Confirm via Xcode GPU frame capture before/after. Acceptable upper bound: render time +10%. If exceeded, narrow CASCADE_BLEND_FRACTION from 0.1 to 0.05 or move to a conditional branch. |
| Per-fragment `distance(worldPos, cameraPos)` adds cost. | ~3 FLOPs (subtract + dot + sqrt) per shadowed fragment. Negligible. Validated by the `csm1` branch staying at ~60 FPS. |

Rollback: Stage 1 and Stage 2 are independently revertable. Each stage is a single coherent set of commits; reverting the latest N commits restores the previous state. The branch starts from `main`, so a full rollback to single-cascade is `git reset --hard main`.

---

# Implementation Order

Recommended commit sequence — each commit independently buildable and testable:

### Stage 1

1. **Add `Shadows/` folder, move `ShadowCamera.swift`.** Update Xcode project. Verify build.
2. **Extend `ShadowCamera.swift` with cascade-fit init.** Backward-compatible; legacy init still works. Verify build.
3. **Add `ShadowCascadeFitting.swift`.** No callers; pure additive. Add basic Swift Testing coverage for `computeSplits` and `boundingSphereForSlice` (deterministic math, easy to test). Verify build + tests.
4. **Extend `TFSCommon.h::LightData` with cascade arrays + `TFS_MAX_SHADOW_CASCADES` + `TFSBufferIndexShadowCascadeVP`.** Recompile shaders; all consumers use stride, no source changes. Verify build.
5. **Replace `LightObject.updateShadowCamera` with `updateShadowCascades`.** `lightData.shadowViewProjectionMatrix` aliases `cascadeViewProjectionMatrices[0]` to keep legacy shaders compiling. Visual at this point: still single-cascade (only the first cascade VP is being consumed). Verify build + run; expect same shadows as today, possibly fitted slightly differently.
6. **Bind `SceneConstants` to fragments in `GameScene.setSceneConstants`.** No-op visually; preparation for next step. Verify build.
7. **Add `SelectCascade`, `SlopeScaledWorldBias`, rewrite `CalculateShadow` to be cascade-aware (3×3 PCF, fallthrough).** Update tiled deferred GBuffer fragments to compute `fragViewSpaceDepth` per-fragment. **Visual: CSM is live; shadows should sharpen near jet.** Critical commit.
8. **Update `Shadow.metal` to consume per-pass `cascadeVP` push constant.** No effect on shader output without the matching renderer-side push, but no break either (the new shader compiles and runs against the cascade-0 matrix that's still also in `lightData.shadowViewProjectionMatrix`).
9. **Update `ShadowRendering` protocol + all four renderers to use `texture2DArray` + array of descriptors + per-cascade pass.** Bind per-cascade VP at index 13. **Visual: all 4 cascades now actually rasterize; shadows sharp at distance.**
10. **Update legacy `GBuffer.metal` GBuffer fragments to recompute view-space depth.** Update transparency vertex shaders to drop `shadowPosition`. Drop `shadowPosition` from `VertexOut`. Verify build + run.
11. **Remove the `lightData.shadowViewProjectionMatrix` alias.** It's unused after step 10. Verify build + run.
12. **Final cleanup**: remove obsolete `_shadowRadius`/`_shadowLift`/`setShadowRadius`/`setShadowLift` from `LightObject` (replaced by cascade machinery).

### Stage 2

13. **Widen PCF kernel to 5×5.** Parameterize `PCF_HALF`. Run all 7 functional checks; if any complaint of softness, dial back to 3×3 and proceed without this commit.
14. **Add cascade blending.** Refactor PCF loop into helper, add blend weight + dual-cascade sample at boundaries. Verify cascade boundaries are seamless.
15. **(Optional, follow-up)** Move skeletal skinning to a shared compute pass.

If a regression appears mid-sequence, `git bisect` resolves to a single commit.

---

# Future Enhancements (Out of Scope)

Listed for completeness; pursue independently once Stages 1 + 2 are shipped.

| Enhancement | Why deferred | When to revisit |
|---|---|---|
| **SDSM** (sample distribution shadow maps) | Requires GPU min/max depth reduction pass before shadow gen. Substantial pipeline change. | If oblique-angle shadow quality is consistently poor (low-flight scenes). |
| **EVSM / MSM** (filterable shadows) | Substantial change to shadow-gen pipeline (separate render target format, blur passes, light bleeding mitigation). | If Stage 2 PCF widening is insufficient and edge-swim on animated geometry remains a top user complaint. |
| **PCSS / contact-hardening soft shadows** | Expensive blocker search. Overkill for a single directional sun; better suited to local lights. | If point/spot lights gain shadow casting. |
| **Camera-relative rendering** ("floating origin") | Current TFS world scale (jets reach ~22K from origin) is small enough that per-fragment world-space precision suffices. | Only if the simulator grows toward planetary-scale coordinates (e.g., earth-curvature, real GPS positions). |
| **Per-cascade resolution mapping** (e.g., 4K cascade-0, 2K cascade-3) | Marginal memory savings; complicates `ShadowMapSize` constant and the texel-snap math. | If memory pressure becomes a constraint (mobile? larger scenes?). |

---

# References (URLs visited during research)

## Stable / Cascaded Shadow Maps — canonical references

- [Microsoft DX docs: Cascaded Shadow Maps](https://learn.microsoft.com/en-us/windows/win32/dxtecharts/cascaded-shadow-maps) — PSSM splits, interval vs map-based selection, blending, PCF, VSM combination. **Primary reference for Stage 1.**
- [Microsoft DX docs: Common Techniques to Improve Shadow Depth Maps](https://learn.microsoft.com/en-us/windows/win32/dxtecharts/common-techniques-to-improve-shadow-depth-maps) — "Moving the light in texel-sized increments" (the canonical texel snap algorithm), slope-scaled bias, near/far plane tightening, front-face culling tradeoffs.
- [A Long Forgotten Blog: Stable Cascaded Shadow Maps](http://longforgottenblog.blogspot.com/2014/12/rendering-post-stable-cascaded-shadow.html) — Bounding-sphere fit (Valient's Killzone 2 algorithm) and the texel-snap rationale.
- [Theomader: Stable CSM](https://dev.theomader.com/stable-csm/) — Texel snap on top of bounding-sphere fit, with diagrams.
- [GameDev.net: Stable CSM sphere-based bounding help](https://www.gamedev.net/forums/topic/691434-stable-cascaded-shadow-maps-sphere-based-bounding-help/5353231/) — Practitioner discussion of the bounding-sphere fit gotchas.
- [LearnOpenGL: Cascaded Shadow Mapping](https://learnopengl.com/Guest-Articles/2021/CSM) — Full code walkthrough: frustum corner computation, light view construction, AABB fit, shader-side cascade selection. Note: uses AABB-of-corners fit, NOT sphere fit; this plan corrects that.
- [Shadow of a doubt - part 2 (Junkship)](https://www.junkship.net/News/2020/11/22/shadow-of-a-doubt-part-2) — Practitioner CSM postmortem.
- [Chetan Jags: Real-Time shadows — Cascaded Shadow Maps](https://chetanjags.wordpress.com/2015/02/05/real-time-shadows-cascaded-shadow-maps/) — Mid-level CSM overview.
- [tsarengine: How we optimized Cascaded Shadow Mapping](https://www.tsarengine.com/Blogs/Article?slug=how-we-optimized-cascaded-shadow-mapping) — Modern engine perspective on CSM optimizations.
- [LWJGL3 Game Dev book chapter 17: Cascade Shadow Maps](https://ahbejarano.gitbook.io/lwjglgamedev/chapter-17) — Java/OpenGL CSM walkthrough.
- [ogldev Tutorial 49: Cascaded Shadow Mapping](https://ogldev.org/www/tutorial49/tutorial49.html) — OpenGL CSM tutorial.
- [NVIDIA SDK: Cascaded Shadow Maps PDF (Dimitrov)](https://developer.download.nvidia.com/SDK/10.5/opengl/src/cascaded_shadow_maps/doc/cascaded_shadow_maps.pdf) — Early CSM whitepaper (2007).
- [iwantthatcake: Cascaded Shadow-Mapping](https://iwantthatcake.wordpress.com/2012/03/05/cascaded-shadow-mapping/) — Hobbyist CSM implementation notes.
- [GameDev.net: View/Projection Matrices for CSM](https://www.gamedev.net/forums/topic/674763-viewprojection-matrices-for-cascaded-shadow-mapping/) — Practitioner Q&A on CSM matrix construction.

## Anti-swimming / filterable shadows

- [MJP: A Sampling of Shadow Techniques](https://therealmjp.github.io/posts/shadow-maps/) — Comprehensive comparison of PCF, VSM, EVSM, MSM with measured performance numbers. **Key reference for Stage 2 decisions.**
- [GameDev.net: Shadow Shimmering When Moving Objects](https://www.gamedev.net/forums/topic/692386-shadow-shimmering-when-moving-objects/) — Confirms "standard CSM stabilization only fixes static geometry."
- [GameDev.net: Shadow map flickering when lights move](https://www.gamedev.net/forums/topic/588182-shadow-map-flickering-when-lights-move/) — Texel-snap rationale from a practitioner discussion.
- [WillP GFX: Dealing with Shadow Map Artifacts](https://willpgfx.com/2015/05/dealing-with-shadow-map-artifacts/) — Modern guide to acne / Peter Panning / slope bias.
- [LearnOpenGL: Shadow Mapping](https://learnopengl.com/Advanced-Lighting/Shadows/Shadow-Mapping) — Basic shadow mapping reference; useful for bias formulas.
- [DigitalRune: Shadow Acne](https://digitalrune.github.io/DigitalRune-Documentation/html/3f4d959e-9c98-4a97-8d85-7a73c26145d7.htm) — Slope-scaled bias details.
- [GitHub: timurson/MomentShadowMapping](https://github.com/timurson/MomentShadowMapping) — Reference MSM implementation.
- [Lousodrome blog: EVSM articles](https://lousodrome.net/blog/light/tag/evsm/) — Lauritzen-style EVSM background.
- [Improved Moment Shadow Maps (JCGT 2017)](https://www.jcgt.org/published/0006/01/03/paper-lowres.pdf) — Modern MSM paper.
- [MJP: Shadow Sample Update](https://therealmjp.github.io/posts/shadow-sample-update/) — Comparison of newer EVSM/MSM variants.
- [NVIDIA: Summed-Area Variance Shadow Maps (GPU Gems 3 Ch. 8)](https://developer.nvidia.com/gpugems/gpugems3/part-ii-light-and-shadows/chapter-8-summed-area-variance-shadow-maps) — SAVSM background.
- [NVIDIA: Shadow Map Antialiasing (GPU Gems Ch. 11)](https://developer.nvidia.com/gpugems/gpugems/part-ii-lighting-and-shadows/chapter-11-shadow-map-antialiasing) — PCF antialiasing techniques.
- [NVIDIA: Percentage-Closer Soft Shadows (Fernando PDF)](https://developer.download.nvidia.com/shaderlibrary/docs/shadow_PCSS.pdf) — PCSS original paper.

## Sample Distribution Shadow Maps (SDSM)

- [ACM: Sample Distribution Shadow Maps (Lauritzen et al., I3D 2011)](https://dl.acm.org/doi/10.1145/1944745.1944761) — SDSM original paper.
- [ResearchGate: Sample distribution Shadow Maps (PDF)](https://www.researchgate.net/publication/220791941_Sample_distribution_Shadow_Maps) — Same paper, PDF host.
- [SlideToDoc: SDSM Evolution Of](https://slidetodoc.com/sdsm-sample-distribution-shadow-maps-the-evolution-of/) — Tutorial slides.
- [bronx's blog: SDSM](http://broniac.blogspot.com/2012/01/sample-distribution-shadow-maps.html) — SDSM implementation notes.
- [ramjam wix: Sample Distribution Shadow Mapping](https://rramillien.wixsite.com/ramjam/sample-distribution-shadow-mapping) — Practitioner SDSM writeup.
- [GameDev.net: SDSM vs PSSM](https://gamedev.net/forums/topic/667207-difference-between-sdsm-and-pssm/5220760/) — Practitioner comparison.

## Floating-point / large-world precision

- [Outerra: Maximizing Depth Buffer Range and Precision](https://outerra.blogspot.com/2012/11/maximizing-depth-buffer-range-and.html) — Reverse-Z + FP32 depth rationale (perspective only).
- [Outerra: Logarithmic Depth Buffer](https://outerra.blogspot.com/2009/08/logarithmic-z-buffer.html) — Alternative for planetary-scale depth.
- [Cornell U: Tightening the Precision of Perspective Rendering (PDF)](https://www.cs.cornell.edu/~paulu/tightening.pdf) — Theory paper on perspective-depth precision.
- [Flax Engine: Large Worlds](https://docs.flaxengine.com/manual/editor/large-worlds/index.html) — Camera-relative rendering reference.
- [Babylon.js: Floating Origin](https://doc.babylonjs.com/features/featuresDeepDive/scene/floating_origin/) — Origin-shifting for huge scenes.
- [Unity HDRP: Camera-Relative Rendering](https://docs.unity3d.com/Packages/com.unity.render-pipelines.high-definition@8.0/manual/Camera-Relative-Rendering.html) — Production engine's approach.
- [Ogre forums: Origin shifting](https://forums.ogre3d.org/viewtopic.php?t=97580) — Practitioner discussion.
- [Ogre forums: Floating point precision and setCameraRelativeRendering](https://forums.ogre3d.org/viewtopic.php?t=73551) — Implementation Q&A.
- [Medium: Floating Point Precision in OpenGL/Vulkan Part 3](https://medium.com/@thibautandrieu/the-problem-of-floating-point-precision-in-opengl-vulkan-and-3d-in-general-part-3-ce101a80995d) — Practitioner deep dive.

## Metal-specific shadow mapping

- [Apple Developer: Tailor your apps for Apple GPUs and tile-based deferred rendering](https://developer.apple.com/documentation/metal/tailor-your-apps-for-apple-gpus-and-tile-based-deferred-rendering) — TBDR best practices applicable to shadow gen.
- [Apple Developer: Deferred Lighting (Obj-C)](https://developer.apple.com/documentation/metal/deferred_lighting) — Reference deferred renderer.
- [Apple Developer: Deferred Lighting (Swift)](https://developer.apple.com/documentation/Metal/rendering-a-scene-with-deferred-lighting-in-swift) — Swift version of the same sample.
- [SamoZ256: Metal API Shadow Mapping Tutorial Part 9](https://medium.com/@samuliak/apples-metal-api-tutorial-part-9-shadow-mapping-b98fac4d3877) — Mid-level Metal shadow mapping walkthrough.
- [Apple Developer Forums: Sampling array of depth2d shows artifacts](https://developer.apple.com/forums/thread/128504) — Practitioner notes on Metal `depth2d_array` gotchas.
- [Apple Developer Forums: Sampler works when debugged from fragment shader](https://developer.apple.com/forums/thread/696135) — Metal sampler debugging.
- [Kodeco: Metal by Tutorials Ch. 15 Tile-Based Deferred Rendering](https://www.kodeco.com/books/metal-by-tutorials/v3.0/chapters/15-tile-based-deferred-rendering) — Reference for the TBDR architecture this repo uses.
- [Medium: Engine Internals: Optimizing for Metal and iOS (Heinäpurola)](https://medium.com/@heinapurola/engine-internals-optimizing-our-renderer-for-metal-and-ios-77aeff5faba) — Practitioner Metal optimization notes.

## Skeletal animation and shadow interactions

- [LearnOpenGL: Skeletal Animation](https://learnopengl.com/Guest-Articles/2020/Skeletal-Animation) — Reference skeletal pipeline.
- [GameDev.net: Combining Deferred rendering, Batching, Model Matrices, Skeletal animations, and shadow maps](https://www.gamedev.net/forums/topic/695775-combining-deferred-rendering-batching-model-matrices-skeletal-animations-and-shadow-maps/5374087/) — Practitioner discussion of the shared-skinning pattern referenced in §2.3.

## PSO/pipeline-side references

- [The Witness: Shadow Mapping Summary Part 1 (Castaño)](http://the-witness.net/news/2013/09/shadow-mapping-summary-part-1/) — Production-game shadow mapping retrospective.
- [Ludicon: Shadow Mapping Summary Part 1 (Castaño mirror)](https://www.ludicon.com/castano/blog/articles/shadow-mapping-summary-part-1/) — Same article, alternate host.
- [GameDev.net: Shadow Mapping Part 4 Bilinear PCF](https://gamedev.net/blogs/entry/2261590-shadow-mapping-part-4-bilinear-pcf/) — Bilinear PCF implementation notes.
- [Opengl-tutorial: Shadow Mapping Tutorial 16](http://www.opengl-tutorial.org/intermediate-tutorials/tutorial-16-shadow-mapping/) — Basic shadow mapping reference.
- [Stevestreeting: UE 5.5 Skeletal Animation / LastRenderTime bug](https://www.stevestreeting.com/2025/05/22/ue-5.5-skeletal-animation-/-lastrendertime-bug/) — Tangentially relevant (skeletal animation + visibility queries).
