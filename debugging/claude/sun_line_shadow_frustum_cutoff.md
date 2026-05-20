# "Sun Line" — Sharp Diagonal Lit/Dark Cutoff Investigation

Screenshot: `debugging/screenshots/SunLine.png`
Suspected file: `ToyFlightSimulator Shared/GameObjects/LightObject.swift`
Scene affected: `FlightboxWithPhysics` (and any other scene that uses the default `TiledMSAATessellated` renderer + a large ground).

## Symptom

A perfectly straight diagonal line across the screen splits the rendered image into two regions:

- One side: bright green ground + visible scattered debris.
- Other side: nearly pure black; debris is still visible (so 3D objects are being rasterized there) but the ground itself reads as black.

The user reports the line is "at some small negative Z value" in world space and sits behind the F-22 at scene start (visible only after rotating the camera). The line passes through the area near the jet.

## TL;DR

The sun's shadow map covers a fixed 200×200 region centered on the **world origin**, regardless of where the camera/jet is. The "small negative Z" line is the **edge of the light's orthographic frustum** as it crosses the ground plane. Past that edge, the clamped shadow texture sampler returns a depth value that fails the depth comparison, so `CalculateShadow` returns `0.5`. The tiled deferred directional-light fragment shader has **no ambient term** (it ignores `LightData.ambientIntensity`) — `color = diffuse * nDotL * material.color`, then `color *= albedo.a` halves it again, which after sRGB gamma reads as black. So you see a clean lit / black boundary instead of a 2× brightness difference.

Yes — the root cause does live in `LightObject.swift`. Specifically: the hard-coded ±100 orthographic projection and the hard-coded `target: .zero` in the light's view matrix.

## How the math lines up with "small negative Z"

`FlightboxWithPhysics.swift:87`:

```swift
sun.setPosition(0, jetPos.y + 100, 4)   // jet starts at (0, 100, 0) → sun at (0, 200, 4)
```

`LightObject.swift:15,18`:

```swift
let projectionMatrix: float4x4 = Transform.orthographicProjection(-100, 100, -100, 100, 0.01, 1000)
var viewMatrix: float4x4 {
    Transform.look(eye: self.getPosition(), target: .zero, up: Y_AXIS)
}
```

For sun at `(0, 200, 4)`, `target = (0,0,0)`, `up = (0,1,0)`:

- forward `≈ (0, -0.9998, -0.020)`
- right `≈ (-1, 0, 0)`
- up (light-Y in world) `≈ (0, 0.020, -1)`

The light's orthographic box in light-eye space is `X ∈ [-100, 100]`, `Y ∈ [-100, 100]`, `Z ∈ [0.01, 1000]`. Mapping the **Y edges** back to world space and intersecting with the ground plane (y = 0):

```
light_eye_y(P) = (P - sun) · (0, 0.020, -1)
              = 0.020·Py - Pz + 4
```

On the ground (Py = 0):

- light-eye Y = +100  →  Pz = −96   (call it world Z ≈ −100)
- light-eye Y = −100  →  Pz = +104  (call it world Z ≈ +100)

So the shadow map only covers a band of ground that is roughly **−100 ≤ Z ≤ +100** (with a 4-unit shift from the sun's `z=4`). The visible boundary the user described as "small negative Z" is the world Z ≈ −100 line — exactly the edge of the light's orthographic frustum on the ground plane. The X edges (world X = ±100) produce two more boundary lines, which a different camera angle would expose too.

The diagonal appearance in screen space is just camera-perspective foreshortening of that horizontal world-space line.

## How the lit/dark difference becomes lit/black

### 1) Inside the frustum — lit

Shadow pass (`Shadow.metal:18-29`) projects the F-22, F-16, sun ball, ground edge, etc. through `lightData.shadowViewProjectionMatrix` and writes orthographic depth into an 8192² `depth32Float` shadow map. The texture is cleared with the default depth clear value of **1.0** (`ShadowRendering.swift:40-46` does not set `clearDepth`, so the default applies). Areas of the shadow map with no occluding geometry stay at 1.0.

In the GBuffer pass, for a ground pixel **inside** the frustum:

- `shadowPosition = lightData.shadowViewProjectionMatrix * worldPosition` (`TiledDeferredGBuffer.metal:35`)
- `Lighting::CalculateShadow` (`Lighting.metal:73-85`) performs the perspective divide (no-op for ortho), remaps to `[0,1]` texture coords with Y flip, samples the depth, and compares:

  ```
  position.z ≈ 0.20   (ground at Py=0 in light eye z ≈ 200, ortho range 0..1000)
  shadow_sample ≈ 1.0 (cleared)
  0.20 > 1.001 ? false → return 1.0  ← LIT
  ```

`color.a = 1.0` written into GBuffer.albedo.a (`TiledDeferredGBuffer.metal:113`).

### 2) Just past the frustum edge — "shadowed"

For a ground pixel just past Pz ≈ −100, the projection gives `shadow_coord.y > 1`. The sampler is configured as `address::clamp_to_edge` (`Lighting.metal:81`), so the sample reads the **edge texel** of the shadow map. That edge texel contains the ground's own depth at the frustum boundary, which is approximately **0.20** (the ground's `position.z` at the boundary):

