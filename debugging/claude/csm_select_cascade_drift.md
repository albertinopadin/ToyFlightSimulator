# CSM `SelectCascade` Drift at Large World Coordinates — Root-Cause Investigation

**Status**: FIXED. Root cause: per-vertex `viewSpaceDepth` is non-linear in eye space, so the rasterizer can't interpolate it correctly across triangles that span the near plane (the ground quad at large world coords). Fix: recompute `viewSpaceDepth` in the fragment shader from the already-perspective-correctly-interpolated `worldPosition`. Two iterations of D1 narrowed down the precise mechanism — see "How the fix landed" at the bottom.
**Branch**: `csm1`
**Prior context**: [`IN_PROGRESS_csm_swimming_and_progressive_blockiness.md`](IN_PROGRESS_csm_swimming_and_progressive_blockiness.md)
**User's narrowing**: replacing `SelectCascade`'s body with `return 0;` eliminates progressive blockiness on the focused jet, so the bug is in cascade selection — either `viewSpaceDepth` or `cascadeSplitDepths` is wrong.

**D1 outcome (2026-05-21)**: confirmed `viewSpaceDepth` is the broken quantity, but with a critical refinement: **the F-22's own vertices stay correct (dim red everywhere on the jet at any distance from origin); it is the GROUND's per-fragment `viewSpaceDepth` that progressively over-reports** as the player flies away from origin. At spawn the ground shows the expected dim-to-bright gradient (close-to-camera fragments dim, horizon fragments bright). At `cam_world ≈ (10K, ?, 22K)` the entire ground saturates to bright red — meaning even ground fragments directly under the camera report `viewSpaceDepth` >100, pushing them out of cascade 0. F-22-self-shadow looks fine (rudder shadows etc.) because the F-22 vertices are at view-space depth ~9 with uniform sign; F-22-shadow-cast-onto-ground gets blocky because the ground samples wrong cascades for those fragments. See `debugging/screenshots/RedVSD_Start.png` and `debugging/screenshots/RedVSD_End.png` for the visual evidence.

**Why the ground specifically breaks** (refinement to the precision story): the ground is a single Quad at scale 1,000,000 with corners at world `(±500K, 0, ±500K)`. From any camera position inside that XZ extent, two of the four corners are **behind the camera** (negative eye-space z) and two are **in front** (positive eye-space z). `viewSpaceDepth = fabs(eyePosition.z)` writes ~200K *positive* at all four corners, losing the sign. The rasterizer then has to homogeneous-clip the triangle against the near plane and interpolate user attributes perspective-correctly across vertices with mixed-sign `clip.w`. In float32 this is a delicate cancellation — `A_i/clip.w_i = ±1` depending on sign, and the perspective-correct fragment value `(Σαᵢ·sign_i) / (Σαᵢ/clip.w_i)` is `~165K / 165K · sign factor` which collapses to roughly the magnitude of `clip.w_i` — i.e., the rasterizer outputs `viewSpaceDepth ≈ 200K` for *every* visible ground fragment regardless of its actual depth. At spawn the camera-world magnitudes are tiny (~100), the precision pool of the cancellation is large enough that the rasterizer still recovers a usable gradient. At the far position the camera-world magnitudes are ~24K, the float32 noise in the interpolated `1/w` swamps the legitimate depth signal, and the ground saturates. The F-22 doesn't have this problem because all its vertices have positive `clip.w` with similar magnitudes (~9, no near-plane crossing inside the mesh).

## TL;DR of the investigation

`cascadeSplitDepths` is **stable**: the user's own debug log shows the same `62.6, 126.1, 204.2, 500.0` values every frame regardless of camera position (`LightObject.swift:280-285`). The PSSM computation only depends on `cam.near` / `cam.far` / `_shadowMaxDistance` / `_cascadeLambda` — none of which depend on the camera's world position. **The splits cannot be the bug.**

That leaves **`viewSpaceDepth`** — produced per-vertex in `tiled_deferred_gbuffer_vertex` / `_animated_vertex` (`TiledDeferredGBuffer.metal:24-36, 71-81`) as `fabs((sceneConstants.viewMatrix * worldPosition).z)`. For a vertex that should be at view-space depth ~9 (the F-22 self-shadow case, see math below), this can drift far enough at large world coords to flip the loop in `SelectCascade` (`Lighting.metal:111-120`) past one or more thresholds.

