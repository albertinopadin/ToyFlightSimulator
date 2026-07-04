# Code Review — Commit range since (and including) `1704e81`

**Range:** `1704e81~1..HEAD` (13 commits)
**Date:** 2026-06-29
**Method:** Multi-angle review (8 finder angles × correctness/cleanup/efficiency/altitude/conventions), with adversarial verification of the highest-impact findings. Findings are tagged **CONFIRMED** (traced end-to-end in source) or **PLAUSIBLE** (mechanism real, visible failure unverified). No build/test run was performed as part of this review.

Commits in range:

```
60203a5 Add configurable, persistent max anisotropy setting
f470994 Reformat tiled MSAA G-buffer fragment signature
40a543d Enable 8x anisotropic filtering on the linear sampler
4877c19 Lazily load texture, model, and submesh asset libraries
d979281 Fix GameStats overlay sizing and show current renderer (#5)
5e46b2a Merge #4 (metal-hud-menu-toggle)
4952c9d Move Metal Performance HUD toggle into the in-app menus
f251bab Merge #3 (metal-perf-hud)
640e2b1 Add Metal Performance HUD toggle (macOS 'H' key, iOS button)
825d49a Tweaks: F16 camera offset + Flightbox scale, remove macOS picker debug print
9401999 iOS: move views into Views/, fix menu scroll + aircraft-picker crash, add close button
6372ec2 Aircraft: runtime player-aircraft selection with safe swap + tests
1704e81 Partial fix for F-18 control surfaces incorrect position offset
```

---

## 1. What changed

| Area | Summary |
|---|---|
| **Lazy asset libraries** | `ModelLibrary`, `SingleSubmeshMeshLibrary`, `TextureLibrary` converted from eager `makeLibrary()` population to lazy `_factories` + `_cache` + `OSAllocatedUnfairLock`. `SingleSubmeshMesh` now caches parent `MDLAsset`s (`_loadedModels`) and copies each submesh's vertex buffer; `clearCachedSourceModels()` is called from `SceneManager.TeardownScene`. |
| **Anisotropic filtering** | New `MaxAnisotropy` enum (1×–16×) + 5 pre-built `Linear_Anisotropy*` sampler variants; `currentLinearSamplerState`/`setLinearMaxAnisotropy`; persisted via `Preferences.SelectedMaxAnisotropy` (UserDefaults). `SamplerState.name` made an instance property; subscript force-unwrap removed. |
| **Runtime aircraft swap** | `AircraftType` enum; `GameScene.playerAircraft` + `setPlayerAircraft` hook; `FlightboxWithPhysics.applyAircraftSwap`/`swappedEntities`; `PendingAircraftSwap` (UI→update-thread mailbox); `SceneManager.RemoveObject`/`Unregister`/`subtreeNodes`/`removeRenderable`. SwiftUI aircraft pickers (macOS + iOS). |
| **Metal Performance HUD** | `MetalPerformanceHUD` toggle (macOS 'H' key + menu, iOS menu); `INFOPLIST_KEY_MetalCaptureEnabled = NO`. |
| **GameStats overlay** | Rewritten layout; shows current renderer via `GameStatsManager.currentRenderer` set from `Renderer.init`. |
| **F-18 tuning + basis** | Single submeshes now receive the `rotate180AroundY` basis (previously identity); `setupControlSurfaces` origin constants re-tuned (`0.25→5.6/14/5.8/15`); rudder axis Z signs and elevon/flap rotation signs flipped; `.F16` model also gained the 180°Y basis; `Store` nested inside `F18`. |
| **Tests** | `AircraftTypeTests`, `SceneManagerUnregisterTests`, `AircraftSwapTests` (Metal-free). |

The structural direction is good — the deferred-swap mailbox, the `subtreeNodes` recursion + tests, the pre-built immutable sampler variants, and the lazy factories are all sound ideas. The issues below are mostly in (a) the F-18 single-submesh geometry path now that a basis transform is applied to shared, cached, mutable meshes, and (b) the lazy-load + locking changes landing on the render hot path.

---

## 2. Findings