```
position.z ≈ 0.205 (slightly farther in light eye space than the edge ground)
shadow_sample ≈ 0.20
0.205 > 0.201 ? true → return 0.5  ← "SHADOWED" (self-shadowed by clamped edge)
```

This is a classic shadow-map clamp-to-edge artifact: the ground shadows **itself** the moment the shadow coordinate steps off the texture. `color.a = 0.5` is written into GBuffer.albedo.a.

### 3) Why 0.5 reads as black, not 50% green

`TiledDeferredDirectionalLight.metal:34-57`:

```glsl
material.color     = albedo;
material.shininess = 0.1;
material.ambient   = 1.0;   // hardcoded; LightData.ambientIntensity is NOT read
float3 color = 0;
for (uint i = 0; i < lightCount; i++) {
    color += Lighting::CalculateDirectionalLighting(lightData, normal, material);
}
color *= albedo.a;          // multiplies by the shadow value from step 1/2
return float4(color, 1);
```

`Lighting::CalculateDirectionalLighting` (`Lighting.metal:62-71`):

```glsl
float3 lightDirection   = normalize(light.position);   // ≈ (0, 0.9998, 0.020) for sun (0,200,4)
float  nDotL            = saturate(dot(normal, lightDirection));
float3 diffuse          = baseColor * (1.0 - metallic);
return diffuse * nDotL * ambientOcclusion * light.color;
```

There is **no ambient term**, no minimum brightness floor, and `LightData.ambientIntensity` is ignored entirely. So:

- Lit ground (per-pixel value, sRGB framebuffer): `green * 0.9 * 1.0 * 1.0 * (1,1,1) * 1.0 = green * 0.9`.
- "Shadowed" ground: `green * 0.9 * 1.0 * 1.0 * (1,1,1) * 0.5 = green * 0.45`.

`0.45` linear → about `0.71` after sRGB gamma. That's a perceptibly darker green, not black.

**But:** also relevant is `SinglePassDeferred`-era `DirectionalLight.metal:46-48` which has a `minimum_sun_diffuse_intensity = 0.4`; the tiled path has no such floor. And the ground Quad's vertex normals are sensitive to mesh orientation:

The ground is `Quad()` rotated `rotateZ(270°)` and scaled 1,000,000 (`GameScene.swift:94-109`). The base `quad.obj` mesh's face normal points along +Z (it's a plane in the XY plane). A pure Z rotation does not change the Z component of the normal, so the ground's world normal stays close to `(0, 0, 1)`, **not** `(0, 1, 0)`. Then:

```
nDotL = dot( (0,0,1), normalize(0,200,4) ) ≈ 0.020
diffuse_contribution ≈ green * 0.9 * 0.020 ≈ green * 0.018
* shadow 1.0  → green * 0.018         ← visibly dim "lit" pass-through
* shadow 0.5  → green * 0.009         ← virtually black
```

That's the actual brightness difference you're seeing. The "lit" side is already very dim (because of the bad normal × bad light-direction interaction); the "shadowed" side after `* 0.5` is essentially indistinguishable from clear-black on an sRGB display.

