# Sun-Follow Shadow Camera — F-22 Stops Casting Ground Shadow + Rudder Self-Shadow Gone

Triggered by: [`plans/claude/single_cascade_sun_following_shadow_camera.md`](../../plans/claude/single_cascade_sun_following_shadow_camera.md) just landed.
Previous related docs: [`sun_line_shadow_frustum_cutoff.md`](sun_line_shadow_frustum_cutoff.md), [`sun_line_shadow_frustum_cutoff_followup.md`](sun_line_shadow_frustum_cutoff_followup.md).

## Symptoms

After the sun-follow shadow camera fix, the SunLine is gone — but:

1. **The player-controlled F-22 no longer casts a shadow on the ground.** (NPC objects near the world origin still cast shadows; debris/balls near the scene's center still appear in the shadow map.)
2. **The F-22's angled rudders stop self-shadowing the rest of the jet** (the rudder-on-fuselage shadow that was visible before is gone).

Both symptoms appeared in the same change set ([`plans/claude/single_cascade_sun_following_shadow_camera.md`](../../plans/claude/single_cascade_sun_following_shadow_camera.md)), so the bug almost certainly lives in either the shadow camera placement or the shadow-comparison math.

## TL;DR

Two independent bugs, both rooted in the new sun-follow implementation:

1. **`cam.getPosition()` returns the LOCAL position, not the WORLD position.** For a parented camera (every flight camera in this codebase is an `AttachedCamera` parented to the aircraft), this is just the offset value passed to `attach()` — e.g., `(0, 55, -150)` for the F-22. The shadow camera ends up anchored at *world* `(0, 55, -150)` for the entire flight, not at the F-22's actual world position. As soon as the F-22 flies more than ~350 units along its facing direction, it exits the ±500-radius shadow frustum and stops appearing in the shadow map. The F-16 (sitting near the origin) still casts because it stays inside the static frustum.

2. **The shader's hard-coded `+ 0.001` epsilon in `CalculateShadow` / `CalculateShadowMSAA` is in NDC depth space, which is now scaled to a 4000-world-unit deep frustum.** `0.001 NDC × 4000 world units = 4 world units` of slack required before a depth comparison registers as "shadowed." The F-22's angled rudders at scale 0.25 are ~0.5 world units across; depth differences between adjacent rudder and fuselage geometry are << 4 world units, so no self-shadow can ever register.

The two bugs compound for the F-22's ground shadow specifically: even when it happens to be inside the frustum at scene start, the ground beneath it is only ~100 world units away from the F-22 in shadow-camera depth, which is well above the epsilon — so that should work *if* (1) is also fixed. Once the F-22 flies forward, (1) takes over and pushes the jet out of the frustum entirely.

## Root cause 1: `cam.getPosition()` returns local position, not world

### What I shipped

`LightObject.updateShadowCamera()` ([`LightObject.swift:83-91`](../../ToyFlightSimulator%20Shared/GameObjects/LightObject.swift)):

```swift
private func updateShadowCamera() {
    guard let cam = CameraManager.CurrentCamera else { return }
    let shadowCamera = ShadowCamera(direction: self.direction,
                                    focus: cam.getPosition(),   // <-- BUG
                                    radius: _shadowRadius,
                                    lift: _shadowLift)
    let svp = shadowCamera.viewProjectionMatrix
    lightData.shadowViewProjectionMatrix = svp
    lightData.viewProjectionMatrix       = svp
}
```

### What `cam.getPosition()` actually returns

`Node.getPosition()` ([`Node.swift:235`](../../ToyFlightSimulator%20Shared/GameObjects/Node.swift)):

```swift
func getPosition() -> float3 { return self._position }
```

It returns `_position` — the *local* translation set by the last `setPosition` call. World position requires walking up the parent chain via `parentModelMatrix`. The world-position accessor is `modelMatrix.columns.3.xyz`.

### How this breaks for the F-22

`AttachedCamera.attach(to:offset:rotation:)` ([`AttachedCamera.swift:28-32`](../../ToyFlightSimulator%20Shared/GameObjects/Cameras/AttachedCamera.swift)):

```swift
public func attach(to node: Node, offset: float3 = [0, 2, -4], ...) {
    self.rotate3Axis(...)
    self.setPosition(offset)        // sets LOCAL position to the offset
    node.addChild(self)
}
```

So `AttachedCamera._position` is the offset; world position is `jet.modelMatrix * (offset, 1)`. For the F-22 specifically, the offset is `[0, 55, -150]` (from [`F22.swift:16-18`](../../ToyFlightSimulator%20Shared/GameObjects/F22.swift)).

So `cam.getPosition()` for the F-22's AttachedCamera returns `(0, 55, -150)` — the offset value, in world space — *regardless of where the F-22 is*. The shadow camera focus is pinned to that single world point for the entire flight.

### Computed: how far the F-22 can fly before the shadow disappears

Shadow camera setup with `shadowRadius = 500`, `shadowLift = 2000`, sun direction `≈ (0, 0.9998, 0.020)`:

- Focus (world): `(0, 55, -150)`
- Eye (world): focus + direction × lift ≈ `(0, 2055, -110)`
- View frustum: ±500 in light-screen XY, [1, 4000] in light-screen Z.

The light-screen-Y axis in world space is `≈ (0, 0.020, -0.998)` (almost world `-Z`). So as the F-22's world position moves in the `+Z` direction (the flight-sim "forward" — and the F-22's default facing), its light-screen-Y coordinate *decreases linearly* with the world-Z delta. The frustum's `Y` bounds are `±500`, so the F-22 exits the frustum when `|0.998 × (jet_z − focus_z)| > 500`, i.e., `|jet_z − (-150)| > 501`, i.e., `jet_z > 351` or `jet_z < -651`.

