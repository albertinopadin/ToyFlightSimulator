# CSM — Shadow Still Swimming + Progressively Blocky Under Movement

**Status**: IN PROGRESS — handoff to a fresh Claude session.
**Branch**: `csm1` (off `main`)
**Plan that landed this work**: [`plans/claude/cascaded_shadow_maps.md`](../../plans/claude/cascaded_shadow_maps.md)
**Prior context**: [`sun_line_shadow_frustum_cutoff.md`](sun_line_shadow_frustum_cutoff.md), [`sun_line_shadow_frustum_cutoff_followup.md`](sun_line_shadow_frustum_cutoff_followup.md), [`sun_follow_lost_shadows.md`](sun_follow_lost_shadows.md)

## Symptoms (still present)

1. **Shadow swims as the player moves.** A shadow on the ground (e.g. F-22 self-shadow, sphere shadows) shifts in screen-space sub-pixel between consecutive frames. Continuous slide, not 1-texel jumps. Most visible at low camera altitude and when flying steadily forward.
2. **Shadow gets progressively less defined ("blocky" / softer / less crisp) as the player flies away from origin.** At spawn (camera y=109, world ≈ (0, ~100, 0)), shadows have visible silhouette detail. After flying a long distance (e.g. cam.world = (10000, 5.9, 22000)), the F-22 shadow degrades to a fuzzy cross-shaped blob with no silhouette detail — even though `Cascade halfExtentX` stays constant at 300.1 throughout, and the F-22 stays at the same relative position in the cascade UV.

User screenshots showing the progression: [`debugging/screenshots/CSM1.png`](../screenshots/CSM1.png) (spawn, OK) → [`CSM2.png`](../screenshots/CSM2.png) → [`CSM3.png`](../screenshots/CSM3.png) → [`CSM4.png`](../screenshots/CSM4.png) (far from origin, very soft / no detail).

The user reads symptom (2) as "cascades not following the jet." The debug instrumentation conclusively shows they ARE following (sphere center = cam + forward × 93.9 world units, NDC of camera/ground stays inside [-1, 1] every frame). So either the user's mental model is mistaken or there's a real degradation that the NDC probes don't expose.

## Build / repro

Scene that reproduces: **`FlightboxWithPhysics`** (default starting scene per `Preferences.StartingSceneType`).
Renderer in user's logs: **`TiledMSAATessellated`** (the macOS default; the same MSAA shadow code path applies to `TiledMultisampleRenderer` too).
Key scene parameters (`Scenes/FlightboxWithPhysics.swift:17-19`):

```swift
var attachedCamera = AttachedCamera(fieldOfView: 75.0,
                                    near: 0.01,
                                    far: 1_000_000.0)
```

Notable: `far = 1,000,000` is huge — necessitated the `_shadowMaxDistance` cap below. F-22 has `scale: 3.0`, which forces the cascade fitting to multiply the radius by the camera scale.

To reproduce: build for macOS Debug, run the app. Spawn shows F-22 from above. Fly forward (the jet has a `F22SimpleFlightModel` that holds altitude/heading by default; flight inputs accelerate it). Observe shadows degrade over time + see swimming in real time.

```bash
xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" \
    -sdk macosx -configuration Debug CODE_SIGNING_ALLOWED=NO
```

## Architecture summary (where things live)

