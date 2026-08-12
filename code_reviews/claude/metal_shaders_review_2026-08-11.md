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
Currently fixed: **P1** and the **`ShaderDefinitions.h` include-guard hole** (§5) — commit
`e086508`, 2026-08-12. All other findings are open.

---

## Contents

1. [Correctness findings](#1-correctness-findings) (C1–C13)
2. [Performance findings](#2-performance-findings) (P1–P7)
3. [Common code to extract](#3-common-code-to-extract) (E1–E8)
4. [Dead code inventory](#4-dead-code-inventory) (D1–D7)
5. [Minor notes & hygiene](#5-minor-notes--hygiene)
6. [Suggested order of attack](#6-suggested-order-of-attack)

Severity key: 🔴 visible rendering error on a live path · 🟠 wrong but masked/partially masked · 🟡 latent/dead-path or behavioral.

---

## 1. Correctness findings

### C1 🔴 Tiled G-buffer writes the raw normal-map texel as the world normal (no decode, no TBN)

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

**Fix** (uses the `ApplyNormalMapWorld` helper from E4):

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

### C2 🔴 OIT layer sort is inverted under reverse-Z — transparency blends front-to-back

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

### C3 🔴 Single-pass point lights compare a world-space light position against eye-space fragments

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

### C4 🔴 Single-pass directional light: direction derived from unnormalized position, wrong position reconstruction, bogus halfway vector

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

### C5 🔴 Tiled point-light volume ignores the light's radius

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

Also in this file's fragment (see C13): the surface albedo is ignored.

---

### C6 🟠 Single-pass G-buffer runs the *geometric* normal through the normal-map decode

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

### C7 🟠 Animated tiled G-buffer vertex feeds the *unskinned* normal to `worldNormal`

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
animated meshes). The E1 skinning helper fixes all of these at once.

---

### C8 🟠 `Base.metal` / `Instanced.metal` transform normals as *points* (w = 1)

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

### C9 🟠 `material_fragment` reads an uninitialized variable (UB on a live path)

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

### C10 🟠 Terrain G-buffer writes the *window-space* position into the world-position target

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

Also: the lifetime check runs *after* `scale` is computed, so the frame a particle expires it
renders with `mix(start, end, age/life > 1)` — an extrapolated scale. Reorder the reset before
the scale computation.

---

### C12 🟡 Cascade selection metric doesn't match the CPU's split metric (comment is wrong at minimum)

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

---

### C13 🟡 Tiled point lights ignore surface albedo

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

### P2 Skinning: blend the matrix once instead of eight matrix·vector transforms

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

### P3 `worldPosition.xyz / worldPosition.w` after an affine model transform

**Files:** `GBuffer.metal:54,99`, `TiledDeferredGBuffer.metal:30,75`,
`TiledDeferredTransparency.metal:26`, `SinglePassDeferredTransparency.metal:26,68`

`modelMatrix` is affine — `worldPosition.w` is exactly 1 — so the divide is dead weight in
seven vertex shaders. Replace with `worldPosition.xyz`. (Micro, but it's also *clarity*: the
divide implies a projective transform that isn't there.)

### P4 Redundant normalize chains between vertex and fragment stages

**File:** `GBuffer.metal:57-59, 102-104` — the vertex stage normalizes T/B/N, converts to
`half3`, and the fragment renormalizes anyway (it must — interpolation denormalizes).
Normalize once, in the fragment. Same pattern in `Base.metal` (`base_fragment` renormalizes
`surfaceNormal`).

### P5 Particle kernel round-trips device memory ~14 times per thread

**File:** `Particles.metal:19-41` — every `particles[id].field` access is a device-memory
dereference the compiler can't always coalesce through the write aliasing. Load `Particle p`
once, mutate locally, store once (folded into C11's diff).

### P6 Fat interpolant structs on trivial passes

`RasterizerData` (ShaderDefinitions.h:34-50) carries ~15 fields; `skysphere_vertex` populates
3 of them and `quad_pass_vertex` populates 1, but every pass pays the struct's interpolation
cost unless the compiler's cross-stage elimination catches it (worth confirming in a GPU
capture). Slimmer per-pass structs (a `SkyVertexOut` with position+uv) are cheap insurance and
document the actual contract.

### P7 Five different full-screen-pass mechanisms

Full-screen passes exist in five flavors: 6-vertex constant-array quad ×2
(`Composition.metal:12-19`, `TiledDeferredDirectionalLight.metal:14-21`), 3-vertex
super-triangle (`OrderIndependentTransparency.metal:28-39`), vertex-buffer quad
(`DirectionalLight.metal:20-33` via `TFSSimpleVertex`), and a full mesh with vertex descriptor
(`Final.metal:18-25`). Consolidating on one 3-vertex full-screen triangle (E6) removes two
buffer bindings, a vertex descriptor, and 3 vertices of redundant work — trivial GPU savings,
real maintenance savings.

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

### E1 Skinning — 5 duplicated blocks → `BlendJointMatrix`

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

### E3 Opacity resolve — 4 duplicated blocks → `ResolveOpacity`

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

### E4 Normal-map decode + TBN — the helper C1/C6 use

Live call sites after fixes: `TiledDeferredGBuffer.metal` (world variant),
`GBuffer.metal` `gbuffer_fragment_material` (eye variant), and `Tessellation.metal`'s
G-buffer fragment once terrain gets a real TBN. This is the one extraction that *fixes bugs by
existing* — today one file decodes-but-shouldn't (C6) while another should-but-doesn't (C1);
a single named helper makes the convention impossible to miss.

### E5 Base-color cascade — 7 duplicated blocks → `ResolveBaseColor`

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

### E6 Full-screen pass — 5 mechanisms → 1 shared triangle

Replace, in order of ease:
1. `TiledDeferredDirectionalLight.metal:14-32` (`tiled_deferred_vertex_quad` + constant array) — direct swap, position-only.
2. `Composition.metal:12-40` (`compositeVertexShader` + its own quad + y-flip) — swap; its fragment keeps sampling with `in.uv`.
3. `OrderIndependentTransparency.metal:28-39` (`quad_pass_vertex`) — swap; stops abusing the fat `RasterizerData` as a position-only varying (P6).
4. `Final.metal` — also drop the Quad mesh + vertex descriptor from its PSO Swift-side, and delete the per-fragment `1 - uv.y` flip (the helper's uv is already texture-oriented).
5. `DirectionalLight.metal` — keep a specialized shader (it needs the eye ray from `projectionMatrixInverse`), but build it on `FullScreenTriangleVertex` + its own eye-ray computation, dropping the `TFSSimpleVertex` buffer.

Each conversion needs its `drawPrimitives` call to use `vertexCount: 3` and no vertex buffer;
verify cull mode as noted in the helper comment.

### E7 Eye-space position reconstruction — 2 sites, 1 currently wrong

`PointLights.metal:70` (correct form) and `DirectionalLight.metal:57` (wrong form, C4) both
become `ReconstructEyePosition(in.eye_position, depth)`.

### E8 Terrain height→layer blend — 2 duplicated blocks

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
| D2 | **`TiledMSAAGBuffer.metal` — whole file.** `TiledMSAAPipeline.swift:51,66` binds `TiledDeferredGBufferFragment` instead. | grep: 0 refs |
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