### 2.1 🚨 High — F-18 control surfaces drift on every repeated selection (CONFIRMED)

`SingleSubmeshMesh.swift:160-162`, `SubMeshGameObject.swift:21`, `F18.swift:302-321`.

`SubMeshGameObject.init` binds the **shared, library-cached** mesh instance:

```swift
_singleSMMesh = Assets.SingleSMMeshes[meshType]   // process-lifetime singleton; returns the cached instance
```

and `setSubmeshOrigin` mutates that shared buffer **additively, in place**:

```swift
public func setSubmeshOrigin(_ origin: float3) {
    translateSubmeshVertices(delta: origin)       // vertex.position += delta  (NOT idempotent)
}
```

`F18.setupControlSurfaces()` runs on every `F18(...)` construction and calls `setSubmeshOrigin(5.6 / 14 / 5.8 / 15)` on each surface. The new aircraft-swap feature lets an F-18 be built repeatedly (select F-18 → another → F-18), and the library `_cache` is **not** reset between builds — `SceneManager.TeardownScene` calls `clearCachedSourceModels()`, which clears a *different* cache (`_loadedModels`, the parent `MDLAsset`s), and the swap path never tears down at all.

Tracing the world position of a surface vertex across builds (init recenter runs only once, on the cache-miss build; `setPosition` uses the constant `initialPositionInParentMesh - origin` each time):

```
build 1: world = R·p₀
build N: world = R·p₀ + (N-1)·origin     // drifts +5.6/+14/+5.8/+15 in Z per extra build
```

So re-selecting the F-18 walks its ailerons/elevons/flaps/rudders off the airframe, further each time.

**Fix — make the origin absolute (idempotent), so re-applying the same origin to the shared mesh is a no-op:**

```diff
--- a/ToyFlightSimulator Shared/AssetPipeline/SingleSubmeshMesh.swift
+++ b/ToyFlightSimulator Shared/AssetPipeline/SingleSubmeshMesh.swift
@@ class SingleSubmeshMesh: Mesh {
     internal var _submesh: Submesh!
     public let vertexMetadata: SingleMeshVertexMetadata
+
+    /// Origin currently baked into the (shared, cached) vertex buffer. Tracked so
+    /// `setSubmeshOrigin` is idempotent: an F-18 rebuilt across aircraft swaps shares
+    /// this one cached mesh, and re-applying the same origin must not accumulate.
+    private var _appliedOrigin: float3 = .zero
@@
     public func setSubmeshOrigin(_ origin: float3) {
-        translateSubmeshVertices(delta: origin)
+        // Absolute, not cumulative: translate from the currently-applied origin.
+        translateSubmeshVertices(delta: origin - _appliedOrigin)
+        _appliedOrigin = origin
     }
```

