# Flightbox-with-Physics Ground / Horizon Artifacts — Investigation

Scene: `ToyFlightSimulator Shared/Scenes/FlightboxWithPhysics.swift`
Screenshot: `debugging/screenshots/GroundArtifacts.png`

## Symptoms (from the screenshot)

1. **Horizon line** where the green ground meets the black "sky": clear staircase / jaggies, and the user reports it flickers frame-to-frame.
2. **Dispersed objects** on the ground (1000 spheres/cubes/capsules): flicker, several appear "bitten off" at the bottom, and many look like sub-pixel dots / partial colored smears.

The default macOS renderer at the time of the screenshot is `TiledMSAATessellated` (`ToyFlightSimulator macOS/Views/MacGameUIView.swift:18`), so **4x MSAA is active** with a `.depth32Float` depth buffer. The artifacts are NOT caused by missing MSAA.

## Root cause #1 — Depth precision exhausted by the camera near/far ratio

### Camera setup in this scene

```swift
// FlightboxWithPhysics.swift:17
var attachedCamera = AttachedCamera(fieldOfView: 75.0,
                                    near: 0.01,
                                    far: 1_000_000.0)
```

### Projection used

`Transform.perspectiveProjection` (`Math/Transform.swift:74-88`) is a **standard left-handed projection that maps clip-space depth to [0, 1]** (not reverse-Z):

```
zs = far / (far - near)
clip.z = view.z * zs - near * zs
clip.w = view.z
d = clip.z / clip.w = 1 - near/z
```

### Precision math

- `near = 0.01`, `far = 1_000_000`. Ratio = 10⁸.
- `depth32Float` has 23 mantissa bits, so the smallest representable distance from 1.0 (ULP near 1.0) is `2⁻²³ ≈ 1.19 × 10⁻⁷`.
- Ground scale = 1,000,000 (`FlightboxWithPhysics.swift:25` and `GameScene.addGround`), so the ground extends ±500,000 along X and Z.
- F22 cameraOffset is `[0, 55, -150]` (`GameObjects/F22.swift:16`); jet starts at `(0, 100, 0)` and is gravity-clamped to y=0 by `F22.doUpdate`. So the camera sits roughly at `(0, ~55–155, -150)`.

At the **far ground edge** the camera-to-edge distance is ~500,000 units. Depth value:

```
d = 1 - 0.01 / 500_000 = 1 - 2 × 10⁻⁸
```

`2 × 10⁻⁸` is **below the float32 ULP near 1.0** (1.19 × 10⁻⁷). Stored depth rounds to exactly **1.0** — the same value the depth buffer is cleared to.

The GBuffer pass uses `.less` (`Graphics/Libraries/DepthStencilStates/SinglePassDeferredDepthStencils.swift:27` and equivalents for the tiled renderers), so `1.0 < 1.0` evaluates **false** and those ground fragments **fail the depth test**. The pixels keep the clear color (black) instead of being shaded green.

### Why this produces the horizon flicker / jaggies