- **CSM math (cascade fitting)**: `ToyFlightSimulator Shared/Shadows/ShadowCascadeFitting.swift` (273 lines). Computes PSSM splits, builds bounding spheres per slice, snaps to texel grid in world space, returns `[FittedCascade]`.
- **Shadow camera value type**: `ToyFlightSimulator Shared/Shadows/ShadowCamera.swift` (73 lines). Stores `viewMatrix`, `projectionMatrix`, `depthRange`, `orthoHalfExtentX`. Two initializers: legacy `(direction, focus, radius, lift)` (for cascadeCount==1 fast path) and CSM `(lightView, orthoMin/Max X/Y/Z)`.
- **Driving the cascade refresh per frame**: `ToyFlightSimulator Shared/GameObjects/LightObject.swift:118-241`. `updateShadowCascades()` runs from `LightObject.update()` (on the UpdateThread) and populates `lightData.cascadeViewProjectionMatrices`, `cascadeSplitDepths`, `cascadeDepthRange`, `cascadeWorldSlack`, `cascadeCount`.
- **Shadow texture allocation + N-cascade render pass loop**: `ToyFlightSimulator Shared/Display/Protocols/ShadowRendering.swift` (203 lines). `shadowMaps` is a `texture2DArray` with `arrayLength = TFS_MAX_SHADOW_CASCADES = 4`. For each cascade i, the encode loop renders to `depthAttachment.slice = i` (or MSAA-target → resolve into slice i for MSAA renderers).
- **Cascade-aware fragment sampling**: `ToyFlightSimulator Shared/Graphics/Shaders/Lighting.metal:99-188`. `Lighting::CalculateShadow(worldPosition, viewSpaceDepth, worldNormal, light, shadowArray)`. Picks a cascade by view-space depth, transforms `worldPosition` to cascade NDC, samples with 3×3 hardware PCF, returns `[0.5, 1.0]`.
- **Shadow generation vertex shader**: `ToyFlightSimulator Shared/Graphics/Shaders/Shadow.metal`. Takes a per-pass `cascadeVP` push constant at buffer index `TFSBufferIndexShadowCascadeVP = 13`.
- **LightData layout**: `ToyFlightSimulator Shared/Graphics/Shaders/TFSCommon.h:72-130`. C struct shared between Swift and Metal. Cascade fields use `TFS_MAX_SHADOW_CASCADES = 4` fixed-size arrays.
- **Renderers that conform to ShadowRendering**: `TiledDeferredRenderer`, `TiledMultisampleRenderer`, `TiledMSAATessellatedRenderer`, `SinglePassDeferredLightingRenderer`. Property is `shadowMaps: MTLTexture` (the texture2DArray); MSAA renderers also have `shadowMSAATexture: MTLTexture?` (the multisample source, resolved into slices of `shadowMaps`).

### Configurable knobs (LightObject defaults)

| Property | Default | Notes |
|---|---|---|
| `_cascadeCount` | 4 | 1 → legacy single-cascade fast path (bit-identical to pre-CSM) |
| `_cascadeLambda` | 0.5 | PSSM blend |
| `_shadowMapRes` | 4096 | MUST match `ShadowRendering.ShadowMapSize` |
| `_cascadeZPad` | 100 (world units, additive) | replaces earlier multiplicative ×10 padding |
| `_baseWorldSlack` | 0.25 | per-cascade scaled by orthoHalfExtentX / cascade-0 reference |
| `_shadowMaxDistance` | 500 | caps cascade reach; decoupled from `cam.far` |

`ShadowRendering.ShadowMapSize = 4_096`. CascadeCount also reads `TFS_MAX_SHADOW_CASCADES = 4`.

## Chronological log of fixes attempted

### Fix 1 — Camera-far cap

**Problem**: `cam.far = 1_000_000`, so PSSM-with-lambda=0.5 produced cascade splits at `[125000, 250000, 380000, 1000000]` view-space units. Cascade 0 alone was ~982,000 world units wide; each shadow texel covered ~480 world units. F-22 (~30 world units) was smaller than a single texel and didn't get rasterized into the shadow map at all.

**Symptoms before fix**: ground had a regular grid of dark stripes (cascade-boundary lines) and NO F-22 shadow.

**Fix**: added `LightObject._shadowMaxDistance: Float = 500` and passed `min(cam.far, _shadowMaxDistance)` as the cascade-fitting far. Cascade splits became `[62.6, 126.1, 204.2, 500]` view-space units, which after the scale-3 multiplier (see Fix 2) become roughly `[188, 378, 612, 1500]` world units.