> The same accumulation class exists in `translateSubmeshVerticesToMatchParentScale` (it nets to zero only because `SubMeshGameObject` uses scale 1.0 for the F-18; a scaled single-submesh part rebuilt — e.g. `FreeCamFlightboxScene`'s `Sidewinder().setScale(4.0)` — would drift similarly). The deeper fix (see §2.4) is to stop editing shared geometry and express origin/scale as per-instance transforms; the diff above is the minimal correctness fix for the shipped F-18 path.

---

### 2.2 🚨 High — Selecting F-16 / F-18 / F-35 spawns an aircraft with gravity but no flight model (CONFIRMED)

`FlightboxWithPhysics.swift:175-186`, `Aircraft.swift:138-145`.

Only the two F-22 variants are built through helpers that attach a `FlightModel`:

```swift
case .f16:           playerAircraft = F16(scale: 12.0)          // no flightModel
case .f18:           playerAircraft = F18(scale: 1.4)           // no flightModel
case .f22:           playerAircraft = getPlayerAcF22()          // ac.flightModel = F22SimpleFlightModel()
case .f22_cgtrader:  playerAircraft = getPlayerAcCGTraderF22()  // ac.flightModel = F22SimpleFlightModel()
case .f35:           playerAircraft = F35(scale: 0.8)           // no flightModel
```

Every swapped aircraft still gets a gravity-applying `SphereRigidBody`. In `Aircraft.doUpdate` the physics path requires **both** a rigid body and a flight model; otherwise it falls back to kinematic `moveAlongVector`:

```swift
if let rigidBody, let flightModel, let rigidBodyState = rigidBody.getState() {
    rigidBody.force += flightModel.computeForce(...)
} else {
    moveAlongVector(getFwdVector(), distance: deltaMove * controlInput.throttle)   // no lift to counter gravity
}
```

So picking F-16, F-18, or F-35 from the menu drops the player at `[0,100,0]` and it falls — gravity integrates downward while only throttle nudges it forward. (The bundled `player_aircraft_selection_review` acknowledges this for F-16/F-35 as a "tuning gap"; it is reachable and player-visible for three of the five menu options, and F-18 shares it.)

**Fix — attach a placeholder flight model via helpers (mirrors the F-22 path), and/or filter the picker to flyable types until real models land:**

```diff
--- a/ToyFlightSimulator Shared/Scenes/FlightboxWithPhysics.swift
+++ b/ToyFlightSimulator Shared/Scenes/FlightboxWithPhysics.swift
         switch aircraft {
             case .f16:
-                playerAircraft = F16(scale: 12.0)
+                playerAircraft = makeFlyable(F16(scale: 12.0))
             case .f18:
-                playerAircraft = F18(scale: 1.4)
+                playerAircraft = makeFlyable(F18(scale: 1.4))
             case .f22:
                 playerAircraft = getPlayerAcF22()
             case .f22_cgtrader:
                 playerAircraft = getPlayerAcCGTraderF22()
             case .f35:
-                playerAircraft = F35(scale: 0.8)
+                playerAircraft = makeFlyable(F35(scale: 0.8))
         }
```

```swift
/// Until per-type flight models exist, give every player aircraft the F-22 model
/// as a placeholder so it flies instead of falling. Replace per type as models land.
private func makeFlyable<A: Aircraft>(_ ac: A) -> A {
    ac.flightModel = F22SimpleFlightModel()
    return ac
}
```

Alternative (keeps the UI honest): add `AircraftType.selectableCases` and drive the `Picker`'s `ForEach` from it.

---

### 2.3 ⚠️ Medium — The new `.F16` 180°Y basis silently re-orients the decorative F-16 prop (CONFIRMED)

`ModelLibrary.swift:68`, `FlightboxWithPhysics.swift:126-131`.

This diff adds the `rotate180AroundY` basis to the shared `.F16` model (previously identity), to orient the new *player* F-16:

```swift
_factories[.F16] = { ObjModel("f16r", basisTransform: rotate180AroundY) }
```

But `FlightboxWithPhysics.buildScene` builds a **decorative** F-16 that shares `Assets.Models[.F16]` and was tuned against the un-rotated model:

```swift
let f16 = F16(shouldUpdateOnPlayerInput: false)
f16.rotateY(Float(-90).toRadians)   // tuned for the OLD basis; now renders 180° off
```

With +180° baked into the model, this static prop now faces the opposite direction.

**Fix — compensate the decorative prop's yaw (verify visually), or special-case the player F-16's basis if the decorator's old heading was intended:**

```diff
--- a/ToyFlightSimulator Shared/Scenes/FlightboxWithPhysics.swift
+++ b/ToyFlightSimulator Shared/Scenes/FlightboxWithPhysics.swift
         let f16 = F16(shouldUpdateOnPlayerInput: false)
         f16.setPosition(0, jetPos.y + 10, jetPos.z + 15)
-        f16.rotateY(Float(-90).toRadians)
+        // .F16 now bakes in a 180°Y basis (for the player F-16); offset the
+        // decorative prop's heading so it still faces its intended direction.
+        f16.rotateY(Float(90).toRadians)
         f16.setScale(10.0)
```

---

### 2.4 ⚠️ Medium — `SingleSubmeshMesh` mixes pre-basis metadata with post-basis geometry (PLAUSIBLE / fragile)

`SingleSubmeshMesh.swift:37-62`.

`vertexMetadata` (including `initialPositionInParentMesh`, the centroid) is captured from the **pre-basis** buffer (it must be — `vertexMetadata` is a `let` and Swift requires it set before `super.init`):

```swift
let vertBuf = mtkMesh.vertexBuffers[0].buffer
vertexMetadata = Self.getVertexMetadata(submesh: submesh, vertexBuffer: vertBuf, vertexCount: mtkMesh.vertexCount)
super.init(mdlMesh: mdlMesh, mtkMesh: mtkMesh, basisTransform: basisTransform, copyVertexBuffer: true) // transforms the copy IN PLACE
...
translateSubmeshVertices(delta: -vertexMetadata.initialPositionInParentMesh) // pre-basis delta on post-basis geometry
```

Now that the F-18 submeshes receive `rotate180AroundY` (which negates X and Z), the recenter delta, the `translateSubmeshVerticesToMatchParentScale` deltas, and any caller reading `vertexMetadata.max*` (e.g. `FreeCamFlightboxScene.swift:57`, `maxZ/2`) are in a different coordinate space than the geometry.

**Why it isn't (yet) a visible F-18 defect:** the rest pose cancels by construction — `setupControlSurfaces` sets `node.position = initialPositionInParentMesh - origin` using the *same* pre-basis centroid, so `world = (a − o) + (R·p₀ − a + o) = R·p₀`. The residual error is that the **rotation pivot** (`node.position`) differs from the true geometry centroid (`R·a`) by `2·aₓ`. Ailerons/elevons/flaps hinge about ≈±X, so the error lies along the hinge axis (invisible); **rudders hinge about ≈Y** (`normalize([±0.25, 0.8, -0.30])`), where it can manifest as an off-axis pivot — unverified. Scaled single-submesh parts (FreeCam missiles) are uncompensated and would be mis-placed.

**Recommended fix — capture the centroid in post-basis space** so the recenter and pivot math match the geometry. Keep `vertexMetadata` a `let` by transforming the centroid with the basis before `super.init`:

```diff
--- a/ToyFlightSimulator Shared/AssetPipeline/SingleSubmeshMesh.swift
+++ b/ToyFlightSimulator Shared/AssetPipeline/SingleSubmeshMesh.swift
         let vertBuf = mtkMesh.vertexBuffers[0].buffer
-        vertexMetadata = SingleSubmeshMesh.getVertexMetadata(submesh: submesh,
-                                                             vertexBuffer: vertBuf,
-                                                             vertexCount: mtkMesh.vertexCount)
+        // Metadata must be set before super.init (it's a `let`), but geometry is
+        // basis-transformed inside super.init. Bring the centroid into post-basis
+        // space so recenter/origin/pivot math matches the transformed vertices.
+        let preBasis = SingleSubmeshMesh.getVertexMetadata(submesh: submesh,
+                                                           vertexBuffer: vertBuf,
+                                                           vertexCount: mtkMesh.vertexCount)
+        vertexMetadata = preBasis.transformingCentroid(by: basisTransform)
```

```swift
extension SingleMeshVertexMetadata {
    /// Returns a copy with `initialPositionInParentMesh` mapped through `basis`.
    /// (Min/max bounds are left as-is; an axis-aligned box isn't preserved under
    /// rotation — recompute from the transformed buffer if a true post-basis AABB
    /// is ever needed, e.g. the FreeCam `maxZ` pivot.)
    func transformingCentroid(by basis: float4x4) -> SingleMeshVertexMetadata {
        var m = self
        m.initialPositionInParentMesh = (basis * float4(initialPositionInParentMesh, 1)).xyz
        return m   // requires `var` fields, or rebuild via the memberwise init
    }
}
```

> **Caveat:** this shifts the rotation pivot to the true centroid, so the empirically-tuned F-18 origin constants (`5.6/14/5.8/15`) and the rudder/elevon/flap sign flips from this diff will likely need re-tuning afterward. Given the rest pose currently looks correct, the pragmatic path is: ship §2.1 now, and take §2.4 the next time this code is touched (or immediately if the rudders are visibly mis-pivoting). At minimum, add a comment documenting that metadata is pre-basis and only cancels by construction.

---

### 2.5 ⚠️ Medium — Lazy library subscripts run on the render hot path; first access builds assets on the render thread (CONFIRMED)

`DrawManager.swift:267, 294, 317, 346`; `SamplerStateLibrary.swift`, `ModelLibrary.swift`, `TextureLibrary.swift` subscripts.

The lazy subscripts now take a lock **and may build the asset** on first access. Several assets are first touched *during the draw loop*, not at scene build:

- `DrawSky` resolves `Assets.Textures[skyObj.textureType]` every frame; `SkyBox`/`SkySphere.init` only store the type (the texture-access line is commented out), so the **first** `DrawSky` runs `TextureLoader` disk I/O + `MTLTexture` upload **inside the library lock, on the render thread, mid-encode** — a first-frame hitch the old eager `makeLibrary` avoided.
- `DrawFullScreenQuad` resolves `Assets.Models[.Quad]` every frame; `.Quad` is referenced nowhere else (the `Quad` object uses `.Plane`; only `TerrainObject` uses `.Quad`), so for the OIT path the quad's OBJ + `MTKMesh` is first built on the render thread.
- `DrawPointLights` / `DrawIcosahedrons` resolve `Assets.Models[.Icosahedron]` every frame (submesh lists are cached, but the locked subscript still fires); both are `isEmpty`-guarded so neither is warmed at build.

**Fix — pre-warm draw-time assets off the render thread at scene/renderer setup, and cache the resolved reference instead of subscripting per frame:**

```diff
--- a/ToyFlightSimulator Shared/Scenes/GameScene.swift  (or renderer setup)
+++ b/ToyFlightSimulator Shared/Scenes/GameScene.swift
     func setupDefaultSky() {
         ...
+        // Warm draw-time assets now (off the render thread) so the first frame
+        // doesn't build them mid-encode inside the library lock.
+        _ = Assets.Textures[skyTextureType]
+        _ = Assets.Models[.Quad]
+        _ = Assets.Models[.Icosahedron]
     }
```

…and cache the resolved sky texture on the sky object (resolve once, store the `MTLTexture`) rather than calling `Assets.Textures[...]` every `DrawSky`.

---

### 2.6 ⚠️ Low–Medium — `currentLinearSamplerState` locks once per submesh on the draw path (CONFIRMED)

`SamplerStateLibrary.swift:74`, `DrawManager.swift:569`.

```swift
var currentLinearSamplerState: MTLSamplerState {
    withLock(currentLinearLock) { _currentLinear }   // lock acquire/release on every read
}
```

`applyMaterialTextures` calls this **once per submesh** (inside `drawSubmeshes`, for every opaque and transparent submesh, every frame) plus once per `DrawLines` batch. The old code was a lock-free dictionary lookup. This is a net-new uncontended lock acquisition on the hottest draw path for a value that only changes on a menu event — and the `setFragmentSamplerState` itself is redundant per submesh (the sampler is identical for all).

**Fix — bind the sampler once per pass (hoist out of the per-submesh helper), which removes both the per-submesh lock and the redundant encoder state-setting:**

```diff
--- a/ToyFlightSimulator Shared/Managers/DrawManager.swift
+++ b/ToyFlightSimulator Shared/Managers/DrawManager.swift
     private static func applyMaterialTextures(_ material: Material, with renderEncoder: MTLRenderCommandEncoder) {
-        renderEncoder.setFragmentSamplerState(Graphics.SamplerStates.currentLinearSamplerState, index: 0)
-
         // setFragmentTexture accepts nil — no need for separate else branches.
         renderEncoder.setFragmentTexture(material.baseColorTexture, index: TFSTextureIndexBaseColor.index)
         ...
     }
```

…with a single `renderEncoder.setFragmentSamplerState(Graphics.SamplerStates.currentLinearSamplerState, index: 0)` read once at the top of each opaque/transparent batch encode. (If a per-pass read is still desired lock-free, store `_currentLinear` as a read-mostly reference — a one-frame-stale sampler after a menu change is harmless.)

---

### 2.7 ℹ️ Medium — `unregisterSingle` is a hand-mirrored copy of `Register` and already diverges (altitude)

`SceneManager.swift:unregisterSingle` vs `Register`/`registerChildObject`.

The new removal path re-enumerates concrete types (`is Camera`, `is SkyBox`, `is Icosahedron`, `is Line`, `is ParticleEmitterObject`, `default → removeRenderable`) to mirror registration. It already omits `Tessellatable` (documented as intentional, since terrain isn't swapped). The hazard is structural: **registration and unregistration are two switches that must be kept in lockstep by hand** — any future registered type that lands in a new collection will register fine but silently fail to unregister (an orphan whose `ModelConstants` keep being written every frame), with no compile error.

**Fix — at minimum, fail loudly on the unhandled-but-registered case; better, drive both directions from one declaration** (e.g. each `GameObject` returns the collection it belongs to, or registration hands back a removal token). Minimal guard:

```diff
     private static func unregisterSingle(_ node: Node) {
         guard let gameObject = node as? GameObject else { return }
         switch gameObject {
             case is Camera, is SkyBox, is SkySphere, is LightObject:
                 break
             ...
+            case is Tessellatable:
+                // Mirror Register: tessellatables aren't removable today. If this
+                // fires, the register/unregister switches have drifted.
+                assertionFailure("Tessellatable unregister not implemented")
             default:
                 removeRenderable(gameObject)
         }
     }
```

---

### 2.8 ℹ️ Medium — The lazy factory + cache + lock triad is copy-pasted into three libraries (reuse)

`ModelLibrary.swift`, `SingleSubmeshMeshLibrary.swift`, `TextureLibrary.swift` each declare identical `_factories` / `_cache` / `_lock` and a byte-identical lock-guarded lazy subscript, while `Core/Types/Library.swift` remains a trivial nil pass-through. The concurrency-correctness logic (lock discipline, build-once invariant) is duplicated 3×; a fix to the pattern must be made in three files and can drift.

**Fix — host the pattern once in a `LazyLibrary` base:**

```swift
class LazyLibrary<Key: Hashable, Value>: Library<Key, Value>, @unchecked Sendable {
    private var _factories: [Key: () -> Value] = [:]
    private var _cache: [Key: Value] = [:]
    private let _lock = OSAllocatedUnfairLock()

    func register(_ key: Key, _ factory: @escaping () -> Value) { _factories[key] = factory }
    func setResolved(_ key: Key, _ value: Value) { withLock(_lock) { _cache[key] = value } }

    func resolve(_ key: Key) -> Value? {
        withLock(_lock) {
            if let cached = _cache[key] { return cached }
            guard let factory = _factories[key] else { return nil }
            let value = factory(); _cache[key] = value; return value
        }
    }
}
```

Each library then only declares its `makeLibrary()` `register(...)` calls and a thin subscript over `resolve(...)`. (The `TextureLibrary` value-vs-`Texture` wrapping and the `MTLTexture?` subscript can be expressed with `Value == Texture`.)

---

## 3. Priority

| # | Severity | Status | Issue | Fix |
|---|---|---|---|---|
| 2.1 | 🚨 High | CONFIRMED | F-18 control surfaces drift on repeated selection | absolute (idempotent) `setSubmeshOrigin` |
| 2.2 | 🚨 High | CONFIRMED | F-16/F-18/F-35 fall (no flight model) | attach placeholder model / filter picker |
| 2.3 | ⚠️ Medium | CONFIRMED | `.F16` basis flips decorative F-16 heading | compensate decorator yaw |
| 2.4 | ⚠️ Medium | PLAUSIBLE | pre-basis metadata vs post-basis geometry | capture centroid post-basis (re-tune after) |
| 2.5 | ⚠️ Medium | CONFIRMED | lazy assets first-built on render thread + per-frame re-resolve | pre-warm + cache resolved refs |
| 2.6 | ⚠️ Low-Med | CONFIRMED | per-submesh lock on `currentLinearSamplerState` | bind sampler once per pass |
| 2.7 | ℹ️ Medium | CONFIRMED | `unregisterSingle` hand-mirrors `Register`, drifts | unify / assert on unhandled |
| 2.8 | ℹ️ Medium | CONFIRMED | lazy triad duplicated across 3 libraries | `LazyLibrary` base |

Fix **2.1** and **2.2** before relying on the swap feature — both manifest in normal menu use. 2.3 is a quick visual fix. 2.5/2.6 are render-path perf. 2.4 is fragile-but-currently-masked. 2.7/2.8 are maintainability.

---

## 4. Additional minor observations

- **Anisotropy: two parallel enums.** `MaxAnisotropy` (raw value = the Int) and `SamplerStateType.Linear_Anisotropy*` encode the same five levels bridged by a hand-maintained `samplerType` switch; the `SamplerStateLibrary` subscript now has zero callers. Could key linear samplers by the `Int` directly (and clamp to the device's reported `maxAnisotropy`).
- **`AttachedCamera.attach` re-parents without detaching** from the previous aircraft's `children` (`Node.addChild` does no detach). Benign today (old aircraft deallocates), but a latent double-parent hazard if a removed aircraft is ever retained (e.g. a fired weapon storing `parentMeshGameObject`).
- **Redundant `physicsWorld.setEntities`** in `buildScene`: `applyAircraftSwap(.f22_cgtrader)` installs `[ground, aircraft]`, then `makeRandomDispersedObjects` appends ~100 bodies and `setEntities` runs again with the full list. Cold path; pass a flag to skip the install on the build path.
- **`ResetScene` cross-thread.** The swap was carefully deferred to the update thread via `PendingAircraftSwap`, but the menu's **Reset Scene** button still calls `SceneManager.ResetScene()` (full teardown + rebuild) directly on the main thread — a larger cross-thread mutation left on the same implicit "rendering is on main" invariant the swap fix removed. Consider routing it through the same deferral.
- **`setPlayerAircraft` lives only in `FlightboxWithPhysics`.** The base `GameScene.setPlayerAircraft` is a no-op, so selecting an aircraft in other aircraft-bearing scenes silently does nothing.
- **Cached parent `MDLMesh` re-processed per extraction** (PLAUSIBLE): `makeSingleSMMeshWithSubmeshNamed` now runs `addTangentBasis` (twice) and `MTKMesh(mesh:)` on the *shared cached* `mdlMesh` for each submesh; previously each extraction used a fresh asset. Mostly redundant work; a correctness risk only if those ModelIO ops aren't idempotent on an already-processed mesh.
- **Lazy load defers asset-missing crashes** from launch to first selection (fail-fast → fail-late). Acceptable tradeoff for lazy loading, worth noting.
- **Trivial:** leftover `/* TODO: placing this here for now */` above `SceneManager.SetPlayerAircraft`; dead `@State private var rendererType` re-added in iOS `TFSMenuMobile`; `GameStatsManager.currentRenderer`'s `.OrderIndependentTransparency` default is always overwritten by `Renderer.init`; `rotate180AroundY` and the `removeAll { $0.id == … }` idiom each duplicated (a `Transform` constant / shared helper would centralize them); macOS `TFSMenu` and iOS `TFSMenuMobile` duplicate the volume/aircraft/HUD control blocks.
- **tvOS:** new Shared files (`MetalPerformanceHUD`, `SamplerStateLibrary` references to `Preferences`) are auto-added to the tvOS target via synchronized groups and reference symbols excluded from tvOS — adds to (does not introduce) the already-non-building tvOS target. Out of CI scope (macOS-only), but worth knowing.

---

## 5. Conventions

No repo-`CLAUDE.md` rule is clearly violated. The new locks correctly use `OSAllocatedUnfairLock` + `withLock`; the new tests are Metal-free (`Node`/`TestRigidBody`/static helpers) with `.timeLimit` on the concurrency test; the new `cameraOffset` overrides keep the documented +Z-forward (−Z offset) convention; `PendingAircraftSwap` upholds the "UpdateThread owns game logic/physics" rule.