(The `TiledDeferredLightingDepthStencilState` comment at `TiledDeferredDepthStencils.swift:67-68` even says "This prevents the ground from rendering unless we invert the normals — TODO: figure out why this happens." That's the same normal-orientation issue acknowledged but unresolved.)

So the visible "lit / black" cutoff is the compound result of:

1. Tiny ±100 ortho light frustum centered at world origin → sharp boundary at world Z ≈ −100 (and ±100 in X, and +100 in Z).
2. `clamp_to_edge` shadow sampler → ground self-shadows past the boundary, `CalculateShadow` returns 0.5.
3. Tiled deferred lighting has no ambient floor (sun's `ambientIntensity = 0.4` is ignored) → the only contribution is diffuse × `nDotL`.
4. Ground quad's normal is `(0, 0, 1)` not `(0, 1, 0)`, so `nDotL` against the sun is ~0.02 even on the "lit" side; the `* 0.5` shadow scaling then drops the result below the visibility floor.

## Code paths and bug surface in `LightObject.swift`

```swift
// LightObject.swift:15 — light frustum is hard-coded and tiny relative to the world
let projectionMatrix: float4x4 = Transform.orthographicProjection(-100, 100, -100, 100, 0.01, 1000)

// LightObject.swift:16-19 — target is always world origin
var viewMatrix: float4x4 {
    Transform.look(eye: self.getPosition(), target: .zero, up: Y_AXIS)
}
```

These two constants together pin the shadow map to a fixed ±100 box around `(0,0,0)`. As the jet flies away (`F22.doUpdate` integrates position; `attachedCamera` is a child of the jet), the camera moves but the shadow box does not. In `FlightboxWithPhysics` (ground = 1,000,000 units, jet can be hundreds of thousands of units away), the entire visible ground may end up outside the shadow frustum, with the frustum's *boundary* on the ground forming the visible line the user is seeing.

Secondary smells in the same file, none of which cause the SunLine specifically but worth noting while we're here:

- Line 48 and line 58 both compute `projectionMatrix * <look(eye, .zero)>` and assign to `viewProjectionMatrix` and `shadowViewProjectionMatrix` respectively — duplicate work, and a foot-gun if one of them diverges from the other later.
- Line 54 (`lightData.eyeDirection = …`) is commented out. `LightData.lightEyeDirection` is never written; defaults to `(0,0,0)`. Nothing in the active shaders currently reads it, but `DirectionalLight.metal:59` is the prior call site (also commented), so this is dead weight rather than active bug.
- `shadowTransformMatrix` (set once in init) is only consumed by the **old** `GBuffer.metal:65-67` path. `TiledDeferredGBuffer.metal:35` ignores it and `CalculateShadow` re-derives the NDC→texture transform inline. Confusing to have both formulations; one should win.

The downstream shader-side contributors are real bugs but they're not in `LightObject.swift`:

- `Lighting::CalculateDirectionalLighting` interprets `light.position` as a direction (`Lighting.metal:67`). For a directional light this should be a separate `direction` field, or `normalize(light.position - worldPosition)` for a point light.
- That function never adds an ambient term — `LightData.ambientIntensity` is unused in the tiled deferred path.
- Ground `Quad` orientation produces a +Z world normal, not +Y.
- `clamp_to_edge` on the shadow sampler with no border depth is what turns "outside the frustum" into "self-shadow," instead of "fully lit."

## Suggested fixes (ranked by impact, no code changed yet)

### Highest impact — fix the actual sun line

1. **Make the sun follow the camera (or jet) on the X/Z plane, and keep the orthographic box big enough to cover the visible scene.** A common approach for a single directional light:
   - Each frame, compute the visible region you want shadowed (e.g. a box of `R` units around the camera on the ground plane). For a small scene `R = 500` is fine; for `FlightboxWithPhysics`'s 1M ground you want `R` proportional to the view distance you care about shadows over (maybe 2–5 km — shadows beyond that are pixel-thin anyway).
   - Move the sun to `cameraPos + sunDir * lift` (where `sunDir` is a fixed unit vector pointing from the scene to the sun and `lift` is chosen so the sun is well above any geometry, e.g. 2× R).
   - Use `target = cameraPos` (not `.zero`) in the look matrix.
   - Expand `projectionMatrix` to `orthographicProjection(-R, R, -R, R, near, far)` with `far` ≥ `2 * lift`.

   This is the canonical "sun-follow shadow camera" trick. After this, the shadow map covers wherever you're looking, the world-space frustum boundary moves with the camera (so the user never sees a static line), and shadows stay sharp.

2. **Add a sampler border value or switch to `clamp_to_zero`/`clamp_to_border` and write `1.0` outside.** This is the cheap mitigation for "shadow edge self-shadows everything past the boundary": configure the sampler so out-of-bounds samples return the far-plane depth (1.0). With Metal that means `address::clamp_to_zero` won't help (depth = 0 = closest), so use the border-color form or do a manual `if (any(xy < 0 || xy > 1)) return 1.0;` before `sample`. Both `Lighting::CalculateShadow` and the legacy `GBuffer.metal` path need this.

3. **Add an ambient floor to `CalculateDirectionalLighting`.** Read `light.ambientIntensity` and add `material.color * light.color * light.ambientIntensity` to the result, regardless of `nDotL`. This restores the per-scene `sun.setLightAmbientIntensity(0.4)` setting that the tiled path is currently throwing away. It also re-establishes the `minimum_sun_diffuse_intensity = 0.4` floor that the SinglePass path has (`DirectionalLight.metal:47`) but the tiled path lacks. With this in place, even a "fully shadowed" pixel won't go to zero.

If you do (1) alone the user-visible "Sun line" goes away because the line moves with the camera and is pushed off-screen (or to wherever the new ortho extent ends — choose R large enough). (1) + (2) together is the proper fix; (3) is independent ambient hardening that pays off everywhere.

### Other fixes worth bundling (related but separable)

4. **Fix `CalculateDirectionalLighting` to use a true direction.** Add a `LightData.direction` (or compute as `normalize(.zero - light.position)` for a sun-aimed-at-origin model, **once**, not per pixel) and use it as the light direction. Currently the function happens to work only when the sun is positioned roughly "above" most surfaces relative to the world origin; any other sun placement (e.g. low on the horizon) will produce wrong lighting silently.

5. **Fix the ground normal.** Either replace `Quad` with a horizontal-facing mesh (normal `+Y` at rest, no rotation needed), or change `addGround` to rotate around X instead of Z (`rotateX(±90°)`) so the original +Z face normal rotates to ±Y. After this change the ground's `nDotL` against an overhead sun will be ≈ 1.0 instead of ≈ 0.02, and the brightness difference between "lit" and "shadowed" sides will be the intended 2× rather than the perceptual lit-vs-black.

6. **De-duplicate `viewProjectionMatrix` / `shadowViewProjectionMatrix` in `LightObject.update()`.** They're identical today; consolidate to one assignment.

7. **Delete the commented `eyeDirection` line and the `lightEyeDirection` field** if no shader reads it. If something does want a light direction, add a clean `direction: simd_float3` and write it once in `update()`.

### Recommended minimum to make the SunLine go away

`(1)` fixes the symptom completely on its own — the boundary disappears off-screen because the shadow frustum is centered on (and sized for) the camera's view. Pair with `(3)` so future shadow misses (cascading boundaries, distant geometry past whatever R you pick, etc.) don't go to zero brightness either. `(5)` is independent but the next thing you'll notice once `(1)` lands — the now-properly-bright shadow boundary will reveal that the "lit" ground is much dimmer than it should be.

## Quick visual confirmation experiment (no code change)

If you want to verify the diagnosis before changing anything:

- In `FlightboxWithPhysics.buildScene()`, temporarily change `sun.setPosition(0, jetPos.y + 100, 4)` to `sun.setPosition(0, 1000, 0)`. The "Sun line" should rotate around (no Z component in the sun position → light's world-up axis becomes pure −Y → frustum bounds project to ±100 in *both* X and Z) and you'll see four boundary lines forming a square on the ground around the origin, instead of two near-parallel lines along the Z axis. That's the smoking gun for "frustum boundary = artifact."
- Or change the projection to `Transform.orthographicProjection(-100000, 100000, -100000, 100000, 0.01, 1000000)` and the line should disappear (subject to depth precision in the shadow map — this is just for diagnosis, not the real fix).