Starting at `jet_z = 0`, the F-22 has ~351 units of forward flight before it leaves the shadow frustum. At any normal flight speed that takes a few seconds. After that, the F-22 is no longer rasterized into the shadow map, and the ground beneath it shows no shadow.

The F-16 stays at world `(0, 110, 15)` — only `165` units from focus in `Z` — and never moves, so it remains inside the static frustum and continues to cast a shadow.

### Same bug also affects every other parented camera

`DebugCamera` is a top-level child of the scene (not parented to anything), so its `getPosition()` ≈ world position and the bug doesn't bite when in debug-camera mode. But the moment the user presses `C` to switch back to the AttachedCamera, the bug returns.

### Fix

Use the world position. The single-character change is:

```swift
focus: cam.modelMatrix.columns.3.xyz,
```

Cleaner option: add `Node.getWorldPosition() -> float3 { modelMatrix.columns.3.xyz }` to formalize the distinction, then use that.

Either form re-establishes the sun-follow behavior we actually wanted: shadow frustum tracks wherever the active camera (i.e., the F-22 in third-person view) is in world space.

After this fix, the F-22 stays inside the shadow frustum no matter where it flies, and its ground shadow returns.

## Root cause 2: `+ 0.001` NDC epsilon is too coarse for the new frustum

### Where it lives

`Lighting.metal:84` (and the same constant on line 105 for the MSAA helper) — the comparison that decides "shadowed vs lit":

```glsl
return (position.z > shadow_sample + 0.001) ? 0.5 : 1;
```

