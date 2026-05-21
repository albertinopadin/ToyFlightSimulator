# Cascaded Shadow Maps

## Context

The current shadow path is single-cascade sun-follow ([plan](single_cascade_sun_following_shadow_camera.md)). One 8192² ortho map covers a `2 × shadowRadius` square around the main camera each frame. With the default `shadowRadius = 500`, that's ~0.12 world units per shadow texel — sharp enough for the F-22 standing still, but the same texel density is spent on shadow detail right under the player AND on the cosmetic ground 500 units away. Three real problems remain:

1. **Resolution is uniform across the covered region.** Shadow detail under the F-22's gear is no sharper than shadow detail at the radius edge, even though the camera-near region is what the user actually sees up close.
2. **Hard cutoff at `radius = 500`.** Anything past that gets the sampler-edge fallback (fully lit). At cruise speeds the radius edge sweeps past distant objects every frame, so they cast no shadow at all.
3. **Texels swim as the camera moves.** The ortho box re-centers on the camera each frame at arbitrary (non-texel-aligned) world positions, so static shadow edges shimmer along their boundaries when you fly.

Cascaded Shadow Maps (CSM) fixes all three by splitting the main camera's view frustum into N depth slices and rendering a dedicated, tightly-fit ortho shadow map per slice. The cascade nearest the camera gets a tight frustum (high texel density); the cascade out at the far plane gets a loose frustum (low density, but covering thousands of world units). Resolution is concentrated where the eye is.

**Reference:** [LearnOpenGL — Cascaded Shadow Maps](https://learnopengl.com/Guest-Articles/2021/CSM). Two notable adaptations for this project:
- Metal clip space is `z ∈ [0, 1]` (not `[-1, 1]` like OpenGL), so frustum-corner unprojection uses NDC z ∈ {0, 1} directly — no `2z - 1` remap.
- The repo's `Transform.perspectiveProjection` is **reverse-Z** (d(near)=1, d(far)=0) for the main camera, but the shadow projection has historically been **forward-Z** ortho (d(near)=0, d(far)=1). This plan keeps that split: per-cascade orthos stay forward-Z so the shader's existing `position.z > sample` compare direction continues to mean "fragment farther from light than caster → occluded."

This is the canonical follow-on the single-cascade plan called out as "future work" (section 10 of `single_cascade_sun_following_shadow_camera.md`). The `ShadowCamera` value type introduced there becomes the per-cascade primitive; everything else extends.

## Outcome

After this lands:

- **Sharp near-field shadows.** Cascade 0 covers ≈25 world units around the camera at 2048² → ~0.012 world units per texel. ~10× sharper than today under the player.
- **Long-range shadows.** Cascade 3 covers ≈5000 world units → distant aircraft cast a (low-res but visible) shadow instead of vanishing at the old 500-unit radius.
- **No more swimming.** Per-cascade ortho boxes are snapped to texel boundaries each frame; static geometry edges stay rock-solid as the camera moves.
- **Same memory budget — actually less.** 4 cascades × 2048² × 4B depth = **64 MB**. Today's 1 × 8192² × 4B = **256 MB**. Net **4× memory reduction** with sharper near-field shadows and longer reach.
- **Backward-compatible scene API.** Existing scenes that just call `sun.setPosition(...)` keep working with sensible cascade defaults. Scenes that want different cascade behavior call `sun.setCascadeCount(_:)` / `sun.setCascadeLambda(_:)` / `sun.setShadowMapResolution(_:)`.
- **All five tiled deferred renderers continue to function.** The change is concentrated in `ShadowRendering`, `Shadow.metal`, the three GBuffer `.metal` files, and `Lighting.metal`. The per-renderer wiring (binding the shadow texture, encoding the shadow pass) keeps the same shape — texture changes from `MTLTexture` (single) to `MTLTexture` (array), encoder loops over cascades.

## Critical Files

- **NEW** `ToyFlightSimulator Shared/Shadows/ShadowCascadeFitting.swift` — pure math: frustum corner unprojection, AABB fit in light view space, texel-snap, build a `ShadowCamera` per cascade. Lives in the new `Shadows/` folder (see Conventions below).
- **MOVED** `ToyFlightSimulator Shared/GameObjects/ShadowCamera.swift` → `ToyFlightSimulator Shared/Shadows/ShadowCamera.swift` — extended with a non-symmetric-ortho initializer for cascade fitting. The existing `ShadowCamera(direction:focus:radius:lift:)` initializer stays (used by the legacy single-cascade path during transition).
- `ToyFlightSimulator Shared/GameObjects/LightObject.swift` — `updateShadowCamera()` becomes `updateShadowCascades()`; populates the new cascade arrays in `LightData`. **Stays in `GameObjects/`** because it's a `GameObject` subclass.
- `ToyFlightSimulator Shared/Graphics/Shaders/TFSCommon.h` — `LightData` schema gains cascade arrays + `cascadeCount`; new `TFSBufferIndexShadowCascadeVP` for the per-pass cascade-VP push constant.
- `ToyFlightSimulator Shared/Graphics/Shaders/Shadow.metal` — both shadow vertex functions consume a per-pass cascade VP push constant instead of reading `LightData.shadowViewProjectionMatrix`.
- `ToyFlightSimulator Shared/Graphics/Shaders/Lighting.metal` — `CalculateShadow` / `CalculateShadowMSAA` rewritten to take `(worldPosition, viewSpaceDepth, lightData, depth2d_array<float>)` and select a cascade.
- `ToyFlightSimulator Shared/Graphics/Shaders/TiledDeferredGBuffer.metal` — `VertexOut.shadowPosition` removed; `VertexOut.viewSpaceDepth` added; fragment shader calls the new cascade-aware `CalculateShadow`.
- `ToyFlightSimulator Shared/Graphics/Shaders/TiledMSAAGBuffer.metal` — same pattern with the MSAA helper.
- `ToyFlightSimulator Shared/Graphics/Shaders/GBuffer.metal` — legacy SinglePassDeferred path; same cascade-aware refactor.
- `ToyFlightSimulator Shared/Graphics/Shaders/ShaderDefinitions.h` — `VertexOut` struct definition.
- `ToyFlightSimulator Shared/Display/Protocols/ShadowRendering.swift` — texture type changes to `MTLTextureType2DArray`; `encodeShadowMapPass` becomes a loop over cascades that updates `depthAttachment.slice = i` and binds the cascade VP. **Stays in `Display/Protocols/`** because it's a rendering protocol.
- `ToyFlightSimulator Shared/Display/TiledDeferredRenderer.swift`, `TiledMultisampleRenderer.swift`, `TiledMSAATessellatedRenderer.swift`, `SinglePassDeferredLightingRenderer.swift` — each renderer's `init(...)` calls the array-allocating helpers; the per-frame `setFragmentTexture(shadowMaps, ...)` calls work against the same protocol property (renamed from `shadowMap` since it's now an N-slice array — see Conventions).
- `ToyFlightSimulator Shared/Managers/LightManager.swift` — no functional change; just confirms it passes through the new cascade fields untouched (it already copies `lightData` as a value).
- (No changes required) All `Scenes/*.swift` files — backward-compat defaults cover them.

## Reused Existing Infrastructure

