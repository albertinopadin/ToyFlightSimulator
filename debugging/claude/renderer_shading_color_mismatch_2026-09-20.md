# Renderer Shading Mismatch — Black Sides (Tiled), Blown-Out Highlights (Single-Pass), Flat Colors (OIT)

**Date:** 2026-09-20 · **Agent:** claude · **Status:** analysis only, no code changed
**Triggered by:** `debugging/screenshots/TiledDeferredColors.png`, `SinglePassDeferredColors.png`, `OIT_Colors.png`
(all three in `FlightboxWithPhysics`, chase camera, sun almost straight overhead).
**Related docs:** [`material_color_bleeding_bug.md`](material_color_bleeding_bug.md) (material defaults),
[`sun_follow_lost_shadows.md`](sun_follow_lost_shadows.md) (shadow epsilon).
**Cross-check:** [`../codex/renderer_shading_color_diagnosis_2026-09-20.md`](../codex/renderer_shading_color_diagnosis_2026-09-20.md)
(Codex, same question). Items adopted from it are marked **[codex]**; each was re-verified in the source and,
where it carries a number, re-derived with the scratch script. See [Comparison with the Codex diagnosis](#comparison-with-the-codex-diagnosis).
**Scratch scripts:** [`renderer_shading_color_mismatch_numbers_2026-09-20.swift`](renderer_shading_color_mismatch_numbers_2026-09-20.swift)
reproduces every number below; [`renderer_shading_color_mismatch_sample_pixels_2026-09-20.swift`](renderer_shading_color_mismatch_sample_pixels_2026-09-20.swift)
reads pixel values out of the screenshots.

## Changelog

- **2026-09-21** — Step 5's closing note on `base_animated_vertex` tangent skinning and the
  zero-light guard expanded, on request, into the full explanation: why T and B must be skinned
  with the same blended matrix as N, a worked 90° flap example where the unskinned bitangent
  collapses onto the normal, and why the guard both avoids an unbound-buffer read and keeps a
  sunless scene from drawing black.
- **2026-09-21** — Step 4 split into the two landing-order commits after implementing it literally
  turned every directly lit surface in the single-pass renderer almost white. The pseudocode read
  the G-buffer alpha as the specular strength, but that channel is a constant 1.0 until Step 6
  lands and the parity-step `kDefaultShininess` is 1, so the highlight became `N·H` in white on
  every sun-facing surface (root cause 2b again, untinted). The parity commit now passes
  `kDefaultSpecularStrength`; the specular commit switches to the alpha. Landing order item 1
  and verification item 7 say so explicitly. Numbers in the new table under Step 4 re-derived
  with the shading formula of the worked example.
- **2026-09-20** — Cross-checked against the Codex diagnosis. Adopted: the secondary inconsistencies
  section (deferred transparency unlit, fallback color, UV transforms, handedness, tangent skinning,
  zero-specular import), the world-space-then-rotate normal repair for the single-pass G-buffer, the
  specular guards, the "specular off first" landing order, the existing 0.4 / 0.5 light values as the
  baseline, and six follow-ups. Re-derived with the script: the 0.4 / 0.5 baseline table, the gray-albedo
  table, the mixed-frame rotation table, the sRGB palette example, the nonuniform-scale example, and the
  transparency compositing check.
- **2026-09-20** — Doc created from the three screenshots and the shader sources.

## Symptoms

| Renderer | What the screenshot shows |
|---|---|
| TiledDeferred, TiledDeferredMSAA, TiledMSAATessellated | Tops of objects lit, every side and underside is pure black. Shadows present. |
| SinglePassDeferredLighting | Shadows present, but the ground is much darker than in the other two renderers, the F-22's grey skin is clipped to pure white, and vertical faces are nearly as bright as top faces. |
| OrderIndependentTransparency | No shading at all. Every surface is its flat base color regardless of orientation. No shadows (expected: the OIT path has no shadow pass). |

Measured pixel values (5×5 average, sRGB 8-bit as stored in the PNG; "linear" is the value the
shader wrote before the display encoding). The ground is the `addGround` default color
`(0.3, 0.7, 0.1)`; the same lit ground pixel is sampled in all three images.

| Sample | Tiled | Single-pass | OIT |
|---|---|---|---|
| Lit ground, sRGB8 | (142, 208, 85) | (96, 144, 56) | (149, 218, 89) |
| Lit ground, linear | (0.270, 0.631, 0.091) | (0.117, 0.279, 0.040) | (0.301, 0.701, 0.100) |
| Lit ground ÷ albedo | 0.90 | **0.40** | 1.00 |
| Ground in the jet's shadow, linear | (0.136, 0.314, 0.047) = 0.45 × albedo | (0.072, 0.168, 0.024) = 0.24 × albedo | n/a |
| Vertical face of a colored object | (0, 0, 0) | 0.62–0.67 × albedo | 1.00 × albedo |
| F-22 upper skin (grey) | (191, 191, 191) | **(255, 255, 255)** | (200, 200, 200) |

Every one of these numbers is predicted exactly by the shader arithmetic below, so the causes
are established, not guessed. (The random objects differ between screenshots because a renderer
switch rebuilds the scene; the ground, the fixed cubes and the aircraft are deterministic, which
is why the ground is the comparison pixel **[codex]**.)

## TL;DR

- **Tiled (all three):** `Lighting::CalculateDirectionalLighting` in `Lighting.metal` computes
  `albedo × 0.9 × max(N·L, 0) × lightColor` and nothing else. There is no ambient term, so any
  surface facing away from the sun gets exactly zero light. `ambientIntensity`,
  `diffuseIntensity` and `brightness` from `LightData` are never read. The shadow factor then
  multiplies the whole result, which is why shadows are 50% instead of "ambient only".
- **Single-pass:** three independent problems stack.
  1. The G-buffer vertex shader (`GBuffer.metal`) converts the un-normalized world normal to
     `half3`. The ground is a quad scaled by 1 000 000, and `half` overflows above 65 504, so
     the ground's normal becomes `inf`, then `NaN` after `normalize()`, then `0` in the
     `rgba8Snorm` G-buffer. The lighting shader's `max(N·L, 0.4)` floor then lights the whole
     ground at 0.4 × albedo. This is a regression from commit `ab04296` (2026-08-17), which
     removed the vertex-stage `normalize()` that used to happen in `float` before the `half`
     conversion.
  2. `DirectionalLight.metal` uses `lightData.specularIntensity` (= 1.0) as the specular
     **exponent** and stores a specular weight of 1.0 for every untextured surface, so the
     "highlight" is a cosine lobe as wide as the diffuse term. Diffuse + specular reaches
     1.7 × albedo on the jet's skin and clips to white; vertical faces facing the camera get
     0.4 (floor) + 0.7 (specular) ≈ 1.1 × albedo, about as bright as the top faces.
  3. The G-buffer normals are **world**-space (`ModelConstants.normalMatrix` is built from the
     world matrix), but the lighting shader dots them with `lightEyeDirection`, an
     **eye**-space vector, and builds an eye-space half vector. With a level camera and an
     overhead sun the error is a few degrees and invisible; when the chase camera banks or
     pitches with the aircraft the lighting will rotate with the camera. The point-light pass
     has the same frame mismatch.
- **OIT:** `material_fragment` (`Base.metal`) and `transparent_material_fragment`
  (`OrderIndependentTransparency.metal`) write the raw base color. The lighting call is
  commented out with the note "This results in very dark scene". It did, because
  `Lighting::GetPhongIntensity` treats the directional sun as a point light at the sun's
  position (the ground 500 m from the origin gets N·L = 0.37), adds ambient only on
  back-facing surfaces (and that ambient is `0.1 × 0.4 = 0.04`), and the scene's
  `diffuseIntensity = 0.5` halves everything.
- **Secondary, verified inconsistencies** that do not explain the three screenshots but will
  show up as soon as the main fix lands **[codex]**: the deferred transparency shaders (the
  F-22 canopy in every deferred renderer) are unlit; two material paths fall back to vertex
  color where the other three use `material.color`; the OIT opaque fragment ignores UV
  transforms; the single-pass and tiled paths use opposite bitangent handedness; the OIT
  animated vertex skins the normal but not the tangents; the importer cannot store an explicit
  zero specular. Listed in [Secondary inconsistencies](#secondary-inconsistencies-verified).

The fix is one shared Blinn-Phong function (`ambient + litFraction × (diffuse + specular)`) that
all three paths call with vectors in a consistent frame, plus: build the single-pass normal in
world space in `float` and rotate only the final unit vector into eye space, use a real shininess
exponent, and make the shadow term scale only the direct light. Land it with specular off first
so the three renderers can be compared on diffuse + ambient alone, then enable specular.
Pseudocode per file is in [The fix](#the-fix).

## Terms

- **Albedo** — the surface's own color, before lighting. In this engine it comes from
  `ModelConstants.objectColor` (set by `GameObject.setColor`), a base-color texture, or
  `MaterialProperties.color` (`ResolveBaseColor` in `ShaderHelpers.h`).
- **N, L, V, H** — unit vectors at a shaded point: surface normal, direction to the light,
  direction to the camera, and the half vector `normalize(L + V)`. All four must be in the
  same coordinate frame or the dot products are meaningless.
- **Ambient / diffuse / specular** — the three terms of the Phong family. Ambient is a constant
  fill (stands in for light bounced off the environment), diffuse is `albedo × max(N·L, 0)`
  (Lambert), specular is a highlight `strength × pow(max(N·H, 0), shininess)` (Blinn-Phong).
  A larger `shininess` gives a smaller, sharper highlight; exponent 1 is a lobe as wide as
  the diffuse term. Strength and exponent are different controls: strength changes brightness,
  exponent changes width **[codex]**.
- **Lit fraction (visibility)** — the fraction of direct sunlight reaching a point, 0 (fully
  shadowed) to 1 (unblocked), as the PCF filter returns it. Today `CalculateShadow` remaps it
  to `0.5 + 0.5 × lit` before returning.
- **Eye space** — coordinates after the view matrix: the camera sits at the origin looking down
  +Z. **World space** — coordinates before the view matrix.
- **G-buffer** — the per-pixel textures a deferred renderer writes in its geometry pass (albedo,
  normal, depth or position) and reads back in its lighting pass.
- **half** — 16-bit float. Largest finite value 65 504; anything bigger becomes `inf`. Smallest
  normal value about 6 × 10⁻⁵; a squared length of 10⁻¹² rounds to 0.
- **sRGB encoding** — the render targets and drawable are `bgra8Unorm_srgb`
  (`Preferences.MainPixelFormat`). The shader writes linear values and the hardware encodes
  them, so a linear `0.3` is stored as `0.58` (149/255). Every "linear" number in this doc is
  the shader's value; every "sRGB8" number is what the PNG holds.

## How a color travels through each renderer

Shared facts, established from the code:

- `LightObject.direction` is derived from the sun's position: `normalize(0, 200, 4)` =
  `(0, 0.9998, 0.020)`, a world-space unit vector from surfaces toward the sun
  (`LightObject.swift:38-43`). For the ground (N = (0, 1, 0)) `N·L = 0.9998`. For a vertical
  face `N·L ≈ 0.02`.
- `FlightboxWithPhysics.swift:171-176` sets brightness 1.0, color (1, 1, 1),
  `ambientIntensity 0.4`, `diffuseIntensity 0.5`; `specularIntensity` keeps the `LightData()`
  default 1.0 (`MetalTypes.swift:109-131`). So the CPU side already supplies an ambient
  setting; the shaders ignore it **[codex]**.
- `ModelConstants.normalMatrix` is the upper-left 3×3 of the **world** matrix
  (`GameObject.swift:84-88`, `Transform.normalMatrix(from:)` at `Transform.swift:65-70`). It is
  not the inverse transpose, and it carries the object's scale. The ground quad is scaled by
  `groundSize = 1_000_000` (`FlightboxWithPhysics.swift:29`, `GameScene.addGround` at
  `GameScene.swift:119-134`), so `normalMatrix × normal` for the ground has length 10⁶.
- `LightManager.GetDirectionalLightData(viewMatrix:)` (`LightManager.swift:54-64`) fills
  `lightEyeDirection = normalize(viewMatrix × (direction, 0))`, the same vector rotated into
  eye space. `GameScene.setDirectionalLightConstants` passes `skyViewMatrix` (translation
  removed), which is correct for a direction.
- `MaterialProperties()` defaults (`MetalTypes.swift:88-96`): ambient (0.1, 0.1, 0.1),
  diffuse (1, 1, 1), specular (1, 1, 1), shininess 2.0. `setColor` objects (the ground, the
  cubes, spheres and capsules) use the model's default material for everything except color.
- The three tiled renderers bind the **same** G-buffer and sun fragment functions:
  `TiledDeferredPipeline.swift:30-75` and `TiledMSAAPipeline.swift:46-88` both select
  `.TiledDeferredGBufferFragment` and `.TiledDeferredDirectionalLightFragment`. The functions
  in `TiledMSAAGBuffer.metal` and `TiledMSAATransparency.metal` are registered in
  `ShaderLibrary.swift` but no pipeline binds them, so editing only those files changes
  nothing on screen **[codex]**.

What each lighting path actually computes today:

| | Tiled ×3 (`TiledDeferredDirectionalLight.metal`) | Single-pass (`DirectionalLight.metal`) | OIT (`Base.metal`, `OrderIndependentTransparency.metal`) |
|---|---|---|---|
| Normal frame | world (`TiledDeferredGBuffer.metal:112`) | world, but treated as eye | world (`RasterizerData.surfaceNormal`) |
| Light vector | `light.direction` (world) ✓ | `lightEyeDirection` (eye) ✗ mismatch | none |
| Ambient | none | `max(N·L, 0.4)` floor + `shadow + 0.1` | none |
| Diffuse | `albedo × 0.9 × N·L` | `albedo × max(N·L, 0.4)` | none |
| Specular | none | `pow(N·H, 1.0) × albedo × 1.0` | none |
| Shadow | multiplies everything, range [0.5, 1] | multiplies everything, range [0.6, 1] | no shadow pass |
| Reads `ambientIntensity` / `diffuseIntensity` / `brightness` | no / no / no | no / no / no | — |

## Root cause 1 — Tiled renderers: there is no ambient term

`TiledDeferredDirectionalLight.metal:19-37`:

```metal
MaterialProperties material;
material.color = albedo;
material.shininess = 0.1;   // Shininess == 1 results in all black screen
material.ambient = 1.0;     // Should be ambient occlusion
...
color += Lighting::CalculateDirectionalLighting(lightData, normal, material);
color *= albedo.a;          // albedo.a holds the shadow factor written by the G-buffer pass
```

`Lighting.metal:62-73`:

```metal
float3 metallic = material.shininess;            // 0.1
float3 ambientOcclusion = material.ambient;      // 1.0
float nDotL = saturate(dot(normal, light.direction));
float3 diffuse = float3(baseColor) * (1.0 - metallic);
return diffuse * nDotL * ambientOcclusion * light.color;
```

So the only light a pixel receives is `albedo × 0.9 × max(N·L, 0) × lightColor`, times the
shadow factor:

- Lit ground: `(0.3, 0.7, 0.1) × 0.9 × 0.9998` = `(0.270, 0.630, 0.090)` → sRGB8 (142, 208, 85).
  Measured (142, 208, 85). ✓
- Ground under the jet: the PCF result is 0, `CalculateShadow` returns `0.5 + 0.5 × 0 = 0.5`
  (`Lighting.metal:210`), so `0.135, 0.315, 0.045` → sRGB8 (103, 152, 60). Measured
  (103, 152, 61). ✓
- Any vertical or downward face: `N·L ≤ 0.02`, so the pixel is ≈ 0, which the 8-bit target
  stores as exactly black. Measured (0, 0, 0). ✓

Why this is wrong rather than just "dark": a directional light alone can never light a surface
it does not face. Real scenes look acceptable because the sky and ground bounce light onto
those surfaces. The Phong ambient term is the cheap stand-in for that bounce, and this path has
none. `material.ambient = 1.0` looks like an ambient control but is only a multiplier inside
the direct term: one times zero is still zero **[codex]**. The `0.5 + 0.5 × lit` floor inside
`CalculateShadow` was doing part of the ambient's job (shadows never go fully black) but it
only helps surfaces that face the sun, which is how one image can hold moderately dark cast
shadows and completely black sides at the same time.

The comment `Shininess == 1 results in all black screen` is a clue to the same problem: the
"metallic" variable is being used as a brightness knob because there is no other one. Shininess
is a highlight exponent elsewhere in the engine; a metallic fraction is a different quantity in
[0, 1], and `1 − shininess` with the default shininess of 2 would be negative. The `0.9`
factor also explains why the tiled ground is 10% darker than the OIT ground.

## Root cause 2 — Single-pass renderer: NaN ground normal, cosine-lobe specular, world/eye mismatch

### 2a. The ground's normal overflows `half`

`GBuffer.metal:56-64` (and the animated variant at `96-101`):

```metal
.worldNormal = modelInstance.normalMatrix * in.normal,          // float3, used for shadow bias
...
.tangent = half3(modelInstance.normalMatrix * in.tangent),
.bitangent = half3(-(modelInstance.normalMatrix * in.bitangent)),
.normal = half3(modelInstance.normalMatrix * in.normal),        // half3, used for lighting
```

`normalMatrix` carries the model's scale. For the ground that scale is 1 000 000, so
`normalMatrix × in.normal` is `(0, 1e6, 0)`; converting it to `half3` gives `(0, inf, 0)`
because `half` tops out at 65 504. In `gbuffer_fragment_material` (`GBuffer.metal:183`)
`normalize(in.normal)` computes `inf / inf = NaN`, and the `rgba8Snorm` normal target stores
that as 0. In the lighting pass:

- `saturate(dot(N, L))` with N = 0 gives 0, then `max(0, 0.4)` gives **0.4**
  (`DirectionalLight.metal:53-55`).
- `powr(max(dot(N, H), 0), 1)` gives 0, so no specular.
- The ground is not in shadow: `shadowSample = 1.0`.

Result: ground = `0.4 × albedo` = `(0.12, 0.28, 0.04)` → sRGB8 (97, 144, 56).
Measured (96, 144, 56). ✓ That 0.40 ratio is the single most telling number in the table: it
is the floor constant, which means the normal contributed nothing.

Before commit `ab04296` ("Drop dead w-divides and vertex-stage TBN normalizes", 2026-08-17) the
vertex shader wrote `half3(normalize(normalMatrix * in.normal))`: the normalize ran in `float`
and the result fit in `half`. The commit's reasoning ("interpolation denormalizes anyway, the
fragment renormalizes once") is correct for `float3` interpolants (the tiled G-buffer and the
OIT path use `float3` and are unaffected) but not for `half3`, where the un-normalized value
must first survive the conversion. Any object scaled above ~65 000 hits this; today only the
ground does.

Switching `Transform.normalMatrix` to the inverse transpose would not make un-normalized `half`
math safe either: the inverse-transpose of a million-scale transform produces components near
10⁻⁶, whose squared length (10⁻¹²) rounds to 0 in `half`, and `normalize` divides by that
**[codex]**. Whatever the normal matrix is, only a unit vector may be narrowed to `half`.

### 2b. Specular exponent of 1 and specular weight of 1

`DirectionalLight.metal:71-79`:

```metal
half specular_intensity = half(lightData.specularIntensity);   // 1.0, used as the EXPONENT
half shininess = half(1.0);
half specular_shininess = albedo_specular.w * shininess;       // 1.0 for every untextured surface
half specular_factor = powr(max(dot(N, H), 0), specular_intensity);
half3 specular_contribution = specular_factor * albedo * specular_shininess * sun_color;
```

`LightData.specularIntensity` is a linear scale factor everywhere else in the engine
(`Lighting.metal:52` multiplies by it), but here it is the power. `pow(x, 1) = x`, so the
highlight is a cosine lobe as wide as the diffuse lobe. `albedo_specular.w` is 1.0 whenever no
specular map is bound (`GBuffer.metal:186-192`), which is every `setColor` object.

- Jet upper skin: its albedo is 0.578 (measured in the OIT screenshot, where it is drawn
  raw). Diffuse (N·L ≈ 1) plus a specular term of ≥ 0.73 × albedo exceeds 1.0 and the
  `bgra8Unorm_srgb` target clips to white. Measured (255, 255, 255). ✓
- A vertical face looking at the camera: N = (0, 0, −1), V = (0, 0, −1), L = (0, 1, 0.02) give
  `N·H = 0.70`, so the face gets `0.4 (floor) + 0.70 (specular)` = 1.1 × albedo while the top
  face gets about 1.0 + its own specular. Measured 0.62–0.67 × albedo on the purple cube's
  sides (the face normals are not exactly camera-aligned). With a real exponent of 32 the same
  face's specular is `0.70³² = 1.1 × 10⁻⁵`, i.e. nothing.
- The highlight is tinted by the albedo (`× albedo`), so it reinforces the surface hue instead
  of adding the light's color; for ordinary non-metal surfaces the highlight should be the
  light's color **[codex]**.
- Because the intensity is the exponent, setting `specularIntensity = 0` would not turn
  specular off: `pow(x, 0) = 1` for any positive `x`, i.e. full highlight everywhere
  **[codex]**.

This is the "colors look too intense / shading is stark" symptom: every surface is pushed toward
white by a term that should only produce a small bright spot, and the hard clip at 1.0 removes
the gradation that would otherwise show shape.

### 2c. World-space normals lit with eye-space vectors

`gbuffer_vertex` transforms normals with `normalMatrix` only (world space; there is no
`viewMatrix` multiply, compare the position, which does go through `sceneConstants.viewMatrix`).
`gbuffer_fragment_material` keeps that frame (`ApplyNormalMapEye` rotates the normal-map sample
onto the world-space T/B/N). But `deferred_directional_lighting_fragment` says "G-buffer
normals are eye-space" (`DirectionalLight.metal:50`) and uses:

- `sun_eye_direction = lightData.lightEyeDirection` — eye space;
- `view_dir = -normalize(eye_space_fragment_pos)` — eye space;
- `halfway_vector = normalize(sun_eye_direction + view_dir)` — eye space.

`dot(N_world, L_eye)` is only correct when the view rotation is the identity. For the ground
with the sun overhead, rotating the camera about X by a pitch angle changes the light vector's
components but not the stored normal's:

| Camera pitch | Correct N·L | Mixed-frame N·L |
|---|---|---|
| 0° | 1.000 | 1.000 |
| 4° (the screenshot) | 1.000 | 0.998 |
| 30° | 1.000 | 0.866 |
| 60° | 1.000 | 0.500 |
| 90° | 1.000 | 0.000 → below the 0.4 floor |

So the error is invisible in the screenshot and becomes the whole picture in a bank or a loop,
because the chase camera is parented to the aircraft. `deferred_point_lighting_fragment_common`
(`PointLights.metal:93-105`) has the identical mismatch (eye-space light position against the
same normal).

### 2d. The fake ambient

`max(N·L, 0.4)` (`DirectionalLight.metal:54-55`) and `shadowSample += 0.1` (`:87`) are two
partial stand-ins for a missing ambient term. Their side effects: the diffuse gradient is
compressed into [0.4, 1.0] (so shape reads flat, with a kink where the floor takes over), the
floor is multiplied by the shadow term (shadowed sides get `0.4 × 0.6 = 0.24 × albedo`, the
sphere-underside reading in the table), and the specular is applied regardless of `N·L`. The
single-pass shadow response (0.6 at full shadow) also differs from the tiled one (0.5), so the
two families cannot match even where both are "correct".

## Root cause 3 — OIT renderer: lighting is switched off, and the switched-off code was wrong

`material_fragment` (`Base.metal:98-144`) resolves the base color and returns it; the lighting
block at `Base.metal:118-136` is commented out ("TODO: This results in very dark scene").
`transparent_material_fragment` has the same commented block at
`OrderIndependentTransparency.metal:89-108`. So the ground pixel is exactly the albedo:
`(0.301, 0.701, 0.100)`, sRGB8 (149, 218, 89). ✓ Flat by construction. Order-independent
transparency only describes how overlapping transparent fragments are combined; it does not
require flat shading **[codex]**.

The commented code calls `Lighting::GetPhongIntensity` (`Lighting.metal:18-60`). Re-enabling it
as-is would indeed be very dark, for these reasons that are each visible in that function:

1. **Directional light treated as a point light.** `unitToLightVector = normalize(light.position
   - worldPosition)` (`:31`). The sun sits at (0, 200, 4). At the origin the ground's `N·L` is
   1.0; 100 m away 0.89; 500 m away 0.37; 2 km away 0.10. The scene is 1 000 km wide.
2. **Ambient only on back faces.** `if (nDotL <= 0) totalAmbient += ambientColor` (`:47-49`).
   Ambient is supposed to reach every surface. And its size is
   `material.ambient (0.1) × light.ambientIntensity (0.4) = 0.04`.
3. **`diffuseIntensity = 0.5` scales everything** (`:39`), and the floor `max(nDotL, 0.3)`
   (`:41`) gives far ground `0.5 × 0.3 = 0.15 × albedo`.
4. **Broad, bright specular.** `material.specular = (1, 1, 1)`, `shininess = 2.0`,
   `specularIntensity = 1.0`: `pow(R·V, 2)` is nearly as wide as diffuse, so the near ground
   would get a large highlight while the far ground stays at 0.15.
5. **Base color applied twice for imported materials [codex].** `Material.setProperties`
   (`Material.swift:195-199`) copies the MDL base color into `material.diffuse`;
   `GetPhongIntensity` multiplies by `material.diffuse`, and the fragment then multiplies the
   result by the resolved base color again.
6. **It no longer compiles as written [codex].** The opaque block tests
   `material.useNormalMapTexture` (`Base.metal:121`), a field `MaterialProperties`
   (`TFSCommon.h:42-52`) does not have.

The transparent variant lights `color` before `finalColor.xyz *= finalColor.w`, which is the
right order (light first, then premultiply), so nothing extra is needed there once the
function is replaced.

## Secondary inconsistencies (verified)

None of these produces the three screenshot symptoms, but each one makes two renderers disagree
on some object, and several become visible the moment the main fix lands (the aircraft body gets
shaded while its canopy stays flat, for instance). All adopted from the Codex review and
re-verified in the source **[codex]**.

1. **Deferred transparency is unlit.** `TiledDeferredTransparency.metal:38-59` and
   `SinglePassDeferredTransparency.metal:72-94` output base color × opacity, no lighting. The
   F-22 canopy has opacity < 1 (see `material_color_bleeding_bug.md`) and goes through this
   path in every deferred renderer. The MSAA pipelines bind the tiled transparency fragment too.
2. **The untextured-material fallback differs per path.** `ResolveBaseColor` takes a caller
   fallback; callers disagree:

   | Path | Fallback when no object color and no base-color texture |
   |---|---|
   | Tiled G-buffer (`TiledDeferredGBuffer.metal:94-99`) | `material.color` |
   | Single-pass G-buffer (`GBuffer.metal:166-171`) | `in.color` (interpolated vertex color) |
   | OIT opaque (`Base.metal:108-113`) | `material.color` |
   | OIT transparent (`OrderIndependentTransparency.metal:82-87`) | `rd.color` (vertex color) |
   | Deferred transparency (both) | `material.color` |

   Commit `f7693b3` (2026-04-15) set `material.color` as the fallback for untextured submeshes
   in four shaders and did not touch these two, so this looks like an omission rather than a
   design choice. `Vertex.color` defaults to `(0, 0, 0, 1)` (`MetalTypes.swift:52`), so an
   untextured imported submesh can render black in single-pass and OIT-transparent while it
   renders with its authored color elsewhere.
3. **The OIT opaque fragment ignores UV transforms.** `material_fragment` samples at
   `rd.textureCoordinate` and does not take `MaterialTextureTransforms` at all
   (`Base.metal:99-106`), while `transparent_material_fragment` and every deferred fragment
   apply them.
4. **Bitangent handedness differs.** `GBuffer.metal:62` negates the bitangent; the tiled
   vertex (`TiledDeferredGBuffer.metal:34`) and `Base.metal:43` do not. The same normal-map
   sample tilts a surface one way in single-pass and the other way in the tiled renderers.
   Which convention is right is not established here; the diagnostic test is in
   [Verification](#verification-for-after-the-fix-nothing-here-was-run-against-modified-code).
5. **`base_animated_vertex` skins the normal but not the tangent or bitangent**
   (`Base.metal:75-77`); the tiled and single-pass animated vertices skin all three. Harmless
   while OIT normal mapping is commented out; wrong once it is re-enabled.
6. **An explicit zero specular cannot be imported.** `Material.setProperties` assigns
   `specular`, `ambient`, `diffuse` and `shininess` only when the MDL value is non-zero
   (`Material.swift:189-209`), so a material authored as matte keeps the default
   `specular = (1, 1, 1)`.

## The fix

### The idea

One function, called by all three paths, with the classic structure

    color = ambient + litFraction × (diffuse + specular)

where `ambient = albedo × lightColor × brightness × ambientIntensity`,
`diffuse = albedo × lightColor × brightness × diffuseIntensity × max(N·L, 0)`,
`specular = lightColor × brightness × specularIntensity × specularStrength × pow(max(N·H, 0), shininess)`,
and `litFraction ∈ [0, 1]` is the raw PCF result. The shadow scales only the direct light, so a
shadowed surface and a surface facing away from the sun both settle at the ambient level, which
is what the eye expects. `ambientIntensity + diffuseIntensity ≤ 1` keeps a fully lit,
non-specular surface from clipping. Each renderer keeps its own frame (world for tiled and OIT,
eye for single-pass) but must pass N, L and V in that one frame. With more than one directional
light, ambient is added once and each light contributes its own direct term; the deferred paths
currently bind only the first sun **[codex]**.

Design sources: [source: Phong 1975 / Blinn 1977] the ambient + Lambert + Blinn half-vector
model; [source: Apple "Rendering a Scene with Deferred Lighting"] the single-pass G-buffer
layout and eye-space reconstruction the engine already follows; [codebase] `LightData`'s
`ambientIntensity` / `diffuseIntensity` / `specularIntensity` / `brightness` fields, which were
designed for exactly this and are currently unused by two of the three paths; [design] shadow
scales direct light only, replacing the `0.5 + 0.5 × lit` floor; [design] ambient is
`albedo × ambientIntensity` and does **not** multiply `material.ambient`, whose contents are a
mix of the legacy Phong reflectance, imported emission and the tiled helper's "occlusion"
**[codex]**.

### Landing order

1. **Diffuse + ambient parity.** Steps 1–5b with `specularStrength = 0` everywhere, no scene
   value changes. "Everywhere" includes the single-pass fragment: Step 4 passes
   `kDefaultSpecularStrength` in this step, never the G-buffer alpha, which is a constant 1.0
   until Step 6 lands. Compare the three renderers on the deterministic objects; they should
   agree to within 8-bit quantization. This isolates the ambient, frame and `half` fixes from
   any specular tuning **[codex]**.
2. **Specular.** Set the default strength and shininess (Step 6), then switch Step 4 to the
   G-buffer alpha. Confirm zero strength removes the highlight and a larger exponent narrows it
   without changing its peak brightness.
3. **Secondary consistency.** Fallback color, UV transforms, handedness, tangent skinning, zero
   specular import (Steps 5 and 6).
4. **Follow-ups** (not needed for the screenshots): the items under
   [Also observed](#also-observed-out-of-scope-and-follow-ups).

### Step 1 — `Lighting.metal`: add the shared function, make the shadow return the raw lit fraction

```pseudocode
// All direction vectors are unit length and in ONE frame chosen by the caller
// (world for the tiled and OIT paths, eye for the single-pass path).
// albedo and light.color are linear RGB. litFraction is 0 (fully shadowed) .. 1 (fully lit).
function shadeDirectionalBlinnPhong(albedo, unitNormal, unitToLight, unitToCamera,
                                    light, specularStrength, shininess, litFraction) -> color
    lightRadiance = light.color * light.brightness
    // ambient: bounce-light stand-in, reaches every surface, never shadowed
    ambient = albedo * lightRadiance * light.ambientIntensity
    // diffuse: Lambert, zero for surfaces facing away from the light
    nDotL = max(dot(unitNormal, unitToLight), 0)
    diffuse = albedo * lightRadiance * light.diffuseIntensity * nDotL
    // specular: Blinn-Phong highlight in the LIGHT's color; the exponent is the material's
    // shininess, and specularIntensity is a linear scale, never an exponent
    specular = 0
    if nDotL > 0 and dot(unitNormal, unitToCamera) > 0 and specularStrength > 0
        halfSum = unitToLight + unitToCamera
        if length(halfSum) > smallEpsilon            // light exactly behind the camera: no half vector
            halfVector = normalize(halfSum)
            nDotH = max(dot(unitNormal, halfVector), 0)
            specular = lightRadiance * light.specularIntensity * specularStrength
                       * pow(nDotH, max(shininess, 1))   // exponent below 1 widens past the diffuse lobe
    return ambient + litFraction * (diffuse + specular)
```

The three guards (front-lit, camera-facing, non-degenerate half vector) and the exponent floor
are adopted from the Codex sketch **[codex]**; they cost nothing and remove the cases where the
old code produced highlights on surfaces the light cannot reach.

```pseudocode
// CalculateShadow: return the PCF lit fraction itself.
// Today: return 0.5 + 0.5 * lit   (Lighting.metal:210)
// New:   return clamp(lit, 0, 1)
// Keep the old mapping as a named, deprecated helper so the "shadows never fully black"
// behaviour can be compared side by side:
function legacyLightenedShadow(litFraction) -> factor
    return 0.5 + 0.5 * litFraction      // deprecated: ambient now provides the fill
```

Change the return contract and its consumers in the same commit: changing only the constant
would make today's renderers darker without adding the ambient that replaces it **[codex]**.
Keep the cascade selection, PCF kernel, bias and cascade blending exactly as they are.

`GetPhongIntensity` and `CalculateDirectionalLighting` stay as deprecated reference code
(project rule: superseded code that teaches something is kept and routed through the surviving
API). Make `CalculateDirectionalLighting` a thin call into `shadeDirectionalBlinnPhong` with
`specularStrength = 0`, `unitToCamera = unitNormal`, `litFraction = 1`, and mark
`GetPhongIntensity` deprecated with a comment naming its defects (point-style direction,
back-face-only ambient, N·L floor, exponent 2, base color applied twice).

Defaults to add next to the function, used wherever no material is available:

| Constant | Value | Why |
|---|---|---|
| `kDefaultSpecularStrength` | 0.25 | a plastic-like highlight on untextured objects; 1.0 doubles the brightness of every camera-facing surface. Land with 0 first (landing order step 1) |
| `kDefaultShininess` | 32 | highlight about 10° wide; exponent 1–2 is a second diffuse lobe. An illustrative tuning value, not a measured material property |

### Step 2 — `TiledDeferredDirectionalLight.metal` (covers all three tiled renderers)

The fragment needs the camera position for V. `SceneManager.SetSceneConstants` already binds
`SceneConstants` to the fragment stage at `TFSBufferIndexSceneConstants`
(`GameScene.swift:224-233`), so add that parameter; no Swift change needed.

```pseudocode
function tiledDirectionalLightFragment(gBuffer, light, sceneConstants) -> lightingColor
    albedo = gBuffer.albedo.rgb
    litFraction = gBuffer.albedo.a                      // written by the G-buffer pass
    unitNormal_world = normalize(gBuffer.normal.xyz)    // rgba16Float; renormalize after storage
    worldPosition = gBuffer.position.xyz
    unitToLight_world = light.direction                 // unit, surface -> sun
    unitToCamera_world = normalize(sceneConstants.cameraPosition - worldPosition)
    color = shadeDirectionalBlinnPhong(albedo, unitNormal_world, unitToLight_world, unitToCamera_world,
                                       light, kDefaultSpecularStrength, kDefaultShininess, litFraction)
    return (color, 1)
```

Delete the `MaterialProperties material` stand-in (`shininess = 0.1`, `ambient = 1.0`) and the
trailing `color *= albedo.a`: the shadow is now applied inside the function, to direct light
only. `TiledDeferredGBuffer.metal:106` keeps writing `color.a = CalculateShadow(...)`; the
value's meaning changes from "0.5..1 factor" to "0..1 lit fraction" automatically once Step 1
lands. `TiledMSAAGBuffer.metal:41` is the same line in a function no pipeline binds; either
keep it in sync or mark the file deprecated **[codex]**.

Optional later step (keeps the simple version as reference): the G-buffer normal target's `w`
is written as `1.0` and never read (`TiledDeferredGBuffer.metal:118`). Store the material's
specular strength there so textured aircraft get their own value instead of the constant. The
tiled G-buffer carries no exponent or specular color; full per-material parity is a documented
G-buffer layout change (`TFSCommon.h`, `ShaderDefinitions.h`, both texture structs, every
pipeline's attachment formats), not something the current layout can recover **[codex]**.

### Step 3 — `GBuffer.metal` (single-pass G-buffer, both vertex variants and both fragments)

Fixes 2a and 2c together and removes secondary item 4. Build the normal in **world space, in
`float`, with the same helper the tiled path uses**, and rotate only the final unit vector
into eye space when storing it. This is the Codex variant of the repair **[codex]**; it was
chosen over the smaller vertex-only change (below) because it gives every renderer one
normal-map helper and one handedness convention, and it never narrows anything but a unit
vector to `half`.

```pseudocode
// gbuffer_vertex and gbuffer_animated_vertex: emit the same world-space basis as the tiled vertex.
// ColorInOut drops its half3 tangent / bitangent / normal fields and gains float3 world ones.
out.worldNormal    = normalMatrix * modelNormal          // length = model scale; fine in float
out.worldTangent   = normalMatrix * modelTangent
out.worldBitangent = normalMatrix * modelBitangent       // no negation: one convention for every renderer
out.eyePosition    = (sceneConstants.viewMatrix * worldPosition).xyz   // unchanged
// the animated variant skins position, normal, tangent and bitangent first, as it does today

// gbuffer_fragment_material (gbuffer_fragment_base is the same without the normal-map branch)
unitNormal_world = normalize(in.worldNormal)
if a normal map is bound and not useObjectColor
    unitNormal_world = applyNormalMapWorld(sample, in.worldTangent, in.worldBitangent, in.worldNormal)
// the view matrix is rigid for both camera types (AttachedCamera strips its parent's scale),
// so its upper-left 3x3 rotates a direction into eye space; use its inverse transpose instead
// if a scaled camera is ever allowed
viewRotation = upperLeft3x3(sceneConstants.viewMatrix)
unitNormal_eye = normalize(viewRotation * unitNormal_world)
gBuffer.normal_shadow = (half3(unitNormal_eye), litFraction)   // a unit vector: safe in half and in rgba8Snorm
gBuffer.depth = in.eyePosition.z                               // unchanged
```

`ApplyNormalMapEye` becomes unused; keep it with a deprecation comment. `in.worldNormal`
continues to feed `SlopeScaledWorldBias` unchanged. The comment in `gbuffer_fragment_base`
("interpolated eye-space geometric normal") becomes true of the stored value. This also repairs
the point-light pass for free, because `PointLights.metal` already works in eye space.

Smallest-diff alternative (kept as reference): keep the `half3` fields and write
`half3(normalize(viewRotation * (normalMatrix * modelNormal)))` in the vertex shader (normalize
in `float` first, then narrow). It fixes 2a and 2c but leaves two normal-map helpers and the
handedness difference in place.

Alternative rejected: keep world-space normals and rewrite `DirectionalLight.metal` and
`PointLights.metal` to light in world space. That needs an inverse view matrix in
`SceneConstants` to get world positions back from the eye-space depth and touches two shaders
instead of one.

### Step 4 — `DirectionalLight.metal` (single-pass lighting)

Two commits, one per landing-order step. The G-buffer alpha is not a usable specular strength
until Step 6 lands: `GBuffer.metal:186-190` writes a constant 1.0 into `albedo_specular.w` for
every surface without a specular map (every `setColor` object), and the parity-step
`kDefaultShininess` is 1 (commit `8af20b4` set it that low because `kDefaultSpecularStrength`
is 0, which keeps the exponent inert). Reading the alpha before Step 6 therefore re-creates root
cause 2b, in white rather than tinted by albedo; the numbers are in the table below.

```pseudocode
// Landing order step 1 (diffuse + ambient parity). Specular off, exactly as the tiled fragment
// does it: TiledDeferredDirectionalLight.metal:59 passes kDefaultSpecularStrength, not a G-buffer value.
function deferredDirectionalLightingFragment(in, gBuffer, light) -> lighting
    albedo = gBuffer.albedo_specular.rgb
    specularStrength = kDefaultSpecularStrength        // 0 in this step; NOT gBuffer.albedo_specular.a yet
    unitNormal_eye = normalize(gBuffer.normal_shadow.xyz)   // renormalize: 8-bit storage changes the length slightly
    litFraction = gBuffer.normal_shadow.a              // raw PCF lit fraction since Step 1
    unitToLight_eye = light.lightEyeDirection
    eyePosition = reconstructEyePosition(in.eyeRay, gBuffer.depth)
    unitToCamera_eye = -normalize(eyePosition)         // camera is at the eye-space origin
    color = shadeDirectionalBlinnPhong(albedo, unitNormal_eye, unitToLight_eye, unitToCamera_eye,
                                       light, specularStrength, kDefaultShininess, litFraction)
    return (color, 1)
```

```pseudocode
// Landing order step 2 (specular on). Only after Step 6 has landed, i.e. GBuffer.metal writes
// material.specular.r (default 0.25) into albedo_specular.w and kDefaultShininess is 32.
// The one line that changes:
    specularStrength = gBuffer.albedo_specular.a       // specular map sample, or the Step 6 material default
```

Removed on purpose: `minimum_sun_diffuse_intensity = 0.4`, `shadowSample += 0.1`,
`specular_intensity` used as the exponent, `shininess = 1.0`, and the `× albedo` tint on the
highlight. The ambient term now does what those constants were approximating.

**What the early switch to the alpha produced (observed 2026-09-21).** Implemented with
`specularStrength = gBuffer.albedo_specular.a` after commit `8af20b4` and before Step 6, every
directly lit object in the single-pass renderer read almost pure white. Inside
`shadeDirectionalBlinnPhong` the three guards pass on any sun-facing, camera-facing surface, and
with strength 1, `specularIntensity` 1 (the `LightData()` default, which the scene never sets)
and exponent 1 the highlight collapses to `N·H` in the sun's white color, added on top of the
`0.9 × albedo` that ambient + diffuse already produce. For a top face under an overhead sun
`N·H = √((1 + sin θ) / 2)`, where θ is the camera's downward pitch, so the chase camera's usual
4°–30° gives about 0.74–0.87 and nothing stays below 1.0. Shadowed ground is unaffected because
the specular sits inside the `litFraction × (…)` term, which is why only the directly lit objects
blew out. Existing 0.4 / 0.5 intensities, camera pitched 10° down, linear then sRGB8:

| Surface | N·H | Alpha read early (strength 1, exponent 1) | `kDefaultSpecularStrength` (parity step) | Step 6 values (0.25, exponent 32) |
|---|---|---|---|---|
| Lit ground (0.3, 0.7, 0.1) | 0.77 | (1.04, 1.40, 0.86) → clips to (255, 255, 239) | (0.270, 0.630, 0.090) → (142, 208, 85) | specular 6 × 10⁻⁵, same (142, 208, 85) |
| F-22 upper skin, albedo 0.578 | 0.77 | 1.29 → (255, 255, 255) | 0.520 → (191, 191, 191) | 0.520 → (191, 191, 191) |
| Ground fully in the jet's shadow | — | (0.120, 0.280, 0.040) → (97, 144, 56) | same | same |

Ruled out while diagnosing it: the eye-space `LightData` does carry the scene's intensities
(`LightManager.GetDirectionalLightData` copies the live struct and overwrites only
`lightEyeDirection`); the directional lighting pipeline has no blending and the G-buffer's
designated initializer zeroes its `lighting` output, so nothing is lit twice; normal and light
are both eye-space after Step 3.

### Step 5 — `Base.metal` and `OrderIndependentTransparency.metal` (OIT)

Re-enable lighting through the shared function. `RasterizerData` already carries
`worldPosition`, `toCameraVector` and `surfaceNormal` (world space, unnormalized), and the
OIT render pass binds `lightCount` + the `LightData` array (`LightManager.SetDirectionalLightData`).

```pseudocode
// material_fragment (opaque) — replaces the commented block at Base.metal:118-136
function materialFragment(rd, material, uvTransforms, lightCount, lights, textures) -> output
    baseUV = rd.textureCoordinate
    normalUV = rd.textureCoordinate
    if uvTransforms.hasTextureTransforms                   // secondary item 3: same as every other fragment
        baseUV = applyUVTransform(rd.textureCoordinate, uvTransforms.baseColorUVTransform)
        normalUV = applyUVTransform(rd.textureCoordinate, uvTransforms.normalUVTransform)
    baseColor = resolveBaseColor(rd.useObjectColor, rd.objectColor, material.color, baseColorMap, baseUV)
    unitNormal_world = normalize(rd.surfaceNormal)
    if a normal map is bound and not useObjectColor
        unitNormal_world = applyNormalMapWorld(sample at normalUV, rd.surfaceTangent, rd.surfaceBitangent, rd.surfaceNormal)
    if lightCount == 0 or not material.isLit                // no sun registered: draw unlit rather than black
        litColor = baseColor.rgb
    else
        unitToCamera_world = normalize(rd.toCameraVector)
        litColor = 0
        for each light in lights[0 ..< lightCount]
            if light.type == Directional
                unitToLight_world = light.direction
            else
                unitToLight_world = normalize(light.position - rd.worldPosition)   // point lights, no attenuation yet
            litColor += shadeDirectionalBlinnPhong(baseColor.rgb, unitNormal_world, unitToLight_world, unitToCamera_world,
                                                   light, material.specular.r, material.shininess, 1)   // OIT has no shadow map
    output.color0 = (litColor, baseColor.a)
    output.color1 = (unitNormal_world, 1)
```

```pseudocode
// transparent_material_fragment — same shading, then the existing premultiply and layer insert
baseColor = resolveBaseColor(rd.useObjectColor, rd.objectColor, material.color, ...)   // secondary item 2: material.color, not rd.color
litColor = same normal resolution and light loop as above
finalColor = (litColor, resolveOpacity(baseColor.a, material.opacity))
finalColor.rgb *= finalColor.a                       // premultiply ONCE, after lighting, as the existing code does
insert into the image-block layers                   // unchanged
```

**Also in `base_animated_vertex`: skin the tangent and bitangent (secondary item 5).** A skinned
mesh moves with a skeleton. For each vertex, `BlendJointMatrix` blends the joint matrices by the
vertex's joint weights into one 4×4 skin matrix, and the position is multiplied by it to follow
the bones. Every direction attached to the surface has to follow the same way, or it describes
the unposed surface. Three directions matter for normal mapping: the normal N, the tangent T
(along the texture's U axis) and the bitangent B (along V). A normal-map texel `(x, y, z)` is
decoded as `x·T + y·B + z·N`, so if T and B lag behind N the bump is tilted in the wrong
direction by the joint's rotation. At commit `8af20b4`, `Base.metal:60-62` and `:75-77` do this:

```pseudocode
skinMatrix       = blendJointMatrix(jointMatrices, joints, jointWeights)   // one 4x4 per vertex
skinnedPosition  = skinMatrix * (modelPosition, w = 1)     // point: translation applies
skinnedNormal    = skinMatrix * (modelNormal,   w = 0)     // direction: translation ignored

rd.surfaceNormal    = normalMatrix * skinnedNormal.xyz     // follows the pose
rd.surfaceTangent   = normalMatrix * modelTangent          // still in the bind pose
rd.surfaceBitangent = normalMatrix * modelBitangent        // still in the bind pose
```

The fix is two extra lines using the same blended matrix, which is what the tiled animated
vertex already does at `TiledDeferredGBuffer.metal:55-56`:

```pseudocode
skinnedTangent   = skinMatrix * (modelTangent,   w = 0)
skinnedBitangent = skinMatrix * (modelBitangent, w = 0)
rd.surfaceTangent   = normalMatrix * skinnedTangent.xyz
rd.surfaceBitangent = normalMatrix * skinnedBitangent.xyz
```

Worked example: a flap with N = (0, 1, 0), T = (1, 0, 0), B = (0, 0, 1) in the bind pose,
deflected 90° about its hinge, the X axis. The skinned N becomes (0, 0, 1). The unskinned B is
still (0, 0, 1), now parallel to N, so the frame is degenerate. A texel tilted along V,
`(0, 0.5, 0.87)`, decodes to `0.5·B + 0.87·N = (0, 0, 1.37)`, which normalizes back to the plain
normal: the bump vanishes. With the fix B becomes (0, −1, 0) and the same texel decodes to
(0, −0.5, 0.87), a real tilt. This is harmless while the OIT fragment's normal-map code is
commented out, because only N is read; it becomes wrong the moment Step 5 re-enables it.

**The zero-light guard [codex].** `LightManager.SetDirectionalLightData`
(`LightManager.swift:78-102`) always binds the count, but binds the `LightData` array only inside
an `if let base = buf.baseAddress` on the scratch array. With no directional light registered
there is nothing to bind, and the shader's `lightData` parameter then points at whatever that
buffer slot last held on this encoder, or at nothing. Reading it is undefined: the validation
layer reports a missing binding, and the GPU reads garbage. At `8af20b4` `material_fragment`
declares the parameters (`Base.metal:101-102`) but never reads them because the lighting block
is commented out, so nothing goes wrong yet. Once Step 5 re-enables the loop, the fragment must
consult the count before touching the array:

```pseudocode
if lightCount == 0 or not material.isLit
    litColor = baseColor.rgb                 // unlit fallback, never indexes lightData
else
    for i in 0 ..< lightCount                // the bound is the only thing that makes lightData[i] safe
        litColor += shade(..., lightData[i], ...)
```

The loop bound alone already prevents the out-of-bounds read. The explicit guard adds the second
purpose: ambient lives inside the per-light call, so a scene with no sun would otherwise sum zero
lights and draw every surface black. The guard makes it draw the base color instead, which is
what the OIT path does at `8af20b4`.

### Step 5b — `TiledDeferredTransparency.metal` and `SinglePassDeferredTransparency.metal` [codex]

Same forward shading as the OIT fragments, so the canopy matches the fuselage. Both fragments
already receive `worldPosition`, `worldNormal`, `worldTangent` and `worldBitangent`
(`VertexOut`), the pass binds `SceneConstants` and the first sun's `LightData` to the fragment
stage, and the shadow array bound for the G-buffer stage is still bound on the same encoder
(`DrawManager.applyMaterialTextures` touches only texture indices 0–2).

```pseudocode
function deferredTransparencyFragment(in, material, uvTransforms, light, sceneConstants, shadowArray) -> color
    baseColor = resolveBaseColor(... material.color ...)          // unchanged
    unitNormal_world = normalize(in.worldNormal), normal-mapped as in the G-buffer fragment
    unitToCamera_world = normalize(sceneConstants.cameraPosition - in.worldPosition)
    fragViewSpaceDepth = (sceneConstants.viewMatrix * (in.worldPosition, 1)).z
    litFraction = calculateShadow(in.worldPosition, fragViewSpaceDepth, in.worldNormal, light, shadowArray)
                  // or 1 if the transparency stage should stay shadow-free in a first version
    litColor = shadeDirectionalBlinnPhong(baseColor.rgb, unitNormal_world, light.direction, unitToCamera_world,
                                          light, material.specular.r, material.shininess, litFraction)
    return (litColor, resolveOpacity(baseColor.a, material.opacity))   // straight alpha: the PSO blends sourceAlpha / oneMinusSourceAlpha
```

Do not premultiply here: these pipelines use `sourceAlpha` / `oneMinusSourceAlpha` blending
(`RenderPipelineState.enableBlending`), which multiplies by alpha itself. Premultiplying as well
would apply the opacity twice **[codex]**.

### Step 6 — Swift-side defaults and scene values

- `MetalTypes.swift:71-97` `MaterialProperties` defaults: `specular` (1, 1, 1) → (0.25, 0.25, 0.25)
  and `shininess` 2.0 → 32. `ambient` and `diffuse` become unused by the new path; leave them
  (the MDL import still fills them) with a comment. `Material.swift:186-217` maps `.emission`
  into `ambient` — mark that as legacy too.
- `Material.swift:189-209`: assign an authored specular / shininess even when it is zero, so a
  matte material stays matte (secondary item 6). Keep the non-zero guard only for the fields
  whose MDL default is a meaningless zero **[codex]**.
- `GBuffer.metal:186-192`: when no specular map is bound, write `material.specular.r` into
  `albedo_specular.w` instead of the constant `1.0`, so Step 4 reads a sensible strength.
- `GBuffer.metal:166-171`: pass `material.color` as the `ResolveBaseColor` fallback instead of
  `in.color` (secondary item 2).
- **Scene light values: no change is required for the fix.** The existing 0.4 / 0.5 in
  `FlightboxWithPhysics` is a usable baseline: a lit top face stays at `0.9 × albedo`, exactly
  today's tiled lit pixel, and sides rise from black to `0.4 × albedo` **[codex]**. The
  optional retune below makes a lit surface reach `1.0 × albedo` (today's OIT pixel) and
  brings the scenes that were tuned against the old floor behaviour into the same range:

| Scene | Today (ambient, diffuse) | Optional retune | Note |
|---|---|---|---|
| `FlightboxWithPhysics.swift:175-176` | 0.4, 0.5 | 0.3, 0.7 | the screenshots' scene |
| `FlightboxWithTerrain.swift:52-53` | 0.4, 0.5 | 0.3, 0.7 | |
| `FlightboxScene.swift:57-59` | 0.04, 0 | 0.3, 0.7 | diffuse 0 was set while the point lights were being tested |
| `BallPhysicsScene.swift:45-46`, `PhysicsStressTestScene.swift:82-83` | 0.04, 0.15 | 0.3, 0.7 | tuned against the old floor behaviour |
| `SandboxScene.swift:27` | 0.04, (default 1.0) | 0.3, 0.7 | |
| `FreeCamFlightboxScene.swift:22-23` | defaults 1.0, 1.0 | 0.3, 0.7 | would clip at 2 × albedo otherwise |

`specularIntensity` can stay at the default 1.0 now that it is a linear scale.

### Worked example

Sun direction (0, 0.9998, 0.02), camera looking slightly down, ground albedo (0.3, 0.7, 0.1),
a hypothetical (0.5, 0, 0.5) cube. Left column: the scene's existing values with specular off
(landing order step 1). Right column: the optional retune with specular strength 0.25 and
shininess 32.

| Surface | N·L | Baseline 0.4 / 0.5, no specular | Retune 0.3 / 0.7 with specular | Today |
|---|---|---|---|---|
| Lit ground | 0.9998 | (0.270, 0.630, 0.090) → (142, 208, 85) | (0.300, 0.700, 0.100) → (149, 218, 89) | tiled (142, 208, 85), single-pass (96, 144, 56), OIT (149, 218, 89) |
| Ground in the jet's shadow | — | (0.120, 0.280, 0.040) → (97, 144, 56) | (0.090, 0.210, 0.030) → (85, 126, 48) | tiled (103, 152, 61), single-pass (76, 114, 43) |
| Cube top | 0.9998 | (0.450, 0, 0.450) → (179, 0, 179) | (0.500, 0, 0.500) → (188, 0, 188) | |
| Cube side facing the camera | 0.02 | (0.200, 0, 0.200) → (124, 0, 124) | (0.150, 0, 0.150) → (108, 0, 108) | tiled (0, 0, 0), single-pass ≈ 1.1 × albedo |
| Highlight peak on a sphere (N = H) | — | no specular | (0.654, 0.250, 0.654) → (211, 137, 211) | a spot, not a wash |

Gray reference surface (albedo 0.5, white sun, brightness 1, the baseline 0.4 / 0.5), linear
per channel, same as the Codex table and re-derived **[codex]**:

| N·L | Lit fraction | Old tiled | Proposed |
|---|---|---|---|
| 0 | 1 | 0 | 0.200 (sRGB 0.485) |
| 0.5 | 1 | 0.225 | 0.325 (sRGB 0.606) |
| 1 | 1 | 0.450 | 0.450 (sRGB 0.701) |
| 1 | 0 | 0.225 (old shadow remap) | 0.200, ambient only |

The three renderers converge on the same lit-ground pixel, sides are visible but clearly
darker than tops, shadows are darker than today but not black, and nothing clips.

### Edge cases and expected results

- A surface facing away from the sun: `N·L = 0`, specular forced to 0, result = ambient.
- Fully shadowed surface facing the sun: `litFraction = 0`, result = ambient (same as above).
- Sun exactly overhead with the camera banked 90° (single-pass): the ground keeps `N·L ≈ 1`
  after Step 3 because both vectors are rotated by the same view matrix; today it would drop
  to the floor (table in 2c).
- Object scaled by 10⁶ (the ground): Step 3 normalizes in `float`; the `half` value is finite
  and unit length.
- `LightData()` defaults (ambient 1.0, diffuse 1.0) in a scene that never calls the setters:
  a lit surface reaches 2 × albedo and clips. Either the scene sets the values (Step 6) or
  `LightData()` defaults change to 0.3 / 0.7.
- No directional light registered (OIT): the guard draws the base color unlit instead of
  reading an unbound buffer.
- `specularStrength = 0` (landing order step 1): the specular branch is skipped entirely, so
  the parity comparison is diffuse + ambient only.
- Point lights in the OIT path get direction but no attenuation from this change; that is the
  existing behaviour (they were never lit there) and can follow later using `light.attenuation`.

## Verification (for after the fix; nothing here was run against modified code)

1. Compile each touched shader standalone:
   `xcrun -sdk macosx metal -c "ToyFlightSimulator Shared/Graphics/Shaders/<file>.metal" -o /dev/null`
   (the header includes resolve from the shader directory).
2. Build macOS Debug (command in `CLAUDE.md`).
3. Compare on **deterministic geometry only** **[codex]**: the ground, the red ground-level
   cube at (0, 1, 110), the blue calibration cube and the aircraft. `makeRandomDispersedObjects`
   re-rolls colors and positions on every scene rebuild, and a renderer switch rebuilds the
   scene.
4. Landing order step 1: run the app in each of the five working renderers, screenshot the
   same chase-camera view, sample the lit ground with the pixel script. All renderers should
   read (142, 208, 85) ± 2 with the existing light values (or (149, 218, 89) after the retune).
   Sides of the colored objects should read about `0.4 × albedo` (baseline) — not black, not
   ≈ albedo. The F-22's upper skin should no longer be (255, 255, 255) in single-pass. The
   canopy should shade like the fuselage in the deferred renderers. The screenshot path
   preserved shader values to ±1 in this analysis, so screenshots are adequate here; a GPU
   capture is the fallback if a display profile ever interferes **[codex]**.
5. Single-pass only: bank the aircraft 90° and confirm the ground brightness does not change.
   With specular off, rotating only the camera must not change any fixed surface's brightness
   in any renderer **[codex]**.
6. Tiled and single-pass: the shadow under the jet should read `ambientIntensity × albedo`,
   (97, 144, 56) for the ground at the baseline values.
7. Landing order step 2: `specularStrength = 0` must remove the highlight entirely; raising
   the exponent must narrow the spot without moving its peak. Before Step 4 switches to the
   G-buffer alpha, confirm `GBuffer.metal` writes `material.specular.r` and not the constant
   1.0 (Step 6), or the single-pass lit surfaces clip to white (table under Step 4).
8. Handedness (secondary item 4) **[codex]**: bind a diagnostic normal map. A flat sample
   `(0.5, 0.5, 1)` must reproduce the unmapped shading in every renderer; a sample tilted
   toward +bitangent must tilt the shading the same way in every renderer.
9. Transparency **[codex]**: a lit transparent sphere keeps its brightness gradient. For a
   straight lit color 0.6 at opacity 0.5 over a 0.2 background the composed value is 0.4;
   premultiplying twice would fail this.

## What was executed for this analysis

- Read the shader, pipeline, renderer, light, material and scene sources listed above.
- Sampled the three screenshots with `renderer_shading_color_mismatch_sample_pixels_2026-09-20.swift`
  (CoreGraphics, 5×5 average).
- Reproduced every quoted number with `renderer_shading_color_mismatch_numbers_2026-09-20.swift`
  (`swift <file>`), including `Float16(1_000_000) == inf` and the resulting NaN, and the
  numbers adopted from the Codex review (its gray-albedo table, the mixed-frame rotation
  values, the sRGB palette example, the nonuniform-scale example, the compositing check).
- Cross-checked the Codex diagnosis against the source: confirmed the `animatedVariant`
  mapping (`RenderPipelineStateLibrary.swift:78-85`), the stale `normalMatrix` in
  `DrawManager` (`:528-530`, `:552`), the unbound-material case (`:579-585`), the unbound MSAA
  fragment functions, the fallback-color table, the missing UV transforms, the handedness
  difference, the unskinned OIT tangents, the zero-specular import, `randomPaletteColor`
  (`RandomColor.swift:49-59`) and the tessellation fragment (`Tessellation.metal:125-151`).
- Did not build, run the app, or modify any source file.

## Comparison with the Codex diagnosis

Both documents reach the same three root causes: no ambient in the tiled sun pass, the
single-pass world/eye mismatch plus `half` overflow plus exponent-1 specular plus diffuse floor,
and OIT lighting commented out with a broken legacy helper behind it. Both propose the same
shape of fix: one shared ambient + Lambert (+ Blinn-Phong) function, the shadow helper
returning raw visibility applied to direct light only, eye-space normals for single-pass, and
lighting before premultiplication for OIT.

What this doc adds: the measured pixel values that turn each cause into an exact prediction
(Codex explicitly did not attribute pixels to calculations), in particular the 0.40 ground
ratio that identifies the `half` overflow as the reason the single-pass ground is dark, the
regression commit `ab04296`, and the clipped-white jet skin as the signature of the exponent-1
specular.

Adopted from Codex (each verified here): the secondary-inconsistencies section, the
world-space-then-rotate normal repair, the specular guards and exponent floor, the "specular
off first" landing order, keeping the existing 0.4 / 0.5 light values as the baseline, the
`lightCount == 0` guard, the straight-alpha rule for the deferred transparency pipelines, the
deterministic-geometry and normal-map verification steps, and the follow-ups below.

Not adopted here, deliberately: the full inverse-transpose normal matrix plus Gram-Schmidt
tangent-basis rebuild (Codex §8.5) and the HDR lighting targets (Codex §8.7). Both are sound but
neither affects the screenshots (the engine's model matrices are rigid + uniform scale, and
nothing needs values above 1.0 once the specular is fixed); they are listed as follow-ups with
a pointer to the Codex sections.

## Also observed, out of scope, and follow-ups

- The sky is black in all three screenshots even though `setupDefaultSky()` adds a SkyBox
  (single-pass) or SkySphere (OIT); the tiled renderers encode no sky stage at all. Separate
  issue.
- `Transform.normalMatrix(from:)` is the plain upper-left 3×3, not the inverse transpose. Correct
  for the engine's rigid + uniform-scale matrices once normalized; wrong for non-uniform scale:
  scale (2, 1, 1) with a local normal along (1, 1, 0) gives (0.894, 0.447, 0) today against the
  correct (0.447, 0.894, 0), and the wrong normal is no longer perpendicular to the transformed
  tangent (dot 0.6 instead of 0) **[codex]**. `TransformTests.normalMatrixBasics` asserts the
  current shortcut and would need updating with it. Codex §8.5 has the full basis rebuild.
- `DrawManager` applies a mesh-local animation transform to `modelMatrix` but leaves
  `normalMatrix` unchanged (`DrawManager.swift:528-530` ring-to-ring, `:552` legacy path), so a
  rotated control surface moves without its lighting normal following **[codex]**. Fix: derive
  the normal matrix from the combined transform in both paths.
- `RenderPipelineStateType.animatedVariant` (`RenderPipelineStateLibrary.swift:78-85`) maps the
  tiled transparency PSOs to the G-buffer **animated** PSOs, whose fragment writes G-buffer
  attachments, not blended lit color. A skinned transparent submesh in a tiled renderer is
  therefore not composited. Fix: real animated transparency PSOs for 1× and 4× sample counts
  **[codex]**.
- `DrawManager.drawSubmeshes` (`:579-585`) binds no material when `submesh.material` is nil,
  leaving the previous submesh's textures and constants bound. Bind an explicit fallback
  material and null textures for that case **[codex]**.
- `randomPaletteColor` (`RandomColor.swift:49-59`) copies `CGColor` components straight into a
  `float4` the shaders treat as linear. Those components are sRGB-encoded: a component of 0.5
  is linear 0.214, and the engine displays a linear 0.5 as sRGB 0.735, so midtone palette
  colors show lighter than their `NSColor` names. `Material.setBaseColor` does the same for
  `.color` properties. Fix: convert through color management to linear sRGB before handing the
  components to the shader; leave numeric `float3/float4` constants (`Colors.swift`) and
  texture samples alone, they are already linear **[codex]**. The same convention note applies
  to `setColor` values: `(0.3, 0.7, 0.1)` displays as sRGB (149, 218, 89). All renderers agree
  on this, so it is a convention, not a bug.
- The tiled albedo G-buffer is `bgra8Unorm` (linear 8-bit, `TiledDeferredGBufferTextures.swift:18`)
  while the single-pass one is `rgba8Unorm_srgb`. Dark albedos band in the tiled path; switching
  to the sRGB format costs nothing. Do not add a manual gamma curve to any shader: sRGB
  targets encode on write and decode on read, so the chain is not double-encoded **[codex]**.
- `tessellation_gbuffer_fragment` (`Tessellation.metal:125-151`, `FlightboxWithTerrain` only)
  writes a placeholder up normal or a raw, undecoded normal-texture sample, computes no
  shadow, and leaves texture alpha in the channel the light pass reads as the lit fraction.
  Terrain needs its own normal derivation and an explicit lit fraction (1 until terrain
  shadows exist) **[codex]**.
- HDR: if highlights or multiple lights should keep values above 1.0, a later milestone can
  render lighting into float targets and tone-map once at presentation. That means changing
  every matching pipeline attachment, the OIT image-block layer format and the composite
  shaders together, not just `Preferences.MainPixelFormat` **[codex]**. Not needed for these
  defects.