**Result**: F-22 shadow appeared. Big visual improvement. Stripes gone.

**File**: `LightObject.swift:34-36` (`_shadowMaxDistance`), `LightObject.swift:158` (passing `shadowFar` to `fitCascades`).

### Fix 2 — Cascade-radius accounting for camera scale

**Problem**: The `AttachedCamera` is parented to the F-22 (which has `scale: 3.0`), so `cameraInverse` (= camera's modelMatrix) has scale 3 baked in. `cameraInverse * (0, 0, midZ, 1)` correctly produced the sphere center in world units (the scale gets absorbed into the translation: `cam.world + forwardUnit * midZ * 3`). But the **radius** was computed purely from view-space slice dimensions and was therefore in scaled-view-space units, NOT world. The cascade ortho box was 3× too small for the area it was centered on.

**Symptoms before fix**: `Sphere0 center world` was correct, but `C0 NDC of camera: uv=(0.000, 0.933)` — camera at the very back edge of cascade 0. Small movement pushed camera+F-22 outside the cascade → shadow vanished.

**Fix**: `boundingSphereForSlice` now multiplies the view-space radius by the camera's scale (extracted from `cameraInverse.columns.0.xyz` length).

**File**: `ShadowCascadeFitting.swift:130-165` (specifically the `radiusView * cameraScale` line at ~158).

**Result**: F-22 stopped disappearing on movement. NDC of camera moved from 0.933 to ~0.311 (well inside the cascade). Shadow persists.

**Critical invariant**: `LightObject._shadowMapRes` and `ShadowRendering.ShadowMapSize` must match (both 4096) — the former drives the texel-snap math, the latter allocates the texture.

### Fix 3 — Bounding sphere fit instead of AABB fit

**Problem**: The original implementation fitted the cascade ortho to the AABB of the frustum-slice's 8 world-space corners projected to light view. As the camera rotated, the corners (relative to the lightView basis) rotated through the AABB, causing `halfExtentX` to swing 60% (debug showed 175 → 280) between consecutive frames. Texel sizes therefore varied frame-to-frame, defeating texel snap.

**Fix**: replaced AABB fit with bounding-sphere fit. Sphere radius depends only on FOV/aspect/near/far (rotation-invariant): `r = sqrt(halfRangeZ² + farHalfH² + farHalfW²)`. Sphere center is the slice midpoint along the camera's view-forward axis, transformed to world via `cameraInverse * (0, 0, midZ, 1)`.

**Result**: `halfExtentX` stays at 300.1 (cascade 0) across all rotations. Texel size is now stable.

**Files**: `ShadowCascadeFitting.swift:118-165` (`boundingSphereForSlice`), `167-228` (`fitOrthoToSphere`).

### Fix 4 — World-space texel snap (replacing no-op snap)

**Problem**: My original snap was a no-op. The light view was constructed with `eye = sphereCenter + lightDirection`, so `lightView * sphereCenter` always equaled `(0, 0, 1)` regardless of camera position. `floor(0 / texelSize) * texelSize = 0` — the snap never shifted anything. Meanwhile, for a fixed world point P, `lv(P) = basis · (P - sphereCenter - lightDir)` depends on `sphereCenter`, so P's UV in cascade slid continuously as the camera moved.

**Fix**: switched to world-space snap. Project `sphereCenter` onto the light view's x and y basis axes (computed directly from `lightDirection`, in world coords). Snap those projections to integer multiples of `texelSize` using `floor`. Apply the resulting shift to `sphereCenter` in world space along `xWorld * shiftX + yWorld * shiftY`. Build lightView around the **snapped** sphereCenter.

**Result (predicted)**: between snaps, the cascade VP matrix is bit-identical across frames; world points map to the same shadow texel. When the camera moves > 1 texel in world along `xWorld` or `yWorld`, `snappedSphereCenter` jumps by exactly one `texelSize` in that direction, and the shadow map's texel grid shifts by exactly 1 world-texel.

**File**: `ShadowCascadeFitting.swift:189-218` (`fitOrthoToSphere` body, snap block at lines 197-216).

**Result (observed)**: swimming **still occurs**. See "Remaining hypotheses" below for why.

### Fix 5 — Slope-scaled bias for shadow acne

Tilted surfaces (F-22 rudders, sphere sides) showed diagonal acne stripes. Added `SlopeScaledWorldBias(baseSlack, normal, lightDir) = baseSlack * (1 + slope * 20)` where `slope = 1 - saturate(dot(normalize(normal), lightDir))`. Ground (normal ⊥ light) gets the base slack; vertical surfaces get up to 21× the slack.

**File**: `Lighting.metal:88-99` (the helper) + `Lighting.metal:114-188` (CalculateShadow), and the three GBuffer fragment shaders that now pass `in.worldNormal` (or `float3(in.normal)` for the legacy GBuffer path).

**Result**: rudder acne gone.

### Fix 6 — Shadow map resolution 2048 → 4096

User requested. Memory: 4 cascades × 4096² × 4B = 256 MB. Texel size in cascade 0: 0.293 → 0.146 world units. Updated **both** `ShadowRendering.ShadowMapSize` and `LightObject._shadowMapRes` (they must match).

**Result**: shadow boundaries marginally crisper but the swimming + blockiness symptoms are unchanged.

### Fix 7 — Hardware PCF (4-tap) → 3×3 PCF (9 hw samples = effective 36-texel average)

Started with `sample_compare` + `filter::linear` + `compare_func::less` (4-tap hw-bilinear). User reported still blocky. Widened to 3×3 grid of hw-bilinear `sample_compare` calls with texel-spaced offsets (9 samples × 4 bilinear taps each = 36-texel effective average). Maps the resulting lit-fraction `[0, 1]` to shadow factor `[0.5, 1.0]`.

**File**: `Lighting.metal:152-188` (the 3×3 PCF block at the bottom of `CalculateShadow`).

**Result**: softer shadows, swimming still visible.

## Debug instrumentation already in place

In `LightObject.debugLogCascades(cascades:cameraView:)` at `LightObject.swift:280-322` — emits a once-per-second `[CSM Debug]` line in DEBUG builds. Fires from `updateShadowCascades()`. Reports:

- `cam=(x, y, z)`: camera world position (from `cameraView.inverse.columns.3`)
- `fwd=(x, y, z)`: camera forward axis in world (= `cameraInverse * (0,0,1,0)`; magnitude = camera scale = 3 in this scene)
- `lightDir=(x, y, z)`: directional light's world direction
- `Sphere0 center world`: cascade 0's sphere center after world-space snap
- `Cascade splits (view-z)`: per-cascade far depths in (scaled) view space
- `Cascade depth ranges`: ortho z-range per cascade in world units
- `Cascade halfExtentX`: bounding sphere radius in world units (per cascade)
- `C0 NDC of camera`: cascade-0 NDC of `camPosWorld` (should be inside [-1, 1])
- `C0 NDC of ground-under-cam`: cascade-0 NDC of (camPosWorld.x, 0, camPosWorld.z)

The user has captured this output extensively. Sample line from the latest run (camera flying steady):

```
[CSM Debug] cam=(10162.4, 5.9, 22236.1) fwd=(0.834, 0.186, 2.876) lightDir=(0.000, 1.000, 0.020)
  Sphere0 center world: (10188.5, 11.7, 22326.1)
  Cascade splits (view-z): 62.6, 126.1, 204.2, 500.0
  Cascade depth ranges:     800.2, 1364.7, 2075.2, 4840.8
  Cascade halfExtentX:      300.1, 582.3, 937.6, 2320.4
  C0 NDC of camera:    uv=(0.087, 0.300) z=0.5095
  C0 NDC of ground-under-cam: uv=(0.087, 0.299) z=0.5168
```

Note how `Cascade halfExtentX`, `Cascade depth ranges`, and `C0 NDC of camera` stay **constant** for many consecutive frames during steady flight (forward axis stops rotating). That's the texel snap working: same cascade VP frame-after-frame. So the cascade is NOT changing between frames during steady flight — yet the user still reports swimming. **This is the key contradiction to investigate next.**

## What I'm confident is correct

1. **Sphere center placement.** Math verified: `sphereCenter = cameraInverse * (0, 0, midZ, 1) = cam.world + forwardUnit * (midZ * scale)`. Debug line `Sphere0 center world` is always `camera + 93.9 * forwardUnit` regardless of camera position. Cascade follows the jet.
2. **Cascade VP stability between snap boundaries.** When the cascade VP is recomputed each frame with the snapped sphere center, sub-texel camera motion does NOT change the snapped center, so the matrix is bit-identical across consecutive frames. (See the long blocks of identical `halfExtentX = 300.1` rows in the user's logs.)
3. **Camera scale handling.** `cameraInverse.columns.0.xyz` has length 3 (jet scale). Multiplying the view-space radius by this length puts the radius in world units, matching the sphere center which already has the scale baked in.
4. **Cascade selection.** Fragment shader's `viewSpaceDepth = fabs(eyePosition.z)` is in the same scaled-view-space units as `cascadeSplitDepths`. The for-loop selection picks cascade 0 for fragments under the jet.

## Theories tested and ruled out

### "The cascade matrix isn't updating each frame"

False. Debug log shows `Sphere0 center world` updates every frame as the camera moves. `cascadeViewProjectionMatrices` are recomputed in `LightObject.updateShadowCascades()` on every UpdateThread tick.

### "Shadow gen and GBuffer pass use different matrices"

Ruled out by code inspection. Both reads come from the same `light.lightData.cascadeViewProjectionMatrices` populated once per UpdateThread tick. The render thread waits on `updateDoneSemaphore` before encoding, so the matrix is stable during a frame's encoding.

In `ShadowRendering.swift:114-117` the helper `cascadeVP(at: i, in: light)` reads via `withUnsafePointer` + `withMemoryRebound`:

```swift
private func cascadeVP(at i: Int, in light: LightObject) -> matrix_float4x4 {
    return withUnsafePointer(to: light.lightData.cascadeViewProjectionMatrices) { tuplePtr in
        tuplePtr.withMemoryRebound(to: matrix_float4x4.self, capacity: 4) { $0[i] }
    }
}
```

Same memory the GBuffer's `SceneManager.SetDirectionalLightConstants` reads via `LightManager.GetDirectionalLightData`. No tearing possible across a single frame's encode.

### "Float32 precision at world coords ~22000 kills the depth compare"

Worked out by hand. At world.x = 22000:
- `cascadeVP.col3.x ≈ -t.x / radius ≈ 33.3` (after scale division)
- `cascadeVP.row0 · worldPos` involves `-0.00333 × 22000 + 33.3 = -73.26 + 33.3` — but wait, this depends on whether the snapped center is also near 22000. For the snapped center at `(10026, 11.7, 22087)`, `t.x = snappedCenter.x = 10026`, so `cascadeVP.col3.x = 10026/300 ≈ 33.42`. For worldPos at `(22000, 0, 22000)` (a hypothetical far-flung ground point), `row0 · worldPos = -0.00333 × 22000 + 33.42 = -73.26 + 33.42`, but this point would be way outside cascade 0 anyway (would use cascade 3).

For a worldPos NEAR the snapped center (within radius 300): say `(10100, 5, 22100)`:
- `row0 · worldPos = -0.00333 × 10100 + 33.42 = -33.63 + 33.42 = -0.21`
- Two terms at magnitude ~33, precision per float32 ≈ 33 × 6e-8 = 2e-6. Subtraction error sqrt(2) × 2e-6 ≈ 3e-6.
- NDC.x precision ≈ 3e-6. Texel index error = 3e-6 × 4096 = 0.012 texels. Negligible.

So float precision at world coords up to ~25k is fine for the shadow texel grid. Likely not the issue.

### "Texel snap is broken"

Mathematically derived (see Fix 4) and visually confirmed via NDC stability across consecutive frames. Within a snap bin (camera moves < 1 texel), the cascade matrix is bit-identical; world points map to the same texel. When the camera crosses a texel boundary, `snappedSphereCenter` shifts by exactly `texelSize` along `xWorld` or `yWorld`. So the snap IS working.

### "The MSAA shadow path is broken differently than the non-MSAA path"

Unlikely — the MSAA path renders to a non-array MSAA texture and resolves into slice i of the array. The depth resolve filter defaults to `.sample0` (picks sample 0). The GBuffer always samples the **resolved** non-MSAA array texture. Same as the non-MSAA path conceptually.

The user could rule this out definitively by switching the renderer (via the `/` menu? Not sure if exposed) to `TiledDeferred` (non-MSAA) and checking if the symptom changes.

## Remaining hypotheses worth investigating

### (A) The "swimming" is per-frame F-22 mesh animation, not cascade motion

The F-22 has animated control surfaces (per `F22Animator.swift`). Animation channels run on the UpdateThread every frame. If channels emit tiny per-frame vertex displacements, the shadow map rasterization moves accordingly, and the F-22's silhouette in the shadow map shifts sub-pixel between frames. PCF smooths it but the eye still picks up the edge motion.

**Test**: temporarily stop the F-22's animator (`AircraftAnimator.update(deltaTime:)` early-return) and observe whether swimming persists. If it stops, this is the cause.

### (B) Shadow generation pass doesn't actually use the per-frame snapped matrix

Worth verifying via Xcode GPU frame capture. Compare the `cascadeVP` push constant bound during the shadow pass to `lightData.cascadeViewProjectionMatrices[0]` bound during the GBuffer pass — they should be **bit-identical**. If they differ, there's a write-after-read race.

Specifically: `ShadowRendering.swift:120` reads `cascadeVP(at: i, in: primaryLight)` BEFORE entering the render-pass closure. Then `SceneManager.SetDirectionalLightConstants(with: renderEncoder)` is called INSIDE the closure (`ShadowRendering.swift:150`), which re-reads `light.lightData`. If anything mutates `lightData` between these two reads, the shadow gen would use a stale `cascadeVPLocal` while the GBuffer's `lightData` reflects the newer state.

**Test**: hoist the `SetDirectionalLightConstants` call outside the per-cascade loop, or read the entire `LightData` into a local once and reuse. If swimming stops, this is the cause.

### (C) The UpdateThread runs LightObject.update() AFTER the camera's world matrix is finalized for this frame, but the cascadeVPs from THIS frame are used for the SHADOW GEN of THIS frame and the GBUFFER of THIS frame — both should match. But maybe the F-22 is updated by physics on a different thread, mid-frame.

This codebase has an `UpdateThread` and a `PhysicsWorld`. Need to verify the F-22's `modelMatrix` (used for shadow gen's draw calls) is stable across the shadow pass + GBuffer pass within a single frame.

**Test**: log F-22's `modelMatrix.columns.3` (world position) at three points: top of `LightObject.update()`, top of shadow gen encode, top of GBuffer encode. They should all match. If they don't, there's a threading hazard.

### (D) The "progressive blockiness" is purely viewing-angle foreshortening

When the camera is at altitude (CSM1, y=109 looking down), the F-22's shadow on the ground occupies a SMALL portion of the screen. Each shadow-map texel (0.146 world units) projects to roughly square screen pixels — texel edges are sub-pixel and invisible.

When the camera is at low altitude (CSM4, y=5.9 looking forward), the F-22's shadow occupies a LARGE screen area, with extreme foreshortening along the depth direction. Each texel projects to a LONG screen strip. The 3×3 PCF can't smooth them away because the kernel is texel-spaced and the strips are many pixels long.

**Test**: at the "very blocky" position, raise the camera (DebugCamera 'C' key gives a free-fly camera that can fly straight up). If the shadow looks crisp from above, this hypothesis is correct and the only fix is more PCF taps or a different filtering technique (VSM, ESM).

If raising the camera doesn't crisp up the shadow, then there's a real degradation NOT caused by viewing angle, and the next-most-likely culprit is float precision in `modelMatrix * vertex` in the shadow vertex shader at huge world coords (see (E)).

### (E) Float precision in `modelMatrix * vertex` for the F-22 at world ~22000

The F-22's `modelMatrix.col3` has values up to ~22000. Multiplying by a vertex (small) gives `worldPos` ≈ `col3 + small_offset_from_basis_rotation`. Then `cascadeVP * worldPos` involves catastrophic cancellation (e.g., `-0.00333 × 22000 + 33.42 = -0.21`).

I worked through this in "Theories ruled out" and found the precision should be 3e-6 NDC = 0.012 texels — not enough to cause visible degradation. But that calculation assumed `cascadeVP.col3.x = snappedCenter.x / radius` was computed in double precision on the CPU. Metal's `simd_float4x4` is single-precision throughout. If the **CPU-side** computation of `cascadeVP = ortho * lightView` loses precision (because lightView's translation is huge), then the matrix passed to the GPU already has degraded precision.

