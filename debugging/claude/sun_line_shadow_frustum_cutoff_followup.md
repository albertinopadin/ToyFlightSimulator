# "Sun Line" Follow-Up — Directional-Light Shadows, Other Light Types, Reverse-Z

Previous doc: [`sun_line_shadow_frustum_cutoff.md`](sun_line_shadow_frustum_cutoff.md)
Screenshot: `debugging/screenshots/SunLine.png`

## Corrections to the previous investigation

The original write-up overstated the brightness gap. Re-reading the screenshot with your clarifications in mind:

- **The "dark" side is dim, not black.** The previous doc claimed the shadow factor of `0.5` "reads as black after sRGB." That was wrong. `0.5` linear → ~`0.73` sRGB; on a lit pixel of green ground at full diffuse it would read as a clearly visible darker green. The objects (debris) on the dark side being still visible is consistent with `* 0.5`, not with "fully black." The black region at the top of the frame is just the framebuffer clear color (no skybox is rendered in `FlightboxWithPhysics`).
- **The diagonal angle is just camera roll.** The line is fixed in world space along the +X axis at roughly world Z ≈ −100; the F-22 is rolled ~45° at scene start so the line is rolled in screen space too. Rolling the camera changes the visible angle but not the existence or location of the line on the ground.
- **The "ground normal is +Z so nDotL ≈ 0.02" sub-bug from the previous doc is also overstated.** I should have looked at `BasicMeshes.swift:13-14` more carefully — `MDLMesh(planeWithExtent:)` makes a plane in the X-Z plane with normal +Y, not in the X-Y plane with normal +Z (per Apple's docs). The `rotateZ(270°)` in `GameScene.addGround` does change that, but it doesn't change the qualitative result: the ground is visibly lit, so whatever the live normal value ends up as, the lit-side brightness is fine. The original doc's whole "the lit side is also dim" tangent doesn't match the screenshot — the lit side reads as a bright green, exactly the color we want.

So the **single visible bug** is the shadow-frustum cutoff itself: a hard `× 0.5` step in brightness along the world line where the directional light's orthographic shadow camera stops covering ground. Everything else in the previous doc's ranked-fix list is either incidental (`ambient` shader fixes, normal correctness) or a code-cleanliness issue (duplicated matrix multiplies, dead `lightEyeDirection`).

The new questions you raised are the right ones to focus on. Answers below.

---

## Q1. Directional light: is sun-follow the right fix, and does a projectionMatrix even make sense?

### Short answer

**Yes, sun-follow is the right fix.** And **yes, a projectionMatrix still makes sense — but as a property of the *shadow camera*, not of the *light*.** The conflation of those two concepts in `LightObject.swift` is the architectural smell that produced the bug.

### Long answer

For a true directional light (rays parallel, source effectively at infinity), there are two completely separate things to model:

| Concept | What it means | What it's for | Used by |
|---|---|---|---|
| **Light direction** | A single unit vector. Position is meaningless. | Computing `nDotL` and specular highlights at each surface. | The fragment lighting shader. |
| **Shadow camera** | A finite-extent virtual camera. Has a position, an orientation aligned with the light direction, and an orthographic projection that bounds the region we want shadowed. | Rendering the shadow map (a depth texture). | The shadow-generation render pass. |

The lighting fragment shader does not need a projectionMatrix at all — it just needs a direction vector. But the shadow-map generation pass is rendering a texture of finite size (8192² in this codebase), so it *must* have a finite view volume, which means it needs a view matrix and a projection matrix. The "rays are parallel" property only tells us that the projection should be orthographic (no perspective foreshortening); it does not tell us where to put the box or how big to make it.

Today, `LightObject.swift` ties both of these things to the light's `position`:

- `Lighting::CalculateDirectionalLighting` does `lightDirection = normalize(light.position)` — treats position as a direction-from-origin proxy.
- `LightObject.viewMatrix` does `Transform.look(eye: getPosition(), target: .zero, ...)` — anchors the shadow camera at the position and aims it at the world origin.
- `LightObject.projectionMatrix` is a hard-coded `ortho(-100, 100, -100, 100, 0.01, 1000)` — a fixed 200×200 box around the world origin.

That third item is what produces the visible line. The first two are conceptually entangled with it, which is why moving the sun "fixes" some things but breaks others (your "// TODO: Why does position with z = 0 result in much darker lighting" comment in `FlightboxWithPhysics.swift:86` is exactly the entanglement biting back: when you put `z = 0`, `normalize(position)` swings, the look() target stays at origin, and the shadow camera goes degenerate or near-degenerate).

The architecturally clean version separates them:

```
DirectionalLight {
    direction:  unit vector pointing FROM the surface TO the sun.   // used by shader
    color, brightness, ambientIntensity, ...                        // used by shader
}

ShadowCamera (for that directional light) {
    eye, target, up      // derived each frame from the camera + light direction
    ortho(L, R, B, T, N, F)   // sized to cover the shadow-receiver volume we care about
}
```

The light has no position. The shadow camera has a position, but it's a *synthesis* — it isn't where the sun "is." It's wherever places the visible scene inside the orthographic frustum.

### Why sun-follow is the canonical fix, even for a directional light

Once you accept that the "shadow camera" is a separate, manipulable thing, the question becomes: where do I put it each frame?

For a directional light shadowing a single visible region, the standard answer is: **align the shadow camera with the camera's view**. Specifically, each frame:

1. Compute the world-space center of the region you want shadowed. Cheapest version: `cameraPosition` projected onto the ground plane (or just `cameraPosition` itself). Better: the center of a snapped bounding sphere of the view frustum.
2. Move the shadow camera to `center + lightDirection * lift` (where `lift` is large enough that all scene geometry lies between the shadow camera's near and far planes).
3. Aim the shadow camera at `center`.
4. Use `ortho(-R, R, -R, R, near, far)` with `R` sized to cover the area you want sharp shadows over and `far − near ≥ 2 * lift`.

This is what people mean when they say "sun-follow shadow camera." The sun direction stays fixed (or animates with time-of-day); only the *shadow camera*, which is conceptually a rendering tool, moves to follow the player. There's no contradiction with the light being directional — sun-follow is precisely the technique designed for directional-light shadowing.

To keep shadow texels from swimming as the camera moves (visible as crawling shadow edges), it's customary to snap the shadow camera's translation to integer multiples of the shadow texel size in light-space. That's a polish step you can defer.

### Alternatives if you don't want sun-follow

Three alternatives, and why none of them is what you actually want for this scene:

1. **Make the ortho box huge** (e.g., ±1M to cover the whole ground in `FlightboxWithPhysics`). Works to eliminate the cutoff, but the 8192² shadow map then covers a 2,000,000×2,000,000 ground region, so each texel is ~244 world units across. The F-22's shadow would be < 1 pixel and you'd see no shadow detail at all. Useless.
2. **Fit the ortho box to the shadow-caster AABB each frame.** Good for small fixed scenes, but in this one the F-22 can be hundreds of thousands of units away from the origin while the F-16 stays at (0, 110, 15) — the AABB explodes.
3. **Cascaded Shadow Maps** (CSM). Render the shadow map multiple times at different scales (e.g., 4 cascades: 50, 200, 1000, 5000 units of radius around the camera), then pick the cascade per pixel based on view-space depth. This is the gold-standard solution for large open scenes and the natural next step after sun-follow. Probably overkill for now but worth knowing as the upgrade path.

**Recommended sequence**: do single-cascade sun-follow first (small surgical change to `LightObject` + adding a per-frame update hook against the current camera), then upgrade to CSM later if you start caring about shadow sharpness near the F-22 *and* still wanting cheap distant shadows.

### Concrete refactor sketch (no code changed yet)

In `LightObject.swift` (or, better, a `DirectionalLight` subclass — see Q2):

```
- Remove `projectionMatrix` from being a stored constant.
- Remove `viewMatrix` from being a hard-coded `look(eye, .zero, ...)`.
- Add a `direction: float3` (unit, points to the sun) as the shader-facing concept.
- In update(), each frame:
    let cam = CameraManager.CurrentCamera
    let center = cam.getPosition()               // or projected-to-ground
    let R: Float = 500                            // shadow extent for this cascade
    let lift: Float = 2000
    let eye = center + direction * lift
    let view = Transform.look(eye: eye, target: center, up: Y_AXIS)
    let proj = Transform.orthographicProjection(-R, R, -R, R, 1, 2 * lift)
    lightData.shadowViewProjectionMatrix = proj * view
- In Lighting.metal, change CalculateDirectionalLighting to read `light.direction` instead of `normalize(light.position)`. `LightData` already has a `lightEyeDirection` field; consider renaming to `direction` or adding a new `worldDirection: simd_float3`.
```

`LightData.position` becomes purely cosmetic (used by the visualization sphere child object); nothing in the shadow or lighting pipeline reads it. You can delete the `// TODO: Why does position with z = 0 result in much darker lighting` comment in `FlightboxWithPhysics` because z will no longer affect lighting.

### How this interacts with the "darker side is still dim" observation

After the sun-follow fix, the dark band slides off-screen on its own — you no longer see the boundary because the shadow camera now follows you. But the underlying `× 0.5` halving still happens past the (new, moving) frustum edge, and you'd see it if you flew above the camera's shadow range and looked down. That's why the previous doc's secondary suggestion to fix the sampler (return 1.0, "fully lit," outside the shadow map) is still worth doing as a defense-in-depth measure even with sun-follow in place. Without it, a flight away from the snap-center direction still produces a (now-moving) cutoff.

---

## Q2. Other light types (point, spot/cone): do we need to fix anything?

### Survey of what actually exists

`TFSCommon.h:65-70`:
```c
typedef enum {
    Ambient,
    Directional,
    Omni,
    Point
} LightType;
```

- **Directional**: implemented, suffering from the SunLine bug as discussed.
- **Point**: implemented for SinglePass (`PointLights.metal`) and tiled deferred (`TiledDeferredPointLight.metal`). **Does not cast shadows.** Both fragment shaders compute attenuation from the per-light `radius` and `attenuation` and apply diffuse + specular contributions, but neither samples a shadow map. Verified: `light_data[].radius` is the only "extent" used; no per-light shadow texture.
- **Omni**: enum member exists, but nothing in the codebase reads `Omni`. `LightManager.AddLightObject` only buckets `Directional` and `Point`; `Omni` would fall into the `default: break` branch and just sit in the `_lightObjects` master list. Effectively unused.
- **Spot / cone**: not implemented — no enum case, no shader, no pipeline state, no `LightManager` bucket, no scene calls it. Has never been wired up.

### Where the bug does and doesn't apply

| Light type | Affected by the SunLine bug today? | Notes |
|---|---|---|
| Directional | **Yes** | The frustum cutoff is the bug. |
| Point | **No** — no shadow map | The base class's `projectionMatrix` / `viewMatrix` *are* inherited but never read on the point-light path. They are dead weight on point lights, not a bug. |
| Spot/cone | N/A — doesn't exist | If you ever add it, see below. |
| Omni | N/A — unused | Dead enum value. |

### What the cleanup should look like, even if no point-light fix is needed today

The reason the directional-only properties live on `LightObject` is historical — there's one shared base class with one set of fields and one set of matrices. That works as long as only directional lights use the matrices, but it's bait for the next bug: if you ever add point-light shadows or spot lights, someone will reach for `lightObject.projectionMatrix` and get the same orthographic-ortho-200 box that bit you here.

Cleaner split (suggested, not required for the SunLine fix itself):

```
LightObject (base)
  // identity, color, brightness — anything common to all light types.

DirectionalLight: LightObject
  var direction: float3              // unit, to the sun
  var shadowCamera: ShadowCamera     // the synthesis camera, per cascade
  // produces the matrices the shadow shader binds

PointLight: LightObject
  var radius: Float
  var attenuation: float3
  // no shadow camera today; would gain a CubeShadowCamera if you ever
  // add omnidirectional shadows.

SpotLight: LightObject                // if you add it
  var direction: float3
  var coneAngle: Float
  var range: Float
  var shadowCamera: ShadowCamera     // perspective, FOV = coneAngle, oriented along direction
```

This makes the question "does this light type need a projection matrix?" structural rather than per-call, and lets each subclass own its own shadow-map infrastructure (or lack thereof).

### Specifically about adding spot/cone shadows later

When you do, **don't reuse the directional pattern**. Spot lights:

- Have a *real* position and direction; the position is not synthesized.
- Use a perspective projection with FOV matching the cone angle, not an orthographic box.
- Need only one shadow map (not a cube map); the frustum is the cone.
- Are good candidates for reverse-Z shadows because they're perspective (see Q3).

For omnidirectional point-light shadows (if you ever want them), the standard answer is a cube-map shadow texture, six perspective projections at 90° FOV per face. Same reverse-Z argument applies per face. None of that machinery exists today, but it would be the natural follow-on.

---

## Q3. Should the shadow map be refactored to use reverse-Z too?

### Short answer

**No, not for the current orthographic shadow camera.** The benefits of reverse-Z come almost entirely from undoing the depth-precision distortion of *perspective* projection. An orthographic projection is already linear in depth, so reverse-Z buys you essentially nothing while costing you several state changes that all have to be flipped consistently. If you later add spot or point-light shadows (which use perspective projection), use reverse-Z there.

### Why reverse-Z helps perspective but not ortho

`float32` doesn't have uniform precision: roughly half of its representable values lie between 0 and 0.5, and a vanishingly small fraction lie between 0.999 and 1.0. So depth precision after writing to a `depth32Float` buffer is enormously denser near 0 than near 1.

Perspective projection has the opposite distribution: clip-space depth as a function of view-space Z is `1 - near/z` (in forward-Z) — most of the depth range is consumed by the small slice near the near plane, and the far end packs many view-space Z values into a narrow clip-space band. Combining these two non-uniform distributions multiplicatively (perspective × float32) puts almost all the precision near the near plane, where you usually don't need it, and starves the far end, where Z-fighting then happens.

Reverse-Z (your `Transform.perspectiveProjection`) flips the perspective direction so far becomes 0 and near becomes 1. Now the dense float32 precision lines up with the perspective compression at far, and you get roughly uniform world-space depth precision across the whole range. That's why your main camera switch was a win.

Orthographic projection is *linear*: clip-space depth is `(z − near) / (far − near)`. Combining that with float32 gives you precision that's much denser at clip-space `~0` than at clip-space `~1`, but the *world-space* depth precision is dominated by the linear ortho mapping, so the precision is reasonably uniform across the shadow frustum's depth range. Reverse-Z would shift the dense float32 region to the far end, but you don't have the perspective-induced precision deficit there in the first place, so the gain is marginal.

For an 8192² shadow map with the current `(near, far) = (0.01, 1000)` and depth32Float, you have:

- Float32 has ≈ 8.4 million distinct representable values in `[0.5, 1.0]`, and ≈ 8.4 billion in `[0, 0.5)`.
- Mapped linearly to the 1000-unit ortho depth range, the "back half" of the frustum (≈ 500..1000 world units from the light) gets ≈ 8.4M unique depth values. That's already ~6 cm of precision at the far end. Reverse-Z would bump this to nanometer-scale precision — irrelevant for shadow generation, since the depth-bias term (`0.1` constant, `1.0` slope-scaled) dominates the precision budget by many orders of magnitude.

So for the shadow camera as it stands, reverse-Z gives no perceivable shadow-quality win.

### What you'd have to change consistently if you did refactor it anyway

For completeness, in case the decision is "yes, I want it for consistency":

| Item | Forward-Z (today) | Reverse-Z |
|---|---|---|
| Ortho projection | `Transform.orthographicProjection` writes `1/(far-near)` for z. | Write `-1/(far-near)`, add `1.0` constant so near maps to 1 and far to 0. (New helper; do not reuse the perspective helper.) |
| Shadow depth clear | Default `1.0` (set implicitly by not setting `clearDepth`, see `ShadowRendering.swift:43-46`). | Must explicitly set `clearDepth = 0.0`. |
| Shadow-gen depth state | `TiledDeferredShadow` uses `.less`. | Flip to `.greater`. |
| `CalculateShadow` compare | `position.z > shadow_sample + 0.001 ? 0.5 : 1` in `Lighting.metal:84`. | `position.z < shadow_sample - 0.001 ? 0.5 : 1`. |
| `CalculateShadowMSAA` compare | Same direction as above. | Same flip. |
| `gbuffer_fragment_base/material` | `sample_compare` with `compare_func::less` samplers (`GBuffer.metal:38-47`). | Switch the samplers to `compare_func::greater`. |
| Depth bias | `setDepthBias(0.1, slopeScale: 1, clamp: 0.0)` in `ShadowRendering.swift:73`. | Negate sign: typical reverse-Z value is something like `-0.001` slope-scaled `-2`, but you'd retune. |

Six interlocking flips, every one of which silently produces all-self-shadow or no-shadow if it goes wrong. The current `TiledDeferredDepthStencils.swift:10-13` comment already calls out that the shadow path is intentionally *not* reverse-Z while the main camera is — splitting the convention is the lesser of two evils.

### When you *should* flip shadows to reverse-Z

Three triggers, in increasing likelihood of actually arising:

1. **You add spot lights** (perspective shadow camera). Reverse-Z them from day one. Don't bother retroactively converting the directional path at the same time — keep one ortho-shadow forward-Z helper and one perspective-shadow reverse-Z helper.
2. **You add point-light cube-map shadows.** Same as above — perspective per face, reverse-Z each one.
3. **You start using a much larger `(far − near)` ratio on the directional shadow** (e.g., `near = 0.01, far = 100_000` for a single very deep cascade). At that point ortho-linear-depth precision in float32 might start mattering, and a careful float-precision audit could land on reverse-Z as the resolution. Unlikely with cascaded shadow maps in the picture — each cascade has its own small `far − near`.

### Recommendation

Keep the directional shadow camera forward-Z. Note this decision near `TiledDeferredDepthStencils.swift:10-13` (the comment already explains it well — leave it). If/when spot or point shadows are added, use reverse-Z for those, and update the shader's `CalculateShadow*` helpers to take the projection convention into account (e.g., a `compare_dir` template arg, or two helpers).

---

## Summary

- **The SunLine bug is real and the previous diagnosis is correct in principle**: it's the orthographic shadow frustum boundary on the ground. Previous doc overstated the brightness gap ("black") and the secondary normal/ambient contributions; the *underlying* root cause (fixed ±100 ortho around origin, target pinned to `.zero`) is unchanged.
- **A projection matrix on a directional light still makes sense — but as a property of the shadow camera, not of the light itself.** The right architectural split is "DirectionalLight has a direction; ShadowCamera has a position, view, and ortho projection."
- **Sun-follow is the canonical fix for directional-light shadows.** It is not in opposition to "the light is directional" — it's exactly the technique designed for that case. CSM is the eventual upgrade for shadow quality across large viewing distances; do single-cascade sun-follow first.
- **Other light types: nothing to fix now.** Point lights don't shadow today; their inherited `projectionMatrix` is dead weight, not a bug. Spot lights and omnidirectional point-light shadows don't exist. If you add them later, give each its own shadow-camera type with its own projection convention.
- **Reverse-Z for the shadow map is not worth it.** Orthographic depth is already linear; float32 has plenty of precision across 1000 units. Cost (six interlocking flips) outweighs benefit (essentially zero). When you add perspective-projection shadows (spot, point cube), use reverse-Z there.

### Recommended minimum work to land the fix

1. Introduce a `ShadowCamera` concept (or just compute the shadow view/proj inline in `LightObject.update()` against the current camera) — replaces the hard-coded `target: .zero` and `ortho(-100, 100, ...)`.
2. Change `Lighting::CalculateDirectionalLighting` to take a direction rather than a position. Populate `LightData.lightEyeDirection` (already exists, currently only set for `cameraPosition`-relative use in `LightManager.GetDirectionalLightData`) or add a `worldDirection` field. The `light.position` in `Sun` becomes purely a visualization concern (the red sphere).
3. As defense-in-depth: in `Lighting::CalculateShadow` and `CalculateShadowMSAA`, return `1.0` (fully lit) when `xy < 0 || xy > 1` before sampling. This stops the `clamp_to_edge` self-shadow misread from biting if/when shadow coords step outside the frustum.

That's the smallest set of changes that makes the SunLine go away, makes the architecture honest about directional-light semantics, and doesn't bite-off any of the larger refactors (light-class split, CSM, reverse-Z shadows).