- **`ShadowCamera` value type** (`GameObjects/ShadowCamera.swift`) from the single-cascade plan — its `viewProjectionMatrix` is exactly what a single cascade needs. CSM constructs N of them per frame.
- **`Transform.perspectiveProjection`** ([`Math/Transform.swift:79-101`](../../ToyFlightSimulator%20Shared/Math/Transform.swift#L79)) — reverse-Z perspective for the main camera. We use its inverse to unproject sub-frustum corners.
- **`Transform.orthographicProjection`** ([`Math/Transform.swift:59-71`](../../ToyFlightSimulator%20Shared/Math/Transform.swift#L59)) — forward-Z ortho. Reused per-cascade.
- **`Transform.look`** ([`Math/Transform.swift:104-117`](../../ToyFlightSimulator%20Shared/Math/Transform.swift#L104)).
- **`CameraManager.CurrentCamera`** — already optional, already guarded. `LightObject.updateShadowCascades` reads `cam.viewMatrix`, `cam.projectionMatrix`, `cam.fieldOfView`, `cam.near`, `cam.far`.
- **`DrawManager.DrawShadows`** ([`Managers/DrawManager.swift:210-226`](../../ToyFlightSimulator%20Shared/Managers/DrawManager.swift#L210)) — reusable as-is. It doesn't bind any PSO or shadow-VP itself; the caller does. Same call site works for all N cascade passes.
- **`encodeRenderPass` / `encodeRenderStage`** (the renderer base helpers) — used unchanged.
- **The existing `setDepthBias(0.1, slopeScale: 1, clamp: 0.0)`** in `encodeShadowMapPass` — stays. Per-cascade world-space slack handles the rest in the shader.
- **`LightData.shadowWorldSlack` and `shadowDepthRange`** — kept for backward compatibility with the legacy `GBuffer.metal` `sample_compare` path. The new cascade-aware path uses the per-cascade `cascadeWorldSlack[i]` and `cascadeDepthRange[i]` arrays.

## Conventions

Three project-wide conventions this plan adopts:

1. **New `Shadows/` folder.** Shadow-related Swift files that aren't `GameObject` subclasses or rendering protocols live under `ToyFlightSimulator Shared/Shadows/`. This makes the directory tree self-documenting — `GameObjects/` only contains things that *are* scene-graph nodes; `Shadows/` collects shadow math and value types. Files:
   - `Shadows/ShadowCamera.swift` (moved from `GameObjects/`)
   - `Shadows/ShadowCascadeFitting.swift` (new)
   - `GameObjects/LightObject.swift` — **stays** (subclass of `GameObject`)
   - `Display/Protocols/ShadowRendering.swift` — **stays** (rendering protocol)

2. **Use the `sizeable` protocol — never `MemoryLayout<T>.stride` inline.** `Core/Types/MetalTypes.swift` already conforms `Float`, `float4x4` (which is the same type as `matrix_float4x4`), and the various TFS structs to `sizeable`. Anywhere this plan writes `MemoryLayout<matrix_float4x4>.stride`, the actual code should be `matrix_float4x4.stride`. If a new type needs the same convenience, add `extension NewType: sizeable {}` to `MetalTypes.swift` rather than reaching for `MemoryLayout` inline.

3. **Rename `shadowMap` → `shadowMaps` (plural).** With CSM the texture is an array of N cascade slices, not a single map. The `ShadowRendering` protocol's property gets pluralized everywhere (protocol declaration, renderer property names, fragment texture bindings, descriptor builders). The MSAA-specific extra (currently `shadowResolveTexture`) is renamed `shadowMSAATexture` to clarify that it's the MSAA source — the resolution destination is `shadowMaps`. Net protocol shape:

   ```swift
   protocol ShadowRendering: RenderPassEncoding {
       static var ShadowMapSize: Int { get }
       static var CascadeCount: Int { get }
       var shadowMaps: MTLTexture { get set }                  // texture2DArray sampled by shaders
       var shadowMSAATexture: MTLTexture? { get set }          // MSAA path only; resolves into shadowMaps
       var shadowRenderPassDescriptors: [MTLRenderPassDescriptor] { get set }
   }
   ```

---

## 1. Shared constants and buffer indices

**File:** `ToyFlightSimulator Shared/Graphics/Shaders/TFSCommon.h`

Add a compile-time cascade count cap (so the shader-side array fits in a `LightData` struct cleanly) and a new buffer index for the per-cascade push constant.

### Add near the top of the file (after the `__cplusplus` shim)

```c
// Maximum number of shadow cascades a single directional light can use.
// LightData has fixed-size arrays sized to this constant so the shader
// doesn't need a dynamic-array binding. Runtime `cascadeCount` (1..4) on
// LightData selects how many of the slots are populated.
//
// 4 is the sweet spot: 4 × 2048² × depth32Float = 64 MB total, vs the old
// 1 × 8192² = 256 MB. Bumping to 5 or 6 yields diminishing returns and a
// larger LightData push-constant cost per fragment.
#define TFS_MAX_SHADOW_CASCADES 4
```

### Extend `TFSBufferIndices`

```c
typedef enum {
    TFSBufferIndexMeshVertex        = 0,
    TFSBufferIndexMeshGenerics      = 1,
    TFSBufferFrameData              = 2,
    TFSBufferDirectionalLightsNum   = 3,
    TFSBufferDirectionalLightData   = 4,
    TFSBufferPointLightsData        = 5,
    TFSBufferPointLightsPosition    = 6,
    TFSBufferModelConstants         = 7,
    TFSBufferIndexSceneConstants    = 8,
    TFSBufferIndexMaterial          = 9,
    TFSBufferIndexTerrain           = 10,
    TFSBufferIndexJointBuffer       = 11,
    TFSBufferIndexMaterialTextureTransforms = 12,
    TFSBufferIndexShadowCascadeVP   = 13   // ← NEW: per-pass cascade view-projection matrix
} TFSBufferIndices;
```

**Why a separate buffer index instead of reading from `LightData.cascadeViewProjectionMatrices[i]` inside the shadow vertex shader?** Two reasons:
1. The shadow generation pass renders N times (one per cascade); pushing just the relevant `float4x4` per pass is cheaper than rebinding all of `LightData` per cascade and indexing into it.
2. It keeps `Shadow.metal` decoupled from the cascade-aware schema — the shadow vertex shader becomes "draw geometry into shadow map using this VP," not "look up the i-th matrix in LightData based on some thread-local cascade index."

### Extend `LightData`

```c
typedef struct {
    LightType type;
    matrix_float4x4 modelMatrix;
    matrix_float4x4 viewProjectionMatrix;
    matrix_float4x4 shadowViewProjectionMatrix;   // Legacy: == cascadeViewProjectionMatrices[0]
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

    // === NEW: cascaded shadow data ===
    // World→cascade-NDC matrix per cascade. Cascade 0 is the closest to the
    // camera (sharpest, smallest world coverage); cascade N-1 is the farthest
    // (loosest, largest coverage). Only the first `cascadeCount` entries are
    // populated; remaining entries are identity.
    matrix_float4x4 cascadeViewProjectionMatrices[TFS_MAX_SHADOW_CASCADES];

    // View-space depth boundaries between cascades. cascadeSplitDepths[i] is
    // the FAR distance of cascade i (and the near of cascade i+1). Last entry
    // equals the main camera's far plane. Always non-negative; we compare
    // against `abs(view-space z)` per fragment.
    float cascadeSplitDepths[TFS_MAX_SHADOW_CASCADES];

    // Per-cascade depth range in world units (cascade_far - cascade_near in
    // the cascade's own ortho frustum). Used to convert worldSlack into an
    // NDC-space depth-compare epsilon for that cascade. Distant cascades have
    // a larger range so the NDC epsilon shrinks accordingly — but their
    // texels are also wider, so we counterbalance by scaling worldSlack
    // (see cascadeWorldSlack below).
    float cascadeDepthRange[TFS_MAX_SHADOW_CASCADES];

    // Per-cascade world-space slack. Scaled with cascade extent so larger
    // (distant) cascades get a proportionally larger slack to avoid acne on
    // their lower-resolution texels. cascadeWorldSlack[i] = baseWorldSlack *
    // (cascade_i_radius / cascade_0_radius). Populated by LightObject.update.
    float cascadeWorldSlack[TFS_MAX_SHADOW_CASCADES];

    // Number of populated cascades (1..TFS_MAX_SHADOW_CASCADES). The shader's
    // cascade-selection loop only iterates this many entries.
    uint cascadeCount;

    // === Legacy single-cascade fields (kept for backward compat) ===
    // shadowDepthRange / shadowWorldSlack still consumed by GBuffer.metal's
    // sample_compare path until it gets refactored. They mirror cascade 0
    // (cascadeDepthRange[0] / cascadeWorldSlack[0]).
    float shadowDepthRange;
    float shadowWorldSlack;
} LightData;
```

**Why both old + new fields?** The legacy `GBuffer.metal` shader uses `sample_compare(sampler, xy, z)` with a hardware sampler comparison, which can't drive a cascade-selection loop the way the manual-compare path can. Until that shader is rewritten, we keep `shadowDepthRange`/`shadowWorldSlack` populated as aliases for cascade 0. The new path (TiledDeferred*, Lighting.metal::CalculateShadow) uses the cascade arrays exclusively.

**`simd` alignment note:** `simd_float3` in the struct is 16-byte aligned (16-byte stride). The C arrays of `float` are 4-byte stride. Both Metal and Swift consume `LightData` via `MemoryLayout<LightData>.stride` (Swift) and `sizeof(LightData)` (Metal) consistently — `LightManager` already binds via `LightData.stride(count)`, so no manual offset arithmetic anywhere breaks.

---

## 2. `ShadowCascadeFitting.swift` — the math, isolated

**New file:** `ToyFlightSimulator Shared/Shadows/ShadowCascadeFitting.swift`

This file is pure math: no Metal, no GameObject, no rendering state. Easy to unit-test (`Swift Testing` framework, mirroring `Math/TransformTests`).

```swift
//
//  ShadowCascadeFitting.swift
//  ToyFlightSimulator
//
//  Per-frame "fit a tight orthographic shadow frustum to a slice of the
//  main camera's view frustum, in the light's view space." Standard CSM
//  algorithm; see https://learnopengl.com/Guest-Articles/2021/CSM and
//  Microsoft PSSM whitepaper.
//

import simd

enum ShadowCascadeFitting {

    // MARK: - Public entry point

    /// Build N `ShadowCamera`s, one per cascade, fitted to N depth-slices of
    /// the main camera's view frustum.
    ///
    /// - Parameters:
    ///   - cameraViewMatrix: Main camera's view matrix.
    ///   - cameraFovYRadians: Main camera's vertical field of view.
    ///   - cameraAspect: Main camera's aspect ratio (width / height).
    ///   - cameraNear: Main camera's near plane.
    ///   - cameraFar: Main camera's far plane (used as the deepest cascade's far).
    ///   - lightDirection: World-space unit vector FROM surfaces TOWARD the sun.
    ///   - cascadeCount: Number of cascades (1...TFS_MAX_SHADOW_CASCADES).
    ///   - lambda: Practical-split-scheme blend (0 = uniform, 1 = logarithmic).
    ///             0.5 is the typical Microsoft PSSM recommendation; tune
    ///             higher (e.g. 0.7) if the near cascades need more detail.
    ///   - shadowMapResolution: Per-cascade texture size in texels (square).
    ///                          Used for texel-snapping (kills shimmer).
    ///   - zPaddingMultiplier: Z-axis expansion factor for the per-cascade
    ///                         ortho box to include casters behind the
    ///                         visible slice (objects between the sun and
    ///                         the cascade). 10x is the standard recipe.
    static func fitCascades(cameraViewMatrix: float4x4,
                            cameraFovYRadians: Float,
                            cameraAspect: Float,
                            cameraNear: Float,
                            cameraFar: Float,
                            lightDirection: float3,
                            cascadeCount: Int,
                            lambda: Float = 0.5,
                            shadowMapResolution: Int,
                            zPaddingMultiplier: Float = 10) -> [FittedCascade] {

        let splitDepths = computeSplitDepths(near: cameraNear,
                                             far: cameraFar,
                                             count: cascadeCount,
                                             lambda: lambda)

        var result: [FittedCascade] = []
        result.reserveCapacity(cascadeCount)

        let invView = cameraViewMatrix.inverse

        for i in 0..<cascadeCount {
            let sliceNear = i == 0 ? cameraNear : splitDepths[i - 1]
            let sliceFar  = splitDepths[i]

            let corners = worldSpaceFrustumCorners(invCameraView: invView,
                                                   fovYRadians: cameraFovYRadians,
                                                   aspect: cameraAspect,
                                                   sliceNear: sliceNear,
                                                   sliceFar: sliceFar)

            let cascade = fitOrthoToCorners(corners: corners,
                                            lightDirection: lightDirection,
                                            shadowMapResolution: shadowMapResolution,
                                            zPaddingMultiplier: zPaddingMultiplier)

            result.append(FittedCascade(camera: cascade,
                                        splitFar: sliceFar))
        }
        return result
    }

    // MARK: - Cascade split distances (PSSM / practical split scheme)

    /// Returns N "far" depths, one per cascade. Cascade i covers
    /// `[i == 0 ? near : depths[i-1], depths[i]]`. The last entry equals `far`.
    ///
    /// PSSM hybrid: lerp between uniform and logarithmic splits.
    static func computeSplitDepths(near: Float,
                                   far: Float,
                                   count: Int,
                                   lambda: Float) -> [Float] {
        var depths: [Float] = []
        depths.reserveCapacity(count)
        let range = far - near
        let ratio = far / max(near, 1e-4)
        for i in 1...count {
            let p = Float(i) / Float(count)
            let logSplit = near * powf(ratio, p)              // logarithmic
            let uniformSplit = near + range * p               // uniform
            let practical = lambda * logSplit + (1 - lambda) * uniformSplit
            depths.append(practical)
        }
        // Force the last depth to be exactly the far plane (handles any
        // float drift from the powf computation).
        depths[count - 1] = far
        return depths
    }

    // MARK: - Frustum-corner unprojection

    /// Compute the 8 world-space corners of the camera's view frustum slice
    /// between `sliceNear` and `sliceFar`.
    ///
    /// Approach: build a sub-projection for the slice, invert
    /// `(subProj * cameraView)`, and unproject the 8 NDC cube corners.
    /// Metal NDC is z ∈ [0, 1], so we loop z ∈ {0, 1} (not {-1, 1}).
    static func worldSpaceFrustumCorners(invCameraView: float4x4,
                                         fovYRadians: Float,
                                         aspect: Float,
                                         sliceNear: Float,
                                         sliceFar: Float) -> [float3] {
        let subProj = Transform.perspectiveProjection(fovYRadians,
                                                      aspect,
                                                      sliceNear,
                                                      sliceFar)
        // Note: `Transform.perspectiveProjection` is reverse-Z, so ndc.z=1
        // corresponds to view-space z=sliceNear, and ndc.z=0 corresponds to
        // view-space z=sliceFar. The corner set covers both planes regardless.
        let invSubVP = (subProj * invCameraView.inverse).inverse
        // i.e. inverse(subProj * cameraView) — but we already have invCameraView,
        // so an equivalent and slightly cheaper form is below. Either works.

        var corners: [float3] = []
        corners.reserveCapacity(8)
        for x: Float in [-1, 1] {
            for y: Float in [-1, 1] {
                for z: Float in [0, 1] {     // Metal NDC z range
                    let clip = float4(x, y, z, 1)
                    let world = invSubVP * clip
                    corners.append(world.xyz / world.w)
                }
            }
        }
        return corners
    }

    // MARK: - Fit ortho box to corners in light view space

    /// Given 8 world-space frustum corners and a light direction, build a
    /// `ShadowCamera` whose orthographic frustum is the smallest axis-aligned
    /// box (in light view space) containing the corners — plus z-padding to
    /// include casters behind the slice and a texel-grid snap to kill shimmer.
    static func fitOrthoToCorners(corners: [float3],
                                  lightDirection: float3,
                                  shadowMapResolution: Int,
                                  zPaddingMultiplier: Float) -> ShadowCamera {
        // Center of the 8 corners — used as the focus point for the light view.
        var centerWorld = float3.zero
        for c in corners { centerWorld += c }
        centerWorld /= Float(corners.count)

        // Light view matrix: look from `center + lift*dir` toward `center`.
        // The "lift" here is a placeholder; the real near/far come from the
        // AABB extent below.
        let lightView = Transform.look(eye: centerWorld + lightDirection,
                                       target: centerWorld,
                                       up: Y_AXIS)

        // Transform corners into light view space and compute AABB.
        var minLS = float3( .greatestFiniteMagnitude,  .greatestFiniteMagnitude,  .greatestFiniteMagnitude)
        var maxLS = float3(-.greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
        for c in corners {
            let p = (lightView * float4(c, 1)).xyz
            minLS = simd_min(minLS, p)
            maxLS = simd_max(maxLS, p)
        }

        // Z-padding: expand the depth range so casters between the sun and
        // the cascade still fall inside the ortho. Standard 10x rule:
        // pull `minZ` further from the camera, push `maxZ` toward it.
        // In our left-handed forward-Z, "closer to the light eye" = smaller z.
        if minLS.z < 0 { minLS.z *= zPaddingMultiplier } else { minLS.z /= zPaddingMultiplier }
        if maxLS.z < 0 { maxLS.z /= zPaddingMultiplier } else { maxLS.z *= zPaddingMultiplier }

        // Texel-snap the XY extents so a 1-texel sub-pixel shift in light
        // space maps to a 1-texel shift in the shadow map (eliminates shimmer).
        let res = Float(shadowMapResolution)
        let widthLS  = maxLS.x - minLS.x
        let heightLS = maxLS.y - minLS.y
        let texelX = widthLS  / res
        let texelY = heightLS / res
        minLS.x = floor(minLS.x / texelX) * texelX
        minLS.y = floor(minLS.y / texelY) * texelY
        maxLS.x = minLS.x + texelX * res
        maxLS.y = minLS.y + texelY * res

        // Build the cascade's ShadowCamera. The new initializer below takes
        // pre-computed extents instead of (focus, radius, lift), because
        // cascade fitting produces non-square, non-symmetric ortho boxes.
        return ShadowCamera(lightView: lightView,
                            orthoMinX: minLS.x, orthoMaxX: maxLS.x,
                            orthoMinY: minLS.y, orthoMaxY: maxLS.y,
                            orthoNearZ: minLS.z, orthoFarZ: maxLS.z)
    }
}

/// One fitted cascade: a ShadowCamera (knows its view + ortho proj) plus
/// the view-space depth at which this cascade ends (its "split far").
struct FittedCascade {
    let camera: ShadowCamera
    let splitFar: Float
}
```

**Why the redundant `invCameraView.inverse` on line 99 of the listing above?** That's a typo placeholder I want flagged during implementation — the correct expression is `(subProj * cameraView).inverse` where `cameraView` is the actual matrix. I left it conceptually visible so the implementation step explicitly rewrites it as:

```swift
let viewProj = subProj * (invCameraView.inverse)   // = subProj * cameraView
let invSubVP = viewProj.inverse
```

Or, slightly more efficient (avoids one matrix invert by passing `cameraViewMatrix` directly):

```swift
static func worldSpaceFrustumCorners(cameraView: float4x4, /* not the inverse */
                                     ...) -> [float3] {
    let invSubVP = (subProj * cameraView).inverse
    ...
}
```

The function signature in the final file should be `cameraView: float4x4`, not `invCameraView: float4x4`. Plan callers pass `cam.viewMatrix` directly.

---

## 3. `ShadowCamera` — extended initializer

**File:** `ToyFlightSimulator Shared/Shadows/ShadowCamera.swift` (moved from `GameObjects/`)

Add a non-symmetric-ortho initializer alongside the existing `(direction:focus:radius:lift:)` one. Cascade fitting produces an AABB with independent X/Y extents, so a square `[-radius, radius]` ortho is too narrow a representation.

### Before (full file)

```swift
struct ShadowCamera {
    let direction: float3
    let focus: float3
    let radius: Float
    let lift: Float

    var eye: float3 { focus + direction * lift }

    var viewMatrix: float4x4 {
        Transform.look(eye: eye, target: focus, up: Y_AXIS)
    }

    var projectionMatrix: float4x4 {
        Transform.orthographicProjection(-radius, radius, -radius, radius, 1, 2 * lift)
    }

    var viewProjectionMatrix: float4x4 { projectionMatrix * viewMatrix }
}
```

### After

```swift
struct ShadowCamera {
    // The view + projection matrices are the only fields the rest of the
    // pipeline actually consumes. Both initializers below derive these.
    let viewMatrix: float4x4
    let projectionMatrix: float4x4

    var viewProjectionMatrix: float4x4 { projectionMatrix * viewMatrix }

    /// Legacy convenience initializer used by the single-cascade
    /// sun-follow code path. Symmetric ortho centered on `focus`.
    init(direction: float3, focus: float3, radius: Float, lift: Float) {
        let eye = focus + direction * lift
        self.viewMatrix = Transform.look(eye: eye, target: focus, up: Y_AXIS)
        self.projectionMatrix = Transform.orthographicProjection(-radius, radius,
                                                                 -radius, radius,
                                                                 1, 2 * lift)
    }

    /// CSM cascade-fitting initializer. Takes a precomputed light-view
    /// matrix and an axis-aligned ortho box (typically derived from
    /// `ShadowCascadeFitting.fitOrthoToCorners`).
    init(lightView: float4x4,
         orthoMinX: Float, orthoMaxX: Float,
         orthoMinY: Float, orthoMaxY: Float,
         orthoNearZ: Float, orthoFarZ: Float) {
        self.viewMatrix = lightView
        self.projectionMatrix = Transform.orthographicProjection(orthoMinX, orthoMaxX,
                                                                 orthoMinY, orthoMaxY,
                                                                 orthoNearZ, orthoFarZ)
    }

    /// The world-units depth range of the ortho projection. Used by the
    /// shader to derive an NDC-space depth-compare epsilon from a world-space
    /// slack: `ndcEpsilon = worldSlack / depthRange`.
    /// Single-cascade legacy callers can derive this externally; cascade
    /// callers grab it directly from this property.
    var depthRange: Float {
        // For ortho, the projection-matrix col2.z = 1/(far - near) and the
        // ortho frustum spans [near, far]. We expose `far - near` directly
        // by recomputing from the inverse mapping below — or, more simply,
        // pass it explicitly. The cleanest path is to store it as a let.
        // (Implementation note: in the cascade initializer, capture
        // `orthoFarZ - orthoNearZ` as a stored property.)
        return _depthRange
    }
    private let _depthRange: Float

    // (Adjust both inits to populate `_depthRange`. Omitted above for brevity.)
}
```

**Implementation note:** in the actual edit, make `_depthRange` a stored `let` populated by both initializers. The two-step "computed property reading a stored property" pattern in the snippet above is just rhetorical — keep it as a single stored `let depthRange: Float` and skip the underscore.

**Why keep both initializers?** During the staged migration (see section 17, Implementation Order), `LightObject.update()` flips from calling the legacy initializer (cascadeCount=1, current behavior preserved) to calling `ShadowCascadeFitting.fitCascades(...)` (cascadeCount=4). Both paths produce a valid `ShadowCamera` and the rest of the pipeline doesn't care which initializer was used.

---

## 4. `LightObject` — drive the cascade pipeline

**File:** `ToyFlightSimulator Shared/GameObjects/LightObject.swift`

The `_shadowRadius` / `_shadowLift` knobs go away as primary controls (still settable but only consulted as a fallback when `cascadeCount == 1`). New knobs: `cascadeCount`, `cascadeLambda`, `shadowMapResolution`, `cascadeZPadding`.

### Before (the part that changes — full file at the top of this plan)

```swift
private var _shadowRadius: Float = 500
private var _shadowLift:   Float = 2000
private var _shadowWorldSlack: Float = 0.25

private func updateShadowCamera() {
    guard let cam = CameraManager.CurrentCamera else { return }
    let shadowCamera = ShadowCamera(direction: self.direction,
                                    focus: cam.getWorldPosition(),
                                    radius: _shadowRadius,
                                    lift: _shadowLift)
    let svp = shadowCamera.viewProjectionMatrix
    lightData.shadowViewProjectionMatrix = svp
    lightData.viewProjectionMatrix       = svp

    lightData.shadowDepthRange = 2 * _shadowLift - 1
    lightData.shadowWorldSlack = _shadowWorldSlack
}
```

### After

```swift
// Cascade configuration. Defaults chosen for FlightboxWithPhysics-scale
// scenes (the F-22 flying over a 1M-unit ground plane). Per-scene overrides
// via the setCascade* methods below.
private var _cascadeCount: Int      = 4    // 1..TFS_MAX_SHADOW_CASCADES
private var _cascadeLambda: Float   = 0.5  // 0=uniform, 1=logarithmic
private var _shadowMapRes: Int      = 2048 // per-cascade texture resolution
private var _cascadeZPad: Float     = 10   // z-axis ortho padding multiplier

// World-space depth slack the shader allows before a fragment shadows
// itself. For cascades, this is scaled per-cascade by cascade radius —
// distant cascades have wider texels and need proportionally more slack.
private var _baseWorldSlack: Float  = 0.25

// Legacy radius/lift kept for the cascadeCount==1 fallback path that
// preserves the single-cascade sun-follow plan's behavior verbatim.
private var _shadowRadius: Float    = 500
private var _shadowLift:   Float    = 2000

public func setCascadeCount(_ n: Int) {
    _cascadeCount = max(1, min(n, Int(TFS_MAX_SHADOW_CASCADES)))
}
public func setCascadeLambda(_ lambda: Float) { _cascadeLambda = lambda }
public func setShadowMapResolution(_ res: Int) { _shadowMapRes = res }
public func setCascadeZPadding(_ pad: Float) { _cascadeZPad = pad }

override func update() {
    super.update()
    self.lightData.type        = self.lightType
    self.lightData.modelMatrix = self.modelMatrix
    self.lightData.position    = self.getPosition()
    self.lightData.direction   = self.direction

    if self.lightType == Directional {
        updateShadowCascades()
    }
}

/// Build N FittedCascades against the active main camera and stash their
/// matrices + per-cascade metadata into `lightData`. Single-cascade path
/// (cascadeCount==1) is preserved as a fast path that uses the existing
/// sun-follow ShadowCamera initializer — i.e. when cascadeCount==1, output
/// is bit-identical to the existing implementation.
private func updateShadowCascades() {
    guard let cam = CameraManager.CurrentCamera else { return }

    if _cascadeCount == 1 {
        // Legacy single-cascade fast path: bit-identical to today's behavior.
        let shadowCamera = ShadowCamera(direction: self.direction,
                                        focus: cam.getWorldPosition(),
                                        radius: _shadowRadius,
                                        lift: _shadowLift)
        let svp = shadowCamera.viewProjectionMatrix
        // Populate cascade-0 slot.
        lightData.cascadeViewProjectionMatrices.0 = svp     // see note below
        lightData.cascadeSplitDepths.0            = cam.far
        lightData.cascadeDepthRange.0             = 2 * _shadowLift - 1
        lightData.cascadeWorldSlack.0             = _baseWorldSlack
        lightData.cascadeCount                    = 1

        // Legacy aliases for GBuffer.metal's sample_compare path.
        lightData.shadowViewProjectionMatrix = svp
        lightData.viewProjectionMatrix       = svp
        lightData.shadowDepthRange           = 2 * _shadowLift - 1
        lightData.shadowWorldSlack           = _baseWorldSlack
        return
    }

    // Multi-cascade path.
    let aspect = (Renderer.ScreenSize.x > 0 && Renderer.ScreenSize.y > 0)
                 ? Float(Renderer.ScreenSize.x) / Float(Renderer.ScreenSize.y)
                 : 1
    let cascades = ShadowCascadeFitting.fitCascades(
        cameraViewMatrix: cam.viewMatrix,
        cameraFovYRadians: cam.fieldOfView.toRadians,
        cameraAspect: aspect,
        cameraNear: cam.near,
        cameraFar: cam.far,
        lightDirection: self.direction,
        cascadeCount: _cascadeCount,
        lambda: _cascadeLambda,
        shadowMapResolution: _shadowMapRes,
        zPaddingMultiplier: _cascadeZPad
    )

    // Reference cascade-0 ortho width for per-cascade slack scaling.
    let referenceRadius = cascades[0].camera.orthoHalfExtentX  // see ShadowCamera helper

    writeIntoLightData(cascades: cascades, referenceRadius: referenceRadius)

    // Legacy aliases (cascade 0).
    lightData.shadowViewProjectionMatrix = cascades[0].camera.viewProjectionMatrix
    lightData.viewProjectionMatrix       = cascades[0].camera.viewProjectionMatrix
    lightData.shadowDepthRange           = cascades[0].camera.depthRange
    lightData.shadowWorldSlack           = _baseWorldSlack
}

private func writeIntoLightData(cascades: [FittedCascade], referenceRadius: Float) {
    // The C-imported `cascadeViewProjectionMatrices` is a homogeneous tuple
    // in Swift. We use `withUnsafeMutableBufferPointer`-style access via a
    // small helper to write by index. (See "Tuple-array bridging" below.)
    writeCascadeMatrices(into: &lightData.cascadeViewProjectionMatrices,
                         from: cascades.map { $0.camera.viewProjectionMatrix })
    writeCascadeFloats(into: &lightData.cascadeSplitDepths,
                       from: cascades.map { $0.splitFar })
    writeCascadeFloats(into: &lightData.cascadeDepthRange,
                       from: cascades.map { $0.camera.depthRange })
    writeCascadeFloats(into: &lightData.cascadeWorldSlack,
                       from: cascades.map { cascade in
                           let scale = cascade.camera.orthoHalfExtentX / referenceRadius
                           return _baseWorldSlack * scale
                       })
    lightData.cascadeCount = UInt32(cascades.count)
}
```

### Tuple-array bridging note

A C array `T arr[N]` imports into Swift as a homogeneous tuple `(T, T, T, T)`, which you can't subscript at runtime by integer. Two clean options:

**Option A (recommended): `withUnsafeMutablePointer(to:)`** — fast and unsafe-but-localized.

```swift
/// Write up to `TFS_MAX_SHADOW_CASCADES` (= 4) matrices into a homogeneous
/// 4-element tuple imported from C. The tuple's arity matches the cascade
/// cap in TFSCommon.h — if that cap ever changes, both the tuple type
/// (auto-generated by the C importer) and the capacity argument here must
/// be updated together.
///
/// C-imported `T arr[N]` arrives in Swift as a tuple `(T, T, T, T)` with no
/// integer subscript at runtime; rebinding the tuple's pointer to a typed
/// pointer is the standard escape hatch (also used elsewhere in Apple's
/// Metal samples for point-light arrays).
private func writeCascadeMatrices(
    into tuple: inout (matrix_float4x4, matrix_float4x4, matrix_float4x4, matrix_float4x4),
    from source: [matrix_float4x4]
) {
    withUnsafeMutablePointer(to: &tuple) { tuplePtr in
        tuplePtr.withMemoryRebound(to: matrix_float4x4.self, capacity: 4) { matPtr in
            for i in 0..<min(source.count, 4) {
                matPtr[i] = source[i]
            }
        }
    }
}

/// Same pattern as `writeCascadeMatrices`, but for `Float` tuples used by
/// the per-cascade split-depth, depth-range, and world-slack arrays. The
/// 4-element arity again mirrors `TFS_MAX_SHADOW_CASCADES`.
private func writeCascadeFloats(
    into tuple: inout (Float, Float, Float, Float),
    from source: [Float]
) {
    withUnsafeMutablePointer(to: &tuple) { tuplePtr in
        tuplePtr.withMemoryRebound(to: Float.self, capacity: 4) { fPtr in
            for i in 0..<min(source.count, 4) { fPtr[i] = source[i] }
        }
    }
}
```

**Option B:** define `cascadeViewProjectionMatrices` as a separate Swift-side `[matrix_float4x4]` and only flatten into the `LightData` struct at bind time. More allocations per frame; not worth it.

`Option A` is fine — the Metal sample code does the same trick for `pointLights[8]` arrays in `LightData`-style structs.

### `ShadowCamera.orthoHalfExtentX`

For the per-cascade slack scaling, the cascade needs to expose its X half-extent. Add to `ShadowCamera.swift`:

```swift
/// Half-width of the orthographic projection on the X axis, in world units.
/// Useful for proportionally scaling shader knobs (e.g. depth-compare slack)
/// across cascades of different sizes.
var orthoHalfExtentX: Float {
    // For our ortho matrix, col0.x = 2 / (right - left), so
    // half-extent = 1 / col0.x.
    return 1 / projectionMatrix.columns.0.x
}
```

---

## 5. `ShadowRendering` protocol — texture array, N descriptors, cascade loop

**File:** `ToyFlightSimulator Shared/Display/Protocols/ShadowRendering.swift`

The shadow map texture changes from `MTLTextureType2D` to `MTLTextureType2DArray`. Each cascade is one slice. The render pass is encoded in a loop, with `depthAttachment.slice = i` per iteration and a per-cascade VP push constant.

### Before (the changing parts)

```swift
protocol ShadowRendering: RenderPassEncoding {
    static var ShadowMapSize: Int { get }
    var shadowMap: MTLTexture { get set }
    var shadowResolveTexture: MTLTexture? { get set }
    var shadowRenderPassDescriptor: MTLRenderPassDescriptor { get set }
}

extension ShadowRendering {
    static var ShadowMapSize: Int { 8_192 }

    public static func makeShadowMap(label: String, sampleCount: Int = 1) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(...)
        ...
    }

    public static func makeShadowRenderPassDescriptor(shadowMapTexture: MTLTexture) -> MTLRenderPassDescriptor {
        let mShadowRenderPassDescriptor = MTLRenderPassDescriptor()
        mShadowRenderPassDescriptor.depthAttachment.texture = shadowMapTexture
        mShadowRenderPassDescriptor.depthAttachment.loadAction = .clear
        mShadowRenderPassDescriptor.depthAttachment.storeAction = .store
        return mShadowRenderPassDescriptor
    }

    func encodeShadowMapPass(into commandBuffer: MTLCommandBuffer) {
        encodeRenderPass(into: commandBuffer, using: shadowRenderPassDescriptor, label: "Shadow Map Pass") { renderEncoder in
            SceneManager.SetDirectionalLightConstants(with: renderEncoder)
            encodeRenderStage(using: renderEncoder, label: "Shadow Generation Stage") {
                setRenderPipelineState(renderEncoder, state: .ShadowGeneration)
                renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.ShadowGeneration])
                renderEncoder.setDepthBias(0.1, slopeScale: 1, clamp: 0.0)
                DrawManager.DrawShadows(with: renderEncoder)
            }
        }
    }
    // ... (analogous encodeShadowPassTiledDeferred, encodeMSAAShadowPass)
}
```

### After

```swift
protocol ShadowRendering: RenderPassEncoding {
    static var ShadowMapSize: Int { get }
    static var CascadeCount: Int { get }
    /// Texture2DArray, arrayLength = CascadeCount. Sampled by the GBuffer/
    /// lighting shaders. For non-MSAA renderers this is also the render
    /// target of the shadow generation passes. For MSAA renderers this is
    /// the resolve destination of `shadowMSAATexture` (see below).
    var shadowMaps: MTLTexture { get set }
    /// MSAA path only: single non-array MSAA texture reused across the N
    /// cascade passes as the multisample source. Each cascade pass resolves
    /// into slice `i` of `shadowMaps`. `nil` for non-MSAA renderers.
    var shadowMSAATexture: MTLTexture? { get set }
    /// One render pass descriptor per cascade. `depthAttachment.slice = i`
    /// for descriptor i; everything else identical.
    var shadowRenderPassDescriptors: [MTLRenderPassDescriptor] { get set }
}

extension ShadowRendering {
    static var ShadowMapSize: Int { 2_048 }
    static var CascadeCount: Int { Int(TFS_MAX_SHADOW_CASCADES) }

    /// Allocate one `MTLTextureType2DArray` with `arrayLength = CascadeCount`.
    public static func makeShadowMapArray(label: String, sampleCount: Int = 1) -> MTLTexture {
        let desc = MTLTextureDescriptor()
        desc.textureType  = .type2DArray
        desc.pixelFormat  = .depth32Float
        desc.width        = Self.ShadowMapSize
        desc.height       = Self.ShadowMapSize
        desc.arrayLength  = Self.CascadeCount
        desc.mipmapLevelCount = 1
        desc.resourceOptions = .storageModePrivate
        desc.usage = [.renderTarget, .shaderRead]
        // Note: MSAA texture-arrays exist (.type2DMultisampleArray) but we
        // intentionally use a single non-array MSAA target + resolve into
        // this array — simpler API, less memory, same visual result.

        guard let tex = Engine.Device.makeTexture(descriptor: desc) else {
            fatalError("[ShadowRendering] Could not create shadow map array texture.")
        }
        tex.label = label
        return tex
    }

    /// Single (non-array) MSAA target used by MSAA renderers as the
    /// multisample side of each cascade's render pass. Resolves into the
    /// corresponding slice of the shadow map array.
    public static func makeShadowMSAATarget(label: String, sampleCount: Int) -> MTLTexture {
        let desc = MTLTextureDescriptor()
        desc.textureType  = .type2DMultisample
        desc.pixelFormat  = .depth32Float
        desc.width        = Self.ShadowMapSize
        desc.height       = Self.ShadowMapSize
        desc.sampleCount  = sampleCount
        desc.resourceOptions = .storageModePrivate
        desc.usage = [.renderTarget]
        guard let tex = Engine.Device.makeTexture(descriptor: desc) else {
            fatalError("[ShadowRendering] Could not create MSAA shadow target.")
        }
        tex.label = label
        return tex
    }

    /// Build `CascadeCount` render pass descriptors, each targeting one slice
    /// of the shadow map array.
    public static func makeShadowRenderPassDescriptors(shadowMapArray: MTLTexture) -> [MTLRenderPassDescriptor] {
        (0..<Self.CascadeCount).map { i in
            let desc = MTLRenderPassDescriptor()
            desc.depthAttachment.texture       = shadowMapArray
            desc.depthAttachment.slice         = i
            desc.depthAttachment.level         = 0
            desc.depthAttachment.loadAction    = .clear
            desc.depthAttachment.storeAction   = .store
            return desc
        }
    }

    /// MSAA variant: render into a shared MSAA target each cascade pass,
    /// resolve into slice `i` of the shadow map array.
    static func makeMSAAShadowRenderPassDescriptors(msaaTexture: MTLTexture,
                                                    resolveArray: MTLTexture) -> [MTLRenderPassDescriptor] {
        (0..<Self.CascadeCount).map { i in
            let desc = MTLRenderPassDescriptor()
            desc.depthAttachment.texture        = msaaTexture
            desc.depthAttachment.resolveTexture = resolveArray
            desc.depthAttachment.resolveSlice   = i
            desc.depthAttachment.loadAction     = .clear
            desc.depthAttachment.storeAction    = .multisampleResolve
            return desc
        }
    }

    /// Iterate over cascades, encoding one shadow generation pass per slice.
    func encodeShadowMapPass(into commandBuffer: MTLCommandBuffer) {
        let directionalLights = LightManager.GetLightObjects(lightType: Directional)
        guard let primaryLight = directionalLights.first else { return }
        let cascadeCount = Int(primaryLight.lightData.cascadeCount)

        for i in 0..<min(cascadeCount, Self.CascadeCount) {
            // Per-pass cascade VP. Read out of the homogeneous tuple via
            // pointer rebind — see LightObject for the symmetric write side.
            let cascadeVP: matrix_float4x4 = withUnsafePointer(to: primaryLight.lightData.cascadeViewProjectionMatrices) { tuplePtr in
                tuplePtr.withMemoryRebound(to: matrix_float4x4.self, capacity: 4) { $0[i] }
            }

            encodeRenderPass(into: commandBuffer,
                             using: shadowRenderPassDescriptors[i],
                             label: "Shadow Map Pass \(i)") { renderEncoder in
                SceneManager.SetDirectionalLightConstants(with: renderEncoder)
                encodeRenderStage(using: renderEncoder, label: "Shadow Generation Stage \(i)") {
                    setRenderPipelineState(renderEncoder, state: .ShadowGeneration)
                    renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.ShadowGeneration])
                    renderEncoder.setDepthBias(0.1, slopeScale: 1, clamp: 0.0)

                    // Per-pass cascade view-projection matrix at index
                    // TFSBufferIndexShadowCascadeVP. The shadow vertex
                    // shader reads this instead of LightData.shadowVP.
                    var cascadeVPLocal = cascadeVP
                    renderEncoder.setVertexBytes(&cascadeVPLocal,
                                                 length: matrix_float4x4.stride,
                                                 index: TFSBufferIndexShadowCascadeVP.index)

                    DrawManager.DrawShadows(with: renderEncoder)
                }
            }
        }
    }

    func encodeShadowPassTiledDeferred(into commandBuffer: MTLCommandBuffer) {
        // Same loop pattern; uses the TiledDeferredShadow PSO/DSS pair.
        let directionalLights = LightManager.GetLightObjects(lightType: Directional)
        guard let primaryLight = directionalLights.first else { return }
        let cascadeCount = Int(primaryLight.lightData.cascadeCount)

        for i in 0..<min(cascadeCount, Self.CascadeCount) {
            let cascadeVP: matrix_float4x4 = withUnsafePointer(to: primaryLight.lightData.cascadeViewProjectionMatrices) { tuplePtr in
                tuplePtr.withMemoryRebound(to: matrix_float4x4.self, capacity: 4) { $0[i] }
            }
            encodeRenderPass(into: commandBuffer,
                             using: shadowRenderPassDescriptors[i],
                             label: "Shadow Pass \(i)") { renderEncoder in
                encodeRenderStage(using: renderEncoder, label: "Shadow Texture Stage \(i)") {
                    setRenderPipelineState(renderEncoder, state: .TiledDeferredShadow)
                    renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.TiledDeferredShadow])
                    SceneManager.SetDirectionalLightConstants(with: renderEncoder)
                    var cascadeVPLocal = cascadeVP
                    renderEncoder.setVertexBytes(&cascadeVPLocal,
                                                 length: matrix_float4x4.stride,
                                                 index: TFSBufferIndexShadowCascadeVP.index)
                    DrawManager.DrawOpaque(with: renderEncoder)
                }
            }
        }
    }

    func encodeMSAAShadowPass(into commandBuffer: MTLCommandBuffer) {
        // Same loop pattern; renders to the MSAA target each iteration,
        // resolves into slice `i` of the shadow map array.
        let directionalLights = LightManager.GetLightObjects(lightType: Directional)
        guard let primaryLight = directionalLights.first else { return }
        let cascadeCount = Int(primaryLight.lightData.cascadeCount)

        for i in 0..<min(cascadeCount, Self.CascadeCount) {
            let cascadeVP: matrix_float4x4 = withUnsafePointer(to: primaryLight.lightData.cascadeViewProjectionMatrices) { tuplePtr in
                tuplePtr.withMemoryRebound(to: matrix_float4x4.self, capacity: 4) { $0[i] }
            }
            encodeRenderPass(into: commandBuffer,
                             using: shadowRenderPassDescriptors[i],
                             label: "MSAA Shadow Pass \(i)") { renderEncoder in
                encodeRenderStage(using: renderEncoder, label: "Shadow Texture Stage \(i)") {
                    setRenderPipelineState(renderEncoder, state: .TiledMSAAShadow)
                    renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.TiledDeferredShadow])
                    SceneManager.SetDirectionalLightConstants(with: renderEncoder)
                    var cascadeVPLocal = cascadeVP
                    renderEncoder.setVertexBytes(&cascadeVPLocal,
                                                 length: matrix_float4x4.stride,
                                                 index: TFSBufferIndexShadowCascadeVP.index)
                    DrawManager.DrawShadows(with: renderEncoder)
                }
            }
        }
    }
}
```

### Why one MSAA target reused, not N?

We could allocate `TFS_MAX_SHADOW_CASCADES` separate MSAA shadow targets (or a multisample-array texture). Both add memory without buying anything — within a single command buffer, after `multisampleResolve` writes slice `i` of the array, the MSAA target's contents are throw-away (it's the resolve that's persisted and sampled later). Reusing one MSAA target for all cascade passes mirrors the typical Apple-sample pattern. The texture is `.storageModePrivate` and `.usage = [.renderTarget]` only — no `shaderRead`.

### Why drop `ShadowMapSize` from 8192 to 2048?

8192 was the right choice for a single fixed map covering the whole world. With 4 cascades, each cascade's coverage is one slice of the frustum, so each cascade's "world units per texel" is now driven by `(cascade_radius / 2048)` rather than `(world_radius / 8192)`. At a typical fitting, cascade 0 covers ~25 world units → 0.012 wu/texel (vs the old 0.122 at 8192² covering 500); cascade 3 covers ~5000 world units → 2.4 wu/texel (vs no coverage at all today past 500). Net: huge near-field gain, modest far-field "softness" that's perceptually fine.

If a future scene needs sharper cascade 0 (zoomed-in cinematic shots), `sun.setShadowMapResolution(4096)` quadruples cascade-0 sharpness for 4× the per-cascade memory.

---

## 6. `Shadow.metal` — consume cascade VP push constant

**File:** `ToyFlightSimulator Shared/Graphics/Shaders/Shadow.metal`

Both vertex functions read `cascadeVP` directly instead of indexing into `LightData`. This makes the shadow PSO completely cascade-count agnostic — the host code just submits N draw calls with different push constants.

### Before

```glsl
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

```glsl
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

`shadow_animated_vertex` gets the same swap (replace `lightData.shadowViewProjectionMatrix` with `cascadeVP`, remove the `LightData` parameter). Skinning logic is unchanged.

**Why remove the `LightData` binding entirely from this shader?** It was being used solely for `shadowViewProjectionMatrix`. With cascades, the per-pass VP is the only thing the shadow vertex shader needs. Dropping the `LightData` parameter shrinks the shader's argument table and clarifies the contract: "draw this geometry into a shadow map using this matrix — that's it."

---

## 7. `Lighting.metal` — cascade-aware shadow sampling

**File:** `ToyFlightSimulator Shared/Graphics/Shaders/Lighting.metal`

`CalculateShadow` and `CalculateShadowMSAA` get rewritten to:
1. Take the fragment's world position + view-space depth (instead of pre-multiplied `shadowPosition`).
2. Pick a cascade based on view-space depth.
3. Transform world position by that cascade's VP and sample the texture array.

### Before

```glsl
static float CalculateShadow(float4 shadowPosition,
                             depth2d<float> shadowTexture,
                             float worldSlack,
                             float depthRange) {
    float3 position = shadowPosition.xyz / shadowPosition.w;
    float2 xy = position.xy;
    xy = xy * 0.5 + 0.5;
    xy.y = 1 - xy.y;
    if (any(xy < 0.0) || any(xy > 1.0) || position.z < 0.0 || position.z > 1.0) {
        return 1.0;
    }
    constexpr sampler s(coord::normalized,
                        filter::nearest,
                        address::clamp_to_edge,
                        compare_func::less);
    float shadow_sample = shadowTexture.sample(s, xy);
    float epsilon = NDCShadowEpsilon(worldSlack, depthRange);
    return (position.z > shadow_sample + epsilon) ? 0.5 : 1;
}
```

### After

```glsl
// Pick the closest cascade whose split distance still includes this fragment.
// `viewSpaceDepth` should be `|view * worldPos|.z` (always non-negative;
// computed in the vertex shader). Falls back to the last cascade if the
// fragment is past every split.
static uint SelectCascade(constant LightData &light, float viewSpaceDepth) {
    for (uint i = 0; i < light.cascadeCount; ++i) {
        if (viewSpaceDepth < light.cascadeSplitDepths[i]) {
            return i;
        }
    }
    return light.cascadeCount - 1;
}

static float CalculateShadow(float3 worldPosition,
                             float viewSpaceDepth,
                             constant LightData &light,
                             depth2d_array<float> shadowArray) {
    if (light.cascadeCount == 0) return 1.0;   // safety: light not initialized

    uint cascadeIdx = SelectCascade(light, viewSpaceDepth);

    // Transform world position into the selected cascade's NDC.
    float4 shadowPosition = light.cascadeViewProjectionMatrices[cascadeIdx] *
                            float4(worldPosition, 1.0);
    float3 position = shadowPosition.xyz / shadowPosition.w;
    float2 xy = position.xy;
    xy = xy * 0.5 + 0.5;
    xy.y = 1 - xy.y;

    // Fragment outside the cascade's frustum: try the next cascade (further
    // out) before giving up. This handles the case where texel-snapping
    // shifted a fragment slightly outside cascade i's snapped box even
    // though its view-space depth said i was the right pick.
    if (any(xy < 0.0) || any(xy > 1.0) || position.z < 0.0 || position.z > 1.0) {
        if (cascadeIdx + 1 < light.cascadeCount) {
            cascadeIdx += 1;
            shadowPosition = light.cascadeViewProjectionMatrices[cascadeIdx] *
                             float4(worldPosition, 1.0);
            position = shadowPosition.xyz / shadowPosition.w;
            xy = position.xy * 0.5 + 0.5;
            xy.y = 1 - xy.y;
            if (any(xy < 0.0) || any(xy > 1.0) || position.z < 0.0 || position.z > 1.0) {
                return 1.0;
            }
        } else {
            return 1.0;
        }
    }

    constexpr sampler s(coord::normalized,
                        filter::nearest,
                        address::clamp_to_edge,
                        compare_func::less);
    // texture2d_array<>::sample takes (sampler, uv, slice).
    float shadow_sample = shadowArray.sample(s, xy, cascadeIdx);

    float epsilon = NDCShadowEpsilon(light.cascadeWorldSlack[cascadeIdx],
                                     light.cascadeDepthRange[cascadeIdx]);
    return (position.z > shadow_sample + epsilon) ? 0.5 : 1;
}
```

`CalculateShadowMSAA` gets the same restructure but uses `depth2d_ms_array<float>` (a Metal type that exists for completeness) — except we deliberately resolve to a non-MSAA array on the host side, so the MSAA helper actually consumes the same `depth2d_array<float>` and is identical to `CalculateShadow`. We can therefore delete `CalculateShadowMSAA` entirely and have all paths call `CalculateShadow`. (Track this as a small cleanup in section 19, Future work — for the initial CSM landing, keep both helpers and have `CalculateShadowMSAA` just call into `CalculateShadow`.)

**Why the "fall through to next cascade on out-of-frustum"?** Texel-snapping shifts the snapped XY extents by up to one texel; a fragment whose `viewSpaceDepth` puts it in cascade `i` may, after the snap, fall just outside cascade `i`'s 2D bounds. The next-cascade fallback gracefully degrades to the looser cascade instead of producing a `× 0.5` ground hole. This is a tiny shader-side robustness; the visual cost is one extra matrix multiply on the boundary fragments.

---

## 8. GBuffer shaders — `worldPosition` + `viewSpaceDepth` in `VertexOut`

**Files:**
- `ToyFlightSimulator Shared/Graphics/Shaders/ShaderDefinitions.h` (struct change)
- `ToyFlightSimulator Shared/Graphics/Shaders/TiledDeferredGBuffer.metal`
- `ToyFlightSimulator Shared/Graphics/Shaders/TiledMSAAGBuffer.metal`
- `ToyFlightSimulator Shared/Graphics/Shaders/GBuffer.metal` (legacy SinglePassDeferred)

### `VertexOut` change

#### Before

```glsl
typedef struct {
    float4 position [[ position ]];
    float3 normal;
    float2 uv;
    float3 worldPosition;
    float3 worldNormal;
    float3 worldTangent;
    float3 worldBitangent;
    float4 shadowPosition;      // ← removed
    uint   instanceId;
    float4 objectColor;
    bool   useObjectColor;
} VertexOut;
```

#### After

```glsl
typedef struct {
    float4 position [[ position ]];
    float3 normal;
    float2 uv;
    float3 worldPosition;
    float3 worldNormal;
    float3 worldTangent;
    float3 worldBitangent;
    float  viewSpaceDepth;       // ← added: |(view * worldPos).z|; used for cascade selection
    uint   instanceId;
    float4 objectColor;
    bool   useObjectColor;
} VertexOut;
```

**Why drop `shadowPosition` and add `viewSpaceDepth` instead?** With cascades, the shader can't know which cascade's matrix to multiply by until it has the fragment's depth — i.e. the cascade selection needs to happen in the fragment shader. Stashing `shadowPosition` for a specific cascade in the vertex shader doesn't help. `viewSpaceDepth` is one float, vs `shadowPosition` being four — bandwidth shrinks.

Side benefit: `viewSpaceDepth` is reusable for any other depth-driven effect (volumetric fog, depth-of-field, distance fade).

### `TiledDeferredGBuffer.metal` vertex shader

#### Before

```glsl
vertex VertexOut tiled_deferred_gbuffer_vertex(...) {
    ModelConstants modelInstance = modelConstants[instanceId];
    float4 worldPosition = modelInstance.modelMatrix * float4(in.position, 1);
    float4 position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * worldPosition;

    VertexOut out {
        .position = position,
        ...
        .shadowPosition = lightData.shadowViewProjectionMatrix * worldPosition,
        ...
    };
    return out;
}
```

#### After

```glsl
vertex VertexOut tiled_deferred_gbuffer_vertex(
           VertexIn       in              [[ stage_in ]],
  constant SceneConstants &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
  constant ModelConstants *modelConstants [[ buffer(TFSBufferModelConstants) ]],
           uint           instanceId      [[ instance_id ]]) {
    ModelConstants modelInstance = modelConstants[instanceId];
    float4 worldPosition = modelInstance.modelMatrix * float4(in.position, 1);
    float4 eyePosition   = sceneConstants.viewMatrix * worldPosition;

    VertexOut out {
        .position = sceneConstants.projectionMatrix * eyePosition,
        .normal = in.normal,
        .uv = in.textureCoordinate,
        .worldPosition  = worldPosition.xyz / worldPosition.w,
        .worldNormal    = modelInstance.normalMatrix * in.normal,
        .worldTangent   = modelInstance.normalMatrix * in.tangent,
        .worldBitangent = modelInstance.normalMatrix * in.bitangent,
        .viewSpaceDepth = abs(eyePosition.z),
        .instanceId     = instanceId,
        .objectColor    = modelInstance.objectColor,
        .useObjectColor = modelInstance.useObjectColor
    };
    return out;
}
```

**Key change:** the `LightData` binding is removed from the vertex shader (it no longer needs the shadow matrix). The animated variant gets the same swap.

### `TiledDeferredGBuffer.metal` fragment shader

#### Before

```glsl
fragment GBufferOut
tiled_deferred_gbuffer_fragment(VertexOut in [[ stage_in ]],
                                ...
                                constant LightData &lightData [[ buffer(TFSBufferDirectionalLightData) ]],
                                ...
                                depth2d<float> shadowTexture [[ texture(TFSTextureIndexShadow) ]]) {
    ...
    color.a = Lighting::CalculateShadow(in.shadowPosition,
                                        shadowTexture,
                                        lightData.shadowWorldSlack,
                                        lightData.shadowDepthRange);
    ...
}
```

#### After

```glsl
fragment GBufferOut
tiled_deferred_gbuffer_fragment(VertexOut in [[ stage_in ]],
                                ...
                                constant LightData &lightData [[ buffer(TFSBufferDirectionalLightData) ]],
                                ...
                                depth2d_array<float> shadowArray [[ texture(TFSTextureIndexShadow) ]]) {
    ...
    color.a = Lighting::CalculateShadow(in.worldPosition,
                                        in.viewSpaceDepth,
                                        lightData,
                                        shadowArray);
    ...
}
```

`TiledMSAAGBuffer.metal` is the same fragment-shader change (also bind `depth2d_array<float>` even though we resolved out of MSAA — the array is the resolve target). `GBuffer.metal`'s two fragment functions (`gbuffer_fragment_base`, `gbuffer_fragment_material`) get the same change; the vertex shader no longer needs the `LightData` binding either.

### Legacy `sample_compare` paths in `GBuffer.metal`

`gbuffer_fragment_base` and `gbuffer_fragment_material` both call `shadowMap.sample_compare(sampler, in.shadow_coord.xy, in.shadow_coord.z)`. That's a hardware sampler-comparison that doesn't suit a cascade-selection loop. Two paths:

**Path 1 (chosen for this plan):** Refactor both functions to call `Lighting::CalculateShadow(worldPosition, viewSpaceDepth, lightData, shadowArray)` — i.e. drop the hardware sample-compare and use the same software-compare cascade-aware helper as everyone else.

**Path 2 (rejected):** Keep `sample_compare` but only on cascade 0. This is what the singular legacy SinglePassDeferred path used to do; it's fast (one hardware-accelerated compare) but loses CSM's whole point.

Path 1 it is. `gbuffer_fragment_base` becomes:

```glsl
fragment GBufferData gbuffer_fragment_base(VertexOut          in           [[ stage_in ]],
                                           constant LightData &lightData   [[ buffer(TFSBufferDirectionalLightData) ]],
                                           depth2d_array<float> shadowArray [[ texture(TFSTextureIndexShadow) ]])
{
    // ... existing normal/tangent math ...

    float shadow_sample = Lighting::CalculateShadow(in.worldPosition,
                                                    in.viewSpaceDepth,
                                                    lightData,
                                                    shadowArray);

    GBufferData gBuffer = {
        .albedo_specular = half4(base_color.xyz, specularContribution),
        .normal_shadow   = half4(eye_normal.xyz, half(shadow_sample)),  // narrowing to half is fine; result is 0.5 or 1.0
        .depth           = in.eye_position.z
    };
    return gBuffer;
}
```

`gbuffer_fragment_material` follows the same pattern. The `eye_position` field in the legacy `ColorInOut` is still present (the legacy path also outputs it), so that bit doesn't need to change. The legacy `shadow_coord` field can be removed from `ColorInOut` once both fragment functions stop reading it.

---

## 9. Per-renderer wiring

Each of the four renderers that conforms to `ShadowRendering` needs ~3 small edits.

### `TiledDeferredRenderer.swift`

#### Before (constructors, line 60-67)

```swift
init() {
    shadowMap = Self.makeShadowMap(label: "Shadow Texture")
    shadowRenderPassDescriptor = Self.makeShadowRenderPassDescriptor(shadowMapTexture: shadowMap)
    super.init(type: .TiledDeferred)
}

init(_ mtkView: MTKView) {
    shadowMap = Self.makeShadowMap(label: "Shadow Texture")
    shadowRenderPassDescriptor = Self.makeShadowRenderPassDescriptor(shadowMapTexture: shadowMap)
    super.init(mtkView, type: .TiledDeferred)
}
```

#### After

```swift
init() {
    shadowMaps = Self.makeShadowMapArray(label: "Shadow Cascade Array")
    shadowRenderPassDescriptors = Self.makeShadowRenderPassDescriptors(shadowMapArray: shadowMaps)
    super.init(type: .TiledDeferred)
}

init(_ mtkView: MTKView) {
    shadowMaps = Self.makeShadowMapArray(label: "Shadow Cascade Array")
    shadowRenderPassDescriptors = Self.makeShadowRenderPassDescriptors(shadowMapArray: shadowMaps)
    super.init(mtkView, type: .TiledDeferred)
}
```

Property declaration change (line 15-18):

```swift
var shadowMaps: MTLTexture                                   // texture2DArray (was shadowMap)
var shadowRenderPassDescriptors: [MTLRenderPassDescriptor]   // (was singular)
var shadowMSAATexture: MTLTexture? = nil                     // (was shadowResolveTexture)
```

The `setFragmentTexture(shadowMaps, index: TFSTextureIndexShadow.index)` line (75) — same Metal API call, just consuming the renamed property. The shader-side declaration (`depth2d_array<float>`) handles the typed view.

### `TiledMultisampleRenderer.swift`

Same edits, plus the MSAA target/resolve change:

#### Before

```swift
shadowMap = Self.makeShadowMap(label: "Shadow Multisample Texture", sampleCount: Self.sampleCount)
shadowResolveTexture = Self.makeShadowMap(label: "Shadow Resolve Texture", sampleCount: 1)
shadowRenderPassDescriptor = Self.makeMultiSampledShadowRenderPassDescriptor(
    shadowTexture: shadowMap, resolveTexture: shadowResolveTexture!)
```

#### After

```swift
// Property semantics after rename:
//   shadowMaps        = the texture2DArray that fragment shaders sample
//                       (resolve destination for the MSAA path).
//   shadowMSAATexture = single non-array MSAA texture, the multisample
//                       source; reused across all N cascade passes.
shadowMaps        = Self.makeShadowMapArray(label: "Shadow Cascade Resolve Array")
shadowMSAATexture = Self.makeShadowMSAATarget(label: "Shadow MSAA Target",
                                              sampleCount: Self.sampleCount)
shadowRenderPassDescriptors = Self.makeMSAAShadowRenderPassDescriptors(
    msaaTexture: shadowMSAATexture!, resolveArray: shadowMaps)
```

And the GBuffer-stage texture binding (line 91):

```swift
// Was: shadowResolveTexture (single non-MSAA depth texture).
// Now: shadowMaps (the texture2DArray we resolved into).
renderEncoder.setFragmentTexture(shadowMaps, index: TFSTextureIndexShadow.index)
```

Same call site, renamed property, different type-shape from the shader's perspective.

### `TiledMSAATessellatedRenderer.swift`

Identical pattern to `TiledMultisampleRenderer`. The tessellation path doesn't touch shadow code; `DrawManager.DrawShadows` is the same call in both.

### `SinglePassDeferredLightingRenderer.swift`

Same pattern as `TiledDeferredRenderer` (no MSAA on the shadow side). Renames `shadowMap` → `shadowMaps`; binds `shadowMaps` at `TFSTextureIndexShadow`; the legacy `GBuffer.metal` fragment shader was rewritten in section 8 to read it as `depth2d_array<float>`.

---

## 10. `LightManager` — no functional change

**File:** `ToyFlightSimulator Shared/Managers/LightManager.swift`

`LightManager` copies entire `LightData` structs by value into its scratch arrays before binding. Since the new cascade fields are inside `LightData`, they propagate "for free" — no edits required. Confirm by inspection that no code does `MemoryLayout<LightData>.size`-based offset arithmetic; only `.stride(count)` is used.

The only place `LightManager` reads individual `LightData` fields is `lightEyeDirection` (computed each frame from `viewMatrix * direction`). That stays.

---

## 11. Texel-snapping correctness check

The snap math in `ShadowCascadeFitting.fitOrthoToCorners` is the key shimmer killer. The principle:

> If the light-space ortho box is the same size every frame and only its **position** changes, snapping that position to the texel grid means each world-space point that survives between frames maps to the same shadow texel (up to one-texel-of-slack).

Our implementation:

```swift
let texelX = widthLS  / Float(shadowMapResolution)
let texelY = heightLS / Float(shadowMapResolution)
minLS.x = floor(minLS.x / texelX) * texelX
minLS.y = floor(minLS.y / texelY) * texelY
maxLS.x = minLS.x + texelX * Float(shadowMapResolution)
maxLS.y = minLS.y + texelY * Float(shadowMapResolution)
```

This holds the **width and height constant** per cascade across frames (because `widthLS` is itself derived from a fixed cascade slice of a fixed camera FOV — only the box's translation in light space changes as the camera moves). Then it snaps `minLS.xy` to texel boundaries. Resulting box: same size, snapped position.

**Edge case:** if the main camera changes FOV (e.g. zoom-in optic), the fitted box width changes too, and snapping won't preserve cross-frame stability. Solution: only snap on stable FOV. The codebase doesn't currently do FOV transitions, so this is a non-issue. Note in a comment for future-you.

**Edge case 2:** if the box's width itself varies frame-to-frame because of float rounding noise (corner coordinates drift by ε), the texel grid shifts. Mitigation: round the box dimensions to a fixed quantum before snapping. The LearnOpenGL article shows a "make the box a fixed size larger than necessary" trick — fit the box to a sphere bounding the frustum corners instead of an AABB, which is FOV-invariant by construction:

```swift
// Alternative robust fit: use the bounding sphere of the corners.
// The sphere's radius is determined by the frustum's diagonal and is
// frame-invariant for fixed FOV/aspect/near-far. Texel-snapping a
// sphere-fit ortho is perfectly stable.
let sphereRadius = computeBoundingSphereRadius(corners)
let extent = sphereRadius  // half-width and half-height of the ortho
minLS.x = lightSpaceCenter.x - extent
maxLS.x = lightSpaceCenter.x + extent
// ... same for y; z still uses AABB extent + padding.
```

**Recommended:** start with AABB-fit (simpler, no separate sphere math), validate visually, switch to sphere-fit only if shimmer is still visible. The visual test (verification step 3 below) catches this.

---

## 12. Optional: cascade-boundary blending

Between cascade `i` and `i+1` there's a visible discontinuity — cascade `i` may have texel-aligned shadow edges while cascade `i+1` has coarser texels. This shows up as a faint line where the cascade boundary crosses a shadow.

The fix is a small overlap band: when a fragment is within ε of a cascade split, sample both cascades and blend.

### Shader addition (Lighting.metal)

```glsl
static float CalculateShadowBlended(float3 worldPosition,
                                    float viewSpaceDepth,
                                    constant LightData &light,
                                    depth2d_array<float> shadowArray) {
    uint cascadeIdx = SelectCascade(light, viewSpaceDepth);

    // Distance to the cascade's far split (in view-space units).
    float splitFar = light.cascadeSplitDepths[cascadeIdx];
    float splitNear = cascadeIdx == 0 ? 0.0 : light.cascadeSplitDepths[cascadeIdx - 1];
    float blendBand = (splitFar - splitNear) * 0.1;   // 10% overlap

    float distanceToFar = splitFar - viewSpaceDepth;
    float blendT = saturate(1.0 - distanceToFar / blendBand);   // 0..1 as we approach the boundary

    float shadowA = SampleCascade(worldPosition, light, shadowArray, cascadeIdx);

    if (blendT > 0.0 && cascadeIdx + 1 < light.cascadeCount) {
        float shadowB = SampleCascade(worldPosition, light, shadowArray, cascadeIdx + 1);
        return mix(shadowA, shadowB, blendT);
    }
    return shadowA;
}

// Inline helper — extracted from the cascade-aware CalculateShadow body.
static float SampleCascade(float3 worldPosition,
                           constant LightData &light,
                           depth2d_array<float> shadowArray,
                           uint cascadeIdx) {
    // (the body of section 7's CalculateShadow, parameterized on cascadeIdx)
    ...
}
```

**Cost:** the blend band doubles the work for the ~10% of fragments inside it. On modern Apple silicon that's ~2-5% total per-frame cost in the GBuffer stage — measurable but not noticeable.

**Recommendation:** ship CSM without blending first (verification step 6 will reveal whether the boundary is visible against the F-22's gray fuselage). Add blending only if a visible seam shows up.

---

## 13. Verification plan

Run on `FlightboxWithPhysics` (the SunLine-bug scene) and at least one secondary scene (`Sandbox` or `FreeCamFlightbox`).

1. **No regression at cascadeCount=1.** Set `sun.setCascadeCount(1)` before the rest of the plan rolls out. The `LightObject.updateShadowCascades` fast path produces bit-identical output to today. Confirm visually: no change vs sun-follow baseline.
2. **Near-field sharpness.** With `cascadeCount=4` and `shadowMapRes=2048`: land the F-22, press 'C' to switch to `DebugCamera`, get within 5 world units of the gear. Shadow edges should be visibly sharper than today's 8192² single-cascade baseline.
3. **No shimmer.** Fly forward in `FlightboxWithPhysics` for several seconds at cruise speed. Static ground geometry (parked F-16, debris) should have rock-solid shadow edges, not flickering ones.
4. **Long-range shadows.** Climb to ~3000 world units altitude, look down. Distant ground objects (>500 world units from camera) should now cast visible shadows — previously the shadow frustum cut off here.
5. **Cascade boundaries are not glaringly visible.** Roll the F-22 slowly. Watch the shadow edge across the cascade boundaries. If a hard seam is visible, enable cascade-edge blending (section 12) and re-test.
6. **All five renderers render correctly.** Cycle the renderer menu: `SinglePassDeferredLighting`, `TiledDeferred`, `TiledDeferredMSAA`, `TiledMSAATessellated`, `OrderIndependentTransparency` (this one doesn't use shadows; just confirm no regression). Look for: shadow appears in all paths, no flickering, no obvious darkness/brightness mismatch between paths.
7. **`z = 0` light position still doesn't darken.** Set `sun.setPosition(0, jetPos.y + 100, 0)` (forcing a non-Z direction). Lighting brightness unchanged. (Same test from the single-cascade plan.)
8. **Memory.** Xcode Memory Graph: confirm shadow textures total ~64 MB, not ~256 MB.
9. **Frame capture inspection.** Xcode GPU Capture, look at the shadow-map array texture. All 4 slices should be populated; cascade 0 should be a tight close-up of the F-22; cascade 3 should be a wide view including the horizon.
10. **GPU Counter:** confirm the per-cascade shadow passes are short. Each cascade pass renders the same scene, but cascade 0's frustum culls aggressively (small ortho box) — total shadow time should be ~1.3× single-cascade time, not 4×. If it's 4×, the per-cascade frustum isn't being respected by culling. (We don't have a CPU-side culler here — the cost is GPU geometry. Worth profiling.)

Build/test gates:

```bash
xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" \
    -sdk macosx -configuration Debug CODE_SIGNING_ALLOWED=NO
xcodebuild test  -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" \
    -sdk macosx -configuration Debug CODE_SIGNING_ALLOWED=NO
```

Add new Swift Testing tests under `ToyFlightSimulatorTests/Shadow/`:
- `ShadowCascadeFittingTests`: split distances are monotonic; corners are in front of the camera; AABB is non-empty; texel-snap is idempotent.
- `ShadowCameraTests`: legacy initializer matches the old `ShadowCamera` output bit-identically (regression guard).

---

## 14. Risks and rollback

| Risk | Mitigation |
|---|---|
| `LightData` grows by ~336 bytes (4 × 64 + 4 × 4 + 4 × 4 + 4 × 4 + 4). All push-constant bindings use `LightData.stride(count)`; nothing breaks. | None needed beyond a recompile. Document the new size in a `LightData` comment. |
| `TFSBufferIndexShadowCascadeVP = 13` conflicts with no current index. | Trivial: it's a new value. |
| Tuple-array bridging is `withUnsafeMutablePointer`-based, easy to typo. | Wrap in named helpers (`writeCascadeMatrices` etc.), unit-test the helpers in `Swift Testing`. |
| Reverse-Z main camera + forward-Z shadow ortho: cascade fitting math could pick the wrong z-direction when transforming corners. | The fit math operates in light view space, which is independent of the main camera's reverse/forward-Z choice. Only the corner unprojection step touches the main camera's projection — and we use `Transform.perspectiveProjection`'s own inverse, so reverse-Z is round-tripped consistently. Verified by step 1 of the verification plan (cascadeCount=1 must produce bit-identical output). |
| Cascade selection in fragment shader uses view-space depth; main camera's `viewMatrix` is needed in fragment, but currently the GBuffer fragment shaders don't bind `SceneConstants` (they get the precomputed eye-space data via VertexOut). | Solution: `viewSpaceDepth` is computed in the vertex shader and interpolated. No need to bind `viewMatrix` in the fragment shader. (Already reflected in section 8.) |
| Texel-snap is correct only if the per-cascade ortho **width** is frame-invariant. With AABB-fit on frustum corners, width does vary slightly (float ε). | Section 11's sphere-fit fallback. Start with AABB-fit; switch only if shimmer reappears. |
| Cascade-edge seams visible. | Section 12's blending. Defer until a seam is actually visible (cheaper to ship without). |
| `ShadowMap` resolution change (8192² → 2048²) hurts cinematic close-ups in some user-customized scenes. | Per-scene override: `sun.setShadowMapResolution(4096)` (or higher). Memory grows 4×; visual quality grows 2× per axis. |
| MSAA path: per-pass MSAA target reused across cascades. If a future change wants per-cascade MSAA preservation, the design has to change. | The pattern matches Apple sample code; reuse is intentional and explicitly documented in the MSAA helper. |
| `cascadeCount == 0` (uninitialized `LightData`). | Shader's `CalculateShadow` checks `cascadeCount == 0` and returns `1.0` (fully lit). |
| Fragment falls outside cascade i's snapped XY box even though it should be inside (texel-snap ε). | Shader fall-through to cascade i+1 (section 7). |
| Geometry not culled per-cascade on the CPU; all cascade passes redraw all opaque geometry. | True. Acceptable for now (modern silicon eats this for breakfast at our scene scale). Section 19 lists CPU per-cascade culling as future work. |

**Rollback:** the change set is contained to:
- `TFSCommon.h`, `ShaderDefinitions.h` (header changes)
- `Shadow.metal`, `Lighting.metal`, `TiledDeferredGBuffer.metal`, `TiledMSAAGBuffer.metal`, `GBuffer.metal` (shader changes)
- `LightObject.swift`, `ShadowCamera.swift`, new `ShadowCascadeFitting.swift` (CPU side)
- `ShadowRendering.swift` and the four renderer files (renderer wiring)

Revert all of the above in a single commit — the single-cascade sun-follow plan's output is unchanged underneath (we kept its initializer + `_shadowRadius`/`_shadowLift` knobs).

---

## 15. Implementation order

Each step is independently buildable and visually inspectable. The order below ensures the `cascadeCount == 1` fast path is never broken — every commit produces a working binary.

1. **Add `TFSBufferIndexShadowCascadeVP` to `TFSCommon.h`.** No callers yet; safe additive change.
2. **Extend `LightData` with cascade arrays + count.** Initialize `cascadeCount = 0` at struct init time so it acts as "not yet populated." Visual: no change (no consumer yet).
3. **Add `ShadowCascadeFitting.swift`.** Pure math; no callers. Add `Swift Testing` unit tests for split-distance monotonicity and AABB-fit non-degeneracy.
4. **Extend `ShadowCamera.swift`** with the cascade-fit initializer and `orthoHalfExtentX` / `depthRange` properties. Visual: no change.
5. **Modify `LightObject.swift`** to populate cascade arrays even at `cascadeCount = 1` (via the legacy fast path). Visual: bit-identical to today.
6. **Switch `Shadow.metal`** to read `cascadeVP` from `TFSBufferIndexShadowCascadeVP` instead of `lightData.shadowViewProjectionMatrix`. Update `ShadowRendering.encodeShadowMapPass` to push `lightData.cascadeViewProjectionMatrices[0]` as the cascade VP. Visual: no change (still one pass, same matrix).
7. **Switch `ShadowRendering` to texture array.** `shadowMap` is now `MTLTextureType2DArray`, `arrayLength = 4`. With `cascadeCount = 1`, only slice 0 is rendered. Visual: no change (shaders still sample only slice 0 — but they haven't been switched yet, so they sample `depth2d<float>` which won't bind to an array. Tricky transition.)

   *Resolution:* steps 7 and 8 must land together. Sketch them as one commit even if the file diffs span multiple files.

8. **Switch GBuffer + Lighting shaders to `depth2d_array<float>` + cascade-aware `CalculateShadow`.** Now they sample slice 0 explicitly. With `cascadeCount = 1`, output is identical to today.
9. **Bump `cascadeCount = 4`.** Visual: cascades activate. Near-field shadows get sharper, distant shadows appear. Validate by sections 13.2–13.5.
10. **Add texel-snapping** in `ShadowCascadeFitting.fitOrthoToCorners`. Validate by section 13.3.
11. **(Optional) Add cascade-edge blending** in `Lighting.metal`. Validate by section 13.5 — only land this step if seams were visible.

Each step is bisectable. If a regression appears, it landed in exactly one of these eleven commits.

---

## 16. Configuration summary (defaults vs scene-overridable)

| Knob | Default | API | Effect |
|---|---|---|---|
| `cascadeCount` | 4 | `sun.setCascadeCount(_:)` | Number of cascades (1..4). Setting to 1 reverts to sun-follow single-cascade. |
| `cascadeLambda` | 0.5 | `sun.setCascadeLambda(_:)` | PSSM blend: 0=uniform, 1=logarithmic. Higher = more detail near camera. |
| `shadowMapResolution` | 2048 | `sun.setShadowMapResolution(_:)` | Per-cascade texture resolution (square). 4096 quadruples per-cascade memory. |
| `cascadeZPadding` | 10 | `sun.setCascadeZPadding(_:)` | Z-axis ortho expansion for back-facing casters. Higher = catches more casters at distance, slightly lower precision. |
| `baseWorldSlack` | 0.25 | `sun.setShadowWorldSlack(_:)` | Cascade-0 depth-compare slack. Larger cascades auto-scale up. |
| `cascadeBlendBand` (if 12 implemented) | 10% of cascade depth | `sun.setCascadeBlendBand(_:)` | Width of blend overlap between consecutive cascades. |

Scenes that want sharper close-ups for cinematic shots:

```swift
sun.setShadowMapResolution(4096)
sun.setCascadeLambda(0.7)        // more near-cascade detail
```

Scenes that want longer reach (chase camera over miles of terrain):

```swift
sun.setCascadeCount(4)            // already the default
// Implicit: cascade 3 covers ~5000 world units; no override needed
```

Scenes that want to revert to single-cascade sun-follow:

```swift
sun.setCascadeCount(1)
sun.setShadowRadius(500)          // back to the old radius/lift API
sun.setShadowLift(2000)
```

---

## 17. Performance budget

Per-frame GPU cost increase, estimated:

| Stage | Before (single cascade) | After (4 cascades) | Delta |
|---|---|---|---|
| Shadow generation passes | 1 × ~0.4 ms (8192² depth) | 4 × ~0.12 ms (2048² depth) ≈ 0.5 ms | +0.1 ms |
| GBuffer fragment | ~1.0 ms (sample 1 shadow tex) | ~1.1 ms (cascade-select + sample array) | +0.1 ms |
| Lighting | unchanged | unchanged | 0 |
| Memory | 256 MB shadow | 64 MB shadow | **−192 MB** |

Net: ~+0.2 ms GPU per frame, 4× less shadow memory, ~10× sharper near-field shadows. On a 16ms/60Hz budget, the cost is rounding error.

If the cascade-blending optional (section 12) lands, add another ~0.05ms for the ~10% of fragments inside the blend band.

---

## 18. What's explicitly NOT in this plan

These are listed in the single-cascade plan's "future work" section and remain out of scope:

- **PCF (percentage-closer filtering)** for soft shadow edges. The cascade-aware `CalculateShadow` currently does `filter::nearest`. Switching to `filter::linear` + N-tap PCF kernel is a clean drop-in once CSM is live.
- **Variance Shadow Maps / ESM / MSM** — more advanced shadow techniques. PCF should be tried first.
- **Subclass `LightObject` into `DirectionalLight` / `PointLight`** — refactor across every scene file.
- **Delete the dead `Omni` enum case.**
- **Reverse-Z shadow refactor.** Not worth it for ortho (Q3 of single-cascade plan's followup).
- **Single-pass layered cascade rendering using `[[render_target_array_index]]`** — Metal supports rendering to multiple slices of a texture array in one pass by emitting the slice index from a vertex/object shader. Saves the N CPU-side encodes and shares vertex work across cascades. Defer until profiling shows the N-pass approach is a bottleneck.
- **CPU per-cascade frustum culling.** Currently `DrawManager.DrawShadows` redraws all opaque geometry for every cascade pass. A per-cascade visibility filter (cull objects that fall entirely outside cascade `i`'s ortho frustum) cuts GPU work by ~50% on dense scenes. Easy to add once `ShadowCascadeFitting` exposes per-cascade frustum bounds.
- **Sphere-fit cascade boxes** for guaranteed shimmer immunity (section 11 alternative). Switch only if texel-snap on AABB-fit shows residual shimmer in scenes with FOV changes.
- **The legacy `Omni` case removal + `LightObject` subclass split** — already deferred by the single-cascade plan, same reasoning applies.

---

## TL;DR

1. New `ShadowCascadeFitting.swift`: split frustum, fit ortho per slice, texel-snap.
2. `LightData` grows with `cascadeViewProjectionMatrices[4]` + companions.
3. `ShadowRendering` allocates a `texture2DArray`; `encodeShadowMapPass` loops over cascades, pushing a per-pass cascade-VP at a new buffer index.
4. `Shadow.metal` reads cascade-VP from the push constant (no longer from `LightData`).
5. GBuffer shaders drop `shadowPosition` from `VertexOut`; add `viewSpaceDepth`.
6. `Lighting.metal::CalculateShadow` picks a cascade from view-space depth, transforms `worldPosition` by that cascade's VP, samples the texture array.
7. `LightObject` defaults to 4 cascades; existing scenes work via backward-compat shim (`cascadeCount=1` fast path).
8. Visual outcome: 10× sharper near-field shadows, 10× longer reach, 4× less shadow memory, no shimmer.