**Test**: log on the CPU: `cascadeVP[0].col3` values at world coords ~22000. The col3 should be approximately `(snappedCenter.x/radius, snappedCenter.y_proj_to_lvY/radius, snappedCenter.z_proj_to_lvZ/depthRange + 0.5, 1)`. If col3.x and col3.y have values much larger than `radius` (i.e., they reflect the raw snapped center magnitude rather than the post-divide ratio), float32 precision on the row0·worldPos dot product will degrade.

**Mitigation if (E) is real**: implement "camera-relative shadow rendering". Pre-subtract the camera's world position from both the shadow gen vertices and the cascade VP before sending to the GPU. The GPU then does all matrix math on small numbers. Requires a shader change: shadow_vertex takes `cameraWorld` as an additional push constant and computes `clip = cascadeVP_rebased * (modelMatrix * vertex - cameraWorld)`.

### (F) The F-22 sometimes lies BELOW the ground (jet world.y < 0)

In the user's final log entry (`cam=(10464, 5.9, 22893)`), if camera-offset extraction gives `jet.world.y = camera.y - 6 = -0.1`, the jet has clipped through the ground (physics bug). Its mesh underside renders into the shadow map. Combined with the ground surface itself being rasterized, the shadow map's depth at the jet's UV alternates between "jet underside" and "ground" depending on which fragment wins the depth test during shadow gen. This produces flicker/blurry shadows.

