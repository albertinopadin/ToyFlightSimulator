# Code Review — Player-selectable aircraft

**Branch:** `main` (uncommitted working-tree changes)
**Files reviewed:**
- `ToyFlightSimulator Shared/GameObjects/AircraftType.swift` (new)
- `ToyFlightSimulator Shared/GameObjects/F18.swift`
- `ToyFlightSimulator Shared/Managers/SceneManager.swift`
- `ToyFlightSimulator Shared/Scenes/FlightboxWithPhysics.swift`
- `ToyFlightSimulator Shared/Scenes/GameScene.swift`
- `ToyFlightSimulator macOS/Views/MacGameUIView.swift`
- `ToyFlightSimulator macOS/Views/TFSMenu.swift`

**Date:** 2026-06-15
**Status:** Resolved 2026-06-16 — see [§4 Resolution](#4-resolution-2026-06-16). 2.1–2.4 and 2.6 are fixed and verified (macOS build passes; 19 new Metal-free logic tests + 23 existing physics tests pass); 2.5 is partially done. The original review and its proposed diffs are retained below as the rationale; a few fixes were ultimately implemented differently than first proposed (noted in §4).

---

## 1. What changed

Runtime player-aircraft switching from the macOS menu.

| Addition | Summary |
|---|---|
| `AircraftType` enum (new file) | `CaseIterable, Identifiable`; 5 cases (`f16`, `f18`, `f22`, `f22_cgtrader`, `f35`), display names as `rawValue`. |
| `GameScene.playerAircraft: Aircraft?` + `setPlayerAircraft(_:)` | Stored property and overridable no-op hook on the base scene. |
| `FlightboxWithPhysics.setPlayerAircraft(_:)` | Builds the chosen aircraft, swaps its rigid body into `entities`, re-attaches the camera, removes the previous aircraft, adds the new one. Factory helpers `getPlayerAcF22()` / `getPlayerAcCGTraderF22()`. `aircraftStartPosition` constant. |
| `SceneManager.SetPlayerAircraft` / `RemoveObject` | Static plumbing forwarding to `CurrentScene`. `ModelData.removeGameObject(_:)`. |
| `TFSMenu` / `MacGameUIView` | SwiftUI `Picker` bound to `aircraftType`; `.onChange` calls `SceneManager.SetPlayerAircraft`. |
| F-18 tweaks | `Store` nested inside `F18`; rudder rotation-axis Z sign flips; rudder origin `14 → 15`; `cameraOffset` override `[0, 9, -20]`. |

The structural shape is good: the base-class hook, the `aircraftStartPosition` constant, the factory helpers, and nesting `Store` inside `F18` (verified — nothing outside `F18` references the old top-level `Store`) all read cleanly. The issues below are in the swap/teardown logic.

---

## 2. Findings

### 2.1 🚨 High — `.f16` / `.f35` selection destructively mutates the *current* aircraft

`FlightboxWithPhysics.swift:159-172`. The `.f16` and `.f35` cases `break` without assigning `playerAircraft`, so it retains the previous aircraft. Execution then enters `if let playerAircraft { … }` with `prevAc === playerAircraft`, and the swap body runs against the live aircraft:

- a fresh `SphereRigidBody` is built for the current aircraft (zeroing its velocity/force/state) and swapped in for the existing one;
- the aircraft is teleported back to `aircraftStartPosition`;
- the camera is re-attached (compounding the tilt — see 2.3);
- `SceneManager.RemoveObject(prevAc)` removes it, then `addChild(playerAircraft)` re-adds the **same instance**, which re-runs `registerChildObject` and double-registers its child game objects (see 2.2) so they draw twice.

So picking F-16 or F-35 — both presented in the menu — silently resets and corrupts the aircraft the player is currently flying.

**Fix:** early-return for unimplemented types so the body never runs with a stale `playerAircraft`.

```diff
--- a/ToyFlightSimulator Shared/Scenes/FlightboxWithPhysics.swift
+++ b/ToyFlightSimulator Shared/Scenes/FlightboxWithPhysics.swift
@@ -156,17 +156,15 @@ final class FlightboxWithPhysics: GameScene {
         let prevAc: Aircraft? = playerAircraft
         let prevAcRigidBody: RigidBody? = playerAircraft?.rigidBody
 
         switch aircraft {
-            case .f16:
-                break
+            case .f16, .f35:
+                print("[setPlayerAircraft] \(aircraft.rawValue) not yet supported — ignoring")
+                return
             case .f18:
                 playerAircraft = F18(scale: 1.4)
             case .f22:
                 playerAircraft = getPlayerAcF22()
             case .f22_cgtrader:
                 playerAircraft = getPlayerAcCGTraderF22()
-            case .f35:
-                break
-//            default:
-//                playerAircraft = getPlayerAcF22()
         }
```

Because the menu lists all five via `CaseIterable`, two of five options remain non-functional. Consider filtering the picker to supported types until F-16/F-35 land (keeps the UI honest):

```diff
--- a/ToyFlightSimulator macOS/Views/TFSMenu.swift
+++ b/ToyFlightSimulator macOS/Views/TFSMenu.swift
@@ -66,7 +66,7 @@ struct TFSMenu: View {
                         Picker("Aircraft: ", selection: $aircraftType) {
-                            ForEach(AircraftType.allCases) { aircraftType in
+                            ForEach(AircraftType.selectableCases) { aircraftType in
                                 Text("\(aircraftType.rawValue)").tag(aircraftType).padding()
                             }
                         }
```
```diff
--- a/ToyFlightSimulator Shared/GameObjects/AircraftType.swift
+++ b/ToyFlightSimulator Shared/GameObjects/AircraftType.swift
@@ -10,4 +10,7 @@ enum AircraftType: String, CaseIterable, Identifiable {
     case f35            = "F/A-35 Lightning II"
 
     var id: String { rawValue }
+
+    /// Types that currently have a working player model/flight-model wired up.
+    static var selectableCases: [AircraftType] { [.f18, .f22, .f22_cgtrader] }
 }
```

---

### 2.2 🚨 High — `RemoveObject` leaks the old aircraft's child objects

`SceneManager.swift:459-462`. `RemoveObject` removes only the single top-level node from the scene and from `modelDatas`. But aircraft register **descendants** with `SceneManager`:

- `F18` adds 8 `SubMeshGameObject` control surfaces (`F18.swift:327-365`) → registered into `modelDatas`.
- `F22` adds two `Afterburner` emitters (`F22.swift:34,38`) → registered into `SceneManager.particleObjects`.

`removeChild(prevAc)` drops the subtree from the scene-graph *traversal*, but `modelDatas` / `particleObjects` still hold strong references, and `writeFrameSnapshot` keeps writing their (now-frozen) `ModelConstants` every frame. After cycling through an F-18 or F-22 and switching away, its control surfaces / afterburners stay rendered as orphans at the swap point and never deallocate.

> Note: the default `F22_CGTrader` has no child game objects (control surfaces are skeletal), so the *first* swap from the default looks clean — which can mask this in casual testing. The leak triggers the moment you select F-18 or F-22 and then switch again.

There is currently no inverse of `Register`/`registerChildObject` for composite objects. Add one that recurses the subtree and removes each node from the collection it was registered into.

```diff
--- a/ToyFlightSimulator Shared/Managers/SceneManager.swift
+++ b/ToyFlightSimulator Shared/Managers/SceneManager.swift
@@ -50,6 +50,10 @@ struct ModelData {
     mutating func removeGameObject(_ gameObject: GameObject) {
         self.gameObjects.removeAll(where: { $0.id == gameObject.id })
     }
@@ -78,6 +82,10 @@ struct TransparentObjectData {
     mutating func addGameObject(_ gameObject: GameObject) {
         self.gameObjects.append(gameObject)
     }
+
+    mutating func removeGameObject(_ gameObject: GameObject) {
+        self.gameObjects.removeAll(where: { $0.id == gameObject.id })
+    }
 
     mutating func addModel(_ model: Model) {
         self.models.append(model)
     }
@@ -456,8 +464,32 @@ final class SceneManager {
     public static func SetPlayerAircraft(_ aircraft: AircraftType) {
         CurrentScene?.setPlayerAircraft(aircraft)
     }
 
     public static func RemoveObject(_ gameObject: GameObject) {
         CurrentScene?.removeChild(gameObject)
-        modelDatas[gameObject.model]?.removeGameObject(gameObject)
+        Unregister(gameObject)
+    }
+
+    /// Inverse of `Register` / `registerChildObject`: removes `node` and its
+    /// entire subtree from whatever batched collections they were registered
+    /// into. Mirrors the type dispatch in `Register`.
+    private static func Unregister(_ node: Node) {
+        // Recurse first so descendants (control surfaces, afterburners, …)
+        // are removed even though they're stored flat, not under the parent.
+        for child in node.children {
+            Unregister(child)
+        }
+
+        guard let gameObject = node as? GameObject else { return }
+
+        switch gameObject {
+            case is SkyBox, is SkySphere, is LightObject:
+                break  // sky is singleton-managed; lights aren't in these tables
+            case let icosahedron as Icosahedron:
+                icosahedrons.removeAll { $0.id == icosahedron.id }
+            case let line as Line:
+                lines.removeAll { $0.id == line.id }
+            case let particleObject as ParticleEmitterObject:
+                particleObjects.removeAll { $0.id == particleObject.id }
+            default:
+                if gameObject.isTransparent {
+                    transparentObjectDatas[gameObject.model]?.removeGameObject(gameObject)
+                } else {
+                    modelDatas[gameObject.model]?.removeGameObject(gameObject)
+                }
+        }
     }
 }
```

Notes:
- `SubMeshGameObject` falls through to `default` (it's a `GameObject`, not matched earlier) and lands in `modelDatas` / `transparentObjectDatas` — matching how `RegisterSubMeshObject` ends in `RegisterObject`. Correct.
- `tessellatables` is intentionally omitted: aircraft don't register as `Tessellatable`. Add a case if a future removable object does.
- Removing the last gameObject from a `modelDatas` / `transparentObjectDatas` entry leaves an empty-but-present entry; `writeFrameSnapshot` already guards on `!gameObjects.isEmpty`, so this is harmless. Drop the entry too if you want the dictionaries to stay tight.

---

### 2.3 ⚠️ Medium — camera pitch accumulates on every swap

`AttachedCamera.swift:28-32`. `attach` applies a **relative** `rotate3Axis(deltaX: -5°, …)`. `setPlayerAircraft` calls `attach` on every swap, so the camera tilts down another 5° each time. (Position is fine — `setPosition` is absolute; only rotation compounds.)

Reset orientation to identity before applying the tilt so repeated attaches are idempotent. `setRotation(angle: 0, axis:)` yields the identity quaternion and marks the transform dirty; `rotate3Axis` then composes the tilt from a known origin:

```diff
--- a/ToyFlightSimulator Shared/GameObjects/Cameras/AttachedCamera.swift
+++ b/ToyFlightSimulator Shared/GameObjects/Cameras/AttachedCamera.swift
@@ -26,8 +26,11 @@ class AttachedCamera: Camera {
 
     public func attach(to node: Node, offset: float3 = [0, 2, -4], rotation: float3 = [Float(-5).toRadians, 0, 0]) {
-        self.rotate3Axis(deltaX: rotation.x, deltaY: rotation.y, deltaZ: rotation.z)
+        // Reset to identity first so repeated attaches (aircraft swaps) don't
+        // accumulate the tilt each call.
+        self.setRotation(angle: 0, axis: [1, 0, 0])
+        self.rotate3Axis(deltaX: rotation.x, deltaY: rotation.y, deltaZ: rotation.z)
         self.setPosition(offset)
         node.addChild(self)
     }
```

Re-calling `addCamera(attachedCamera)` per swap is itself harmless — `CameraManager.RegisterCamera` is keyed by `cameraType` and just replaces. Also note the camera is never removed from the *old* aircraft's `children`; benign today only because the old aircraft deallocates — which stops being true if 2.2's reference leak isn't fixed.

---

### 2.4 ⚠️ Medium — scene mutation from the SwiftUI callback is only *accidentally* thread-safe

`TFSMenu`'s `.onChange` runs on the main thread and mutates `children`, `entities`, `physicsWorld`, and `modelDatas` — all read by the `UpdateThread`. This is safe today only because:

1. the render loop runs on the main thread (`MTKView.draw(in:)` with `preferredFramesPerSecond`, no custom queue), so `.onChange` and `draw(in:)` are serialized; and
2. the render↔update handshake (`Renderer.render` signals `updateSemaphore`, then blocks on `updateDoneSemaphore` — `Renderer.swift:132-136`) means the `UpdateThread` is parked on `updateSemaphore.wait()` whenever the main thread is processing UI events.

That's a real invariant but an implicit, undocumented one — it breaks silently if rendering ever moves off the main thread. Two options:

- **Cheapest:** document the coupling at `SetPlayerAircraft` / `setPlayerAircraft`.
- **Robust:** defer the swap to a safe point in the update loop via a pending-request flag, so it never races regardless of where rendering runs:

```diff
--- a/ToyFlightSimulator Shared/Scenes/FlightboxWithPhysics.swift
+++ b/ToyFlightSimulator Shared/Scenes/FlightboxWithPhysics.swift
@@ -25,6 +25,9 @@ final class FlightboxWithPhysics: GameScene {
     private let aircraftStartPosition: float3 = [0, 100, 0]
+
+    /// Aircraft-swap requested from the UI thread; applied at the top of the
+    /// next `doUpdate` so the mutation runs on the update thread.
+    private var pendingAircraftSwap: AircraftType?
@@ -155,6 +158,11 @@ final class FlightboxWithPhysics: GameScene {
     override func setPlayerAircraft(_ aircraft: AircraftType) {
+        // Called from the SwiftUI main thread — just record the request.
+        pendingAircraftSwap = aircraft
+    }
+
+    private func applyAircraftSwap(_ aircraft: AircraftType) {
         let prevAc: Aircraft? = playerAircraft
         // … existing body …
     }
@@ -211,6 +219,11 @@ final class FlightboxWithPhysics: GameScene {
     override func doUpdate() {
         super.doUpdate()
+
+        if let pending = pendingAircraftSwap {
+            pendingAircraftSwap = nil
+            applyAircraftSwap(pending)
+        }
 
         let fdTime = Float(GameTime.DeltaTime)
```

(With the deferred approach, `buildScene`'s initial `setPlayerAircraft(.f22_cgtrader)` should call `applyAircraftSwap(.f22_cgtrader)` directly, since `buildScene` runs before the update loop spins and there's no aircraft to render until it does.)

---

### 2.5 ℹ️ Low — cleanups

- **Leftover debug prints:** `setPlayerAircraft` ("Removing previous aircraft") and the `.onChange` handler ("Setting Player Aircraft"). Fine on a feature branch; drop before merge.
- **`ObjectIdentifier` comparison** (`FlightboxWithPhysics.swift:180`): `ObjectIdentifier($0) == ObjectIdentifier(prevAcRigidBody)` simplifies to `$0 === prevAcRigidBody` (both are class instances).

```diff
--- a/ToyFlightSimulator Shared/Scenes/FlightboxWithPhysics.swift
+++ b/ToyFlightSimulator Shared/Scenes/FlightboxWithPhysics.swift
@@ -178,7 +178,7 @@ final class FlightboxWithPhysics: GameScene {
             if let prevAcRigidBody {
-                entities.removeAll(where: { ObjectIdentifier($0) == ObjectIdentifier(prevAcRigidBody) })
+                entities.removeAll(where: { $0 === prevAcRigidBody })
             }
```

- **WIP markers:** `// TODO: placing this here for now` and the commented-out `default:` case — resolve or remove before merge.

---

### 2.6 ℹ️ Low — no tests

The swap bookkeeping (entity add/remove with no duplicate rigid bodies, subtree deregistration) is registry logic that's testable without Metal, in line with the existing `Physics/` and `Cameras/` Swift Testing suites. A test asserting that swapping away from an `F18` leaves no orphaned entries in `SceneManager.modelDatas` would have caught 2.2; one asserting a single rigid body per swap would have caught 2.1.

---

### 2.7 F-18 tuning tweaks (no action required)

The rudder rotation-axis Z-sign flips (`F18.swift:283-284`), rudder origin `14 → 15` (`:319`), and the `cameraOffset` override are empirical control-surface tuning continuing commit `1704e81`. No correctness concern, but they're only verifiable visually and there's no test guarding the constants — confirm in-app that the rudders sit and deflect correctly.

---

## 3. Priority

| # | Severity | Issue | Action | Status |
|---|---|---|---|---|
| 2.1 | 🚨 High | `.f16`/`.f35` fall-through resets + double-registers the live aircraft | early-return | ✅ Resolved (full F-16/F-35 implemented) |
| 2.2 | 🚨 High | `RemoveObject` orphans registered child objects (control surfaces, afterburners) | add recursive `Unregister` | ✅ Resolved (+ `Camera` skip) |
| 2.3 | ⚠️ Medium | camera pitch accumulates per swap | reset rotation in `attach` | ✅ Resolved |
| 2.4 | ⚠️ Medium | cross-thread scene mutation safe only by implicit invariant | document, or defer swap to `doUpdate` | ✅ Resolved (lock-backed deferral) |
| 2.5 | ℹ️ Low | debug prints, `ObjectIdentifier`, WIP markers | cleanup | 🟡 Partial |
| 2.6 | ℹ️ Low | no tests for swap logic | add registry tests | ✅ Resolved (19 tests) |

Fix 2.1 and 2.2 before merge; they manifest in normal use. 2.3 and 2.4 are quick follow-ups; 2.5/2.6 are polish.

---

## 4. Resolution (2026-06-16)

All blockers and the test gap are closed; one low cleanup remains. Verified with `xcodebuild build` (macOS Debug, **BUILD SUCCEEDED**) and scoped `test-without-building` runs (**19 new + 23 existing physics tests pass**).

- **2.1 — ✅ Resolved, differently than proposed.** Rather than early-returning and filtering the picker to `selectableCases`, F-16 and F-35 were given real player instantiation (`F16(scale: 6.0)`, `F35(scale: 0.8)`), and the F-16 model got the `rotate180AroundY` basis the F-18 already uses. `playerAircraft` is now always reassigned to a fresh instance, so `prevAc !== playerAircraft` and the destructive fall-through can't occur. All five menu entries are functional. (Note: F-16/F-35 have no `FlightModel` yet, so they use the `moveAlongVector` fallback while still subject to gravity — a tuning item, not a correctness bug.)
- **2.2 — ✅ Resolved.** `RemoveObject` now calls a recursive `Unregister`, which walks `subtreeNodes(of:)` (extracted, pure, unit-tested) and removes each node from the collection it was registered into, dropping now-empty per-`Model` entries. Added `TransparentObjectData.removeGameObject`. **Beyond the proposed diff,** an `is Camera` skip was added — `Camera` is a `GameObject` (`modelType: .None`) living in the aircraft subtree but never registered, so removal must skip it just as `registerChildObject` does.
- **2.3 — ✅ Resolved.** `AttachedCamera.attach` zeroes rotation (`setRotationX/Y/Z(0)` → identity quaternion) before applying the −5° tilt, so repeated attaches are idempotent.
- **2.4 — ✅ Resolved, more robustly than proposed.** Instead of a plain `var pendingAircraftSwap` (which would itself be a cross-thread data race), the swap is deferred through `PendingAircraftSwap` — an `OSAllocatedUnfairLock`-backed single-slot mailbox (matches the `TFSCache` convention). `setPlayerAircraft` (UI thread) only records the request; `doUpdate` (update thread) consumes and applies it via `applyAircraftSwap` before stepping physics; `buildScene` applies immediately. The implicit "rendering is on the main thread" invariant is no longer relied upon.
- **2.5 — 🟡 Partial.** `ObjectIdentifier` → `===` (done, now inside `swappedEntities`); the `setPlayerAircraft` "Removing previous aircraft" print and the commented-out `default:` case are gone. Still outstanding: the `.onChange` `print("[Setting Player Aircraft]…")` in `TFSMenu.swift` and the `// TODO: placing this here for now` marker above `SceneManager.SetPlayerAircraft`.
- **2.6 — ✅ Resolved.** 4 Swift Testing suites, 19 tests, all Metal-free per the repo's test constraint (no `GameObject`/`Model` is constructible without a Metal device, since `Assets.Models` eager-loads every model). The bug-prone logic was extracted into pure helpers and tested directly:
  - `AircraftTypeTests` — enum cases, `id == rawValue`, round-trip.
  - `PendingAircraftSwapTests` — take-once semantics, latest-wins coalescing, 2 000-task concurrency stress (`.timeLimit`).
  - `AircraftEntitySwapTests` — `FlightboxWithPhysics.swappedEntities` dedup; "repeated swaps never accumulate" directly guards 2.1; identity-based removal.
  - `SceneManagerUnregisterTests` — `SceneManager.subtreeNodes` visits grandchildren/deeper, the direct regression guard for 2.2.

### 2.7 follow-up
F-18 rudder tuning constants are unchanged and remain visually-verified-only (no automated guard) — confirm in-app.