`position.z` and `shadow_sample` are both NDC depth values in `[0, 1]`. The `0.001` is a guard against shadow acne (a flat receiver self-shadowing because of texel quantization or float-rounding when comparing its own depth against the shadow map's depth).

### Why 0.001 NDC is the wrong constant for a 4000-unit-deep ortho

For an orthographic projection, NDC depth scales linearly with view-space depth. So `0.001 NDC` corresponds to:

| Frustum depth range | 0.001 NDC in world units |
|---|---|
| Old (0.01, 1000), range ≈ 1000 | ~1 world unit |
| New (1, 4000), range ≈ 4000 | ~4 world units |

The `0.001` was already borderline in the old setup (rudder self-shadowing on a scale-0.25 F-22 has depth differences of ~0.5 world units, which is below `~1 world unit` slack). In the new setup it's a wall: nothing under 4 world units of depth difference can register as shadowed.

The F-22's geometry at scale `0.25`:

- Overall length: ~5 world units
- Rudder thickness / fuselage offset: ~0.1–0.5 world units
- Wing-to-fuselage depth (from a top-down sun view): ~0.5–1 world unit

All of these are well below `4 world units`. With the new epsilon, the F-22 cannot self-shadow at all.

### Why this doesn't affect the F-22 ground shadow much

The F-22's ground shadow has a depth difference of `~jet_altitude` world units between the F-22 and the ground beneath it. At altitude 100, that's `100 world units` ≈ `0.025 NDC` — *far* above the `0.001` epsilon. So the F-22-on-ground case is purely about root cause 1 (the F-22 leaving the frustum). The rudder-on-jet case is purely about root cause 2.

### Fix

Two reasonable approaches, in order of effort:

1. **Just lower the constant.** `0.0001` NDC = `0.4 world units` in the new frustum — appropriate for the F-22 scale. The trade-off is shadow acne on flat receivers, but for the test scene (1M ground at altitude 0, F-22 at altitude 100) the receivers are far enough that any acne is at clip-space depth differences << 0.0001, so it's safe.

2. **Scale the epsilon to match the frustum.** Pass `shadowDepthRange = far - near` as part of `LightData` from CPU, and use `desired_world_slack / shadowDepthRange` as the epsilon at sample time. Lets each scene pick its own world-space slack (`~0.5 world units` is sensible for the F-22). Adds one float to `LightData` and one division in the shader. Cleaner long-term; right answer if shadow frustums vary widely across renderers or future cascades.

For the smallest fix that recovers the rudder self-shadow today: change both `Lighting.metal:84` and `Lighting.metal:105` from `+ 0.001` to `+ 0.0001`. (Same constant, two call sites.)

## Why the previous plan said the bias was independent of frustum size

The plan said:

> | Item | Forward-Z (today) | Reverse-Z |
> | Depth bias | `setDepthBias(0.1, slopeScale: 1, clamp: 0.0)` in `ShadowRendering.swift:73`. | Negate sign: ... |

…and the "no behavior change" claim implicitly assumed the existing bias and shader epsilon were already correctly sized for the new frustum. That was wrong:

- `setDepthBias` on `ShadowRendering.swift:73` only fires inside `encodeShadowMapPass` (SinglePass path). The MSAA path (which `TiledMSAATessellated` uses) doesn't call it at all, so this particular bias didn't change in the new code. ✓
- But the in-shader `+ 0.001` constant in `CalculateShadow*` *is* the slack that matters on the MSAA path, and that constant *is* frustum-dependent through NDC. The plan didn't flag it. ✗

I should have caught this when sizing the new `(near, far) = (1, 4000)` — the constant `0.001` was inherited from a 1000-deep frustum and not re-tuned for the new 4000-deep one.

If/when we later refactor to support cascades (each cascade has a different depth range), the per-cascade epsilon scaling becomes essentially required. Better to plumb it through `LightData` now than to deal with cascade-specific epsilons later.

## Suggested fix order

1. **Fix root cause 1 first** (single-line change to `LightObject.updateShadowCamera()`): change `cam.getPosition()` → `cam.modelMatrix.columns.3.xyz`. Verify visually: F-22 ground shadow reappears and follows the jet as it flies.
2. **Then fix root cause 2** (two-line change to `Lighting.metal`): drop epsilon from `0.001` → `0.0001`. Verify visually: rudder-on-fuselage self-shadow reappears, no new acne on the ground or other flat receivers.
3. Optional (cleanup, not required for the fix): add `Node.getWorldPosition()` helper so callers can stop indexing into `modelMatrix.columns.3.xyz` by hand.
4. Optional (forward-looking, only worth it if cascades are imminent): plumb `shadowDepthRange` through `LightData` and compute the epsilon as `desired_world_slack / shadowDepthRange` per fragment. Defers comfortably until CSM lands.

If you want to apply (1) and (2) immediately in one commit and verify together, the failure mode if either is wrong is well-bounded — (1) controls whether the shadow appears at all (binary visible/not), (2) controls how fine-grained the shadow can be (acne or no-shadow on small features). Easy to distinguish visually.

## What I'd add to the plan retroactively

If we were re-drafting `plans/claude/single_cascade_sun_following_shadow_camera.md`, the two missed items would be:

- A "world position vs local position" callout in §1's `ShadowCamera` doc comment, recommending callers pass `modelMatrix.columns.3.xyz` (or the equivalent helper) rather than `getPosition()`.
- A new shader-side item alongside §4 (sampler-edge safety): retune the `+ 0.001` constant in `CalculateShadow` and `CalculateShadowMSAA` to match the new frustum depth range, or plumb a frustum-aware epsilon through `LightData`.