**Test**: print jet.world.y per frame and check whether it goes below zero. If yes, this is a physics-collision-resolution bug, not a CSM bug.

## Things I deliberately did NOT try (and why)

- **VSM / ESM / MSM**: out of scope. Big architectural change. Should only attempt if (A)–(F) all fail and the user wants soft analog shadows.
- **Cascade-boundary blending**: addresses a different symptom (visible seams between cascades). Not relevant to the swimming/blockiness reported.
- **5×5 or Poisson-disk PCF**: tried 3×3; widening further is the obvious next step if 3×3 isn't enough. But likely diminishing returns vs the cost (25 samples vs 9).
- **Camera-relative rendering**: mentioned in (E) but it's a substantial refactor — touches shadow vertex shader, cascade VP computation, and probably the GBuffer vertex shader too. Only do this if (E) is confirmed via testing.

## Critical files to read first

In priority order for the next investigator:

1. **`ToyFlightSimulator Shared/Shadows/ShadowCascadeFitting.swift`** — the snap math. Lines 130-165 (`boundingSphereForSlice`) and 167-228 (`fitOrthoToSphere`).
2. **`ToyFlightSimulator Shared/GameObjects/LightObject.swift`** lines 158-241 — `updateShadowCascades()`. Especially the multi-cascade path (line 178 onward).
3. **`ToyFlightSimulator Shared/Display/Protocols/ShadowRendering.swift`** lines 113-200 — the three encode functions (`encodeShadowMapPass`, `encodeShadowPassTiledDeferred`, `encodeMSAAShadowPass`). Investigate the read-once-vs-read-twice question in hypothesis (B).
4. **`ToyFlightSimulator Shared/Graphics/Shaders/Lighting.metal`** lines 99-188 — `CalculateShadow` with 3×3 hw PCF.
5. **`ToyFlightSimulator Shared/Graphics/Shaders/Shadow.metal`** — the shadow vertex shader; reads `cascadeVP` at `TFSBufferIndexShadowCascadeVP` = 13. Identical for the animated variant.
6. **`ToyFlightSimulator Shared/Scenes/FlightboxWithPhysics.swift`** — scene setup, camera FOV/near/far, F-22 scale and position.