- The transition is binary at every sample: depth is either exactly 1.0 (fail) or one-ULP-below 1.0 (pass). MSAA cannot anti-alias this because all 4 samples in a pixel land at the same precision-quantized depth.
- Tiny per-frame changes to camera position (see cause #3 below) push the rounded depth across the 1-ULP boundary at different pixels each frame, producing the flicker.
- It looks like aliasing, but adding *more* MSAA samples wouldn't help; it's a depth quantization artifact, not a coverage artifact.

## Root cause #2 — No skybox is drawn under this renderer

`GameScene.setupDefaultSky()` (`Scenes/GameScene.swift:114-123`) only handles two renderer types:

```swift
switch _rendererType {
    case .OrderIndependentTransparency: addChild(SkySphere(...))
    case .SinglePassDeferredLighting:   addChild(SkyBox(...))
    default: break
}
```

For `TiledMSAATessellated` (the default), `TiledDeferred`, and `TiledDeferredMSAA`, the scene gets **no sky geometry**. The "sky" in the screenshot is just `Preferences.ClearColor` (`ClearColors.Black` — `Core/Preferences.swift:22`).

This isn't itself an artifact, but it **massively amplifies the horizon problem**:
- A real skybox would write to depth=1.0 with `.lessEqual` and cover every "empty" pixel with sky color, hiding the depth-precision dropouts.
- Without a skybox, every pixel where the ground fails depth test exposes raw black clear color, so the artifact is high-contrast and obvious instead of being hidden.

## Root cause #3 — Camera micro-jitter from the new flight model

`F22SimpleFlightModel.computeForce` runs every physics step. Even when the aircraft is "at rest" on the ground:

- `Aircraft` still has a rigid body that's being integrated against gravity each frame.
- `F22.doUpdate` (`GameObjects/F22.swift:48-53`) clamps `positionY` to 0 and zeroes downward velocity AFTER it goes negative, so velocity accumulates a small negative each step from gravity, then gets snapped to 0. Positions on other axes can drift very slightly from any floating-point noise in `computeForce`.
- The attached camera is a **child of the jet** (`AttachedCamera.attach` calls `node.addChild(self)`, `AttachedCamera.swift:31`), so any jet wobble propagates directly to camera worldMatrix → viewMatrix.

Sub-pixel camera shifts per frame, combined with the depth-precision boundary from cause #1, are exactly what makes the artifact look like *flicker* rather than just jaggies. The pixel coverage at the horizon changes every frame.

## Root cause #4 — Dispersed-object placement allows bottoms at y=0

```swift
// FlightboxWithPhysics.swift:30-34
let randomSize = Float.random(in: 2.0..<10.0)
let y: Float = Float.random(in: randomSize..<randomSize * 2)
```

Mesh extents at unit scale (`AssetPipeline/Libraries/Meshes/BasicMeshes.swift` / `ProgrammaticMeshes.swift`):

| Shape | Unit Y range | After `setScale(randomSize)` |
|---|---|---|
| Sphere (`MDLMesh.sphere…diameter=2`) | [-1, +1] | [-randomSize, +randomSize] |
| Cube (custom) | [-1, +1] | [-randomSize, +randomSize] |
| Capsule rotated 90° X or Z | [-1, +1] (radius, after the rotation) | [-randomSize, +randomSize] |

With `position.y = randomSize` (the **lower bound** of the random Y range), the bottom of each shape is at world y = `randomSize - randomSize = 0` — coincident with the ground plane → guaranteed z-fight on those rows of pixels.

Even for objects whose center sits a bit higher (e.g. `position.y = 1.5 × randomSize`, bottom at `0.5 × randomSize`), depth precision at a few-thousand-unit camera distance is on the edge: at distance z=5000, depth ULP corresponds to ~5000² × 1.19×10⁻⁷ / 0.01 ≈ 30 world units of indistinguishability near the far end. Bottoms within tens of units of the ground are *not* reliably above the ground in the depth buffer.

### Capsule rotation order — separate but related

```swift
case .capsule:
    let capsule = CapsuleObject()
    switch CapsuleAxis.allCases.randomElement()! {
        case .x: capsule.rotateX(Float(90).toRadians)
        case .z: capsule.rotateZ(Float(90).toRadians)
    }
    capsule.setScale(randomSize)
    capsule.setPosition(randomPosition)
```

Because the model matrix multiplies as `T · R · S · v`, this gives "scale → rotate → translate", which is what's intended (rotate the unit capsule to lie horizontal, then scale, then place). After 90° rotation the capsule's *long* axis is horizontal (Z or X) and its Y extent is ±radius, which is why the bottoms land at y=0 in the same way as the sphere/cube. So the rotation isn't *buggy* per se, but it makes capsules behave like rolling rods on the ground rather than upright pills — combined with the y-range issue above, their bottoms also coincide with the ground.

## Root cause #5 — Sub-pixel object sizes at viewing distance

- Cluster radius = `groundSize / 100 = 10_000`; `halfClusterRadius = 5_000`. Objects are placed in `[-5_000, +5_000]` on X and Z.
- Camera ~150 units behind and 55 above the jet at (0, 0, 0) → most objects are 2_000 – 7_000+ units away.
- Object size 2–10 units. For a ~5-unit object at 5_000 units distance with a 75° FOV on a 1920-wide framebuffer: pixel width ≈ `1920 × (5 / 5000) / (1.31 rad) ≈ 1.5 pixels`. Many objects are **sub-pixel or 1-pixel wide**.
- Sub-pixel triangles produce severe temporal aliasing — the rasterizer's coverage flips on/off as the camera shifts by a fraction of a pixel each frame. 4x MSAA only gives 4 samples per pixel; that's not enough integration for a ~1-pixel-wide object to be stable, especially when the camera micro-jitters every frame (cause #3).

This is what produces the "smeared dots" appearance for distant objects in the screenshot.

## Why these symptoms got worse with this scene specifically

The original `FlightboxScene` already used the same `near=0.01 / far=1_000_000` camera and the same 1M-scale ground via `addGround()` — so depth precision was always shaky in those scenes too, just less obvious. What changed in `FlightboxWithPhysics`:

1. **Flight model attached to the jet** → continuous physics integration → small per-frame camera shifts → exposes the precision boundary at the horizon as flicker instead of a static (still aliased) line.
2. **1000 dispersed objects across a 10_000-unit cluster** → most of them at distances where they're sub-pixel and where their *bottoms* z-fight with the ground.

The combination is what turns latent precision problems into very visible flicker.

---

# Suggestions (ranked by impact)

> *No code changes have been made yet; this is the proposed plan.*

### Highest impact — fix the depth precision

1. **Switch to reverse-Z depth.**
   - Modify `Transform.perspectiveProjection` to map `near → 1.0`, `far → 0.0`.
   - Clear depth to `0.0`, change every GBuffer / opaque / particle depth-stencil state from `.less` / `.lessEqual` to `.greater` / `.greaterEqual`, invert the skybox/sky test the other way, and invert shadow-pass compares as well.
   - Effect: float32 has *enormous* precision near 0, so the far plane gets dense resolution and the near plane gets coarser (which is fine — nothing is at z=0.01). This is the standard fix for open-world depth and should make the horizon flicker disappear without changing the near/far values.
   - Cost: medium — touches every depth-stencil state and every shader that writes/tests depth explicitly. Best done as a tracked refactor with screenshots before/after on every renderer.

2. **Shrink `far` if reverse-Z isn't worth the refactor right now.**
   - `far = 1_000_000` with `near = 0.01` is 10⁸ — extreme. Drop to e.g. `far = 50_000` (still gives a 50 km view distance, which is plenty for visuals). This alone makes far-edge depth ~2×10⁻⁶ from 1.0, well within float32 ULP, and the horizon should stop flickering.
   - Optionally also bump `near` (e.g. 0.1 or 1.0) — the F22 + AttachedCamera offset puts the camera tens of units from anything visible, so a near plane of 1.0 is safe and improves precision further.

3. **Add a skybox under the tiled renderers in `setupDefaultSky()`.**
   - Add `.TiledMSAATessellated`, `.TiledDeferred`, `.TiledDeferredMSAA` cases that add a `SkyBox` (or `SkySphere`) and wire up the appropriate sky pipeline.
   - Even without fixing depth precision, this *hides* the horizon dropout because the skybox writes a non-black color at depth=1.0. (This is cosmetic if depth precision is fixed, but valuable for non-default renderers as well.)

### Object-flicker fixes

4. **Keep dispersed-object bottoms off the ground plane.**
   - Change `y` range to e.g. `Float.random(in: (randomSize * 1.2)..<(randomSize * 2))`, or compute per-shape mesh-bottom offset and add a small epsilon. Eliminates the z-fight on the bottom row of pixels of every object.

5. **Reduce cluster radius or grow object sizes.**
   - `clusterRadius = groundSize / 100 = 10_000` is enormous relative to the 2–10 unit objects. Try `groundSize / 1_000 = 1_000` (objects within 500 units of origin) or grow size range to `20..<50`. Either way, more objects stay at distances where they're multi-pixel and stable.
   - Also consider lowering `count` from 1000 — most are unseeable detail anyway, and 1000 sub-pixel objects burns rasterization work for no visual benefit.

6. **(Band-aid) Add a small polygon offset / depth bias on the ground.**
   - In the ground's depth-stencil or pipeline state, push ground fragments slightly back. Objects whose bottoms touch y=0 will then reliably draw on top. Doesn't fix the horizon, but cheap and covers cause #4 specifically.

### Physics-jitter fix

7. **Stop or freeze the flight model when grounded with no input.**
   - `F22.doUpdate` already detects ground contact for the Y axis. Extend it: if the aircraft has zero throttle input, zero velocity (within an epsilon), and `positionY <= 0`, skip `physicsWorld.update` on this entity / skip `flightModel.computeForce`.
   - This eliminates the per-frame sub-pixel camera shift that turns static aliasing into flicker.
   - Independent of the depth-precision fix, this alone should noticeably calm the horizon.

### Bigger-hammer options (probably not needed if 1–3 are done)

8. Temporal antialiasing (TAA) on the lighting-resolve output — would also smooth sub-pixel object aliasing.
9. Logarithmic depth, split frustum, or "near + far" cascade — only worth it for genuinely planet-scale scenes.

### Recommended minimum set

If you only do three things: **reverse-Z (1) + grounded-flight-model freeze (7) + skybox for tiled renderers (3)** should remove essentially all of the flicker in the screenshot. Adding **(4)** on top removes the object-bottom z-fight as a cherry on top.
