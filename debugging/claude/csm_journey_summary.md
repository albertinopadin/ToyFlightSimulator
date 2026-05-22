# Cascaded Shadow Maps — Two-Day Debugging Journey

**Branch**: `csm1` (off `main`)
**Final state**: WORKING. F-22 self-shadow + cast-shadow on ground stay crisp at any world coordinate the player can fly to. No swimming, no progressive blockiness, no missing F-22 shadow.
**Plan that initiated the work**: [`plans/claude/cascaded_shadow_maps.md`](../../plans/claude/cascaded_shadow_maps.md)
**Mid-debugging handoff doc** (full chronological diary): [`IN_PROGRESS_csm_swimming_and_progressive_blockiness.md`](IN_PROGRESS_csm_swimming_and_progressive_blockiness.md)
**Final root-cause writeup**: [`csm_select_cascade_drift.md`](csm_select_cascade_drift.md)
**Prior context**: [`sun_line_shadow_frustum_cutoff.md`](sun_line_shadow_frustum_cutoff.md), [`sun_line_shadow_frustum_cutoff_followup.md`](sun_line_shadow_frustum_cutoff_followup.md), [`sun_follow_lost_shadows.md`](sun_follow_lost_shadows.md) — the single-cascade sun-follow predecessor that CSM extends.

---

## Why this debugging took two days

The initial plan (`cascaded_shadow_maps.md`) was a complete CSM design built on top of the working single-cascade sun-follow path. It correctly identified all the pieces — PSSM splits, frustum-corner unprojection, AABB fit in light view space, texel snap, depth bias, per-cascade shader selection. Implementing it gave a *functioning* CSM in one shot. But "functioning" turned out to be a long way from "correct" because the system has four properties that compound each other:

1. **The scene is huge** (1,000,000 × 1,000,000 ground plane) and the camera flies at thousands of world units from origin during normal use.
2. **The camera is parented to a scale-3 jet**, so the active view matrix has 1/3 scale baked in — every "view-space" magnitude is 1/3 of the corresponding "world-space" magnitude, and the camera's `cam.near`/`cam.far` are interpreted in scaled-view-space.
3. **The directional light comes from nearly overhead**, so the cascade fit produces a light-view basis that's degenerate-adjacent and very sensitive to small errors.
4. **The shadow map's perception of "correct" is a comparison between a per-vertex GPU-interpolated value (`viewSpaceDepth`) and per-cascade CPU-derived thresholds (`cascadeSplitDepths`).** Get either side's units wrong, or let the interpolation produce a non-linear-attribute pathology, and the symptom is "shadows quietly degrade as you move" — which doesn't look like a precision bug, it looks like the cascades aren't following the player.

Every fix on the journey unlocked a *different* dormant problem that the previous brokenness had been masking.

---

## Chronological summary — what broke and what fixed it

### Pre-session fixes (Fixes 1–7 from the IN_PROGRESS doc)

Each of these landed before this session started. They're documented in detail at [`IN_PROGRESS_csm_swimming_and_progressive_blockiness.md`](IN_PROGRESS_csm_swimming_and_progressive_blockiness.md); summarized here so the journey reads end-to-end.

#### Fix 1 — Camera-far cap (`_shadowMaxDistance = 500`)
**Symptom**: cam.far = 1,000,000 → PSSM with lambda=0.5 produced cascade-0 splits at 125,000 view-space units → cascade-0 alone was 982,000 world units wide → each texel covered ~480 world units → F-22 (~30 world units) was smaller than one texel → no F-22 shadow at all; ground had a regular grid of dark stripes (cascade-boundary lines).
**Fix**: cap the cascade-fitting `far` at `min(cam.far, _shadowMaxDistance)` with `_shadowMaxDistance = 500`. Decouples shadow reach from the flight-sim sky/horizon far plane.
**Why this is non-obvious**: the plan assumed the camera's near/far would already be sensible. Flight sims aren't sensible — they need a huge far plane so the horizon and sky render, but realistic shadow casters never sit more than a few hundred units from the camera.

