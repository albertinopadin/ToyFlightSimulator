# Metal Shader Review — Shared Code Extraction, Performance & Correctness

**Date:** 2026-08-11
**Scope:** All 22 `.metal` files + `TFSCommon.h` + `ShaderDefinitions.h` under
`ToyFlightSimulator Shared/Graphics/Shaders/` (~2,450 lines), reviewed at commit `870d464`.
The uncommitted `GBuffer.metal` change is parameter re-indentation only — no functional
difference, so every finding applies to both the staged and committed state.

**Method:** Every shader file read in full. Suspicious findings were cross-checked against the
Swift side (`ShaderLibrary`, the five `*Pipeline.swift` files, `LightObject`, `LightManager`,
`ShadowCascadeFitting`, `OITRenderer`, `BasicMeshes`) to confirm which shader functions are
actually wired to pipelines, what data the CPU uploads, and which depth convention each
renderer runs under. Findings below are labeled **CONFIRMED** (verified against both sides)
or **SUSPECTED** (shader-side evidence only).

**Fix tracking:** findings marked ✅ FIXED are done, with the fixing commit noted in place.
Currently fixed: **P1** and the **`ShaderDefinitions.h` include-guard hole** (§5) in
`e086508`; **E1** and **P2** (skinning consolidation via `ShaderHelpers.h`) in `b4fb581`;
**C7** (skinned `worldNormal` + tangent basis in animated vertices) in `d1b3286`
(all 2026-08-12); **C10** (terrain world-position G-buffer write), **C5** (point-light volume
calibration — the CPU-side `LightData.modelMatrix` variant), and **C14** (missing MSAA
point-light PSO bind, a new renderer-side finding) in `cc06a3c` (2026-08-13); **E3**
(opacity resolve → `ResolveOpacity`) and **E5** (base-color cascade → `ResolveBaseColor`,
plus a `texture2d<float>` overload) in `5105324` (2026-08-14); **E4** (normal-map decode +
TBN → `ApplyNormalMapEye` at the single-pass material fragment — which is also C6's
material-fragment half — plus `ApplyNormalMapWorld` staged for C1) in `fad8684`
(2026-08-14); **E7** (eye-space reconstruction → `ReconstructEyePosition` at both sites —
the DirectionalLight site being C4's wrong-form problem 2) and **E8** (terrain layer pick →
file-local `SampleTerrainLayer`) in `62e3dbf` (2026-08-14); **C1** (tiled G-buffer normal
decode + TBN — `ApplyNormalMapWorld`'s first caller; mirrored into the dead D2 duplicate)
and **C2** (OIT sort keyed on view-space depth via `1/position.w`, plus removal of the
10%-opacity clamp, confirming that SUSPECTED item as a debugging leftover) in `0ec59ea`
(2026-08-15); **C3** (point-light eye-space position computed per instance in the vertex
stage, passed flat) and **C4** (problems 1 and 3 — sun diffuse from `lightEyeDirection`,
real eye-space Blinn-Phong halfway vector — completing the finding after E7's problem 2)
in `e6949e5` (2026-08-16); **C6** (completed — `gbuffer_fragment_base` no longer runs the
geometric normal through the sample decode, finishing the finding after E4's
material-fragment half), **C8** (Base.metal direction vectors via the 3×3 `normalMatrix`),
**C9** (`unitNormal` initialized — the UB read removed), and **C13** (tiled point lights
tinted by the G-buffer albedo; the 0.9 fudge dropped) in `80d8f50` (2026-08-16);
**C12** (cascade selection + blend on true view-space depth — free via `eye_position.z`
in the single-pass G-buffer, a view-matrix dot4 in the tiled ones) in `878becf`
(2026-08-16); **P3** (the affine `/ worldPosition.w` divides dropped at all seven sites)
and **P4** (vertex-stage T/B/N normalizes removed — fragments renormalize once) in
`ab04296` (2026-08-17); **P5** (particle kernel: one device→thread load, with a
deliberately narrow store-back — see the banner for why not whole-struct) in `c1c6d81`
(2026-08-18); **E6** and **P7** (every full-screen pass — composite, Final, OIT blend,
both tiled directional lights, the single-pass directional light — on the one bufferless
`FullScreenTriangleVertex` triangle, per the call-site diffs staged under E6; the Final
PSO also drops its leftover vertexDescriptor, which the debug layer's draw validation
had turned into a required-but-unbound vertex buffer at index 0) in `5bc2e21`
(2026-08-18). All other findings are open.

---

## Contents

1. [Correctness findings](#1-correctness-findings) (C1–C14)
2. [Performance findings](#2-performance-findings) (P1–P7)
3. [Common code to extract](#3-common-code-to-extract) (E1–E8)
4. [Dead code inventory](#4-dead-code-inventory) (D1–D7)
5. [Minor notes & hygiene](#5-minor-notes--hygiene)
6. [Suggested order of attack](#6-suggested-order-of-attack)

Severity key: 🔴 visible rendering error on a live path · 🟠 wrong but masked/partially masked · 🟡 latent/dead-path or behavioral.

---

## 1. Correctness findings

### C1 ✅ FIXED — Tiled G-buffer writes the raw normal-map texel as the world normal (no decode, no TBN)

> **Fixed in `0ec59ea` (2026-08-15):** as the Fix diff below — `tiled_deferred_gbuffer_fragment`
> now feeds the sample and the (finally-read) `worldTangent`/`worldBitangent`/`worldNormal`
> to `ApplyNormalMapWorld` — the staged E4 world variant's first caller; the no-map path is
> unchanged. `normal.w` is now always 1.0 where the mapped path previously stored the
> sample's alpha — safe: both tiled lighting fragments read only `gBuffer.normal.xyz`. The
> same change was mirrored into the dead `tiled_msaa_gbuffer_fragment` (D2) so it stays
> consistent until deleted. The terrain G-buffer fragment's raw sample (C10's "also here"
> note) remains, pending a real terrain TBN. Compiles standalone; macOS Debug build passes.
> §6 step 2's visual check (the normal-mapped F-22 per renderer) is now unblocked.

**File:** `TiledDeferredGBuffer.metal:121-125` — **CONFIRMED**
**Affects:** TiledDeferred, TiledDeferredMSAA, TiledMSAATessellated (all three tiled renderers
share `tiled_deferred_gbuffer_fragment`; `TiledMSAAPipeline.swift:51,66` binds this same
function — the file `TiledMSAAGBuffer.metal` is dead, see D2).

When a mesh has a normal map, the fragment stores the **tangent-space, [0,1]-encoded texture
sample** directly into the world-space normal G-buffer target:

```metal
float4 normal = float4(normalize(in.worldNormal), 1.0);

if (!in.useObjectColor && !is_null_texture(normalTexture)) {
    normal = float4(normalTexture.sample(sampler2d, normalUV));   // raw sample!
}
```

Downstream, `tiled_deferred_directional_light_fragment` and
`tiled_deferred_point_light_fragment` treat `gBuffer.normal.xyz` as a world-space unit normal.
The sample is neither decoded (`*2−1`) nor rotated out of tangent space, so every
normal-mapped surface (the aircraft) is lit with a normal that points roughly `(±0.5, ±0.5, ~1)`
in *tangent* space interpreted as *world* space. The vertex stage even computes
`worldTangent`/`worldBitangent` for exactly this purpose and the fragment never reads them.

**Fix** (uses the `ApplyNormalMapWorld` helper from E4 — staged in `ShaderHelpers.h` since
`fad8684`, so only this call-site diff remains):

```diff
--- a/ToyFlightSimulator Shared/Graphics/Shaders/TiledDeferredGBuffer.metal
+++ b/ToyFlightSimulator Shared/Graphics/Shaders/TiledDeferredGBuffer.metal
@@ -118,12 +118,14 @@
     color.a = Lighting::CalculateShadow(in.worldPosition,
                                         fragViewSpaceDepth,
                                         in.worldNormal,
                                         lightData,
                                         shadowArray);

-    float4 normal = float4(normalize(in.worldNormal), 1.0);
-
-    if (!in.useObjectColor && !is_null_texture(normalTexture)) {
-        normal = float4(normalTexture.sample(sampler2d, normalUV));
-    }
+    float3 N = normalize(in.worldNormal);
+    if (!in.useObjectColor && !is_null_texture(normalTexture)) {
+        half3 tangentSample = normalTexture.sample(sampler2d, normalUV).xyz;
+        N = ApplyNormalMapWorld(tangentSample,
+                                in.worldTangent, in.worldBitangent, in.worldNormal);
+    }
+    float4 normal = float4(N, 1.0);
```

---

### C2 ✅ FIXED — OIT layer sort is inverted under reverse-Z — transparency blends front-to-back

> **Fixed in `0ec59ea` (2026-08-15):** as the Fix diff below — both `transparent_fragment`
> and `transparent_material_fragment` now key on `half(1.0 / rd.position.w)` (view-space
> depth), restoring nearest-in-layer-0 ordering and back-to-front compositing;
> `blend_fragments` needed no change, as predicted. The 10%-opacity hard clamp (the
> SUSPECTED item below) was also removed — confirmed a debugging leftover, so
> `ResolveOpacity(sampled alpha, material.opacity)` alone governs OIT opacity now.
> Compiles standalone; macOS Debug build passes. §6 step 4's visual check (overlapping
> canopy/afterburner layering) is now unblocked.

**File:** `OrderIndependentTransparency.metal:56-67, 135-148, 160-163` — **CONFIRMED**
(`OITRenderer.swift:76` clears depth to `Preferences.MainClearDepth` = 0.0 and uses the
`Closer*` states, i.e. the reverse-Z main projection.)

The image-block sort key is:

```metal
half depth = rd.position.z / rd.position.w;
```

In a fragment shader `position.z` is NDC depth and `position.w` is `1/w_clip`, so this key is
`z_ndc · viewZ`. Under **forward-Z** (Apple's original sample) that key *increases* with
distance, so the insertion sort (`insert if depth <= layerDepth`, layers initialized to
`+INFINITY`) keeps the **nearest** fragments in layer 0 and `blend_fragments`' loop from layer
3 → 0 composites **back-to-front**. Correct.

Under the project's **reverse-Z** projection the key becomes `n(f−z)/(f−n)`, which *decreases*
with distance. Consequences, both inverted from intent:

- Layer 0 now holds the **farthest** fragment; the blend loop composites near surfaces first
  and then paints farther surfaces **over** them with the `over` operator.
- When more than `kNumLayers` transparent surfaces overlap, the sort now evicts the
  **nearest** fragments instead of the farthest.

With ≤2 overlapping low-alpha layers the error is subtle (which is why it can survive
visually), but layering of canopy-over-canopy, afterburner-behind-canopy, etc. is wrong.

**Fix** — key on view-space depth directly; it is projection-convention independent:

```diff
--- a/ToyFlightSimulator Shared/Graphics/Shaders/OrderIndependentTransparency.metal
+++ b/ToyFlightSimulator Shared/Graphics/Shaders/OrderIndependentTransparency.metal
@@ -52,8 +52,10 @@
     half4 finalColor = half4(rd.color);
     finalColor.xyz *= finalColor.w;

-    // Get fragment distance from camera:
-    half depth = rd.position.z / rd.position.w;
+    // View-space depth as the sort key ([[position]].w = 1/clipW, and clipW is
+    // view depth for both forward- and reverse-Z projections). Ascending order
+    // keeps the NEAREST kNumLayers fragments, layer 0 = nearest.
+    half depth = half(1.0 / rd.position.w);
```

Apply the same two-line change in `transparent_material_fragment` (line 136). `blend_fragments`
then composites correctly with no change. (Note `half` gets coarse (~0.5 ulp) around 1,000 m
view depth — acceptable as an ordering key for transparency, but worth knowing.)

While here: `transparent_material_fragment` also hard-clamps every transparent surface to 10%
opacity (`OrderIndependentTransparency.metal:129-131`):

```metal
if (finalColor.w > 0.1) {
    finalColor.w = 0.1;
}
```

This overrides `material.opacity` for **all** OIT materials and looks like a debugging
leftover. If the translucency level is intentional, it belongs in `MaterialProperties.opacity`
per material, not a shader-wide constant. **SUSPECTED** intent bug — please confirm.

---

### C3 ✅ FIXED — Single-pass point lights compare a world-space light position against eye-space fragments

> **Fixed in `e6949e5` (2026-08-16):** as the Fix diff below — the vertex computes the
> light's eye-space position once per instance into the new flat-interpolated
> `LightInOut.light_eye_position` (with a comment recording that `LightData.position` is
> world-space) and the fragment reads it. The parenthetical `eye_space_light_pos` note is
> satisfied by construction: that local derives from the same `light_eye_position`
> variable, so direction, diffuse, and halfway vector all correct together. Compiles
> standalone; macOS Debug build passes. §6 step 3's visual check (PhysicsStressTestScene
> point lights + a low sun) is now fully unblocked — C4's remaining problems landed in the
> same commit.

**File:** `PointLights.metal:70-80` — **CONFIRMED**
(`LightObject.update()` stores `lightData.position = getPosition()` — world space; only
`lightEyeDirection` is view-transformed in `LightManager.GetDirectionalLightData`. Nothing
transforms point-light positions to eye space before upload.)

```metal
float3 eye_space_fragment_pos = in.eye_position * (depth / in.eye_position.z);  // eye space ✓
float3 light_eye_position = light_data[in.iid].position;                         // WORLD space ✗
float light_distance = length(light_eye_position - eye_space_fragment_pos);
```

The radius test, direction, and attenuation all mix spaces, so point-light contribution in the
SinglePassDeferredLighting renderer is only ~right when the view matrix is near identity, and
swims as the camera moves/rotates.

**Fix** — compute the light's eye-space position once per instance in the vertex stage (which
already binds both `light_data` and `sceneConstants`) and pass it flat:

```diff
--- a/ToyFlightSimulator Shared/Graphics/Shaders/PointLights.metal
+++ b/ToyFlightSimulator Shared/Graphics/Shaders/PointLights.metal
@@ -35,9 +35,10 @@
 typedef struct {
     float4 position [[ position ]];
     float3 eye_position;
+    float3 light_eye_position [[ flat ]];
     uint   iid [[ flat ]];
 } LightInOut;
@@ -48,13 +49,15 @@
     float4 modelPosition = vertices[vid];
     float4 worldPosition = light_data[iid].modelMatrix * modelPosition;
     float4 eyePosition = sceneConstants.viewMatrix * worldPosition;

     LightInOut out = {
         .position = sceneConstants.projectionMatrix * eyePosition,
         .eye_position = eyePosition.xyz,
+        .light_eye_position =
+            (sceneConstants.viewMatrix * float4(light_data[iid].position, 1)).xyz,
         .iid = iid
     };
@@ -69,7 +72,7 @@
     // Used eye_space depth to determine the position of the fragment in eye_space
     float3 eye_space_fragment_pos = in.eye_position * (depth / in.eye_position.z);

-    float3 light_eye_position = light_data[in.iid].position;
+    float3 light_eye_position = in.light_eye_position;
     float light_distance = length(light_eye_position - eye_space_fragment_pos);
```

(Also update the `eye_space_light_pos` usage below it — it's the same value.)

---

### C4 ✅ FIXED — Single-pass directional light: direction derived from unnormalized position, wrong position reconstruction, bogus halfway vector

> **Fixed across two commits.** Problem 2 in `62e3dbf` (2026-08-14, the E7 conversion):
> `eye_space_fragment_pos` comes from `ReconstructEyePosition` (the correct
> PointLights-style ray scaling), superseding that hunk of the Fix diff below. Problems 1
> and 3 in `e6949e5` (2026-08-16), as the remaining hunks: diffuse is
> `saturate(dot(normal, sun_eye_direction))` with `sun_eye_direction =
> lightData.lightEyeDirection` (verified surface→sun, eye space, renormalized from the
> live view matrix each frame — LightManager.swift:60/86, LightObject.swift:31), and the
> specular half-vector is real Blinn-Phong in eye space, `H = normalize(L + V)` with
> `V = -normalize(eye_space_fragment_pos)`. The superseded lines were deleted, not left
> commented. The specular-exponent note below (intensity used as exponent) remains open by
> design — tuning, not correctness. Compiles standalone; macOS Debug build passes. §6
> step 3's visual check is now unblocked.

**File:** `DirectionalLight.metal:45-72` — **CONFIRMED**

Three stacked problems in `deferred_directional_lighting_fragment`:

1. **Direction from position** (line 45-46):
   ```metal
   half3 lightDirection = half3(-lightData.position);
   half sun_diffuse_intensity = saturate(-dot(lightDirection, normal_shadow.xyz));
   ```
   `lightData.position` is the sun's world position (magnitude in the hundreds), so the dot
   product saturates to 1.0 for nearly every upward-facing normal — diffuse is effectively
   flat. It also ignores the purpose-built `lightData.direction` /
   `lightData.lightEyeDirection` fields, and compares a **world** vector against the
   **eye-space** G-buffer normal.

2. **Eye-position reconstruction** (line 57):
   ```metal
   float3 eye_space_fragment_pos = normalize(in.eye_position) * depth;
   ```
   `depth` is the stored eye-space **z**, not the radial distance, so this lands on the wrong
   point along the view ray. `PointLights.metal:70` already has the correct form:
   `in.eye_position * (depth / in.eye_position.z)`.

3. **"Halfway" vector** (line 62) subtracts a world-space light *position* from an eye-space
   fragment *position* — not a halfway vector in any space.

**Fix** — light entirely in eye space with the fields the CPU already populates:

```diff
--- a/ToyFlightSimulator Shared/Graphics/Shaders/DirectionalLight.metal
+++ b/ToyFlightSimulator Shared/Graphics/Shaders/DirectionalLight.metal
@@ -42,31 +42,27 @@
     float depth = GBuffer.depth;
     half4 normal_shadow = GBuffer.normal_shadow;
     half4 albedo_specular = GBuffer.albedo_specular;
-    half3 lightDirection = half3(-lightData.position);
-    half sun_diffuse_intensity = saturate(-dot(lightDirection, normal_shadow.xyz));
+    // G-buffer normals are eye-space; LightManager recomputes lightEyeDirection
+    // (surface → sun, eye space, unit length) from the live view matrix each frame.
+    half3 sun_eye_direction = half3(lightData.lightEyeDirection);
+    half sun_diffuse_intensity = saturate(dot(normal_shadow.xyz, sun_eye_direction));
     half minimum_sun_diffuse_intensity = 0.4h;
     sun_diffuse_intensity = max(sun_diffuse_intensity, minimum_sun_diffuse_intensity);

     half3 sun_color = half3(lightData.color.xyz);

     half3 diffuse_contribution = albedo_specular.xyz * sun_diffuse_intensity * sun_color;

     // Calculate specular contribution from directional light

-    // Used eye_space depth to determine the position of the fragment in eye_space
-    float3 eye_space_fragment_pos = normalize(in.eye_position) * depth;
-
-//    float4 eye_light_direction = lightData.eyeDirection;
-
-    // Specular Contribution
-    float3 halfway_vector = normalize(eye_space_fragment_pos - lightData.position);
+    // Reconstruct the eye-space position by scaling the view ray so its z equals
+    // the stored eye-space depth (see ReconstructEyePosition, E7).
+    float3 eye_space_fragment_pos = in.eye_position * (depth / in.eye_position.z);
+
+    // Blinn-Phong halfway vector, eye space: H = normalize(L + V), V = toward camera.
+    float3 view_dir = -normalize(eye_space_fragment_pos);
+    float3 halfway_vector = normalize(float3(sun_eye_direction) + view_dir);
```

The specular exponent on line 70 (`powr(..., specular_intensity)`) uses an *intensity* as an
*exponent*; consider a real shininess constant, but that's tuning, not correctness.

---

### C5 ✅ FIXED — Tiled point-light volume ignores the light's radius

> **Fixed in `cc06a3c` (2026-08-13):** via the CPU-side variant at the end of this section,
> not the shader-constant Fix diff below (kept for the record). `setLightRadius` scales the
> node by `radius / IcosahedronMesh.inscribedRadius`, the tiled vertex applies
> `light.modelMatrix`, `PointLightObject` defaults to a 10 m radius, and FlightboxScene's
> manual `setScale` calls became `setLightRadius(10.0)`. The default attenuation was also
> softened `(1,1,1)` → `(0.5,0.5,0.5)`. None of this was observable in the MSAA renderers
> until C14 (missing PSO bind, same commit) was fixed alongside.

**File:** `TiledDeferredPointLight.metal:30-31` — **CONFIRMED**
(`IcosahedronMesh` is built once with `MDLMesh.newIcosahedron(withRadius: 0.7557)`,
`BasicMeshes.swift:148-153`.)

```metal
float4 lightPosition = float4(lightDatas[instanceId].position, 0);
float4 position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix
                * (in.position + lightPosition);   // no scale anywhere
```

The stencil/lighting volume is always the raw ~0.76-unit icosahedron regardless of
`light.radius`, so a point light with radius 10 only lights fragments covered by a ~0.76 m
mesh on screen. (`modelConstants` is bound to both stages and never used — likely the remnant
of the intended scaling path.) The single-pass renderer doesn't have this bug: its vertex uses
`light_data[iid].modelMatrix`.

**Fix:**

```diff
--- a/ToyFlightSimulator Shared/Graphics/Shaders/TiledDeferredPointLight.metal
+++ b/ToyFlightSimulator Shared/Graphics/Shaders/TiledDeferredPointLight.metal
@@ -27,11 +27,15 @@
                                   constant LightData      *lightDatas     [[ buffer(TFSBufferPointLightsData) ]],
                                            uint           instanceId      [[ instance_id ]])
 {
-    float4 lightPosition = float4(lightDatas[instanceId].position, 0);
-    float4 position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * (in.position + lightPosition);
+    constant LightData &light = lightDatas[instanceId];
+    // Scale the unit-ish icosahedron so its *inscribed* sphere covers the light's
+    // falloff radius, then translate to the light. NOTE: verify the mesh's
+    // inscribed radius (MDLMesh withRadius: 0.7557 — circum vs. inscribed matters
+    // here); regenerating the mesh at circumradius 1 and using radius/0.7947
+    // is the cleanest calibration.
+    const float kMeshInscribedRadius = 0.7557 * 0.7947;
+    float3 world = in.position.xyz * (light.radius / kMeshInscribedRadius) + light.position;
+    float4 position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * float4(world, 1);
```

**Why** — is `kMeshInscribedRadius` right, why does the shader need it at all, and where should
it live?

**The constant is numerically correct — measured, not assumed.** Verified 2026-08-13 with a
headless ModelIO script (build `MDLMesh.newIcosahedron`, read vertices via
`vertexAttributeData(forAttributeNamed:)`, inradius = min origin→face-plane distance over the
index buffer's triangles):

| quantity | measured |
|---|---|
| `withRadius:` semantics | **circumradius** — all 12 vertices land at exactly the param distance |
| engine mesh circumradius (param 0.75576) | 0.75576 |
| engine mesh inscribed radius | **0.60057** |
| inradius/circumradius, regular icosahedron | 0.79465 |
| shader constant `0.7557 × 0.7947` | 0.60055 — agrees to 0.003% |

So the two factors are `(mesh circumradius) × (inradius/circumradius ratio)`. The genuinely
fishy part is upstream: `BasicMeshes.swift:150`'s `icoRadius = √3/12·(3+√5) ≈ 0.75576` is the
inradius-to-**edge** ratio of a regular icosahedron — Apple's DeferredLighting sample's
expression with the reciprocal dropped (Apple passes `1.0 / (√3/12·(3+√5))`, commented "so the
minimum radius is 1"; even that overshoots ~5% against measured ModelIO, yielding inradius
1.051). The engine mesh's size is an accident of copying, not a chosen dimension.

**Why a mesh-size constant is irreducible.** The vertex shader sees one model-space vertex at
a time. `light.radius` says how big the volume *should* be in world meters; nothing in any
binding says how big the mesh *is* in model units. The scale must be desired/actual, and
"actual mesh size" is asset metadata — the GPU cannot derive the extent of a mesh it never
sees whole. The information is unavoidable; only its *home* is a design choice.

**Why the *inscribed* radius.** The polyhedron must **contain** the light's sphere of
influence. An icosahedron's flat faces cut chords inside its vertex sphere — face centers sit
20.5% closer than vertices. Calibrate by circumradius and the volume clips lit fragments near
each face center, giving the light a faceted rim. Calibrate by inradius and the faces are
tangent to the light sphere — containment guaranteed; the cost is a thin shell of extra
fragments whose attenuation ≈ 0 (and which `CalculatePointLighting`'s `< 0.01 → 0` floor
rounds to exact black). Erring big is free; erring small is a visible artifact.

⚠️ **Erratum (2026-08-13):** an earlier revision of this section claimed `LightData()`
zero-inits (radius 0 → volumes collapse). Wrong — `MetalTypes.swift:109-131` defines an
explicit `LightData` extension `init()` with `radius: 1.0`, `attenuation: [1, 1, 1]`,
`brightness: 1.0`, so unset lights default to a 1 m volume, not zero. Still ship a usable
default radius (no scene calls `setLightRadius`; the only call site, `FlightboxScene:73`, is
commented out — 1 m is barely visible). The *real* default-value problem is
`attenuation = (1,1,1)`: `1/(1 + d + d²)` is 0.14 at 2 m, 0.032 at 5 m, and drops below
`CalculatePointLighting`'s `< 0.01 → black` floor past ~9.4 m — every point light is
effectively a dim ≲3 m glow regardless of `radius`, and no attenuation setter exists.
(`cc06a3c` softens the default to `(0.5, 0.5, 0.5)`, stretching the black floor to ~13.6 m.)
A radius-windowed falloff like the single-pass `(1 − d/r)²` would make `radius` the single
knob (C13 territory).

**Cleaner variant — fold the calibration into `LightData.modelMatrix` on the CPU.** The
plumbing already exists: `LightObject.update()` copies the node's `modelMatrix` into
`lightData.modelMatrix` every frame (LightObject.swift:80), and the single-pass volume
vertices already consume it (`light_mask_vertex` / `deferred_point_lighting_vertex`,
PointLights.metal:24/49). Nothing couples radius → scale today — which means **the
single-pass renderer has the same latent bug through a different mechanism**: its volumes are
the raw mesh at whatever node scale the scene hand-set (`FlightboxScene` calls
`pl.setScale(2.0)` — evidence the modelMatrix channel was the intended calibration path,
driven manually), while its fragment gates on `light_distance < light_radius` with a
`(1 − d/r)²` falloff, so the volume covers only a sliver of the falloff sphere. Folding the
scale into the node fixes both renderers at once, moves the constant into Swift next to the
mesh it describes, unifies the tiled vertex with the single-pass ones, and deletes the MSL
constant:

```diff
--- a/ToyFlightSimulator Shared/AssetPipeline/Libraries/Meshes/BasicMeshes.swift
+++ b/ToyFlightSimulator Shared/AssetPipeline/Libraries/Meshes/BasicMeshes.swift
@@ class IcosahedronMesh: Mesh {
 class IcosahedronMesh: Mesh {
+    /// ModelIO's `withRadius:` is the CIRCUMRADIUS — all 12 vertices land at exactly this
+    /// distance (measured 2026-08-13). The expression is the inradius/edge ratio of a
+    /// regular icosahedron, inherited from Apple's DeferredLighting sample minus the
+    /// reciprocal — i.e. the mesh's size is a historical accident, kept for compatibility.
+    static let circumradius: Float = sqrtf(3.0) / 12.0 * (3.0 + sqrtf(5.0))   // ≈ 0.75576
+
+    /// Center-to-face-plane distance: the radius of the largest sphere the mesh fully
+    /// CONTAINS (r/R of a regular icosahedron ≈ 0.79465; measured 0.60057). Light volumes
+    /// scale by `radius / inscribedRadius` so the flat faces clear the light's sphere.
+    /// Pure constants — safe to reference from Metal-free logic tests.
+    static let inscribedRadius: Float = circumradius * 0.79465                // ≈ 0.60057
+
     override init() {
-        let icoRadius = sqrtf(3.0) / 12.0 * (3.0 + sqrtf(5.0))
-        let mdlIcosahedron = MDLMesh.newIcosahedron(withRadius: icoRadius, 
+        let mdlIcosahedron = MDLMesh.newIcosahedron(withRadius: Self.circumradius,
                                                     inwardNormals: false,
                                                     allocator: Self.mtkMeshBufferAllocator)
--- a/ToyFlightSimulator Shared/GameObjects/LightObject.swift
+++ b/ToyFlightSimulator Shared/GameObjects/LightObject.swift
@@ extension LightObject {
-    public func setLightRadius(_ radius: Float) { self.lightData.radius = radius }
+    /// Sets the falloff radius AND scales the node so the icosahedron volume mesh contains
+    /// the radius-sized sphere of influence. `update()` copies the node's modelMatrix into
+    /// `lightData.modelMatrix`, which every volume vertex path consumes
+    /// (PointLights.metal light_mask_vertex / deferred_point_lighting_vertex,
+    /// TiledDeferredPointLight.metal) — the mesh-size calibration lives here, next to the
+    /// asset it describes, not hardcoded in MSL.
+    public func setLightRadius(_ radius: Float) {
+        self.lightData.radius = radius
+        if lightType == Point {
+            self.setScale(radius / IcosahedronMesh.inscribedRadius)
+        }
+    }
--- a/ToyFlightSimulator Shared/GameObjects/PointLightObject.swift
+++ b/ToyFlightSimulator Shared/GameObjects/PointLightObject.swift
@@ class PointLightObject: LightObject {
     init() {
         super.init(name: "Point Light", lightType: Point, modelType: .Icosahedron)
+        // LightData's extension init defaults radius to 1 m — technically valid but
+        // barely visible. Give point lights a usable default; scenes override as needed.
+        setLightRadius(10.0)
     }
--- a/ToyFlightSimulator Shared/Graphics/Shaders/TiledDeferredPointLight.metal
+++ b/ToyFlightSimulator Shared/Graphics/Shaders/TiledDeferredPointLight.metal
@@ tiled_deferred_point_light_vertex(...)
-//    float4 lightPosition = float4(lightDatas[instanceId].position, 0);
-//    float4 position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * (in.position + lightPosition);
-
-    constant LightData &light = lightDatas[instanceId];
-
-    const float kMeshInscribedRadius = 0.7557 * 0.7947;
-    float3 world = in.position.xyz * (light.radius / kMeshInscribedRadius) + light.position;
-    float4 position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * float4(world, 1);
-
+    // Volume sizing (radius / mesh inscribed radius) is baked into the light's modelMatrix
+    // CPU-side (LightObject.setLightRadius) — the same contract as the single-pass volume
+    // vertices in PointLights.metal.
+    float4 world = lightDatas[instanceId].modelMatrix * float4(in.position.xyz, 1);
+    float4 position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * world;
```

Caveats, checked against the code:

- Scaling the light's node is side-effect-free: `LightObject.objectType == .none`, so lights
  never enter SceneManager's batched draws (`DrawIcosahedrons` draws
  `SceneManager.icosahedrons`, not lights), and while `DrawPointLights` writes the lights'
  `ModelConstants`, the volume vertex functions read `light_data`/`lightDatas`, not
  ModelConstants. `Sun` is unaffected (coupling gated on `Point`).
- `setLightRadius` now owns the node scale — `FlightboxScene`'s manual `pl.setScale(2.0)`
  (today: a ~1.5 m volume) should become a real radius call, e.g. the commented-out
  `setLightRadius(10.0)`.
- A light parented under a scaled node inherits that scale into the volume (consistent with
  world-space semantics; no current scene does this).
- `deferred_point_lighting_fragment`'s eye/world-space mixing is a separate bug — see C3/C4
  (both since fixed in `e6949e5`).

Also in this file's fragment (see C13, since fixed in `80d8f50`): the surface albedo was
ignored.

---

### C6 ✅ FIXED — Single-pass G-buffer runs the *geometric* normal through the normal-map decode

> **Fixed across two commits.** The `gbuffer_fragment_material` half landed in `fad8684`
> (2026-08-14, the E4 conversion — the collapsed `ApplyNormalMapEye` form, superseding the
> **Fix (material)** diff below). The `gbuffer_fragment_base` half landed in `80d8f50`
> (2026-08-16) exactly as the **Fix (base)** diff below: decode + TBN deleted, plain
> `normalize(in.normal)`. The material fragment's fallback branch now carries a comment
> marking it load-bearing — an interim edit had collapsed it into an unconditional
> `ApplyNormalMapEye` call, which would have sampled a null texture (UB in MSL) and
> re-decoded the geometric normal on every no-normal-map submesh; reverted in the same
> commit. Verified: standalone `metal -c` + macOS Debug build; §6 step 2's
> SinglePassDeferred visual check now covers untextured objects too.

**File:** `GBuffer.metal:117-128` (`gbuffer_fragment_base`) and `184-200`
(`gbuffer_fragment_material`, fallback path) — **CONFIRMED** live via
`SinglePassDeferredPipeline.swift:35` etc.

`gbuffer_fragment_base` has no normal map at all, yet decodes the interpolated eye-space
normal as if it were a [0,1] texture sample and then pushes it through the TBN:

```metal
half4 normal = half4(in.normal, 1.0);                       // eye-space unit normal
half3 tangent_normal = normalize((normal.xyz * 2.0) - 1.0); // bogus decode of a [−1,1] vector
half3 eye_normal = (tangent_normal.x * in.tangent +
                    tangent_normal.y * in.bitangent +
                    tangent_normal.z * in.normal);
```

For `in.normal = (0,0,1)` this produces `normalize(-1,-1,1)` mixed through the TBN — a
significantly skewed normal on every untextured object in the single-pass renderer.
`gbuffer_fragment_material` has the same bug on its no-normal-map fallback
(`normal_sample = half4(in.normal, 1.0)` then decode).

**Fix (base):**

```diff
@@ fragment GBufferData gbuffer_fragment_base(...)
     half4 base_color = half4(in.color);
-    half4 normal = half4(in.normal, 1.0);
     half specularContribution = 1.0;  // Hardcoded for base
-
-    // Calculate normal in eye space
-    half3 tangent_normal = normalize((normal.xyz * 2.0) - 1.0);
-
-    half3 eye_normal = (tangent_normal.x * in.tangent +
-                        tangent_normal.y * in.bitangent +
-                        tangent_normal.z * in.normal);
-
-    eye_normal = normalize(eye_normal);
+    // in.normal is already the interpolated eye-space geometric normal; the
+    // [0,1]→[−1,1] decode + TBN rotation only applies to normal-map *samples*.
+    half3 eye_normal = normalize(in.normal);
```

**Fix (material)** — decode only on the texture path:

```diff
@@ fragment GBufferData gbuffer_fragment_material(...)
-    if (!in.useObjectColor && !is_null_texture(normalMap)) {
-        normal_sample = normalMap.sample(sampler2d, normalUV);
-    } else {
-        normal_sample = half4(in.normal, 1.0);
-    }
+    half3 eye_normal;
+    if (!in.useObjectColor && !is_null_texture(normalMap)) {
+        half3 tangent_normal = normalize(normalMap.sample(sampler2d, normalUV).xyz * 2.0h - 1.0h);
+        eye_normal = normalize(tangent_normal.x * in.tangent +
+                               tangent_normal.y * in.bitangent +
+                               tangent_normal.z * in.normal);
+    } else {
+        eye_normal = normalize(in.normal);
+    }
@@
-    // Calculate normal in eye space
-    half3 tangent_normal = normalize((normal_sample.xyz * 2.0) - 1.0);
-    half3 eye_normal = normalize(tangent_normal.x * in.tangent +
-                                 tangent_normal.y * in.bitangent +
-                                 tangent_normal.z * in.normal);
```

(With E4 both branches collapse into one `ApplyNormalMapEye` call site.)

---

### C7 ✅ FIXED — Animated tiled G-buffer vertex feeds the *unskinned* normal to `worldNormal`

> **Fixed in `d1b3286` (2026-08-12):** `worldNormal` in the tiled animated vertex now derives
> from the skinned normal, and the tangent/bitangent outputs are skinned (via the `skinMatrix`
> local from E1) in all three animated vertex producers. The fix's scope was slightly wider
> than this finding recorded: `GBuffer.metal`'s animated `tangent`/`bitangent` had the same
> defect, and unlike the other two files that TBN is consumed *today* by
> `gbuffer_fragment_material`'s normal mapping. The bitangent handedness negation is
> preserved; static vertex functions are untouched.

**File:** `TiledDeferredGBuffer.metal:76` — **CONFIRMED**

`tiled_deferred_gbuffer_animated_vertex` skins `normal` (lines 62-65) and then ignores it for
the field the fragment actually uses:

```metal
.normal = normal.xyz,                                   // skinned ✓ (unused downstream)
.worldNormal = modelInstance.normalMatrix * in.normal,  // UNskinned ✗ (used for shadow bias + lighting)
```

Rotating gear doors / control surfaces on animated aircraft get lighting/shadow-bias normals
frozen in bind pose.

```diff
-        .worldNormal = modelInstance.normalMatrix * in.normal,
+        .worldNormal = modelInstance.normalMatrix * normal.xyz,
```

`worldTangent`/`worldBitangent` are also unskinned here and in
`single_pass_deferred_transparency_animated_vertex` — currently harmless-ish (only the normal
feeds lighting until C1's fix lands, after which skinned tangents matter for normal-mapped
animated meshes). *(The E1 extraction landed in `b4fb581` as a pure consolidation without
touching output fields; the follow-up `d1b3286` then applied the `skinMatrix` local to the
`worldNormal` and tangent assignments — see the FIXED banner above.)*

---

### C8 ✅ FIXED — `Base.metal` / `Instanced.metal` transform normals as *points* (w = 1)

> **Fixed in `80d8f50` (2026-08-16):** as the diff below in both `base_vertex` and
> `base_animated_vertex` (the latter feeding the skinned `normal.xyz`) — directions go
> through the 3×3 `normalMatrix`, so no translation leaks in and `normalize()` runs over
> three components. One nuance the aside below overstates: `Transform.normalMatrix(from:)`
> is the plain upper-left 3×3 of the model matrix, NOT an inverse-transpose, so it does not
> correct for non-uniform scale — fine for the rigid + uniform-scale model matrices the
> engine produces (meterization folds a uniform scale). `Instanced.metal` is untouched:
> `instanced_vertex` is dead, and deleting it stays with D1.

**Files:** `Base.metal:35-37, 80-82`, `Instanced.metal:28-30` — **CONFIRMED**
(`base_vertex`/`base_animated_vertex` are live: OIT's opaque pipelines,
`OrderIndependentTransparencyPipeline.swift:50-73`. `instanced_vertex` is dead, see D1.)

```metal
.surfaceNormal = normalize(modelInstance.modelMatrix * float4(vIn.normal, 1.0)).xyz,
```

With `w = 1` the model translation is added to the direction vector, and the `normalize()` runs
over the 4-vector (including w) before `.xyz` is taken. Both are wrong; direction vectors need
`w = 0` — or better, the `normalMatrix` that `ModelConstants` already carries (which also
handles non-uniform scale):

```diff
--- a/ToyFlightSimulator Shared/Graphics/Shaders/Base.metal
+++ b/ToyFlightSimulator Shared/Graphics/Shaders/Base.metal
@@ vertex RasterizerData base_vertex(...)
-        .surfaceNormal = normalize(modelInstance.modelMatrix * float4(vIn.normal, 1.0)).xyz,
-        .surfaceTangent = normalize(modelInstance.modelMatrix * float4(vIn.tangent, 1.0)).xyz,
-        .surfaceBitangent = normalize(modelInstance.modelMatrix * float4(vIn.bitangent, 1.0)).xyz,
+        .surfaceNormal = normalize(modelInstance.normalMatrix * vIn.normal),
+        .surfaceTangent = normalize(modelInstance.normalMatrix * vIn.tangent),
+        .surfaceBitangent = normalize(modelInstance.normalMatrix * vIn.bitangent),
```

Same change in `base_animated_vertex` (using the skinned `normal.xyz`). Practical impact today
is muted because the OIT lighting path is commented out (C9), but `base_fragment` writes
`surfaceNormal` to `color1` and any future re-enable of Phong inherits the bug.

---

### C9 ✅ FIXED — `material_fragment` reads an uninitialized variable (UB on a live path)

> **Fixed in `80d8f50` (2026-08-16):** the minimal fix below —
> `unitNormal = normalize(rd.surfaceNormal)` — plus a comment that `color1` needs the value
> even while the lit path stays commented out. The commented-out Phong experiment is left in
> place; with C8's `surfaceNormal` fixed in the same commit, the "very dark scene" TODO's
> suspected cause is gone, so re-enabling it can be retried as its own tuning change.

**File:** `Base.metal:120-143` — **CONFIRMED** live
(`OrderIndependentTransparencyPipeline.swift:62,73`, `BasicPipeline.swift:24`).

```metal
float3 unitNormal;
// TODO: This results in very dark scene:
//    if (material.isLit) { ... }        // everything that would write it is commented out

FragmentOutput out = {
    .color0 = half4(color.r, color.g, color.b, color.a),
    .color1 = half4(unitNormal.x, unitNormal.y, unitNormal.z, 1.0)   // ← uninitialized read
};
```

Reading an uninitialized variable is undefined behavior in MSL; today the garbage lands in
`color1`, which the OIT opaque pass presumably masks, but the compiler is free to do worse.
Minimal fix:

```diff
-    float3 unitNormal;
+    float3 unitNormal = normalize(rd.surfaceNormal);
```

(Incidentally, "TODO: This results in very dark scene" — the darkness likely traces to C8's
broken `surfaceNormal` plus `GetPhongIntensity`'s clamping, not to the idea of lighting itself.)

---

### C10 ✅ FIXED — Terrain G-buffer writes the *window-space* position into the world-position target

> **Fixed in `cc06a3c` (2026-08-13):** as the Fix diff below — the pre-projection world
> position rides through `TessellationVertexOut` and the fragment stores it with w = 1;
> the superseded commented-out mvp lines were removed.

**File:** `Tessellation.metal:149-153` — **CONFIRMED** (TiledMSAATessellated renderer)

```metal
GBufferOut out {
    .albedo = color,
    .normal = normal,
    .position = in.position    // [[position]] = (pixels.x, pixels.y, ndc.z, 1/w) — NOT world!
};
```

`GBufferOut.position` is consumed as a world-space position by
`tiled_deferred_point_light_fragment` (`Lighting::CalculatePointLighting(light, worldPosition,…)`),
so point lights on terrain compute garbage distance/attenuation. Also here: the normal target
gets a raw `normalTexture` sample (same class of bug as C1), and the shadow term is a
commented-out TODO while `albedo.a` (which the directional pass multiplies by) is whatever the
terrain texture's alpha happens to be.

**Fix** — carry the pre-projection world position through the patch stage:

```diff
--- a/ToyFlightSimulator Shared/Graphics/Shaders/ShaderDefinitions.h
+++ b/ToyFlightSimulator Shared/Graphics/Shaders/ShaderDefinitions.h
@@ struct TessellationVertexOut {
     float4 position [[ position ]];
     float4 color;
     float height;
     float2 uv;
+    float3 worldPosition;
 };
--- a/ToyFlightSimulator Shared/Graphics/Shaders/Tessellation.metal
+++ b/ToyFlightSimulator Shared/Graphics/Shaders/Tessellation.metal
@@ tessellation_vertex(...)
-    float4x4 mvp = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * modelConstants.modelMatrix ;
-    position = mvp * position;
+    float4 worldPosition = modelConstants.modelMatrix * position;
+    position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * worldPosition;

     TessellationVertexOut out {
         .position = position,
         .color = float4(color.r),
         .height = height,
-        .uv = xy
+        .uv = xy,
+        .worldPosition = worldPosition.xyz
     };
@@ tessellation_gbuffer_fragment(...)
     GBufferOut out {
         .albedo = color,
         .normal = normal,
-        .position = in.position
+        .position = float4(in.worldPosition, 1.0)
     };
```

**Why** — what was actually in the buffer, and why nobody ever saw it:

`[[position]]` means two different things on the two sides of the rasterizer. In the vertex
stage it's the clip-space position the shader computed; the rasterizer consumes that, and what
a `[[position]]`-attributed **fragment** input delivers is the window coordinate: `x, y` are
the fragment's pixel coordinates in the viewport (half-pixel centers, e.g. `(1412.5, 380.5)`),
`z` is the depth-buffer value after the viewport transform (reverse-Z here: ~1 near, ~0 far),
`w` is `1/clip.w`. So terrain fragments wrote `(1412.5, 380.5, 0.997)` into a target where
every other object writes world-space meters like `(83.2, -4.1, 1120.7)`.

A G-buffer target's "correct" contents are defined entirely by its consumer — the geometry is
gone by the time the lighting pass runs, so whatever the lighting math needs is what must be
stored. The one consumer of `GBufferOut.position` is `tiled_deferred_point_light_fragment` →
`Lighting::CalculatePointLighting` (Lighting.metal:216-219), which computes
`distance(light.position, fragmentWorldPosition)` and
`normalize(light.position - fragmentWorldPosition)` — both meaningful only if the stored value
shares a space with `light.position`, i.e. world space. (Window-`xy` + depth is not an absurd
thing to find in a position target — depth-reconstruction renderers store exactly that and
rebuild world position via the inverse view-projection, cf. the eye-ray variant in C4/E7 — but
that only works if the consumer does the reconstruction math. This one uses the texel
directly.)

Why it produced no visible artifacts — three layers of masking, stacked:

1. **The directional pass never reads position.** `tiled_deferred_directional_light_fragment`
   uses only `gBuffer.albedo` + `gBuffer.normal`; the shadow term was already computed in the
   G-buffer pass and stashed in `albedo.a`. So 100% of the lighting actually visible on
   terrain (sun + shadows) never touched the broken data.
2. **`FlightboxWithTerrain` had no point lights** (at analysis time — one was added along
   with the fix as its visual check). The scene added one `Sun` and nothing else, so the
   point-light volume pass drew zero instances and the bogus texels sat unread in a
   memoryless tile attachment.
3. **Even with a point light near terrain, the symptom is darkness, not glitch colors.**
   `distance((1412, 380, 0.99), lightPos)` is on the order of 10³, so quadratic attenuation
   collapses toward zero, and `CalculatePointLighting` floors totals below 0.01 to exact
   black; the volume pass blends additively, and adding zero changes nothing. Add C5 (the
   unscaled icosahedron volume covers well under a meter of screen) and the observable
   "artifact" was terrain *not receiving a subtle glow* — an absence-of-effect bug, the kind a
   GPU frame capture catches (the position target under terrain shows a smooth screen-space
   gradient instead of world coordinates) and eyeballs don't.

The fix is therefore latent until a point light hovers near terrain under TiledMSAATessellated
— and actually *seeing* the glow also wants C5 (scale the volume by `light.radius`).

---

### C11 🟡 Particle simulation is frame-rate dependent

**File:** `Particles.metal:19-41` — **CONFIRMED** (no time uniform is bound)

`compute_particle` advances `position += speed * direction` and `age += 1.0` **per dispatch**,
so particle velocity and lifetime scale with FPS (120 Hz ProMotion = 2× faster flames than
60 Hz). The fix is the standard one — bind `deltaTime` (or reuse
`SceneConstants.totalGameTime` deltas) and integrate with it:

```diff
-kernel void compute_particle(device Particle *particles [[ buffer(0) ]],
-                             uint id [[ thread_position_in_grid ]]) {
+kernel void compute_particle(device Particle *particles [[ buffer(0) ]],
+                             constant float  &deltaTime  [[ buffer(1) ]],
+                             uint id [[ thread_position_in_grid ]]) {
+    Particle p = particles[id];                     // one device→thread load (P5)
-    float xVelocity = particles[id].speed * particles[id].direction.x;
-    ...
-    particles[id].age += 1.0;
+    p.position += p.speed * p.direction * deltaTime;
+    p.age += deltaTime;                             // Particle.life becomes seconds
```

*(P5's load-once landed standalone in `c1c6d81` (2026-08-18), so the `Particle p` line and
the per-field-read conversion sketched above are already in the tree; what remains for C11
is the `deltaTime` binding + integration and the reorder below. When rebasing, keep the
narrow `{position, age, scale}` store-back — the rationale is in P5's banner and at the
store site.)*

Also: the lifetime check runs *after* `scale` is computed, so the frame a particle expires it
renders with `mix(start, end, age/life > 1)` — an extrapolated scale. Reorder the reset before
the scale computation.

---

### C12 ✅ FIXED — Cascade selection metric doesn't match the CPU's split metric (comment is wrong at minimum)

> **Fixed in `878becf` (2026-08-16):** the **Fix (true view-z)** diffs below, as
> prescribed — with one tightening in `GBuffer.metal`: both fragments pass the
> already-interpolated `in.eye_position.z` straight into `CalculateShadow` (no local),
> visibly the same value the G-buffer writes as `.depth`. The tiled G-buffers derive
> view-z via the view matrix exactly as diffed. Selection, the 10% cross-fade, and
> `SelectCascade`'s naming now share one metric; the stale comments (GBuffer's
> "recomputing per-fragment", TiledDeferred's Sterbenz note about the removed
> subtraction) were replaced. Verified: all three files compile standalone via
> `metal -c`; macOS Debug build passes.

**Files:** `GBuffer.metal:131, 203`, `TiledDeferredGBuffer.metal:114`,
`TiledMSAAGBuffer.metal:40` vs. `ShadowCascadeFitting.swift:27` — **CONFIRMED (minor)**

The shaders comment "recomputing **view-space depth** per-fragment" but compute **radial
distance**:

```metal
float fragViewSpaceDepth = distance(in.worldPosition, sceneConstants.cameraPosition);
```

`cascadeSplitDepths` are per-cascade far **view-space depths** (PSSM splits of near→far).
Radial distance ≥ view-z, so fragments near the screen edges select a later (coarser) cascade
slightly early; the out-of-bounds fallthrough in `Lighting::CalculateShadow` absorbs the
mismatch, and the rotation-invariant bounding-sphere fitting makes a radial metric arguably
*more* consistent with cascade coverage. So: either metric is defensible — but pick one story
and fix the comments (or compute true view-z: `(sceneConstants.viewMatrix * float4(in.worldPosition,1)).z`,
one extra mat4·vec4 per fragment). Low priority; no visible artifact expected either way.

**Fix (true view-z)** — the recommended story (diffs added 2026-08-16, written against the
tree at `80d8f50`; supersedes the parenthetical costing above). Two facts found while
closing C6/C8/C9/C13 tip "either metric is defensible" toward view-z:

- The "one extra mat4·vec4" price only applies to the tiled files. The single-pass
  `ColorInOut` already interpolates `eye_position`, so both `GBuffer.metal` sites get true
  view-z as a component read — *cheaper* than the current `distance()`, which pays a sqrt.
- The mismatch isn't selection-only: `CalculateShadow`'s cross-fade compares the same
  `fragViewSpaceDepth` against `cascadeSplitDepths` spans, so a radial metric also starts
  each 10% blend early at screen edges. View-z additionally restores a by-construction
  guarantee: a slice's bounding sphere contains every fragment of that slice, so the
  depth-selected cascade always covers its fragment (texel snap aside — the fallthrough's
  job). Radial selection promotes edge fragments into the *next* slice's cascade, where
  coverage rests on box overlap instead.

`GBuffer.metal`, same change in both fragments (`gbuffer_fragment_base` and
`gbuffer_fragment_material`):

```diff
-    // Cascade-aware shadow, recomputing view-space depth per-fragment.
-    float fragViewSpaceDepth = distance(in.worldPosition, sceneConstants.cameraPosition);
+    // Cascade-aware shadow. eye_position is already interpolated, so true
+    // view-space depth (the metric cascadeSplitDepths is defined in) is a
+    // component read; the old radial distance() paid a sqrt and promoted
+    // screen-edge fragments into coarser cascades slightly early.
+    float fragViewSpaceDepth = in.eye_position.z;
```

`TiledDeferredGBuffer.metal` (`VertexOut` carries no eye-space position, so derive from
`worldPosition`; only `.z` is consumed, so the compiler folds the mat4·vec4 to one dot4):

```diff
-    // Per-fragment view-space depth from the perspective-correctly interpolated
-    // worldPosition. worldPos - cameraPos is Sterbenz-exact in float32 for
-    // visible fragments, avoiding the precision collapse of writing it per-vertex.
-    float fragViewSpaceDepth = distance(in.worldPosition, sceneConstants.cameraPosition);
+    // Per-fragment view-space depth (the metric cascadeSplitDepths is defined
+    // in), derived from the perspective-correctly interpolated worldPosition
+    // rather than a per-vertex interpolant (precision); only .z is consumed,
+    // so the multiply folds to a dot4.
+    float fragViewSpaceDepth = (sceneConstants.viewMatrix * float4(in.worldPosition, 1)).z;
```

`TiledMSAAGBuffer.metal` (same one-liner, no comment in place today):

```diff
-    float fragViewSpaceDepth = distance(in.worldPosition, sceneConstants.cameraPosition);
+    float fragViewSpaceDepth = (sceneConstants.viewMatrix * float4(in.worldPosition, 1)).z;
```

No `Lighting.metal` change: `SelectCascade`'s parameter/comment and the blend logic already
say view-space depth — this fix makes the call sites match them. Expected visual delta:
none, except marginally sharper shadows at screen edges near cascade boundaries (fragments
hold the finer cascade to the defined split). If the radial story is preferred instead, the
honest minimum is renames, not just comments: `fragViewSpaceDepth` → `fragCameraDistance`
at all four sites, `SelectCascade`'s parameter + doc comment, and the
`VertexOut.worldPosition` struct comment ("fragment derives viewSpaceDepth",
ShaderDefinitions.h:86).

---

### C13 ✅ FIXED — Tiled point lights ignore surface albedo

> **Fixed in `80d8f50` (2026-08-16):** `material.color = gBuffer.albedo` as the diff below,
> so `CalculatePointLighting`'s `light.color * material.color.xyz` tints by the surface. The
> `*= 0.9` fudge was removed entirely (the "tuning call" below, resolved by dropping it).
> §6 step 5's visual check (a large-radius point light under TiledDeferred) is now
> meaningful — with C14's PSO bind already fixed, it applies to the MSAA renderers too.

**File:** `TiledDeferredPointLight.metal:49-55` — **CONFIRMED**

```metal
MaterialProperties material {
    .color = 1                       // white — gBuffer.albedo never read
};
float3 color = Lighting::CalculatePointLighting(lightDatas[in.instanceId], worldPosition, normal, material);
color *= 0.9;                        // magic constant
```

*(Snippet and diff updated after `e086508` removed the P1-related local `LightData` copy here;
the albedo and 0.9 issues remain open.)*

Point-light contribution isn't tinted by the surface it hits (a red sphere under a white point
light glows white). Fix:

```diff
     MaterialProperties material {
-        .color = 1
+        .color = gBuffer.albedo
     };
-    float3 color = Lighting::CalculatePointLighting(lightDatas[in.instanceId], worldPosition, normal, material);
-    color *= 0.9;
+    float3 color = Lighting::CalculatePointLighting(lightDatas[in.instanceId],
+                                                    worldPosition, normal, material);
```

(Whether to keep the 0.9 fudge is a tuning call; if kept, name it.)

---

### C14 ✅ FIXED — MSAA renderers never bind the point-light PSO (stage ran on the directional pipeline)

> **Fixed in `cc06a3c` (2026-08-13):** both MSAA renderers now bind `.TiledMSAAPointLight`
> in `encodePointLightStage` (`TiledDeferredRenderer` already bound its equivalent).

**Files:** `TiledMSAATessellatedRenderer.swift` / `TiledMultisampleRenderer.swift`
(`encodePointLightStage`) — **CONFIRMED**. Found 2026-08-13 while visually verifying C5/C10;
a renderer-side encode bug, outside the original shader review's scope but blocking all of
its point-light fixes.

`encodePointLightStage` called `DrawManager.DrawPointLights(...)` without setting any
pipeline, and `DrawManager.Draw` deliberately never sets pipelines — PSO state is the
caller's job. The volumes therefore drew with `.TiledMSAADirectionalLight` still bound from
the immediately preceding stage:

- vertex = `tiled_deferred_vertex_quad`, which indexes a **6-entry** constant array with
  `[[vertex_id]]` — the indexed icosahedron draw feeds it index values 0–11, so half the
  fetches read **out of bounds** (undefined behavior, garbage triangles);
- fragment = the directional-light fragment, re-running sun lighting wherever those
  triangles landed (a visually near-idempotent rewrite, which is why the stage always read
  as a no-op);
- the actual point-light shaders (`tiled_deferred_point_light_vertex/fragment`) **never
  executed** in either MSAA renderer — point lights have been a silent no-op there since the
  stage was written, and shader-side fixes (C5/C10/C13) are unobservable in these renderers
  without this bind.

`TiledMSAAPointLightPipelineState` had existed in the library the whole time — correct
shader pair, additive blending, `rasterSampleCount = 4` — with zero call sites.

**Fix** (as landed, both renderers):

```diff
     func encodePointLightStage(using renderEncoder: MTLRenderCommandEncoder) {
+        // DrawManager never sets pipelines — without this bind the volumes draw on the
+        // directional-light PSO left over from the previous stage (quad vertex shader,
+        // out-of-bounds vertex fetches, and the point-light shaders never run).
+        setRenderPipelineState(renderEncoder, state: .TiledMSAAPointLight)
         DrawManager.DrawPointLights(with: renderEncoder)
     }
```

---

## 2. Performance findings

### P1 ✅ FIXED — ~700-byte `LightData` structs copied by value per fragment

> **Fixed in `e086508` (2026-08-12):** both `Lighting.metal` signatures now take
> `constant LightData &`, and `TiledDeferredPointLight.metal` passes
> `lightDatas[in.instanceId]` directly instead of through a local copy. Verified: all call
> sites bind to `constant` lvalues, all shaders compile standalone, macOS Debug build passes.
> The one remaining by-value copy (`GetPhongIntensity:29`) is dead code slated for deletion
> under D6. Original finding kept below for the record.

**Files:** `Lighting.metal:62, 213`, `TiledDeferredPointLight.metal:53` (and the dead
`GetPhongIntensity` at line 29) — **CONFIRMED**

`LightData` is ~700 bytes (7 × `float4x4` incl. the 4 cascade matrices, plus vectors/arrays).
These signatures force a full copy out of `constant` memory into thread storage per fragment
per light:

```metal
static float3 CalculateDirectionalLighting(LightData light, float3 normal, MaterialProperties material)
static float3 CalculatePointLighting(LightData light, float3 fragmentWorldPosition, ...)
```

On TBDR hardware that's register pressure → occupancy loss in exactly the fragment shaders
that run full-screen. The shadow path already does this right (`constant LightData &light`).

```diff
--- a/ToyFlightSimulator Shared/Graphics/Shaders/Lighting.metal
+++ b/ToyFlightSimulator Shared/Graphics/Shaders/Lighting.metal
@@
-    static float3 CalculateDirectionalLighting(LightData light, float3 normal, MaterialProperties material) {
+    static float3 CalculateDirectionalLighting(constant LightData &light,
+                                               float3 normal,
+                                               MaterialProperties material) {
@@
-    static float3 CalculatePointLighting(LightData light,
+    static float3 CalculatePointLighting(constant LightData &light,
                                          float3 fragmentWorldPosition,
                                          float3 normal, MaterialProperties material) {
```

Call sites: `TiledDeferredDirectionalLight.metal:52` already passes a `constant` ref ✓;
`TiledDeferredPointLight.metal:53-54` must drop its local copy (done in `e086508`).
`MaterialProperties` (~64 B) by value is fine.

### P2 ✅ FIXED — Skinning: blend the matrix once instead of eight matrix·vector transforms

> **Fixed in `b4fb581` (2026-08-12)** as part of the E1 extraction: each animated vertex now
> computes one `skinMatrix` via `BlendJointMatrix` and reuses it for position and normal.

**Files:** all five skinned vertex functions (see E1) — the current pattern does 8 `float4x4 * float4`
multiplies (4 for position, 4 for normal) plus vector blends. Blending the palette matrix
first is mathematically identical for linear-blend skinning and does 4 matrix-scale-adds + 2
transforms, and it extends to tangents for free (fixes the unskinned-tangent gap from C7):

```metal
float4x4 skin = weights.x * jointMatrices[joints.x] +
                weights.y * jointMatrices[joints.y] +
                weights.z * jointMatrices[joints.z] +
                weights.w * jointMatrices[joints.w];
position = skin * position;
normal   = skin * normal;
```

This lands automatically with the E1 extraction.

### P3 ✅ FIXED — `worldPosition.xyz / worldPosition.w` after an affine model transform

> **Fixed in `ab04296` (2026-08-17):** all seven listed sites are now plain
> `worldPosition.xyz`; a tree-wide grep confirms no `/ worldPosition.w` remains. The
> animated vertices are exact too, not just approximately so: `BlendJointMatrix` blends
> affine joint matrices with weights summing to 1, so the skinned position's w is still
> exactly 1 when the (affine) modelMatrix sees it. Verified: all five files compile
> standalone via `xcrun metal -c`; macOS Debug build passes. No visual delta expected.

**Files:** `GBuffer.metal:54,99`, `TiledDeferredGBuffer.metal:30,75`,
`TiledDeferredTransparency.metal:26`, `SinglePassDeferredTransparency.metal:26,68`

`modelMatrix` is affine — `worldPosition.w` is exactly 1 — so the divide is dead weight in
seven vertex shaders. Replace with `worldPosition.xyz`. (Micro, but it's also *clarity*: the
divide implies a projective transform that isn't there.)

### P4 ✅ FIXED — Redundant normalize chains between vertex and fragment stages

> **Fixed in `ab04296` (2026-08-17):** vertex-stage `normalize()` removed from
> `GBuffer.metal`'s T/B/N (both vertices; the bitangent handedness negation preserved) and
> `Base.metal`'s `surfaceNormal`/`surfaceTangent`/`surfaceBitangent` (both vertices).
> Every fragment consumer was verified to renormalize: `gbuffer_fragment_base` and the
> material fragment's no-map fallback (`normalize(in.normal)`), the mapped path via
> `ApplyNormalMapEye`'s final normalize — the interpolants now carry the normalMatrix's
> uniform scale (rigid + uniform-scale model matrices only, per C8's note), common to all
> three vectors, so it cancels there and the resulting direction is unchanged — and
> `base_fragment`/`material_fragment` (`normalize(rd.surfaceNormal)`; the tangent fields
> feed only commented-out code). `worldNormal` was never vertex-normalized and its consumer
> `SlopeScaledWorldBias` normalizes internally. Comments at both vertex sites and on
> `ApplyNormalMapEye` now record the cross-stage contract (and why the Eye variant skips
> the World variant's per-input renormalization). `Instanced.metal` untouched — dead (D1).
> Verified: compiles standalone; macOS Debug build passes.

**File:** `GBuffer.metal:57-59, 102-104` — the vertex stage normalizes T/B/N, converts to
`half3`, and the fragment renormalizes anyway (it must — interpolation denormalizes).
Normalize once, in the fragment. Same pattern in `Base.metal` (`base_fragment` renormalizes
`surfaceNormal`).

### P5 ✅ FIXED — Particle kernel round-trips device memory ~14 times per thread

> **Fixed in `c1c6d81` (2026-08-18):** `compute_particle` now snapshots
> `Particle p = particles[id]` once and does all integration/lifetime math on the local
> copy — landed standalone, ahead of C11 rather than folded into its diff. One deliberate
> narrowing vs. the "store once" prescription below: the write-back stores only the three
> mutated fields (`position`, `age`, `scale`), NOT the whole struct.
> `ParticleEmitter.emit()` (update thread) writes fresh spawns into this same
> shared-storage buffer while earlier frames' dispatches are still in flight, and the
> dispatch covers all `particleCount` slots, born or not — a whole-struct store losing
> that pre-existing birth-frame race would stomp the spawn's CPU-only fields
> (direction/speed/life/color/…) with stale pre-spawn data, permanently deadening the
> slot, where the old write set loses only {position, age, scale} and self-heals on the
> next pass. Both constraints are commented at the store site. The commented-out cos/sin
> velocity experiment was deleted in passing. C11 (deltaTime) remains open and composes
> on top. Verified: compiles standalone via `xcrun metal -c`; macOS Debug build passes.

**File:** `Particles.metal:19-41` — every `particles[id].field` access is a device-memory
dereference the compiler can't always coalesce through the write aliasing. Load `Particle p`
once, mutate locally, store once (folded into C11's diff).

### P6 Fat interpolant structs on trivial passes

`RasterizerData` (ShaderDefinitions.h:34-50) carries ~15 fields; `skysphere_vertex` populates
3 of them and `quad_pass_vertex` populates 1, but every pass pays the struct's interpolation
cost unless the compiler's cross-stage elimination catches it (worth confirming in a GPU
capture). Slimmer per-pass structs (a `SkyVertexOut` with position+uv) are cheap insurance and
document the actual contract.

*(E6's landing (`5bc2e21`) deleted `quad_pass_vertex` — the worst offender here, paying for
all ~15 fields to populate 1 and read none. `skysphere_vertex`'s 3-of-15 is what remains of
this finding.)*

### P7 ✅ FIXED — Five different full-screen-pass mechanisms

Full-screen passes exist in five flavors: 6-vertex constant-array quad ×2
(`Composition.metal:12-19`, `TiledDeferredDirectionalLight.metal:14-21`), 3-vertex
super-triangle (`OrderIndependentTransparency.metal:28-39`), vertex-buffer quad
(`DirectionalLight.metal:20-33` via `TFSSimpleVertex`), and a full mesh with vertex descriptor
(`Final.metal:18-25`). Consolidating on one 3-vertex full-screen triangle (E6) removes two
buffer bindings, a vertex descriptor, and 3 vertices of redundant work — trivial GPU savings,
real maintenance savings.

**✅ FIXED in `5bc2e21` (2026-08-18)** via E6's conversion diff set — shader-side call
sites, the Swift-side ShaderLibrary/PSO/draw edits, and a per-site cull/winding audit
(see E6's banner and diffs). (Found while staging: the OIT "3-vertex" pass was actually
drawn with `vertexCount: 6` — vids 3–5 collapse to a degenerate spare triangle. That
draw is now the shared bufferless `vertexCount: 3`.)

---

## 3. Common code to extract

The concrete proposal: one new shared header plus PSO-level function reuse. New file:

**`ToyFlightSimulator Shared/Graphics/Shaders/ShaderHelpers.h`** (imported after
`ShaderDefinitions.h`; `#import` keeps inclusion idempotent):

```metal
//
//  ShaderHelpers.h
//  ToyFlightSimulator
//
//  Shared inline helpers for vertex skinning, normal mapping, transparency,
//  full-screen passes, and deferred-lighting reconstruction.
//

#ifndef ShaderHelpers_h
#define ShaderHelpers_h

#include <metal_stdlib>
using namespace metal;

// ============================================================ E1: skinning
// Linear-blend skinning: blend the palette matrix once, then transform.
// Replaces the 8-transform pattern duplicated across 5 vertex functions.
inline float4x4 BlendJointMatrix(constant float4x4 *jointMatrices,
                                 ushort4 joints,
                                 float4 weights) {
    return weights.x * jointMatrices[joints.x] +
           weights.y * jointMatrices[joints.y] +
           weights.z * jointMatrices[joints.z] +
           weights.w * jointMatrices[joints.w];
}

// ====================================================== E4: normal mapping
// Decode a [0,1]-encoded tangent-space sample and rotate it onto the surface
// basis. World-space variant (tiled G-buffers):
inline float3 ApplyNormalMapWorld(half3 sampleRGB, float3 T, float3 B, float3 N) {
    float3 tn = normalize(float3(sampleRGB) * 2.0 - 1.0);
    return normalize(tn.x * normalize(T) + tn.y * normalize(B) + tn.z * normalize(N));
}

// Eye-space, half-precision variant (single-pass G-buffer):
inline half3 ApplyNormalMapEye(half3 sampleRGB, half3 T, half3 B, half3 N) {
    half3 tn = normalize(sampleRGB * 2.0h - 1.0h);
    return normalize(tn.x * T + tn.y * B + tn.z * N);
}

// ================================================= E3: transparency opacity
// Combine a sampled alpha with the material's opacity. Duplicated verbatim in
// 3 live fragments (+1 dead) before extraction.
inline float ResolveOpacity(float sampledAlpha, float materialOpacity) {
    if (sampledAlpha < 1.0 && materialOpacity < 1.0) {
        return max(sampledAlpha, materialOpacity);
    }
    return min(sampledAlpha, materialOpacity);
}

// ================================================== E5: base-color resolve
// The objectColor → texture → fallback cascade duplicated in 7 fragments.
inline float4 ResolveBaseColor(bool useObjectColor,
                               float4 objectColor,
                               float4 fallbackColor,
                               texture2d<half> baseColorMap,
                               sampler s,
                               float2 uv) {
    if (useObjectColor)                  { return objectColor; }
    if (!is_null_texture(baseColorMap))  { return float4(baseColorMap.sample(s, uv)); }
    return fallbackColor;
}

// ============================================== E7: eye-space reconstruction
// Scale the interpolated view ray so its z equals the G-buffer eye-space depth.
// (The correct form already used by PointLights.metal; DirectionalLight.metal
// had normalize(ray)*depth, which is wrong — see C4.)
inline float3 ReconstructEyePosition(float3 eyeRay, float eyeSpaceDepth) {
    return eyeRay * (eyeSpaceDepth / eyeRay.z);
}

// ===================================================== E6: full-screen pass
struct FullScreenVertexOut {
    float4 position [[ position ]];
    float2 uv;
};

// One super-triangle covering the screen; emit with drawPrimitives(.triangle,
// vertexCount: 3), no vertex buffer / descriptor. uv is [0,1] with y down
// (texture convention). NOTE: verify winding against the pass's cull mode —
// full-screen passes should disable culling or match setFrontFacing(.clockwise).
inline FullScreenVertexOut FullScreenTriangleVertex(uint vid) {
    FullScreenVertexOut out;
    float2 ndc = float2(vid == 1 ? 3.0 : -1.0,
                        vid == 2 ? -3.0 : 1.0);
    out.position = float4(ndc, 0, 1);
    out.uv = float2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
    return out;
}

#endif /* ShaderHelpers_h */
```

### E1 ✅ FIXED — Skinning: 5 duplicated blocks → `BlendJointMatrix`

> **Fixed in `b4fb581` (2026-08-12):** `ShaderHelpers.h` added with `BlendJointMatrix`; all
> five sites below converted to the blend-once `skinMatrix` form (which is also P2). The
> `jointMatrices != nullptr` guards were dropped after verifying the DrawManager invariant:
> `SetupAnimation` binds the palette before switching to an animated PSO and restores the
> pass PSO before unbinding, so the guard was unreachable. **Caveat vs. the text below:** the
> application was a pure consolidation — output fields were not touched, so C7 (unskinned
> `worldNormal` in the tiled animated vertex) was left open by that commit and subsequently
> fixed in `d1b3286`. Verified: identical math (matrix-vector products are linear in
> the matrix), all shaders compile standalone, macOS Debug build passes.

The identical 12-line skinning block appears in:

| File | Function | Skins |
|---|---|---|
| `Base.metal:54-67` | `base_animated_vertex` | pos + normal |
| `GBuffer.metal:76-89` | `gbuffer_animated_vertex` | pos + normal |
| `TiledDeferredGBuffer.metal:53-66` | `tiled_deferred_gbuffer_animated_vertex` | pos + normal |
| `SinglePassDeferredTransparency.metal:47-60` | `..._transparency_animated_vertex` | pos + normal |
| `Shadow.metal:44-52` | `shadow_animated_vertex` | pos only |

Representative diff (`Shadow.metal`; the other four are the same shape and also gain skinned
normals/tangents where relevant, fixing C7):

```diff
--- a/ToyFlightSimulator Shared/Graphics/Shaders/Shadow.metal
+++ b/ToyFlightSimulator Shared/Graphics/Shaders/Shadow.metal
@@
 #import "ShaderDefinitions.h"
+#import "ShaderHelpers.h"
@@ vertex ShadowOutput shadow_animated_vertex(...)
     ModelConstants modelInstance = modelConstants[instanceId];
     float4 position = float4(in.position, 1.0);
-    
-    // Hope this works, ugh...
-    if (jointMatrices != nullptr) {
-        float4 weights = in.jointWeights;
-        ushort4 joints = in.joints;
-        
-        position = weights.x * (jointMatrices[joints.x] * position) +
-                weights.y * (jointMatrices[joints.y] * position) +
-                weights.z * (jointMatrices[joints.z] * position) +
-                weights.w * (jointMatrices[joints.w] * position);
-    }
+    position = BlendJointMatrix(jointMatrices, in.joints, in.jointWeights) * position;
```

Note on the dropped `if (jointMatrices != nullptr)`: null-checking a `constant T*` argument
is not a defined Metal idiom (an unbound buffer is undefined, not nil). These animated PSOs
are only ever encoded for skinned meshes and DrawManager binds the joint palette for them, so
the guard is dead weight; if a belt-and-braces guard is wanted, make it a function constant.

### E2 PSO-level dedup — three byte-identical vertex/fragment pairs

`single_pass_deferred_transparency_vertex` ≡ `tiled_deferred_transparency_vertex` and
`single_pass_deferred_transparency_fragment` ≡ `tiled_deferred_transparency_fragment`
(byte-identical bodies and identical binding layouts; `SinglePassDeferredTransparency.metal`
additionally has the animated variant). The static G-buffer vertex
`tiled_deferred_gbuffer_vertex` is likewise identical to the transparency vertex.

The project already has precedent: `TiledMSAAPipeline.swift:50-51` reuses the TiledDeferred
functions rather than duplicating them. Do the same here — point the single-pass transparency
PSO at the tiled functions and delete the duplicates:

```diff
--- a/ToyFlightSimulator Shared/Graphics/Libraries/Pipelines/Render/SinglePassDeferredPipeline.swift
+++ b/ToyFlightSimulator Shared/Graphics/Libraries/Pipelines/Render/SinglePassDeferredPipeline.swift
@@ (transparency PSO descriptor)
-            descriptor.vertexFunction = Graphics.Shaders[.SinglePassDeferredTransparencyVertex]
-            descriptor.fragmentFunction = Graphics.Shaders[.SinglePassDeferredTransparencyFragment]
+            descriptor.vertexFunction = Graphics.Shaders[.TiledDeferredTransparencyVertex]
+            descriptor.fragmentFunction = Graphics.Shaders[.TiledDeferredTransparencyFragment]
```

then delete `SinglePassDeferredTransparency.metal` (moving its *animated* vertex — the one
function without a tiled twin — into `TiledDeferredTransparency.metal`), and remove the
orphaned `ShaderLibrary` keys. Net: −~100 lines and one source of truth for transparency.

### E3 ✅ FIXED — Opacity resolve — 4 duplicated blocks → `ResolveOpacity`

> **Fixed in `5105324` (2026-08-14):** all four sites converted (E2 hasn't landed, so the
> pre-E2 site list applied — three live + one dead). The OIT half variant got no dedicated
> half overload: its half alpha promotes through the float helper and narrows back on
> assignment, which selects the same branch (the old code compared `material.opacity` as
> float too) and agrees to half rounding.

Sites: `SinglePassDeferredTransparency.metal:98-102`, `TiledDeferredTransparency.metal:56-60`,
`TiledMSAATransparency.metal:42-46` (dead file), `OrderIndependentTransparency.metal:123-127`
(half variant). After E2, two live sites remain:

```diff
--- a/ToyFlightSimulator Shared/Graphics/Shaders/TiledDeferredTransparency.metal
@@
-    if (color.a < 1.0 && material.opacity < 1.0) {
-        color.a = max(color.a, material.opacity);
-    } else {
-        color.a = min(color.a, material.opacity);
-    }
+    color.a = ResolveOpacity(color.a, material.opacity);
```

### E4 ✅ FIXED — Normal-map decode + TBN — the helper C1/C6 use

> **Fixed in `fad8684` (2026-08-14):** as the diffs below — `ApplyNormalMapWorld` added
> above its eye twin (doc comment included) and `gbuffer_fragment_material` converted to the
> collapsed sample-path-only form (texture path agrees with the old math to half rounding;
> the fallback-path behavior change IS C6's material-fragment fix, so C6 is now half-fixed).
> Scope per this section's own carve-outs: the tiled call site was NOT converted — that
> conversion is exactly C1's Fix diff and stayed with C1 (landed in `0ec59ea`, 2026-08-15,
> making `ApplyNormalMapWorld` live) — and `gbuffer_fragment_base` (C6's other half,
> no helper involved) followed in `80d8f50` (2026-08-16), completing C6. Verified:
> `GBuffer.metal` compiles standalone
> (type-checking both helpers); macOS Debug build passes. §6 step 2's visual check (the
> normal-mapped F-22 per renderer) unblocked once C1 landed.

Live call sites after fixes: `TiledDeferredGBuffer.metal` (world variant),
`GBuffer.metal` `gbuffer_fragment_material` (eye variant), and `Tessellation.metal`'s
G-buffer fragment once terrain gets a real TBN. This is the one extraction that *fixes bugs by
existing* — today one file decodes-but-shouldn't (C6) while another should-but-doesn't (C1);
a single named helper makes the convention impossible to miss.

**Diffs** (added 2026-08-14, written against the tree at `5105324`, i.e. after the E3/E5
conversion; both call-site files already `#import "ShaderHelpers.h"`).

`b4fb581` staged only the eye variant, so `ApplyNormalMapWorld` lands with this finding,
slotted above its eye twin:

```diff
--- a/ToyFlightSimulator Shared/Graphics/Shaders/ShaderHelpers.h
+++ b/ToyFlightSimulator Shared/Graphics/Shaders/ShaderHelpers.h
@@
+// Decode a [0,1]-encoded tangent-space normal-map sample and rotate it onto the
+// interpolated surface basis. World-space float variant for the tiled G-buffer,
+// whose T/B/N interpolants are float3 in world space. Each basis vector is
+// renormalized: interpolation denormalizes them unevenly, which reweights the
+// tangent-space components — a skew that normalizing only the combined result
+// would keep.
+inline float3 ApplyNormalMapWorld(half3 sampleRGB, float3 T, float3 B, float3 N) {
+    float3 tn = normalize(float3(sampleRGB) * 2.0 - 1.0);
+    return normalize(tn.x * normalize(T) + tn.y * normalize(B) + tn.z * normalize(N));
+}
+
 // Decode a [0,1]-encoded tangent-space normal-map sample and rotate it onto the
 // interpolated surface basis. Eye-space half-precision variant for the
 // single-pass deferred G-buffer, whose T/B/N interpolants are half3 in eye
```

(The eye variant deliberately does *not* renormalize T/B/N — that keeps the C6 conversion
below equivalent-to-half-rounding with the existing single-pass math on the texture path. If
the asymmetry ever bothers, change it as its own tuning commit, not inside the extraction.)

**Tiled call site** (`TiledDeferredGBuffer.metal`): the conversion is exactly C1's Fix diff,
landed with C1 in `0ec59ea` (2026-08-15). `VertexOut` already carried
`worldTangent`/`worldBitangent` (float3, ShaderDefinitions.h:88–89), populated by both the
static and animated vertices (skinned since `d1b3286`/C7) — the fragment finally reads them.

**Single-pass call site** (`GBuffer.metal` `gbuffer_fragment_material`): the collapsed form of
C6's material fix. `normal_sample` has no consumer besides the decode (`eye_normal` alone
feeds `normal_shadow`), so the sample-vs-fallback cascade and the unconditional decode fuse
into one branch:

```diff
--- a/ToyFlightSimulator Shared/Graphics/Shaders/GBuffer.metal
+++ b/ToyFlightSimulator Shared/Graphics/Shaders/GBuffer.metal
@@ fragment GBufferData gbuffer_fragment_material(...)
-    half4 normal_sample;
     half specular_contrib;
 
-    if (!in.useObjectColor && !is_null_texture(normalMap)) {
-        normal_sample = normalMap.sample(sampler2d, normalUV);
-    } else {
-        normal_sample = half4(in.normal, 1.0);
-    }
+    // Decode + TBN only on the sample path (fixes C6): the interpolated
+    // geometric normal is already in [-1,1] and must skip the *2-1 decode.
+    half3 eye_normal;
+    if (!in.useObjectColor && !is_null_texture(normalMap)) {
+        eye_normal = ApplyNormalMapEye(normalMap.sample(sampler2d, normalUV).xyz,
+                                       in.tangent, in.bitangent, in.normal);
+    } else {
+        eye_normal = normalize(in.normal);
+    }
 
     if (!in.useObjectColor && !is_null_texture(specularMap)) {
         specular_contrib = specularMap.sample(sampler2d, specularUV).r;
     } else {
         specular_contrib = 1.0;
     }
-    
-    // Calculate normal in eye space
-    half3 tangent_normal = normalize((normal_sample.xyz * 2.0) - 1.0);
-    half3 eye_normal = normalize(tangent_normal.x * in.tangent +
-                                 tangent_normal.y * in.bitangent +
-                                 tangent_normal.z * in.normal);
```

On the texture path this matches the old math to half rounding (the old `* 2.0` promoted
through float and narrowed back; the helper stays in half — the TBN combine and final
normalize are identical). On the fallback path it *changes* behavior — that is C6's fix, the
point of the exercise.

Not converted by E4: `gbuffer_fragment_base` (C6's other half) has no normal map at all — its
fix is plain `normalize(in.normal)` with the decode/TBN deleted, no helper involved
(applied in `80d8f50`, 2026-08-16). And
`Tessellation.metal`'s raw-sample normal write (noted under C10) can't call the helper until
the terrain pipeline produces tangents. Verification is §6 step 2's: the normal-mapped F-22
under TiledDeferred and SinglePassDeferred, before/after screenshots per renderer.

### E5 ✅ FIXED — Base-color cascade — 7 duplicated blocks → `ResolveBaseColor`

> **Fixed in `5105324` (2026-08-14):** all seven sites converted with their original
> fallbacks preserved. `ShaderHelpers.h` gained a second `ResolveBaseColor` overload for
> `texture2d<float>` — Base.metal and the OIT material fragment bind float-element
> base-color textures while the other five bind `texture2d<half>`, and MSL textures don't
> implicitly convert between element types. `gbuffer_fragment_material` wraps the float4
> result back to `half4` (exact round trip on the sample path).
> `TiledMSAATransparency.metal`'s cascade was deliberately left: its `texture2d_ms` can't
> bind to the helper, the file is dead (D3), and it was never on this finding's site list.

The `useObjectColor → texture sample → fallback` cascade appears in
`GBuffer.metal:176-182` (fallback `in.color`), `TiledDeferredGBuffer.metal:105-109`
(fallback `material.color`), `TiledMSAAGBuffer.metal:34-38` (dead),
`SinglePassDeferredTransparency.metal:92-96`, `TiledDeferredTransparency.metal:50-54`,
`OrderIndependentTransparency.metal:93-97`, `Base.metal:114-118`. Example:

```diff
--- a/ToyFlightSimulator Shared/Graphics/Shaders/TiledDeferredGBuffer.metal
@@
-    float4 color = material.color;
-
-    if (in.useObjectColor) {
-        color = in.objectColor;
-    } else if (!is_null_texture(baseColorTexture)) {
-        color = float4(baseColorTexture.sample(sampler2d, baseUV));
-    }
+    float4 color = ResolveBaseColor(in.useObjectColor, in.objectColor,
+                                    material.color, baseColorTexture, sampler2d, baseUV);
```

### E6 ✅ FIXED — Full-screen pass — 5 mechanisms → 1 shared triangle

**✅ FIXED in `5bc2e21` (2026-08-18).** The staged diffs below landed essentially
verbatim, with the Swift draw sites going through one shared
`RenderPassEncoding.drawFullScreenTriangle(with:)` helper instead of five inline
`drawPrimitives` calls. One landing lesson worth keeping: the Final PSO's
`vertexDescriptor = .Simple` deletion is load-bearing, not cosmetic — the debug layer
validates every draw against the pipeline's descriptor layouts even when the vertex
function has no `[[stage_in]]`, so leaving it in produced
`missing vertexDescriptor Buffer binding at index 0` the moment the draw went
bufferless. One behavioral footnote beyond the equivalence list: the OIT blend geometry
moves from z = 1 (`quad_pass_vertex` set `position.zw = 1`) to the helper's z = 0 —
inert under that stage's `AlwaysNoWrite` depth state. The `SetScene` `.Quad` warm-up
note below was applied. Verified by macOS Debug build and on-screen runs with the
validation layer (OIT explicitly confirmed); the six-renderer screenshot sweep from
the notes remains optional.

Replace, in order of ease:
1. `TiledDeferredDirectionalLight.metal:14-32` (`tiled_deferred_vertex_quad` + constant array) — direct swap, position-only.
2. `Composition.metal:12-40` (`compositeVertexShader` + its own quad + y-flip) — swap; its fragment keeps sampling with `in.uv`.
3. `OrderIndependentTransparency.metal:28-39` (`quad_pass_vertex`) — swap; stops abusing the fat `RasterizerData` as a position-only varying (P6).
4. `Final.metal` — also drop the Quad mesh + vertex descriptor from its PSO Swift-side, and delete the per-fragment `1 - uv.y` flip (the helper's uv is already texture-oriented).
5. `DirectionalLight.metal` — keep a specialized shader (it needs the eye ray from `projectionMatrixInverse`), but build it on `FullScreenTriangleVertex` + its own eye-ray computation, dropping the `TFSSimpleVertex` buffer.

Each conversion needs its `drawPrimitives` call to use `vertexCount: 3` and no vertex buffer;
verify cull mode as noted in the helper comment.

**Fix diffs** (added 2026-08-18, written against the tree at `a86ef83`; landed in
`5bc2e21` — this section and P7 closed together). Design: ONE shared vertex entry point,
`full_screen_vertex`, homed in `Composition.metal` (the file keeps its composite fragment, so
it becomes "the full-screen file"), bound by all five generic full-screen PSOs — Composite,
Final, OIT Blend, and both tiled directional lights. Only the single-pass directional light
keeps a specialized vertex (it interpolates the eye ray), rebuilt on
`FullScreenTriangleVertex`. The old `.FinalVertex`/`.QuadPassVertex`/`.TiledDeferredQuadVertex`/
`.CompositeVertex` keys collapse into one `.FullScreenVertex`.

Pre-verified equivalences — why the expected visual delta is **none**:

- **Composite uv is algebraically identical.** At post-flip NDC `(x, y)` the old shader's
  uv is `((x+1)/2, (1−y)/2)` (it computes uv from the pre-flip position); the helper emits
  `((x+1)/2, 0.5 − y/2)` — the same expression, so the drawable composite is bit-identical.
- **Final's `1 − uv.y` flip is absorbed.** The helper's uv is already texture-oriented
  (uv (0,0) at NDC top-left), which is exactly what the old flip manufactured from the Quad
  mesh's bottom-left-origin texcoords. The fragment samples `rd.uv` directly.
- **The single-pass eye ray is unchanged.** The old quad and the helper both emit
  `z = 0, w = 1`, so `projectionMatrixInverse * position` is the same function of NDC x/y,
  and with clip w ≡ 1 interpolation is exactly linear — off-screen vertices at ±3 NDC
  interpolate to the identical per-pixel values the quad produced.
- **The tiled directional fragment reads no varyings**, so retyping its `[[stage_in]]` from
  the position-only `VertexQuadOut` to `FullScreenVertexOut` costs nothing — Metal compiles
  the vertex/fragment pair together per PSO and dead-strips the unused uv interpolant.
- **OIT was already a super-triangle, drawn badly.** `quad_pass_vertex`'s formula sends
  vids 3–5 all to `(-1, 1)` — the existing `vertexCount: 6` draw rasterizes the 3-vertex
  triangle plus one degenerate zero-area spare (P7's list understates this one: the
  *mechanism* was already a super-triangle; only the draw call never got the memo).

Cull/winding audit (resolving the helper comment's "verify per pass" note — the helper
triangle is **clockwise in window space**, matching every site that culls):

| Draw site | Cull state at draw time | Verdict |
|---|---|---|
| Single-pass directional (`SinglePassDeferredLightingRenderer`) | explicit `.back`; front = `.clockwise` persisting from `DrawManager.DrawOpaque` earlier in the same encoder | old quad was CW; helper CW ✓ |
| Tiled directional (all 3 renderers) | inherits `.clockwise`/`.back` from the G-buffer stage's `DrawOpaque` (same encoder) | old quad was CW; helper CW ✓ |
| OIT blend | explicit `setCullMode(.none)` | winding irrelevant ✓ |
| OIT final | fresh encoder, cull never set (default `.none`) | ✓ |
| Composite (late CB, all `LateDrawablePresenting` renderers) | fresh encoder, cull never set (default `.none`) | ✓ |

Metal side:

```diff
--- a/ToyFlightSimulator Shared/Graphics/Shaders/Composition.metal
+++ b/ToyFlightSimulator Shared/Graphics/Shaders/Composition.metal
@@
 #include <metal_stdlib>
 using namespace metal;
 
-/// The normalized device coordinates (NDC) for two triangles that form a full-screen quad.
-constant float2 quadVertices[] = {
-    float2(-1, -1),
-    float2(-1,  1),
-    float2( 1,  1),
-    float2(-1, -1),
-    float2( 1,  1),
-    float2( 1, -1)
-};
-
-/// A vertex format for drawing a full-screen quad.
-struct CompositionVertexOut {
-    float4 position [[position]];
-    float2 uv;
-};
-
-/// Outputs the normalized device coordinates (NDC) to render a full-screen quad based on the vertex ID.
-vertex CompositionVertexOut
-compositeVertexShader(unsigned short vid [[vertex_id]])
-{
-    const float2 position = quadVertices[vid];
-
-    CompositionVertexOut out;
-
-    out.position = float4(position, 0, 1);
-    out.position.y *= -1;
-    out.uv = position * 0.5f + 0.5f;
-
-    return out;
-}
+#import "ShaderHelpers.h"
+
+/// THE full-screen vertex stage (E6): every generic full-screen PSO binds this
+/// one function — composite, tiled directional light, OIT blend, OIT final.
+/// A pass needing extra varyings (the single-pass directional light's eye ray)
+/// builds its own vertex on FullScreenTriangleVertex instead.
+vertex FullScreenVertexOut full_screen_vertex(uint vid [[vertex_id]])
+{
+    return FullScreenTriangleVertex(vid);
+}
 
 /// Copies the input resolve texture to the output.
 fragment half4
-compositeFragmentShader(CompositionVertexOut in [[stage_in]],
+compositeFragmentShader(FullScreenVertexOut in [[stage_in]],
                         texture2d<half> resolvedTexture)
```

```diff
--- a/ToyFlightSimulator Shared/Graphics/Shaders/TiledDeferredDirectionalLight.metal
+++ b/ToyFlightSimulator Shared/Graphics/Shaders/TiledDeferredDirectionalLight.metal
@@
 #import "ShaderDefinitions.h"
+#import "ShaderHelpers.h"
 #import "Lighting.metal"
 
-constant float3 vertices[6] = {
-    float3(-1,  1,  0),    // triangle 1
-    float3( 1, -1,  0),
-    float3(-1, -1,  0),
-    float3(-1,  1,  0),    // triangle 2
-    float3( 1,  1,  0),
-    float3( 1, -1,  0)
-};
-
-struct VertexQuadOut {
-    float4 position [[ position ]];
-};
-
-vertex VertexQuadOut tiled_deferred_vertex_quad(uint vertexId [[ vertex_id ]]) {
-    VertexQuadOut out {
-        .position = float4(vertices[vertexId], 1)
-    };
-    return out;
-}
-
 fragment float4
-tiled_deferred_directional_light_fragment(         VertexQuadOut  in         [[ stage_in ]],
+tiled_deferred_directional_light_fragment(         FullScreenVertexOut in    [[ stage_in ]],
                                           constant LightData      &lightData [[ buffer(TFSBufferDirectionalLightData) ]],
                                                    GBufferOut     gBuffer) {
```

```diff
--- a/ToyFlightSimulator Shared/Graphics/Shaders/OrderIndependentTransparency.metal
+++ b/ToyFlightSimulator Shared/Graphics/Shaders/OrderIndependentTransparency.metal
@@
-// A vertex function that generates a full-screen quad pass:
-vertex RasterizerData quad_pass_vertex(uint vid [[ vertex_id ]]) {
-    float4 position;
-    position.x = (vid == 2) ? 3.0 : -1.0;
-    position.y = (vid == 0) ? -3.0 : 1.0;
-    position.zw = 1.0;
-    
-    RasterizerData out = {
-        .position = position
-    };
-    
-    return out;
-}
-
 kernel void init_transparent_fragment_store(...)
```

(`blend_fragments` takes no `[[stage_in]]` at all — imageblock + `color(0)` only — so the
Blend PSO just rebinds its vertex function; no fragment change. This deletion is also the
P6 fix for the worst offender: a fat `RasterizerData` with 14 undefined fields is no longer
smuggled through the rasterizer for a pass that reads none of them.)

```diff
--- a/ToyFlightSimulator Shared/Graphics/Shaders/Final.metal
+++ b/ToyFlightSimulator Shared/Graphics/Shaders/Final.metal
@@
 #import "ShaderDefinitions.h"
+#import "ShaderHelpers.h"
 
-struct FinalRasterizerData {
-    float4 position [[ position ]];
-    float2 textureCoordinate;
-};
-
-vertex FinalRasterizerData final_vertex(const VertexIn vIn [[ stage_in ]]) {
-    FinalRasterizerData rd = {
-        .position = float4(vIn.position, 1.0),
-        .textureCoordinate = float2(vIn.textureCoordinate)
-    };
-    
-    return rd;
-}
-
-fragment half4 final_fragment(const FinalRasterizerData rd [[ stage_in ]],
+fragment half4 final_fragment(const FullScreenVertexOut rd [[ stage_in ]],
                               texture2d<float> baseTexture [[ texture(0) ]]) {
     sampler s;
-    float2 textureCoordinate = rd.textureCoordinate;
-    textureCoordinate.y = 1 - textureCoordinate.y;  // Flip
-    float4 color = baseTexture.sample(s, textureCoordinate);
+    // FullScreenVertexOut.uv is already texture-oriented (y down); the old
+    // 1 - uv.y flip compensated the Quad mesh's bottom-left-origin texcoords.
+    float4 color = baseTexture.sample(s, rd.uv);
     
     return half4(color);
 }
```

```diff
--- a/ToyFlightSimulator Shared/Graphics/Shaders/DirectionalLight.metal
+++ b/ToyFlightSimulator Shared/Graphics/Shaders/DirectionalLight.metal
@@ vertex QuadInOut deferred_directional_lighting_vertex(...)
 vertex QuadInOut
-deferred_directional_lighting_vertex(constant TFSSimpleVertex * vertices       [[ buffer(TFSBufferIndexMeshVertex) ]],
-                                     constant SceneConstants  & sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
+deferred_directional_lighting_vertex(constant SceneConstants  & sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
                                      uint                       vid            [[ vertex_id ]])
 {
-    float4 position = float4(vertices[vid].position, 0, 1);
+    // Full-screen triangle (E6) instead of the old TFSSimpleVertex quad buffer;
+    // this pass keeps its own vertex only to interpolate the eye ray below.
+    float4 position = FullScreenTriangleVertex(vid).position;
     float4 unprojected_eye_coord = sceneConstants.projectionMatrixInverse * position;
```

```diff
--- a/ToyFlightSimulator Shared/Graphics/Shaders/TFSCommon.h
+++ b/ToyFlightSimulator Shared/Graphics/Shaders/TFSCommon.h
@@
-typedef struct {
-    vector_float2 position;
-} TFSSimpleVertex;
-    
 typedef struct {
     packed_float3 position;
 } TFSShadowVertex;
```

(`TFSSimpleVertex`'s only consumer was this pass pair, so it joins D7's Apple-sample
leftovers — deleted here rather than left to rot.)

Swift side — ShaderLibrary key collapse (4 keys → 1):

```diff
--- a/ToyFlightSimulator Shared/Graphics/Libraries/ShaderLibrary.swift
+++ b/ToyFlightSimulator Shared/Graphics/Libraries/ShaderLibrary.swift
@@ enum ShaderType
     case BaseVertex
     case InstancedVertex
     case SkySphereVertex
-    case FinalVertex
-    case QuadPassVertex
+    case FullScreenVertex
@@
     case TiledDeferredGBufferVertex
     case TiledDeferredGBufferFragment
-    case TiledDeferredQuadVertex
     case TiledDeferredDirectionalLightFragment
@@
-    case CompositeVertex
     case CompositeFragment
@@ makeLibrary()
-        _library.updateValue(Shader(functionName: "final_vertex"), forKey: .FinalVertex)
-        _library.updateValue(Shader(functionName: "quad_pass_vertex"), forKey: .QuadPassVertex)
+        _library.updateValue(Shader(functionName: "full_screen_vertex"), forKey: .FullScreenVertex)
@@
-        _library.updateValue(Shader(functionName: "tiled_deferred_vertex_quad"), forKey: .TiledDeferredQuadVertex)
         _library.updateValue(Shader(functionName: "tiled_deferred_directional_light_fragment"),
                              forKey: .TiledDeferredDirectionalLightFragment)
@@
-        _library.updateValue(Shader(functionName: "compositeVertexShader"), forKey: .CompositeVertex)
         _library.updateValue(Shader(functionName: "compositeFragmentShader"), forKey: .CompositeFragment)
```

PSO rebinds (5 sites; Final also drops its vertex descriptor — the whole point of item 4):

```diff
--- a/ToyFlightSimulator Shared/Graphics/Libraries/Pipelines/Render/BasicPipeline.swift
+++ b/ToyFlightSimulator Shared/Graphics/Libraries/Pipelines/Render/BasicPipeline.swift
@@ struct FinalRenderPipelineState
         createRenderPipelineState(label: "Final Render") { descriptor in
             descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
-            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
-            descriptor.vertexFunction = Graphics.Shaders[.FinalVertex]
+            descriptor.vertexFunction = Graphics.Shaders[.FullScreenVertex]
             descriptor.fragmentFunction = Graphics.Shaders[.FinalFragment]
--- a/ToyFlightSimulator Shared/Graphics/Libraries/Pipelines/Render/OrderIndependentTransparencyPipeline.swift
+++ b/ToyFlightSimulator Shared/Graphics/Libraries/Pipelines/Render/OrderIndependentTransparencyPipeline.swift
@@ struct BlendRenderPipelineState
             descriptor.vertexDescriptor = nil
-            descriptor.vertexFunction = Graphics.Shaders[.QuadPassVertex]
+            descriptor.vertexFunction = Graphics.Shaders[.FullScreenVertex]
             descriptor.fragmentFunction = Graphics.Shaders[.BlendFragment]
--- a/ToyFlightSimulator Shared/Graphics/Libraries/Pipelines/Render/TiledDeferredPipeline.swift
+++ b/ToyFlightSimulator Shared/Graphics/Libraries/Pipelines/Render/TiledDeferredPipeline.swift
@@ struct TiledDeferredDirectionalLightPipelineState
-            descriptor.vertexFunction = Graphics.Shaders[.TiledDeferredQuadVertex]
+            descriptor.vertexFunction = Graphics.Shaders[.FullScreenVertex]
--- a/ToyFlightSimulator Shared/Graphics/Libraries/Pipelines/Render/TiledMSAAPipeline.swift
+++ b/ToyFlightSimulator Shared/Graphics/Libraries/Pipelines/Render/TiledMSAAPipeline.swift
@@ struct TiledMSAADirectionalLightPipelineState
-            descriptor.vertexFunction = Graphics.Shaders[.TiledDeferredQuadVertex]
+            descriptor.vertexFunction = Graphics.Shaders[.FullScreenVertex]
@@ struct TiledMSAACompositePipelineState
-            descriptor.vertexFunction = Graphics.Shaders[.CompositeVertex]
+            descriptor.vertexFunction = Graphics.Shaders[.FullScreenVertex]
```

Draw-site conversions (every generic site becomes the same bufferless 3-vertex draw):

```diff
--- a/ToyFlightSimulator Shared/Display/Protocols/LateDrawablePresenting.swift
+++ b/ToyFlightSimulator Shared/Display/Protocols/LateDrawablePresenting.swift
@@ encodeCompositeStage
             setRenderPipelineState(renderEncoder, state: .Composite)
             renderEncoder.setFragmentTexture(lightingResolveTexture, index: 0)
-            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
+            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
--- a/ToyFlightSimulator Shared/Display/TiledDeferredRenderer.swift
+++ b/ToyFlightSimulator Shared/Display/TiledDeferredRenderer.swift
@@ encodeDirectionalLightStage
             setRenderPipelineState(renderEncoder, state: .TiledDeferredDirectionalLight)
-            // Draw full screen quad
-            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
+            // Draw full-screen triangle
+            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
```

Same two-line change in `TiledMultisampleRenderer.swift` and `TiledMSAATessellatedRenderer.swift`
(their `encodeDirectionalLightStage` bodies are identical but for the `.TiledMSAADirectionalLight`
PSO), and in `OITRenderer.swift`'s Blend Fragments stage. OIT's final stage replaces the mesh
walk entirely:

```diff
--- a/ToyFlightSimulator Shared/Display/OITRenderer.swift
+++ b/ToyFlightSimulator Shared/Display/OITRenderer.swift
@@ finalRenderPass
                 setRenderPipelineState(renderEncoder, state: .Final)
                 renderEncoder.setFragmentTexture(Assets.Textures[.BaseColorRender_0], index: 0)
-                DrawManager.DrawFullScreenQuad(with: renderEncoder)
+                renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
```

The single-pass renderer loses its quad plumbing wholesale:

```diff
--- a/ToyFlightSimulator Shared/Display/SinglePassDeferredLightingRenderer.swift
+++ b/ToyFlightSimulator Shared/Display/SinglePassDeferredLightingRenderer.swift
@@ class SinglePassDeferredLightingRenderer
 final class SinglePassDeferredLightingRenderer: Renderer, ShadowRendering, LateDrawablePresenting, @unchecked Sendable {
-    // Create quad for fullscreen composition drawing
-    private let _quadVertices: [TFSSimpleVertex] = [
-        .init(position: .init(x: -1, y: -1)),
-        .init(position: .init(x: -1, y:  1)),
-        .init(position: .init(x:  1, y: -1)),
-
-        .init(position: .init(x:  1, y: -1)),
-        .init(position: .init(x: -1, y:  1)),
-        .init(position: .init(x:  1, y:  1))
-    ]
-
-    private let _quadVertexBuffer: MTLBuffer!
-
     var shadowMapArray: MTLTexture
@@ init()   (both initializers)
     init() {
-        _quadVertexBuffer = Engine.Device.makeBuffer(bytes: _quadVertices,
-                                                     length: MemoryLayout<TFSSimpleVertex>.stride * _quadVertices.count)
         shadowMapArray = Self.makeShadowMapArray(label: "Shadow Map Array")
@@ encodeDirectionalLightingStage
             renderEncoder.setCullMode(.back)
             renderEncoder.setStencilReferenceValue(128)
-            renderEncoder.setVertexBuffer(_quadVertexBuffer,
-                                          offset: 0,
-                                          index: TFSBufferIndexMeshVertex.index)
-            
-            // Draw full screen quad
-            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
+            // Full-screen triangle; position + eye ray come from
+            // deferred_directional_lighting_vertex, no vertex buffer.
+            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
```

And `DrawManager` drops the now-orphaned quad path (`DrawFullScreenQuad` plus its
`_fullScreenQuadMeshes` cache, DrawManager.swift:312/325-345) — no other caller exists.

Post-landing notes:

- **`SceneManager.SetScene`'s `Assets.Models[.Quad]` warm-up loses its original
  justification** (it existed because `DrawFullScreenQuad` resolved the model on the render
  thread mid-encode). Keep the touch — scene ground quads still use the model and the
  warm-up is one dictionary hit — but its comment should stop citing the render thread once
  this lands.
- **Verification:** all six renderers before/after screenshots (§6 pattern). Composite and
  OIT-final outputs should be bit-identical, directional lighting analytically identical;
  a GPU capture should show 3-vertex bufferless draws at every converted site.
- Net deletions: 4 vertex functions, 3 varying structs, 2 constant quad arrays,
  `TFSSimpleVertex` + the `_quadVertices`/`_quadVertexBuffer` plumbing, 2 runtime buffer
  binds, 1 vertex descriptor, `DrawFullScreenQuad` + cache, and 3 ShaderType keys.

### E7 ✅ FIXED — Eye-space position reconstruction — 2 sites, 1 currently wrong

> **Fixed in `62e3dbf` (2026-08-14):** both sites converted; both files gained the
> `ShaderHelpers.h` import. The PointLights site is a pure refactor — the helper's body IS
> the old expression, so point-light output is bit-identical. The DirectionalLight site is
> the behavior change this finding pointed at: C4's problem 2 (reconstruction), leaving C4
> partially fixed at the time — its problems 1 and 3 followed in `e6949e5` (2026-08-16),
> completing C4. The reconstructed position feeds only the specular halfway vector there,
> so diffuse was unchanged by this commit. Verified: both files compile standalone; macOS
> Debug build passes.

`PointLights.metal:70` (correct form) and `DirectionalLight.metal:57` (wrong form, C4) both
become `ReconstructEyePosition(in.eye_position, depth)`.

### E8 ✅ FIXED — Terrain height→layer blend — 2 duplicated blocks

> **Fixed in `62e3dbf` (2026-08-14):** as proposed below — file-local `static
> SampleTerrainLayer`, both fragments converted, branch-for-branch identical thresholds.
> `tiling` stays a hardcoded 1.0 inside each fragment; the §5 fold-into-`Terrain`-uniform
> note stands.

`Tessellation.metal:107-116` and `129-138` duplicate the height-threshold texture pick. Local
to one file, so a `static` function in `Tessellation.metal` is enough:

```metal
static float4 SampleTerrainLayer(float height, float2 uv, float tiling,
                                 texture2d<float> grass, texture2d<float> cliff,
                                 texture2d<float> snow, sampler s) {
    if (height < -0.5) { return grass.sample(s, uv * tiling); }
    if (height <  0.3) { return cliff.sample(s, uv * tiling); }
    return snow.sample(s, uv * tiling);
}
```

---

## 4. Dead code inventory

All verified by exhaustive grep of `ShaderLibrary` keys against every `Shaders[.X]` /
`vertexShaderType:`/`fragmentShaderType:` reference (both wiring patterns checked):

| # | Item | Evidence |
|---|---|---|
| D1 | **`Instanced.metal` — whole file.** `InstancedVertex` key never referenced; `base_vertex` already is the instanced path. | grep: 0 refs |
| D2 | **`TiledMSAAGBuffer.metal` — whole file.** `TiledMSAAPipeline.swift:51,66` binds `TiledDeferredGBufferFragment` instead. (C1's fix was mirrored into it in `0ec59ea` so it stays consistent until deleted.) | grep: 0 refs |
| D3 | **`TiledMSAATransparency.metal` — whole file.** MSAA pipeline binds `TiledDeferredTransparencyFragment`. For the record it also has a real bug: it accumulates MSAA texel reads *on top of* `color = material.color` before dividing — the average includes the material color as a phantom sample. Don't resurrect without fixing; also `texture2d_ms` for a *material* texture can't be bound to the regular file textures DrawManager provides. | grep: 0 refs |
| D4 | **`fragment_particle_msaa`** (`Particles.metal:75-100`). Same `texture2d_ms`-material concern. `ParticlePipeline.swift:64-70` uses `ParticlesFragment` for the MSAA pipeline (correct — MSAA-ness lives in `rasterSampleCount`, not the material texture). | grep: 0 refs |
| D5 | **`transparent_fragment`** (`OrderIndependentTransparency.metal:50-75`). OIT pipelines bind `TransparentMaterialFragment` only. Deleting it removes one of the two copies of the layer-insert loop. | grep: 0 refs |
| D6 | **`Lighting::GetPhongIntensity`** — zero uncommented call sites (both callers are the commented-out blocks in `Base.metal` / `OrderIndependentTransparency.metal`). Its quirks (diffuse floored at 0.3, ambient added only on back faces) suggest deleting rather than reviving; if Phong returns, rebuild on `CalculateDirectionalLighting`'s conventions. Also removable then: the dead `lightCount`/`lightData`/`normalMap` bindings in `material_fragment` and `transparent_material_fragment`. | grep: 0 live calls |
| D7 | **`TFSCommon.h` Apple-sample leftovers:** `TFSFrameData` (temple/fairy fields), `TFSPointLight`, `TFSShadowVertex` — zero references outside the header. Also the commented `SkyboxVertex` struct in `Skybox.metal:13-17` and `Particle`'s commented `float direction` field. | grep: 0 refs |

Removing D1–D5 also deletes their `ShaderLibrary` registrations (9 orphaned keys found:
`BaseFragment`* and `MaterialFragment`* are **live** — OIT/Basic pipelines — the other
listed keys are not: `InstancedVertex`, `ParticlesFragmentMSAA`, `TiledMSAAGBufferFragment`,
`TiledMSAATransparencyFragment`, `TransparentFragment`).

---

## 5. Minor notes & hygiene

- ✅ **FIXED in `e086508` (2026-08-12) — `ShaderDefinitions.h` include-guard hole.** The
  `#endif` now sits at EOF so `GBufferOut`, `VertexOut`, and `TessellationVertexOut` are
  inside the `SHARED_METAL` guard, and the stale `Shared.metal` header comment now reads
  `ShaderDefinitions.h`. (Original finding: the `#endif` sat at line 75, leaving those three
  structs unguarded — safe only under `#import` semantics; any `#include` would have
  double-defined them.)
- **`Lighting.metal` imported as a header** (`#import "Lighting.metal"` from 6 files) while
  also compiling standalone. It works (in-class statics are implicitly inline), but renaming
  it `Lighting.h` would say what it is and remove one no-op TU from the metallib build.
- **`CalculateDirectionalLighting` semantics:** `float3 metallic = material.shininess;` —
  shininess is repurposed as *metallic*, which is why
  `TiledDeferredDirectionalLight.metal:43` carries the mystery comment
  `"Shininess == 1 results in all black screen"` (metallic 1 ⇒ diffuse 0 — the comment is
  documenting the confusion, not a GPU quirk). Rename the parameter or add a real
  `metallic` field to `MaterialProperties`.
- **`GBuffer.metal:58` negated bitangent** (`-normalize(...)`) is a load-bearing handedness
  convention; if it stays, it deserves a one-line comment stating which convention (MikkTSpace
  vs. flipped-green-channel) it encodes — it's exactly the kind of sign future refactors flip
  by accident.
- **`TiledDeferredDirectionalLight.metal:49-53`:** `uint lightCount = 1;` with a loop that
  ignores `i` — either bind `TFSBufferDirectionalLightsNum` like the OIT path or drop the loop.
- **`Skybox.metal:21-22`** hardcodes attribute indices 0/1 with the TFS enum version commented
  out right above — either use the enum or delete the comment.
- **`Tessellation.metal:107/129`:** `float tiling = 1.0; // Get this passed in ???` — fold
  into the `Terrain` uniform struct when touched next.

---

## 6. Suggested order of attack

Each step is independently shippable and screenshot-verifiable
(`debugging/screenshots/` before/after per renderer):

1. **Delete dead code** (D1–D7) — zero risk, −~350 lines, and it shrinks every later diff.
2. **C1 + C6 + E4** (normal-map decode unification) — biggest visual payoff; verify the
   normal-mapped F-22 under TiledDeferred and SinglePassDeferred.
3. **C4 + C3 + E7** (single-pass light math) — verify with `PhysicsStressTestScene`'s point
   lights and a low sun.
4. **C2** (OIT layer order) — verify overlapping canopy/afterburner layering in the OIT
   renderer; decide the 0.1-alpha clamp question while in the file.
5. **C5 + C13** (tiled point-light volume + albedo) — verify a large-radius point light.
6. **E1 + P2, C7** (skinning consolidation) — verify gear animation lighting.
7. **E2/E3/E5** (transparency + base-color dedup), then **E6** (full-screen triangle,
   includes Swift-side PSO edits), then P3/P4/P5 micro-cleanups opportunistically.

*Not covered:* `ForwardPlusTileShading` (stub, no shader file), compute pipelines outside
`Shaders/`, and Swift-side pipeline-descriptor hygiene beyond what the extractions require.