The leading root cause is **catastrophic cancellation in `view * worldPos` when both `view`'s translation column and `worldPos` are large**. The fix is to compute view-space depth in a **camera-relative** form that does the cancellation in source-of-truth world coordinates *before* the matrix multiply destroys precision. Implementation sketch and diagnostics below.

## Why F-22 fragments *should* always be in cascade 0

Setup (FlightboxWithPhysics + F22_CGTrader):
- `AttachedCamera(fov: 75°, near: 0.01, far: 1_000_000)` parented to F-22 (`FlightboxWithPhysics.swift:17-19, 104-105`).
- F-22 `setScale(3.0)` (`FlightboxWithPhysics.swift:97`). Camera localOffset `[0, 3, -9]` (`F22_CGTrader.swift:11-13`).
- Camera's `modelMatrix = F22.modelMatrix * camera.localMatrix` bakes the F-22's scale-3 into the camera (Node's lazy `modelMatrix` getter at `Node.swift:35-43`, AttachedCamera's `updateModelMatrix` override at `AttachedCamera.swift:34-38`).
- Therefore `camera.viewMatrix = camera.modelMatrix.inverse` has scale **1/3** baked in. All "view-space" magnitudes are 1/3 of world.

Cascade split units (`LightObject.swift:188-203`):
```swift
let shadowFar = min(cam.far, _shadowMaxDistance)            // 500
let cascades = ShadowCascadeFitting.fitCascades(
    cameraNear: cam.near,      // 0.01
    cameraFar: shadowFar,      // 500
    ...
)
```
`computeSplitDepths(near: 0.01, far: 500, count: 4, lambda: 0.5)` produces `[62.6, 126.1, 204.2, 500.0]` (`ShadowCascadeFitting.swift:111-128`). These are **in the same units as `cam.near`/`cam.far`** — i.e., **scaled-view-space units (1/3 of world)**.

Fragment view-space depth (the matching unit):
- F-22 origin in view space: `camera.viewMatrix * F22_world = -R_camera^T * (3 * cameraOffset) / 3 = -R_camera^T * cameraOffset`.
- For offset `(0, 3, -9)` plus the camera's tiny -5° initial pitch, this resolves to about `(0, ~-3, ~9)`.
- **View-space depth ≈ 9** — well under cascade 0's split at 62.6.
- This calculation is **invariant** to the F-22's world translation: `worldPos − cam_world` is the same relative vector wherever the F-22 is in the world.

So in principle, the F-22 and all ground fragments within a few meters of it should *always* land in cascade 0, regardless of `(F22_world, cam_world)` magnitude.

## Why the *invariant* result is not what the GPU computes

The vertex shader doesn't compute `R_camera^T * (worldPos − cam_world) / 3` directly. It computes:

```metal
float4 eyePosition = sceneConstants.viewMatrix * worldPosition;
viewSpaceDepth     = fabs(eyePosition.z);
```

For the scale-3 attached camera, `sceneConstants.viewMatrix.row2` looks like:
- `view[0][2] = R[0,2] / 3 ≈ 0.093`
- `view[1][2] = R[1,2] / 3 ≈ 0.021`
- `view[2][2] = R[2,2] / 3 ≈ 0.320`
- `view[3][2] = −(1/3) · R.col2 · cam_world` — at `cam_world ≈ (10162, 5.9, 22236)` this is **≈ −8050**.

For an F-22 wingtip vertex at `worldPos ≈ (10185, 7.7, 22263, 1)`:

```
eyePos.z = 0.093 · 10185
         + 0.021 ·   7.7
         + 0.320 · 22263
         + (−8050)
         =   944.2  +  0.16  +  7117.3  +  (−8050.0)
         =  8061.66 − 8050   ≈ 11.6
```

This is **massive catastrophic cancellation**: a ~10-unit result is the difference of two ~8050-unit positives and negatives. Every term carries a relative error from one or more of:

1. **`simd_inverse(modelMatrix)` precision** — the upper-left 3x3 of `view` is `S(1/3)·R^T`. `simd_inverse` is a general-purpose float4x4 inverter; it doesn't know the input is TRS. With `col3` at magnitude ~22000 and the upper-left 3x3 at magnitude ~3, the cofactor expansion produces intermediate products at magnitude ~200,000. Each such intermediate has ulp(200k) ≈ 0.024 absolute error; dividing by `det = 27` gives the `view` rotation entries an absolute precision floor of about **0.001** (relative ≈ 0.003, i.e. 0.3% of the ~0.333 entry value).
2. **`view * worldPos` term precision** — `0.333 ± 0.001` times `22000 ± 0.003` gives a per-term absolute error ≈ `22000 · 0.001 = 22`. Four terms summed with independent errors compounds to ~40 absolute error on `eyePos.z`.
3. **`view[3][2]` storage** — `−(1/3) · R.col2 · cam_world` is stored as a single float32. At magnitude ~8050, ulp ≈ 0.001 absolute, but the *computation* that produced it (a 3-term dot of ~7000-magnitude products on the CPU) carries another ~0.001-0.005 absolute error.

The end result: at `cam_world ≈ (10000, 5.9, 22000)`, the GPU's `eyePos.z` for an F-22 fragment is *approximately* `9.5 ± 40` rather than the analytic `9.5`. The huge cancellation means the relative error in `eyePos.z` is on the order of **the absolute precision of the inputs divided by ~10**, not divided by ~8000.

### Why the symptom is *progressive*

The cancellation error scales **linearly** with `|cam_world|` because `view[3][2]` and the matrix-vector products both grow linearly:

| `|cam_world|` (≈) | `view[3][2]` magnitude | Per-term abs error | Total `eyePos.z` error |
|------------------:|----------------------:|--------------------:|------------------------:|
|              100  |                  ~33  |              ~0.0001 |                 ~0.0002 |
|            1,000  |                 ~330  |              ~0.0007 |                  ~0.001 |
|           22,000  |                ~8050  |                 ~22 |                     ~44 |
|          100,000  |              ~36,000  |                ~100 |                    ~200 |
|        1,000,000  |             ~360,000  |               ~1000 |                   ~2000 |

At spawn (`cam_world ≈ (0, 109, -27)`, magnitude ~112), error is ~0.0002 — invisible.

At the user's screenshot 4 (`cam_world ≈ (10000, 5.9, 22000)`, magnitude ~24K), error is ~44 absolute, with `viewSpaceDepth = 9.5 ± 44`. That tail crosses cascade boundaries 62.6 (cascade 0→1), 126.1 (1→2), and 204.2 (2→3) for a *small but visible fraction* of F-22 / shadow fragments. Those fragments sample low-resolution cascades, producing the **"fuzzy cross-shaped blob"** the user describes.

At even larger world coords (sustained flight beyond ~30K from origin), more fragments cross boundaries until effectively no fragment lands consistently in cascade 0 — and the shadow becomes the *aggregate* low-res blob.

This matches the user's observation that the symptom *progressively worsens* with distance from the world origin.

### Why forcing `return 0` "fixes" it

Setting `SelectCascade` to `return 0` bypasses the bad `viewSpaceDepth` entirely; the F-22 always samples its sharp cascade-0 silhouette. Cascade 0's VP matrix is still computed correctly (`ShadowCascadeFitting` uses well-conditioned `Transform.look` math, and the texel snap also works because `sphereCenter` arithmetic isn't catastrophically subtractive — it's *constructive*: `cam_world + forward * midZ * scale`).

So the cascade 0 *shadow map* contains the F-22 silhouette correctly. It's only the *per-fragment selection* that's broken.

## Diagnostics to confirm (in priority order)

### D1. Output `viewSpaceDepth` as a fragment color

In `tiled_msaa_gbuffer_fragment` (`TiledMSAAGBuffer.metal:40-44`), temporarily replace the shadow sample with a debug colorization:

```metal
// Visualize viewSpaceDepth as red intensity. Red = depth/100; full red at 100.
color.rgb = float3(min(in.viewSpaceDepth / 100.0, 1.0), 0.0, 0.0);
color.a = 1.0;
```