#### Fix 2 — Cascade radius accounting for camera scale
**Symptom**: `Sphere0 center world` was correct, but `C0 NDC of camera = uv=(0, 0.933)` — the camera was sitting at the very back edge of cascade 0. Tiny camera motion pushed the camera (and the attached jet) outside the cascade → shadow vanished entirely.
**Root cause**: `boundingSphereForSlice` returned a `sphereCenter` in world units (because `cameraInverse * (0, 0, midZ, 1)` correctly absorbs the camera's scale into the translation) but a `radius` in pure view-space units (computed from view-space slice dimensions). The cascade ortho box was *3× too small* for the area it was centered on.
**Fix**: extract `cameraScale = simd_length(cameraInverse.columns.0.xyz)` and multiply the view-space radius by it. (`ShadowCascadeFitting.swift:178-181`)
**Why this is non-obvious**: there are *two* unit systems in play (world and scaled-view-space) and the original code mixed them in the same function. The bug only triggers when the camera has a non-unit scale — which the attached-camera setup does as a side effect of being a child of a `setScale(3.0)` aircraft.

#### Fix 3 — Bounding sphere fit (replacing AABB-of-corners fit)
**Symptom**: even after Fix 2, `Cascade halfExtentX` swung 60% (175 → 280) between consecutive frames as the camera rotated, so texel sizes were not stable and the world-space texel snap couldn't hold a shadow edge still.
**Root cause**: the original fit computed the AABB of the slice's 8 world-space corners *projected to light view*. As the camera rotates, those corners rotate through the light-view AABB, so the AABB extents change.
**Fix**: replace AABB fit with bounding-sphere fit. Sphere radius depends only on FOV/aspect/near/far (`r = sqrt(halfRangeZ² + farHalfH² + farHalfW²)`) — rotation-invariant. Sphere center is the slice midpoint along the camera's view-forward axis. (`ShadowCascadeFitting.swift:130-188`)
**Why this is non-obvious**: the LearnOpenGL CSM tutorial uses AABB-of-corners and works fine because it doesn't combine that with texel snap. To make snap work at all, you need cascade-extent stability across rotations.

#### Fix 4 — World-space texel snap (replacing a no-op snap)
**Symptom**: shadow edges visibly shimmer/swim sub-pixel across frames as the camera moves, despite a "texel snap" being in the code.
**Root cause**: the original snap projected `sphereCenter` into light view (where it always evaluates to `(0, 0, 1)` by construction, because the light's eye is placed at `sphereCenter + lightDir`) and rounded those zero coordinates. The snap was a no-op.
**Fix**: do the snap in *world space* before building lightView. Project `sphereCenter` onto the light-view's `xWorld` / `yWorld` basis axes (which depend only on `lightDirection`, not on the camera), snap those projections to integer multiples of `texelSize`, apply the shift in world space along `xWorld * shiftX + yWorld * shiftY`. Build lightView around the *snapped* sphereCenter. (`ShadowCascadeFitting.swift:209-274`)
**Why this is non-obvious**: the snap operates on a *world-space* shift but lives downstream of the lightView basis. Easy to write it in lightView space and not notice that the lightView basis is itself derived from the value you're trying to snap.

#### Fix 5 — Slope-scaled depth-compare bias
**Symptom**: diagonal acne stripes on tilted surfaces (F-22 rudders, sphere sides).
**Root cause**: flat depth-compare epsilon was tuned for ground (which is perpendicular to the overhead sun and needs minimal bias) and was much too small for surfaces nearly parallel to the light.
**Fix**: `SlopeScaledWorldBias(baseSlack, normal, lightDir) = baseSlack * (1 + slope * SLOPE_BIAS_FACTOR)` where `slope = 1 - saturate(dot(normalize(normal), lightDir))`. Ground gets base slack; vertical surfaces get up to 21× the slack. (`Lighting.metal:88-105`)
**Why this is non-obvious**: standard shadow-bias tutorials cover this, but the existing single-cascade path didn't need it (one big map, modest texels).

#### Fix 6 — Shadow map resolution 2048² → 4096²
Texel size in cascade 0 goes from 0.293 to 0.146 world units. Memory: 4 × 4096² × 4B = 256 MB, same as the pre-CSM single 8192² map. `LightObject._shadowMapRes` and `ShadowRendering.ShadowMapSize` must match (the former drives the texel-snap math, the latter allocates the texture).

#### Fix 7 — Hardware PCF 4-tap → 3×3 PCF kernel
9 hardware-bilinear `sample_compare` calls in a 3×3 grid, mapped to a `[0.5, 1.0]` shadow factor. Smooths the per-texel snap-shift below the eye's discrimination threshold. (`Lighting.metal:152-216`)

After all seven fixes, the IN_PROGRESS doc handed off two persistent symptoms:
- **Swimming** during steady flight (cascade VP confirmed bit-identical frame-to-frame in the debug log, yet shadow edges still slide sub-pixel).
- **Progressive blockiness**: the F-22 shadow degrades to a "fuzzy cross-shaped blob with no silhouette detail" as the player flies from spawn to e.g. `cam_world = (10K, 5.9, 22K)`.

The IN_PROGRESS doc enumerated six remaining hypotheses (A–F). Three were ruled out by code inspection (race conditions, MSAA path differences, F-22 dipping below ground). Hypothesis (E) — float precision in `view * worldPos` at huge world coordinates — was the one this session pursued.

### This session — narrowing to `SelectCascade`

#### User's key insight: replace `SelectCascade` body with `return 0`
**Outcome**: F-22 shadow stays crisp on the user-focused jet regardless of distance from origin.
**Why this is decisive**: it proves that cascade 0's shadow map *does* contain a correctly-rasterized F-22 silhouette at any world coordinate. The bug is purely in *which cascade is selected per fragment*, not in any of:
- The cascade-VP matrix (still produces a correct shadow map when forced).
- The shadow generation pass (still rasterizes the F-22 into cascade 0 correctly).
- The shadow sampler / PCF kernel (still reads correct depths).
- `cascadeSplitDepths` (debug-logged as the same `62.6, 126.1, 204.2, 500.0` every frame regardless of camera position).

So `SelectCascade(viewSpaceDepth, splits)` is wrong, and since splits are stable, **`viewSpaceDepth` is the broken quantity**.

#### D1 iteration 1: visualize `viewSpaceDepth` as red intensity
**Method**: replace shadow sample with `color = float4(min(viewSpaceDepth / 100.0, 1.0), 0, 0, 1)` in the fragment shader.
**Observation at spawn**: F-22 is uniformly dim red (~0.09); ground shows a dim→bright gradient from camera-near to horizon. Both correct.
**Observation at `cam_world ≈ (10K, 5.9, 22K)`**: F-22 still uniformly dim red — `viewSpaceDepth` is *fine* per-vertex for the F-22 mesh. But the **entire ground** saturates to bright red, meaning ground fragments directly under the camera report `viewSpaceDepth > 100` — pushing them out of cascade 0.

This is the crucial refinement to hypothesis (E): the per-vertex precision story explains the F-22 being marginally affected, but the ground is *catastrophically* broken in a way the precision math alone doesn't predict. F-22-self-shadow looks fine (small mesh, all vertices in front of camera); F-22-cast-on-ground gets blocky (because the ground fragments under the F-22 sample the wrong cascade).

**Why the ground specifically breaks**: the ground is a single Quad at scale 1,000,000 with corners at world `(±500K, 0, ±500K)`. From any camera position inside that XZ extent, two of the four corners are behind the camera (negative eye-space z) and two are in front. `viewSpaceDepth = fabs(eyePosition.z)` writes ~200K positive at all four corners, *losing the sign*. The rasterizer then has to homogeneous-clip the triangle against the near plane and interpolate user attributes perspective-correctly across vertices with *mixed-sign clip.w*. In float32 this collapses to a near-constant value across the visible portion of the triangle — at spawn the cancellation noise is tolerable (cam_world ~100); at the far position it's not (cam_world ~24K).

#### D1 iteration 2 (proposed fix v1): vertex-shader `distance(worldPos, cameraPos)`
**Method**: replace `viewSpaceDepth = fabs(eyePosition.z)` with `viewSpaceDepth = distance(worldXYZ, sceneConstants.cameraPosition)` in the vertex shader. Multiply `cascadeSplitDepths` by `cameraScale` on the CPU to keep both sides in world units.
**Observation**: F-22 still uniformly dim red (good). But the **ground develops a faint dim patch that stays at a fixed world location instead of tracking the camera**.
**Why iteration 1 failed**: `distance(worldPos, cameraPos)` is `sqrt(Σ(worldPosᵢ − cameraPosᵢ)²)` — **non-linear in eye space**. The rasterizer's perspective-correct interpolation produces exact per-fragment values *only for attributes that are linear in eye space*. Interpolating a non-linear attribute across a triangle whose vertices span the near plane produces a value that varies with the triangle's geometry but doesn't track the camera position. The dim patch is the interpolation minimum of the per-vertex distances; it sits at a fixed world location because the ground's vertices are fixed in world space.

This was the *most informative* failure of the journey: it ruled out "any per-vertex scalar that depends on camera position" as the right shape of the fix.

#### D1 iteration 3 (final fix): fragment-shader recomputation
**Method**: don't write `viewSpaceDepth` as a per-vertex attribute at all (or write it but ignore it). In the fragment shader, recompute it from the already-perspective-correctly-interpolated `worldPosition`:
```metal
float fragViewSpaceDepth = distance(in.worldPosition, sceneConstants.cameraPosition);
color.a = Lighting::CalculateShadow(in.worldPosition,
                                    fragViewSpaceDepth,
                                    in.worldNormal,
                                    lightData, shadowArray);
```
**Why this works**:
- **`worldPosition` is linear in eye space** (it's `view⁻¹ · eyePos` where `view⁻¹` is affine), so the rasterizer interpolates it correctly even for triangles spanning the near plane.
- The per-fragment subtraction `worldPos - cameraPos` is **Sterbenz-exact** in float32 (when `|a/2| ≤ b ≤ 2a`, the subtraction is computed exactly). Visible fragments satisfy this trivially.
- `length` of the small relative vector is well-conditioned.

User confirmed: dim red region of the ground tracks the camera correctly, F-22 still uniformly dim red, and once the diagnostic was disabled, the actual shadows look correct.

---

## Key correct insights, why they mattered

In rough order of impact:

### 1. "Replace `SelectCascade` with `return 0` and see if the bug goes away" (user)
This is the *single most useful* debugging move in the journey. It collapsed an enormous hypothesis space (shadow gen, shadow sampling, cascade fitting, texel snap, depth bias, sample_compare semantics, MSAA resolve, threading, struct layout, …) down to a single five-line function. Without this, the next session would have continued chasing the swimming hypothesis (which was also real, but separate) and missed the real cascade-selection bug.

### 2. "F-22 stays dim red but ground is bright red" (user, D1 iteration 1)
The refinement that distinguished per-vertex precision (which is real but small) from per-fragment interpolation pathology (which dominates). Without this refinement, the proposed fix would have been "improve per-vertex precision" — which the iteration-1 attempt showed isn't enough.

### 3. "Dim patch stays at a fixed world location" (user, D1 iteration 2)
Distinguished "the camera position isn't reaching the shader" from "the camera position reaches the shader but the interpolated value doesn't track". Forced the realization that `distance` is non-linear in eye space.

### 4. Switching from AABB-of-corners fit to bounding-sphere fit (earlier session, Fix 3)
The first time anyone realized that texel snap requires *cascade-extent stability across camera rotations*, not just camera-position stability. AABB-of-corners fails this trivially because the corners rotate through the AABB.

### 5. Computing cascade radius in world units, not scaled-view-space (earlier session, Fix 2)
The first time the scale-3 attached-camera scenario was recognized as introducing two coexisting unit systems. Until this fix, the F-22 was disappearing from its own cascade because the cascade was 3× too small for the area it was centered on.

### 6. Decoupling shadow reach from camera far plane (earlier session, Fix 1)
The flight-sim-specific issue: huge `cam.far` for horizon rendering would otherwise blow up the cascade splits and make individual texels larger than the F-22.

---

## What didn't work, and why the dead ends were useful

### "Float precision in `simd_inverse(modelMatrix)`"
Worked through analytically: at world coords ~22K, the inverse matrix entries lose ~0.003 relative precision (~0.001 absolute at magnitude 0.333). The per-term error compounds to ~40 absolute error on `eyePos.z` for an F-22 fragment. This *should* have caused visible cascade-misselection on the F-22, but the user's D1 iteration-1 result showed the F-22 was actually unaffected. Confused us into thinking the precision story was right but only for the F-22 — when in fact the precision story was barely relevant; the ground bug was a *separate* mechanism (mixed-sign-clip.w in the rasterizer) that the precision math didn't predict.

**Useful lesson**: precision math gives an upper bound on error magnitude, not a lower bound. A "should have visible error" by precision analysis may not actually show up if the rasterizer happens to interpolate the noisy values *consistently* across nearby fragments. The visible symptoms come from cases where consistency breaks — which is what the near-plane clipping does.

### Vertex-shader `distance(worldPos, cameraPos)` (iteration 1 of the proposed fix)
Worked perfectly for the F-22. Failed for the ground. The exact same change at vertex level vs fragment level has dramatically different correctness characteristics, because the rasterizer is in between.

**Useful lesson**: when an attribute is non-linear in eye space, *don't write it from the vertex shader*. Either pick a linear attribute (e.g., signed `eyePos.z`, which is the same as `clip.w`) or compute the non-linear function in the fragment shader from a linear precursor.

### Texel snap in lightView space (original implementation, replaced by Fix 4)
A textbook example of "the code does what it looks like it should do, but the inputs make it a no-op." `floor(0 / texelSize) * texelSize = 0` — the snap evaluates exactly when the input is the only stable thing about the whole computation, because the snap's *frame of reference* was derived from the very value being snapped.

---

## Files changed across the entire journey

These are the files that bear scars from the journey. For a clean re-implementation, see the next section.

### Created
- `ToyFlightSimulator Shared/Shadows/ShadowCascadeFitting.swift` — PSSM splits + bounding-sphere fit + world-space texel snap.
- `debugging/claude/IN_PROGRESS_csm_swimming_and_progressive_blockiness.md` — mid-debugging diary.
- `debugging/claude/csm_select_cascade_drift.md` — final root-cause writeup of the `SelectCascade` bug.
- `debugging/claude/csm_journey_summary.md` — this file.
- Many screenshots under `debugging/screenshots/` (`CSM1.png`–`CSM4.png`, `BlockyShadow*.png`, `RedVSD_*.png`, `DB1.png`, `DB2.png`).

### Moved
- `ToyFlightSimulator Shared/GameObjects/ShadowCamera.swift` → `ToyFlightSimulator Shared/Shadows/ShadowCamera.swift` (and extended with the cascade-fit initializer).

### Modified
- `ToyFlightSimulator Shared/GameObjects/LightObject.swift` — replaced `updateShadowCamera` with `updateShadowCascades`; added cascade-config knobs (`_cascadeCount`, `_cascadeLambda`, `_shadowMapRes`, `_cascadeZPad`, `_shadowMaxDistance`, `_baseWorldSlack`); per-cascade homogeneous-tuple writes via `withUnsafeMutablePointer`; multiplies `splitFar` by `cameraScale` on the way into `cascadeSplitDepths`.
- `ToyFlightSimulator Shared/Graphics/Shaders/TFSCommon.h` — added `TFS_MAX_SHADOW_CASCADES = 4`, `TFSBufferIndexShadowCascadeVP = 13`, and the cascade fields on `LightData`.
- `ToyFlightSimulator Shared/Graphics/Shaders/Lighting.metal` — rewrote `CalculateShadow`/`CalculateShadowMSAA` to be cascade-aware; added `SelectCascade`, `SlopeScaledWorldBias`, `NDCShadowEpsilon`; 3×3 hardware PCF.
- `ToyFlightSimulator Shared/Graphics/Shaders/Shadow.metal` — both shadow vertex functions consume `cascadeVP` push constant at index 13.
- `ToyFlightSimulator Shared/Graphics/Shaders/TiledDeferredGBuffer.metal` — vertex writes `worldPosition` & `viewSpaceDepth = distance(worldXYZ, cameraPosition)`; fragment binds `SceneConstants` and recomputes `fragViewSpaceDepth` per-fragment.
- `ToyFlightSimulator Shared/Graphics/Shaders/TiledMSAAGBuffer.metal` — same per-fragment recomputation pattern.
- `ToyFlightSimulator Shared/Graphics/Shaders/GBuffer.metal` — same per-fragment recomputation pattern (both `gbuffer_fragment_base` and `gbuffer_fragment_material`).
- `ToyFlightSimulator Shared/Graphics/Shaders/TiledDeferredTransparency.metal`, `SinglePassDeferredTransparency.metal` — vertex shaders write the new `distance(worldXYZ, cameraPosition)` for VertexOut consistency (transparency doesn't sample shadows but uses the same struct).
- `ToyFlightSimulator Shared/Graphics/Shaders/ShaderDefinitions.h` — `VertexOut` lost `shadowPosition`, gained `viewSpaceDepth`.
- `ToyFlightSimulator Shared/Scenes/GameScene.swift` — `setSceneConstants` now also binds via `setFragmentBytes` so fragment shaders can read `cameraPosition`.
- `ToyFlightSimulator Shared/Display/Protocols/ShadowRendering.swift` — `shadowMaps` is now a `texture2DArray`; `shadowRenderPassDescriptors` is an array of N descriptors with `depthAttachment.slice = i`; three encode functions iterate over cascades and bind the per-pass cascade VP at `TFSBufferIndexShadowCascadeVP`.
- All renderers conforming to `ShadowRendering` (`TiledDeferredRenderer`, `TiledMultisampleRenderer`, `TiledMSAATessellatedRenderer`, `SinglePassDeferredLightingRenderer`) — switched to the array-allocating helpers and the renamed property.

---

## Minimal change set for a clean re-implementation

For a future Claude implementing CSM in a fresh branch off `main`, this section consolidates everything we learned into the smallest correct change set. **Do not also bring along** the contents of `IN_PROGRESS_csm_swimming_and_progressive_blockiness.md`, `csm_select_cascade_drift.md`, this file, or any of the debug screenshots — they're useful as a record but they pollute the branch history. Reference them in the PR description if you want, but don't carry the docs forward.

The minimal correct change set follows the *structure* of [`plans/claude/cascaded_shadow_maps.md`](../../plans/claude/cascaded_shadow_maps.md) but supersedes its implementation details where the journey found them wrong. Read the plan for the macro architecture (sections 1–17), then apply the corrections below.

### 1. Cascade-fitting math (`Shadows/ShadowCascadeFitting.swift`)

- **Use bounding-sphere fit, not AABB-of-corners fit.** The plan's section 2 describes AABB; replace it with sphere fit:
  ```swift
  static func boundingSphereForSlice(cameraInverse: float4x4,
                                     fovYRadians: Float,
                                     aspect: Float,
                                     sliceNear: Float,
                                     sliceFar: Float) -> (centerWorld: float3, radius: Float) {
      let midZ = (sliceNear + sliceFar) * 0.5
      let halfRangeZ = (sliceFar - sliceNear) * 0.5
      let tanHalfFov = tanf(fovYRadians * 0.5)
      let farHalfH = sliceFar * tanHalfFov
      let farHalfW = farHalfH * aspect
      let radiusView = sqrtf(halfRangeZ * halfRangeZ
                           + farHalfH * farHalfH
                           + farHalfW * farHalfW)
      // Camera may be parented to a scaled node — keep radius in world units.
      let cameraScale = simd_length(simd_float3(cameraInverse.columns.0.x,
                                                cameraInverse.columns.0.y,
                                                cameraInverse.columns.0.z))
      let radius = radiusView * cameraScale
      let centerWorld4 = cameraInverse * float4(0, 0, midZ, 1)
      return (float3(centerWorld4.x, centerWorld4.y, centerWorld4.z), radius)
  }
  ```
  The sphere's radius depends only on FOV/aspect/near/far so it's invariant under camera rotation — required for texel-snap stability.

- **Snap in world space, not light-view space.** Compute the light-view basis (`xWorld`, `yWorld`, `zWorld`) from `lightDirection` *first*, then project `sphereCenter` onto `xWorld` and `yWorld`, snap those projections to `texelSize` multiples, and shift `sphereCenter` in world space before building `lightView`:
  ```swift
  let texelSize = (2 * radius) / Float(shadowMapResolution)
  let centerProjX = simd_dot(xWorld, sphereCenter)
  let centerProjY = simd_dot(yWorld, sphereCenter)
  let snappedProjX = floor(centerProjX / texelSize) * texelSize
  let snappedProjY = floor(centerProjY / texelSize) * texelSize
  let shiftWorld = (snappedProjX - centerProjX) * xWorld
                 + (snappedProjY - centerProjY) * yWorld
  let snappedSphereCenter = sphereCenter + shiftWorld
  let lightView = Transform.look(eye: snappedSphereCenter + lightDirection,
                                 target: snappedSphereCenter, up: Y_AXIS)
  ```

- **Use additive z-padding in world units (`zPaddingWorldUnits: Float = 100`), not the multiplicative 10× factor in the plan.** The multiplicative form blows up the depth range when the AABB straddles `0` in light-view z. Additive padding is bounded and predictable.

- **In Transform.look's degenerate "sun straight up" case** (where `cross(Y_AXIS, zWorld)` collapses to zero), fall back to world `+X` for the light's x-axis. The plan glosses over this.

### 2. `ShadowCamera` value type (`Shadows/ShadowCamera.swift`)

Keep the plan's two initializers (legacy `(direction:focus:radius:lift:)` for the single-cascade fast path, plus the cascade-fit `(lightView:orthoMinX/MaxX/MinY/MaxY/NearZ/FarZ)`). Add `depthRange: Float` as a stored `let` populated by both — used by the shader to derive the NDC depth-compare epsilon.

### 3. `LightObject` cascade refresh (`GameObjects/LightObject.swift`)

- **Add `_shadowMaxDistance: Float = 500` and pass `min(cam.far, _shadowMaxDistance)` to `fitCascades`** as the cascade-fitting far. The plan uses `cam.far` directly; flight-sim cameras with 1M-unit far planes destroy this.

- **After `fitCascades` returns, multiply each cascade's `splitFar` by `cameraScale`** before writing into `lightData.cascadeSplitDepths`. The shader compares per-fragment `viewSpaceDepth` (in world units, from the fragment-shader recomputation — see #5 below) against these splits, so the splits must be in world units too.
  ```swift
  let cameraScale = simd_length(simd_float3(cam.viewMatrix.inverse.columns.0.x,
                                            cam.viewMatrix.inverse.columns.0.y,
                                            cam.viewMatrix.inverse.columns.0.z))
  let splitDepths: [Float] = cascades.map { $0.splitFar * cameraScale }
  ```
  Apply the same `* cameraScale` to `cam.far` in the single-cascade fast path.

- **Default `_cascadeCount = 4`, `_shadowMapRes = 4096`** (plan suggests 2048; 4096 trades 256 MB total memory for visibly sharper shadows at the cost the pre-CSM single 8192² already paid).

### 4. `SceneConstants` binding (`Scenes/GameScene.swift`)

Bind `SceneConstants` to both vertex *and* fragment shaders:
```swift
func setSceneConstants(with renderEncoder: MTLRenderCommandEncoder) {
    renderEncoder.setVertexBytes(&_sceneConstants, length: SceneConstants.stride,
                                 index: TFSBufferIndexSceneConstants.index)
    renderEncoder.setFragmentBytes(&_sceneConstants, length: SceneConstants.stride,
                                   index: TFSBufferIndexSceneConstants.index)
}
```
Fragment shaders need `cameraPosition` for per-fragment `viewSpaceDepth` recomputation.

### 5. Vertex shaders that write `viewSpaceDepth`

**Do NOT write `viewSpaceDepth = fabs(eyePosition.z)`** (the plan's recommendation). This is broken in two ways for huge meshes that span the near plane:
1. The `fabs` loses sign; mixed-sign-clip.w vertices collapse perspective-correct interpolation to a near-constant value.
2. Even with signed `eye.z`, `view * worldPos` at world coords ~22K suffers catastrophic cancellation in float32.

**Do NOT write `viewSpaceDepth = distance(worldXYZ, cameraPosition)` either** — `distance` is non-linear in eye space, so the rasterizer's perspective-correct interpolation produces a value that doesn't track the camera as the geometry moves through clipping.

Instead, **don't write a meaningful value at the vertex level at all** (write zero, or remove the field from `VertexOut` if you're willing to touch every consumer):
```metal
// In every vertex shader that produces VertexOut for the GBuffer/transparency:
.viewSpaceDepth = 0.0,  // intentionally unused; fragment recomputes from worldPosition.
```

### 6. Fragment shaders that consume `viewSpaceDepth`

Recompute it per-fragment from the (perspective-correctly-interpolated) `worldPosition`:
```metal
fragment GBufferOut
tiled_deferred_gbuffer_fragment(VertexOut                          in              [[ stage_in ]],
                                constant SceneConstants            &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
                                /* ... */) {
    float fragViewSpaceDepth = distance(in.worldPosition, sceneConstants.cameraPosition);
    color.a = Lighting::CalculateShadow(in.worldPosition,
                                        fragViewSpaceDepth,
                                        in.worldNormal,
                                        lightData, shadowArray);
    /* ... */
}
```
This applies to **every** GBuffer fragment shader that calls `CalculateShadow` / `CalculateShadowMSAA`:
- `TiledDeferredGBuffer.metal::tiled_deferred_gbuffer_fragment`
- `TiledMSAAGBuffer.metal::tiled_msaa_gbuffer_fragment`
- `GBuffer.metal::gbuffer_fragment_base`
- `GBuffer.metal::gbuffer_fragment_material`

**Why this is correct**: `worldPosition` is linear in eye space (it's `view⁻¹ · eyePos` where `view⁻¹` is affine), so the rasterizer interpolates it correctly even for triangles spanning the near plane. The per-fragment subtraction `worldPos - cameraPos` is Sterbenz-exact in float32 for visible fragments (they satisfy `|a/2| ≤ b ≤ 2a` trivially). `length` of the small relative vector is well-conditioned.

### 7. `Lighting.metal::CalculateShadow`

Use the plan's cascade-aware structure but with these specifics:

- **Slope-scaled world-space bias** in the depth-compare epsilon:
  ```metal
  static float SlopeScaledWorldBias(float baseSlack, float3 normal, float3 lightDir) {
      float nDotL = saturate(dot(normalize(normal), lightDir));
      float slope = 1.0 - nDotL;
      constexpr float SLOPE_BIAS_FACTOR = 20.0;
      return baseSlack * (1.0 + slope * SLOPE_BIAS_FACTOR);
  }
  ```

- **3×3 hardware-PCF kernel** (9 calls to `sample_compare` with `filter::linear`):
  ```metal
  constexpr sampler pcfSampler(coord::normalized, filter::linear,
                               address::clamp_to_edge, compare_func::less);
  float invW = 1.0 / float(shadowArray.get_width());
  float invH = 1.0 / float(shadowArray.get_height());
  float litSum = 0.0;
  for (int dy = -1; dy <= 1; ++dy) {
      for (int dx = -1; dx <= 1; ++dx) {
          float2 offset = float2(float(dx) * invW, float(dy) * invH);
          litSum += shadowArray.sample_compare(pcfSampler, xy + offset, cascadeIdx, refZ);
      }
  }
  return 0.5 + 0.5 * (litSum * (1.0 / 9.0));
  ```

- **`SelectCascade` falls back to the last cascade**, not cascade 0:
  ```metal
  static uint SelectCascade(constant LightData &light, float viewSpaceDepth) {
      for (uint i = 0; i < light.cascadeCount; ++i) {
          if (viewSpaceDepth < light.cascadeSplitDepths[i]) return i;
      }
      return light.cascadeCount > 0 ? light.cascadeCount - 1 : 0;
  }
  ```

- **Cascade fallthrough**: if the selected cascade's UV is outside `[0, 1]` or its `position.z` is outside `[0, 1]`, try the next cascade up before returning fully-lit. Texel snap can shift fragments slightly outside the depth-selected cascade's XY box.

### 8. `ShadowRendering` protocol (`Display/Protocols/ShadowRendering.swift`)

Follow the plan's section 5 structure. Two corrections:

- **`ShadowMapSize = 4_096`** (plan uses 2048).
- **Don't set `setDepthBias` during the shadow gen pass.** The plan's section 5 sets `setDepthBias(0.1, slopeScale: 1, clamp: 0.0)` but for cascade orthos that are 600 world units wide, the slope-scaled bias peter-pans aircraft shadows visibly off the ground. The shader-side per-cascade slope-scaled epsilon handles bias correctly without depth bias on the rasterizer.

### 9. Defaults that work for the existing scenes

These configuration values are tuned for `FlightboxWithPhysics` (the default scene). They can be overridden per-scene but the defaults should be:

| Property | Default | Why |
|---|---|---|
| `_cascadeCount` | 4 | PSSM sweet spot for this scene scale |
| `_cascadeLambda` | 0.5 | Standard Microsoft PSSM hybrid blend |
| `_shadowMapRes` | 4096 | Same memory as pre-CSM 8192² single map |
| `_cascadeZPad` | 100 (world units, **additive**) | Avoids the multiplicative-padding blow-up |
| `_shadowMaxDistance` | 500 | Decouples shadow reach from camera far plane |
| `_baseWorldSlack` | 0.25 | Per-cascade scaled by `orthoHalfExtentX / cascade0_radius` |

`LightObject._shadowMapRes` and `ShadowRendering.ShadowMapSize` must be kept in sync — the former drives texel-snap math, the latter allocates the texture.

### 10. Final checklist for the clean implementation

Before merging the clean branch:

- [ ] Build for macOS Debug. Run.
- [ ] At spawn, F-22 has a visible cast shadow on the ground with sharp silhouette detail (rudders, wings).
- [ ] Fly to `cam_world ≈ (10K, 5.9, 22K)` (or further). Confirm:
   - F-22 self-shadow stays crisp (no fuzzy cross-blob).
   - F-22 cast-shadow on ground stays sharp.
   - Shadow edges on static geometry (spheres, cubes) don't visibly swim during steady flight.
- [ ] Land near the ground (low altitude). Confirm ground shadows don't degrade at oblique viewing angles (cascade selection should still be correct).
- [ ] Switch the renderer through the macOS menu to each of TiledDeferred / TiledMultisample / TiledMSAATessellated / SinglePassDeferredLighting. Confirm shadows render correctly in each.
- [ ] No console errors, no validation layer complaints.

If all of the above pass, the clean implementation matches the working state of the `csm1` branch at the end of this debugging journey.

---

## What's still imperfect (acceptable for shipping, but room for improvement)

The user described the final state as "shadows look far better now, though there is still room for fine tuning and a little improvement." Items not addressed in this session:

- **Cascade-boundary visible seams**: when cascade 0 ends and cascade 1 begins, the texel-resolution change is visible. Could be smoothed via cascade-blending in `Lighting.metal::CalculateShadow` (blend between cascade i and i+1 in the last 10% of cascade i's range).
- **PCF kernel size at oblique angles**: 3×3 hardware PCF works well from above but produces blockier soft edges when the camera is at ground level looking forward. Could widen to 5×5 or switch to Poisson-disk sampling.
- **Per-cascade resolution tuning**: cascade 0 at 4096² is sharper than necessary for most viewing situations; cascade 3 at 4096² is wasted on lower-detail-needed far-field. A per-cascade resolution mapping could halve memory without visual loss.
- **Animated F-22 control surfaces**: per-frame vertex displacements on the F-22 cause sub-pixel shadow-map edge motion. The eye picks this up as residual "swimming" during steady flight. Listed as hypothesis (A) in `IN_PROGRESS_csm_swimming_and_progressive_blockiness.md`; not addressed in this session. Easy test: freeze the F-22 animator and see if residual swim disappears.

None of these block shipping CSM as a major upgrade over the single-cascade sun-follow path. They're polish, not correctness.