## Suggested investigation order

1. **Run the app, fly to "blocky" state, switch to `DebugCamera` (press 'C'), fly straight up.** If shadow crisps up, hypothesis (D) is the cause and the issue is purely viewing-angle PCF kernel width. Move to wider PCF or different filtering.
2. If shadow stays blocky from above too: **freeze the F-22 animator** (early return in `F22Animator.update`) and re-test. Tests hypothesis (A).
3. If still bad: **GPU frame capture in Xcode**, inspect cascadeVP bound to shadow gen vs LightData bound to GBuffer. Verify bit-identical. Tests hypothesis (B).
4. **Log F-22.modelMatrix.col3 at three sync points** (LightObject.update, shadow gen encode start, GBuffer encode start). Tests hypothesis (C).
5. **Log cascadeVP matrix elements at world coord 22k** vs world coord 100. Compare precision. Tests hypothesis (E).
6. **Log jet.world.y per frame** and check for negative values. Tests hypothesis (F).

## Cross-references to prior work

- The plan that landed CSM: [`plans/claude/cascaded_shadow_maps.md`](../../plans/claude/cascaded_shadow_maps.md). Sections of interest: §2 (ShadowCascadeFitting), §4 (LightObject refactor), §11 (texel snap stability).
- The single-cascade sun-follow plan (predecessor): [`plans/claude/single_cascade_sun_following_shadow_camera.md`](../../plans/claude/single_cascade_sun_following_shadow_camera.md).
- The original SunLine bug: [`debugging/claude/sun_line_shadow_frustum_cutoff.md`](sun_line_shadow_frustum_cutoff.md).
- The "lost shadows after sun-follow" investigation (mirrors current debug methodology): [`debugging/claude/sun_follow_lost_shadows.md`](sun_follow_lost_shadows.md).

## Test artifacts captured

Screenshots in `debugging/screenshots/`:
- `CSM1.png` … `CSM4.png` — progressive blockiness over a long flight.
- `BlockyShadow.png`, `BlockyShadow2.png` — earlier states with different fixes applied.
- `BlockShadowAcne.png` — pre-slope-bias acne on rudders.
- `SoftBlockShadows.png` — after PCF 4-tap, before 3×3 widen.
- `StartPosShadows.png` — initial-position reference.
- `CascadedShadowMapsLines.png`, `CSMLines1.png`, `CSMLines2.png` — earliest state with the cascade-far bug (huge texels, ground stripes).