Then fly the F-22:
- **At spawn**: F-22 fragments should be barely-pink (depth ~9 → red ≈ 0.09). All fragments roughly the same.
- **At `cam_world ≈ (10000, 5.9, 22000)`**: if hypothesis is correct, F-22 fragments will *flicker* between depths ~5 and ~50+. Some bright red, some dark red, varying frame-to-frame. **Crucially**, fragments whose red exceeds 0.626 (= 62.6/100) are misselected to cascade 1+.

If the F-22's depth-color *stays uniformly ~0.09* across the flight, then `viewSpaceDepth` is fine and my hypothesis is wrong — the bug is elsewhere (see "alternate hypotheses" below).

### D2. Bracket which cascade is being selected per pixel

Replace the same shadow-sample call with a per-cascade color tag:

```metal
uint c = Lighting::SelectCascade(lightData, in.viewSpaceDepth);
float3 cols[4] = {
    float3(1, 0, 0),   // cascade 0 → red
    float3(0, 1, 0),   // cascade 1 → green
    float3(0, 0, 1),   // cascade 2 → blue
    float3(1, 1, 0),   // cascade 3 → yellow
};
color.rgb = cols[clamp(c, 0u, 3u)];
color.a = 1.0;
```

(You'll need to make `SelectCascade` public — currently `static` in the `Lighting` class. Move it out of the class or expose a wrapper.)

Expected behavior:
- **At spawn**: F-22 fragments all red (cascade 0).
- **At `cam_world ≈ (10000, ?, 22000)`**: if hypothesis is correct, F-22 fragments show a *checkerboard* of red + green + blue + yellow — different fragments selecting different cascades because their per-vertex `eyePos.z` has independent precision noise after interpolation.

### D3. CPU-side cross-check of `view * F22_world`

In `LightObject.debugLogCascades` (`LightObject.swift:240-285`), add the same `view * F22_world` calculation that the vertex shader performs, but in Swift (which uses double precision in `simd` for intermediate operations in some cases):

```swift
// At the bottom of debugLogCascades:
// Pick a stable point near the F-22. If you can grab the F-22's
// actual model matrix here, use its col3; otherwise probe the
// camera-relative point that should be view-space-depth 9.
let probeWorld = camPosWorld.xyz + float3(0, 0, 9) * 3  // arbitrary in front of cam
let probeView  = cameraView * float4(probeWorld, 1)
print("[CSM Debug]  probe world-z=9*scale → view.z = \(probeView.z) (expect ~9)")
```

If `probeView.z` is *exactly* 9 at all camera positions, the CPU's `cameraView` is fine and the precision loss must be happening in the GPU's vertex shader (because the GPU uses pure float32; SIMD on CPU may use higher precision internally). If `probeView.z` already drifts at large `cam_world`, the matrix itself is corrupted by `simd_inverse` precision.

### D4. Compare cascade-VP precision across positions

In `LightObject.debugLogCascades`, log `cascadeViewProjectionMatrices[0].columns.3` (the translation column of cascade 0's VP). For a fixed-distance F-22 probe (e.g., a fragment 9 view-space units in front of the camera), `cascade0VP * probeWorld` should yield NDC `(0, 0, ~0.5)` regardless of `cam_world`. If the NDC z drifts as `cam_world` grows, then the cascade-VP itself has precision issues (a different but related problem).

## Proposed fix: camera-relative `viewSpaceDepth`

The minimal, surgical fix is to compute `viewSpaceDepth` in a form that performs the **subtraction-of-similar-magnitudes** *before* the matrix multiply destroys precision. The vertex shader already has `worldPosition` and the scene constants have `cameraPosition`. Replace `fabs(eyePosition.z)` with a camera-relative scalar projection:

### Vertex shader change (`TiledDeferredGBuffer.metal:36, 81` + `GBuffer.metal:58` + others)

The shader is `tiled_deferred_gbuffer_vertex` and its `_animated_vertex` sibling. The user's actual renderer is **`TiledDeferred`** (not MSAA — `tiled_deferred_gbuffer_fragment` confirmed by them as the active fragment shader during D1). The same vertex shader (`tiled_deferred_gbuffer_vertex`) feeds both the non-MSAA `tiled_deferred_gbuffer_fragment` and the MSAA `tiled_msaa_gbuffer_fragment`, so a single change to the vertex shader covers both renderer paths.

**Option A — world-units viewSpaceDepth (recommended)**

Compute the distance in world units, and change cascade splits to be in world units too:

```metal
// In every vertex shader that writes viewSpaceDepth — at least:
//   TiledDeferredGBuffer.metal:36, 81
//   TiledDeferredTransparency.metal:32
//   SinglePassDeferredTransparency.metal:30
//   GBuffer.metal:58
.viewSpaceDepth = distance(worldPosition.xyz, sceneConstants.cameraPosition),
```

`distance` computes `length(a - b)`. The subtraction `worldPosition - cameraPosition` cancels the large-magnitude parts at *full input precision* (because both operands have the same precision — `worldPosition` is `modelMatrix * vertex` and `cameraPosition` is a SceneConstants float3 with the same float32 storage). The resulting small vector has full ulp-of-result precision. `length` on a small vector is well-conditioned.

Then on the CPU side, in `LightObject.updateShadowCascades`:

```swift
// LightObject.swift, around line 190:
let cameraScale = simd_length(simd_float3(cam.viewMatrix.inverse.columns.0.x,
                                          cam.viewMatrix.inverse.columns.0.y,
                                          cam.viewMatrix.inverse.columns.0.z))
let worldShadowFar = min(cam.far, _shadowMaxDistance) * cameraScale
let cascades = ShadowCascadeFitting.fitCascades(
    cameraView: cam.viewMatrix,
    cameraFovYRadians: cam.fieldOfView.toRadians,
    cameraAspect: aspect,
    cameraNear: cam.near * cameraScale,           // world units
    cameraFar: worldShadowFar,                    // world units
    ...
)
```

**Important**: `ShadowCascadeFitting.boundingSphereForSlice` *already* multiplies the radius by `cameraScale` to keep its output in world units (`ShadowCascadeFitting.swift:178-181`). With this change, the slice `near`/`far` inputs that drive `computeSplitDepths` will also be in world units, so the returned `splitFar` values (which become `cascadeSplitDepths`) are already in world units — matching the new `viewSpaceDepth`. The `boundingSphereForSlice` math becomes simpler (no implicit unit conversion) but its output is unchanged.

This is a **two-line conceptual change** with a small unit conversion. No matrix math change. No new shader buffer bindings.

**Option B — keep view-space units, but compute precisely**

If you want to avoid changing the unit convention, you can still avoid the cancellation:

```metal
// Vertex shader. Requires camera forward direction as a scene constant.
float3 rel        = worldPosition.xyz - sceneConstants.cameraPosition;
float  worldDepth = dot(rel, sceneConstants.cameraForwardWorld);
.viewSpaceDepth   = fabs(worldDepth) / sceneConstants.cameraScale;
```

This needs two new fields in `SceneConstants`:
```c
typedef struct {
    ...
    simd_float3 cameraForwardWorld;   // unit vector
    float       cameraScale;          // 3 for the F-22 scene
    ...
} SceneConstants;
```

Both fields are derivable from `camera.modelMatrix` (`col2.xyz / cameraScale`, length of `col0.xyz`) so the Swift side just fills them in `GameScene.update()` (`GameScene.swift:158-170`).

Option B keeps cascadeSplitDepths in view-space units (no CPU change), but adds two scene constants. **Option A is cleaner** (one unit convention everywhere).

### Why this fix is bulletproof

`worldPosition - cameraPosition` is the *only* operation in the data flow that can cancel large magnitudes — and in a single-precision IEEE-754 subtraction `a - b` where `a` and `b` differ only in their low bits, **the result is exact** ([Sterbenz's lemma](https://en.wikipedia.org/wiki/Loss_of_significance#Sterbenz's_lemma): if `|a/2| ≤ b ≤ 2a`, then `a - b` is computed exactly in floating point). The F-22's vertex worldPosition and the cameraPosition are within `cameraScale * cameraOffset ≈ 28.5` world units of each other but at world magnitude `~22000`, so they trivially satisfy Sterbenz. The subtraction is exact; `length` of the resulting small vector is well-conditioned; no precision is lost.

By contrast, the current `view * worldPos` does the subtraction *implicitly* via the matrix's `view[3][:]` column (which is `−R^T · cam_world / scale`, computed on the CPU and stored at limited precision) added to the row-by-column dot products (also limited precision). The cancellation happens at limited precision; ~22 absolute error per term is the result, as shown in the table above.

## Alternate hypotheses (in case D1/D2 don't confirm the precision story)

If the diagnostic D1 shows `viewSpaceDepth` is *uniformly* ~9 across world positions (no drift), then the precision hypothesis is wrong. Other possibilities to check:

### H1. F-22 model has a stray submesh at a huge local offset

If the F22_CGTrader USDZ model has any submesh (rudder, weapon, child joint) with bind-pose vertex coordinates far from the F-22 origin (e.g., a "weapon attachment point" at local `(0, 0, 100)`), after `setScale(3.0)` that's 300 world units of offset. View-space depth for that submesh would be ~100, crossing the cascade 0→1 boundary.

But: this would be **constant**, not progressive. The user reports progressive degradation, so this is unlikely to be primary cause — but a per-cascade D2 colorization would expose it if any submeshes show a consistent non-red color regardless of world position.

To check: in `tiled_deferred_gbuffer_animated_vertex` (`TiledDeferredGBuffer.metal:45-87`), log the magnitude of `position.xyz` (post-joint-skin) for the F-22:

```metal
// Temporarily route the local-space magnitude through unused field:
.objectColor = float4(length(position.xyz), 0, 0, 1),
```

Then read this via the fragment shader and visualize. If any F-22 mesh has post-skin `|position|` > 30 (anything beyond ±10 local meaning ±30 world after scale), that submesh is a separate problem.

### H2. Skin-palette joint matrix drift

`Skeleton.evaluateWorldPoses` (`Skeleton.swift:143-173`) computes joint world matrices iteratively via `worldPose[parentIdx] * localMatrix`. The bind-transform conjugation at the bottom multiplies by `bindTransforms[index].inverse`. If `bindTransforms` is not pure rotation (e.g., bind-pose includes a non-unity scale that the `inverse` doesn't perfectly cancel), the resulting palette matrices can have a small scale drift.

But: this would also be **constant** with respect to world position. Rule it out via the F-22-only D1: if a *stationary* F-22 has fragments at varying `viewSpaceDepth`, this is the cause.

### H3. `sceneConstants.viewMatrix` race / staleness

Within a frame, `_sceneConstants.viewMatrix` is set in `GameScene.update()` (`GameScene.swift:161`) AFTER scene-graph traversal updates `camera.viewMatrix`. The render thread reads `_sceneConstants` via `setVertexBytes` (a byte-copy) before encoding. The update→render handshake (per CLAUDE.md "Frame pacing") guarantees the update has finished before the encoder reads. So `_sceneConstants.viewMatrix` and `lightData.cascadeViewProjectionMatrices` should always be from the same update tick. No race.

But if D3 (above) shows the *CPU* `cameraView * probeWorld` already drifts, this is moot — the problem is in `simd_inverse` precision, not in synchronization.

## What I deliberately did NOT recommend

- **VSM / ESM / soft-shadow filtering**: orthogonal to the cascade-selection bug. Even with VSM, picking the wrong cascade still samples low-resolution data.
- **Adding more PCF taps**: already at 3x3 (effective 36-tap via hw bilinear). Wider kernels would smooth the per-cascade output but wouldn't fix the *wrong-cascade-being-sampled* issue.
- **Hard-coding `return 0` in `SelectCascade`**: works for the F-22 self-shadow case but breaks cascades for *anything else* — the cascades exist for a reason (distant ground and far objects need lower-res maps to fit in their slice). Not a fix, only a diagnostic confirmation.
- **Bumping shadow resolution**: doesn't help if the per-fragment cascade selection is wrong. The cascade-3 shadow map at 8192² would still have the F-22 silhouette as 50 texels, not 4096.

## Files to touch when implementing Option A

1. **`ToyFlightSimulator Shared/Graphics/Shaders/TiledDeferredGBuffer.metal`** lines 36, 81 — change `.viewSpaceDepth = fabs(eyePosition.z)` to `.viewSpaceDepth = distance(worldPosition.xyz, sceneConstants.cameraPosition)`.
2. **`ToyFlightSimulator Shared/Graphics/Shaders/TiledDeferredTransparency.metal`** line 32 — same change.
3. **`ToyFlightSimulator Shared/Graphics/Shaders/SinglePassDeferredTransparency.metal`** line 30 — same change.
4. **`ToyFlightSimulator Shared/Graphics/Shaders/GBuffer.metal`** line 58 — same change.
5. **`ToyFlightSimulator Shared/GameObjects/LightObject.swift`** lines 188-203 — multiply `cam.near` and `shadowFar` by `cameraScale` before passing to `fitCascades`.
6. **`ToyFlightSimulator Shared/Shadows/ShadowCascadeFitting.swift`** lines 178-181 — since `near`/`far` are now in world units, **remove** the implicit `* cameraScale` on `radiusView` (it's already in matching units now). Verify: `Cascade halfExtentX` in debug log should stay ~300 for cascade 0.
7. **`ToyFlightSimulator Shared/Graphics/Shaders/Lighting.metal`** — no change to `SelectCascade` itself, but the inline comments at lines 107-109 reference "view-space |z|" — update to "world-space distance from camera" for consistency.

A reasonable test cycle:
1. Apply changes.
2. Build for macOS Debug, run.
3. Verify cascade splits in the debug log still match expectations (in world units now — `splits[0]` should be ~`62.6 * 3 = 187.8`, etc.).
4. Fly the F-22 to `cam ≈ (10000, ?, 22000)` (or as far as you can quickly reach) and visually confirm the shadow stays crisp.
5. Run D2 (per-cascade colorization) at the far position to confirm all F-22 fragments tag as cascade 0 (red).

## Suggested verification before going further

Before writing any code, run **D1** and **D2** to *confirm* the cascade-selection drift is happening as predicted. If D1 shows F-22 `viewSpaceDepth` flickering between ~5 and ~50+ at large `cam_world`, the precision hypothesis is essentially proven and Option A is the right fix. If D1 shows a steady ~9 at all distances, then `viewSpaceDepth` isn't drifting — start with H1/H2 instead.

## Cross-references

- The plan that landed CSM: [`plans/claude/cascaded_shadow_maps.md`](../../plans/claude/cascaded_shadow_maps.md).
- The handoff doc with the broader swimming/blockiness picture: [`IN_PROGRESS_csm_swimming_and_progressive_blockiness.md`](IN_PROGRESS_csm_swimming_and_progressive_blockiness.md).
- The earlier scaling-related camera-relative discussion (similar precision concerns, never implemented): the in-progress doc's "Remaining hypotheses" section (E). This investigation supersedes (E) with a concrete fix.

## How the fix landed (iterative D1)

The fix took two iterations because the first attempt only addressed half the precision problem.

### Iteration 1: vertex-shader `distance(worldPos, cameraPos)` (incorrect)

I first replaced `viewSpaceDepth = fabs(eyePosition.z)` with `viewSpaceDepth = distance(worldXYZ, sceneConstants.cameraPosition)` in the GBuffer vertex shaders, plus multiplied `cascadeSplitDepths` by `cameraScale` on the CPU to keep both sides in world units.

User ran D1 with this change and reported: F-22 is now uniformly dim red (good — F-22 self-shadow precision was fixed), but the ground still has the wrong intensity — there is a faint dimmer red patch on the ground but it stays at a fixed **world** location instead of tracking the camera.

That smoking-gun observation revealed the deeper issue. `distance(worldPos, cameraPos)` is **non-linear** in eye space (it's `sqrt(Σ(worldPosᵢ − cameraPosᵢ)²)`). The rasterizer's perspective-correct interpolation produces exact per-fragment values only for attributes that are **linear** in eye space. For the huge ground quad whose vertices straddle the near plane (with the camera inside the quad's XZ extent, two corners are behind the camera), the per-vertex `distance` values are all very similar (~700K world units to either back or front corner), and the rasterizer interpolates them into a value that varies with the triangle's geometry — producing a dim patch anchored to a world-space "center" of the interpolation, not to the moving camera.

So iteration 1 fixed the **F-22 precision** (small mesh, all vertices in front of camera, interpolation behaves well) but **not the ground cancellation** (huge mesh, mixed-sign-clip.w vertices, non-linear attribute breaks under interpolation).

### Iteration 2: fragment-shader recomputation (works)

The right fix: recompute `viewSpaceDepth` in the fragment shader using the perspective-correctly-interpolated `in.worldPosition`.

```metal
// In tiled_deferred_gbuffer_fragment (and the two MSAA / legacy siblings):
float fragViewSpaceDepth = distance(in.worldPosition, sceneConstants.cameraPosition);
color.a = Lighting::CalculateShadow(in.worldPosition,
                                    fragViewSpaceDepth,
                                    in.worldNormal,
                                    lightData, shadowArray);
```

Why this works where iteration 1 didn't:

- `worldPosition` **is linear in eye space** (it's `view⁻¹ · eyePos` where `view⁻¹` is affine), so the rasterizer's perspective-correct interpolation produces the exact per-fragment world position even for triangles spanning the near plane.
- The subtraction `worldPos - cameraPos` happens **per-fragment** and is **Sterbenz-exact in float32** whenever the two are within ~2× of each other in magnitude — which is trivially true for any visible fragment (visible ⇒ in front of camera ⇒ within near/far of cameraPos).
- The small relative vector then gets `length()` applied, which is well-conditioned for small magnitudes.
- Result: every fragment sees its true world-space distance from the camera. No precision noise, no clipping-attribute-interpolation pathology, no non-linearity blowup.

User ran D1 with iteration 2 and confirmed: the dim red region of the ground tracks the camera correctly as the jet moves around the world. Both F-22 self-shadow and ground cast-shadow get their correct cascade now.

### Final file list

Shader changes (per-fragment recomputation):
- **`ToyFlightSimulator Shared/Graphics/Shaders/TiledDeferredGBuffer.metal`** — added `SceneConstants` binding to `tiled_deferred_gbuffer_fragment`, computed `fragViewSpaceDepth` per-fragment, passed to `CalculateShadow`.
- **`ToyFlightSimulator Shared/Graphics/Shaders/TiledMSAAGBuffer.metal`** — same change to `tiled_msaa_gbuffer_fragment` (for the MSAA renderer path).
- **`ToyFlightSimulator Shared/Graphics/Shaders/GBuffer.metal`** — same change to `gbuffer_fragment_base` and `gbuffer_fragment_material` (legacy renderer).

Vertex shader changes (per-vertex precision improvement, also kept):
- **`ToyFlightSimulator Shared/Graphics/Shaders/TiledDeferredGBuffer.metal`** — `viewSpaceDepth = distance(worldXYZ, sceneConstants.cameraPosition)` in both `tiled_deferred_gbuffer_vertex` and `_animated_vertex`.
- **`TiledDeferredTransparency.metal`**, **`SinglePassDeferredTransparency.metal`**, **`GBuffer.metal`** — same vertex change for consistency (the transparency paths don't sample shadows, but the field is shared via VertexOut).

CPU / Swift:
- **`ToyFlightSimulator Shared/Scenes/GameScene.swift`** — `setSceneConstants` now also calls `setFragmentBytes(&_sceneConstants, ...)` so fragment shaders can read `cameraPosition`.
- **`ToyFlightSimulator Shared/GameObjects/LightObject.swift`** — multiplies `splitFar` by `cameraScale` before writing into `cascadeSplitDepths`, both in the single-cascade fast path and the multi-cascade path. Debug log now prints world-unit splits alongside view-z splits.

### Open follow-ups

- **Disable D1 diagnostic before shipping**: the `color = float4(...red...)` override in `tiled_deferred_gbuffer_fragment` should be removed (it's already commented out in the final state, but verify before merging the branch).
- **Other render paths**: the SinglePass deferred lighting path has its own GBuffer fragment shaders (`gbuffer_fragment_base` / `_material`) which have been patched. If any new render path is added that samples shadows, it must recompute `viewSpaceDepth` per-fragment too. Consider extracting a helper in `Lighting.metal` (e.g. `static float ViewSpaceDepth(float3 worldPos, float3 cameraPos)`) so the convention is enforced.
- **`viewSpaceDepth` in `VertexOut`**: now vestigial (every consumer recomputes). Could be removed for cleanliness, but would touch every vertex/fragment shader pair. Not load-bearing.
