# Implement the 'C' key camera cycle (N cameras, slot-indexed)

Status: **implemented** (2026-07-12). All diffs below landed as written. Verified: macOS Debug + iOS Simulator builds pass, scoped `CameraManagerCycleTests` suite passes (5/5), app-launch smoke test clean. Manual 'C'-key runtime checks (Verification step 3) are user-driven and still pending.

Revision note: the original draft implemented a two-camera Debug ↔ Attached toggle. Per review, the design is generalized to **cycle through any number of registered cameras** — one chase camera on the player's jet, perhaps another chase camera on an enemy jet, an orbit camera around a tower, etc. The 'C' key is the only input wired now, but every selection path funnels through a slot-indexed `CameraManager.SetCamera(at:)`, so mapping the number row (1–0) or F1–F12 to specific cameras later is an input-table addition, not a redesign (see "Future: direct slot selection").

## Problem

CLAUDE.md documents a 'C' key that switches cameras, but no such input path exists — and git pickaxe across all history (`toggleCamera`, `SetCamera`, `.c` keycode variants, `--all`) shows it **never** existed. The doc was aspirational.

Verified current state:
- `Keycodes.c = 0x08` is defined (`Keycodes.swift:26`) but referenced nowhere. (The number row `one`–`zero` is also already defined, `Keycodes.swift:52-61` — relevant to the future direct-selection mapping.)
- `DiscreteCommand` (`InputManager.swift:10-23`) has no camera case; `keyboardMappingsDiscrete` (lines 108-117) maps p/l/space/n/m/j/f/g only.
- **The registry itself caps the feature**: `CameraManager._cameras` is `[CameraType: Camera]` (`CameraManager.swift:9`) and `CameraType` has exactly two cases (`Debug`, `Attached`). A dictionary keyed by type holds at most one camera per type — a scene with chase cameras on both the player's jet and an enemy jet is unrepresentable. Any N-camera design must re-key the registry.
- `SetCamera(by type)` has a latent footgun the redesign removes: a lookup miss (`_cameras[type]` nil) silently sets `CurrentCamera = nil`.
- The only `CameraManager.SetCamera` caller is scene-build (`GameScene.addCamera`, `GameScene.swift:81-86`), passing `camera.cameraType`. `CameraManager` has no cycle/toggle method.
- **No scene registers two cameras**: `FlightboxWithPhysics` (default scene) registers only the persistent `AttachedCamera`; `FreeCamFlightboxScene` only a `DebugCamera`. (`SandboxScene` constructs both a `DebugCamera` and an `AttachedCamera` but the debug `addCamera` is commented out.) A cycle key would have nothing to advance to.
- **Input bleed (bidirectional), verified — must be fixed as part of this work, and it scales with camera count.** `Mouse.GetDX/GetDY/GetDWheel` are consume-and-zero reads. If a `DebugCamera` were simply registered non-current, `CameraManager.Update` (which updates every **unparented** registered camera, `CameraManager.swift:29-36`) would run its `doUpdate` each tick, where it unconditionally consumes arrows/a/d, the `Pitch`/`Roll`/`MoveFwd`/`MoveSide` continuous commands, and mouse deltas (`DebugCamera.swift:18-65`) — stealing input from the flying player. Conversely `AttachedCamera` is **parented**, so scene-graph traversal updates it regardless of which camera is current, and its `doUpdate` (`AttachedCamera.swift:72-101`) would keep consuming right-drag/wheel/i-j-k-l while another camera is active, silently re-aiming the chase view. With N cameras this is multiplicative: *every* parented chase camera (player's jet, enemy jet) and *every* unparented free/orbit camera would fight over the same mouse deltas and axes each tick. The per-camera `isActiveCamera` guard is therefore load-bearing for the whole feature, not a two-camera nicety.

## Design

**Ordered registry; registration order is the contract.** `CameraManager._cameras` becomes `ContiguousArray`-style ordered `[Camera]` (identity-deduped append). Registration order defines both the **cycle order** ('C' walks the list, wrapping) and the **slot indices** for future direct selection (slot 0 = first registered = number-row key 1). Scenes control the order simply by the order of their `addCamera` calls.

**One selection funnel.** A private `makeCurrent(_:)` performs the aspect-ratio refresh (an inactive camera misses window resizes — `SetAspectRatio` only updates the current camera) and assigns `CurrentCamera`. Three public entry points route through it:
- `SetCamera(_ camera: Camera)` — instance-based (scene-build; replaces set-by-type, which can't distinguish two chase cameras and could nil `CurrentCamera` on a miss).
- `SetCamera(at index: Int)` — slot-based; out-of-range is a no-op. **This is the hook the number row / F keys bind to later.** The cycle uses it too.
- `CycleCamera()` — 'C' key. Advances to the next slot in registration order via the pure rule below.

**Pure, Metal-free cycle rule** (unit-testable — same pattern as `FlightboxWithPhysics.swappedEntities`, `SceneManager.subtreeNodes`, `AttachedCamera.scaleStrippedInverse`):

```swift
nextCameraIndex(after: Int?, count: Int) -> Int?   // (i + 1) % count; nil when count < 2 or no current
```

**`CameraType` is demoted, not removed.** The registry no longer keys on it; it stays on `Camera` as descriptive metadata (one existing test constructs `Camera(name:cameraType:aspectRatio:)` — `SceneManagerRegisterTests.swift:26`). Optional follow-up: delete it entirely once nothing reads it.

**Input side**: `DiscreteCommand.CycleCamera` (named for what it does now, not "Toggle") mapped to `.c`, polled debounced in `GameScene.doUpdate()` — the **update thread**, so shadow-cascade fitting, view matrix, and `_sceneConstants.cameraPosition` all see the same camera within one tick (a main-thread switch from the `MacGameUIView` timer could swap cameras between the cascade fit and the scene-constants read, and wouldn't exist on iOS). Same precedent as `Aircraft.handleGearToggle` and the existing ClickSelect/ResetScene handling in that method.

**Input-bleed fix**: `Camera.isActiveCamera` guard at the top of both existing input-driven `doUpdate`s. Per-camera guard, not a `CameraManager.Update` filter — a filter can't reach parented cameras (chase cameras update via scene-graph traversal). Behavior-neutral today: in every existing scene the registered camera *is* the current camera.

Known/accepted behavior (documented, not "fixed" here):
- While viewing through a non-chase camera, the **aircraft** still consumes stick/throttle input (`Aircraft` has no active-camera concept) — same class of behavior `FreeCamFlightboxScene` avoids via `shouldUpdateOnPlayerInput: false`.
- Swapping aircraft while in another view snaps back to the player chase view (`applyAircraftSwap` → `addCamera(attachedCamera)` → `SetCamera(attachedCamera)`). Reasonable — a swap implies "look at my new jet". The re-`addCamera` is idempotent by identity, so the chase camera **keeps its original slot** (slot stability across swaps — number-row bindings won't shuffle).
- `BallPhysicsScene`/`PhysicsStressTestScene` don't call `super.doUpdate()`, so the key is dead there — harmless, both are single-camera scenes where it would no-op anyway.
- Switching to a camera runs its input from the **next** tick (`CameraManager.Update` ran earlier in the same tick) — deterministic 1-tick latency, imperceptible.
- Scene reset / renderer switch are clean: `teardownScene()` → `CameraManager.RemoveAllCameras()`, and the rebuilt scene re-registers fresh cameras (slots reassigned by rebuild order).
- `CameraManager.Update` iteration becomes deterministic (array order) — previously unspecified dictionary-values order. No observable change today.

## Diffs

### 1. `ToyFlightSimulator Shared/Managers/InputManager.swift`

```diff
     case ToggleFlaps
     case ToggleGear
+    case CycleCamera
     
     case Pause
     case ClickSelect
 }
```

```diff
     nonisolated(unsafe) private static var keyboardMappingsDiscrete: [DiscreteCommand: Keycodes] = [
         .Pause: .p,
         .ResetLoadout: .l,
         .FireMissileAIM9: .space,
         .FireMissileAIM120: .n,
         .DropBomb: .m,
         .JettisonFuelTank: .j,
         .ToggleFlaps: .f,
-        .ToggleGear: .g
+        .ToggleGear: .g,
+        .CycleCamera: .c
     ]
```

No controller/joystick mapping (the debounce helper's other device branches guard-let and no-op). `DiscreteCommand` is never `switch`ed over anywhere, so iOS/tvOS compile untouched; iOS never feeds hardware-key state, so the mapping is dormant there.

### 2. `ToyFlightSimulator Shared/Managers/CameraManager.swift` — ordered registry + selection funnel

Nearly every line changes; full replacement body shown instead of a diff:

```swift
final class CameraManager {
    /// Registration order is the contract: it defines the 'C'-cycle order AND
    /// the slot indices for direct selection (slot 0 = first registered).
    /// Identity-deduped — re-registering a camera keeps its original slot
    /// (aircraft swaps re-add the persistent chase camera every time).
    nonisolated(unsafe) private static var _cameras: [Camera] = []
    nonisolated(unsafe) public static var CurrentCamera: Camera?

    public static func RegisterCamera(camera: Camera) {
        if !_cameras.contains(where: { $0 === camera }) {
            _cameras.append(camera)
        }
    }

    /// Makes a camera current (registering it first if needed — cannot miss
    /// and nil out CurrentCamera like the old set-by-type lookup could).
    public static func SetCamera(_ camera: Camera) {
        RegisterCamera(camera: camera)
        makeCurrent(camera)
    }

    /// Slot-indexed selection: the binding point for future number-row /
    /// F-key camera hotkeys (slot N = Nth addCamera call in the scene).
    /// Out-of-range index is a no-op. Update-thread only, like every other
    /// gameplay CurrentCamera mutation.
    public static func SetCamera(at index: Int) {
        guard _cameras.indices.contains(index) else { return }
        makeCurrent(_cameras[index])
    }

    /// Advances to the next registered camera in registration order,
    /// wrapping ('C' key). No-op in single-camera scenes.
    public static func CycleCamera() {
        guard let next = nextCameraIndex(after: currentCameraIndex(),
                                         count: _cameras.count) else { return }
        SetCamera(at: next)
    }

    /// Pure cycle rule, unit-testable without touching the live registry
    /// (tests run app-hosted; mutating the real registry would hijack the
    /// running scene's camera). nil = stay put: fewer than two cameras, or
    /// no current camera (pre-scene / mid-teardown — don't grab one).
    static func nextCameraIndex(after currentIndex: Int?, count: Int) -> Int? {
        guard count >= 2, let currentIndex else { return nil }
        return (currentIndex + 1) % count
    }

    private static func currentCameraIndex() -> Int? {
        guard let current = CurrentCamera else { return nil }
        return _cameras.firstIndex(where: { $0 === current })
    }

    /// Single selection funnel. The aspect-ratio refresh matters here:
    /// SetAspectRatio only updates the CURRENT camera, so a camera that was
    /// inactive during a window resize has a stale projection.
    private static func makeCurrent(_ camera: Camera) {
        camera.setAspectRatio(Renderer.AspectRatio)
        CurrentCamera = camera
    }

    public static func RemoveAllCameras() {
        _cameras.removeAll()
        CurrentCamera = nil
    }

    public static func SetAspectRatio(_ aspectRatio: Float) {
        CurrentCamera?.setAspectRatio(aspectRatio)
    }

    public static func Update(deltaTime: Double) {
        for camera in _cameras {
            // Parented cameras (e.g. AttachedCamera) are updated during the
            // scene graph traversal. Only update unparented cameras here:
            guard camera.parent == nil else { continue }
            camera.update()
        }
    }

    /// Returns the active camera's world position, or `.zero` if no camera is active.
    public static func GetCurrentCameraPosition() -> float3 {
        CurrentCamera?.modelMatrix.columns.3.xyz ?? .zero
    }
}
```

Notes:
- `makeCurrent` also runs at scene-build time (via `SetCamera` from `addCamera`) — behavior-neutral: camera initializers already pass `Renderer.AspectRatio`, so this recomputes an identical projection.
- The `guard camera.parent == nil` in `Update` and `GetCurrentCameraPosition` are byte-for-byte the current behavior; only the container type changed.

### 3. `ToyFlightSimulator Shared/GameObjects/Cameras/Camera.swift`

```diff
 class Camera: GameObject {
     // Cameras live in CameraManager, not in SceneManager's batched collections.
     override var objectType: GameObjectType { .none }
 
+    /// Whether this camera is the one the scene currently renders through.
+    /// Input-driven cameras guard doUpdate on this so inactive registered
+    /// cameras neither drift with the shared flight-control axes nor
+    /// destructively consume Mouse.GetDX/GetDY/GetDWheel (consume-and-zero
+    /// reads). With N registered cameras, EVERY inactive chase/free camera
+    /// would otherwise fight the active one for the same deltas each tick.
+    var isActiveCamera: Bool { CameraManager.CurrentCamera === self }
+
     var fieldOfView: Float!
```

### 4. `ToyFlightSimulator Shared/GameObjects/Cameras/DebugCamera.swift`

```diff
     override func doUpdate() {
+        // Registered but not rendering (e.g. a chase view is active): consume no input.
+        guard isActiveCamera else { return }
+
         if Keyboard.IsKeyPressed(.leftArrow) || Keyboard.IsKeyPressed(.a) {
```

### 5. `ToyFlightSimulator Shared/GameObjects/Cameras/AttachedCamera.swift`

```diff
     override func doUpdate() {
+        // Parented cameras update via scene-graph traversal even when not
+        // current — without this guard every chase camera in the scene would
+        // keep consuming right-drag/wheel/i-j-k-l while another camera is active.
+        guard isActiveCamera else { return }
+
         if Mouse.IsMouseButtonPressed(button: .RIGHT) {
```

### 6. `ToyFlightSimulator Shared/Scenes/GameScene.swift` — instance-based selection + 'C' poll

`addCamera` passes the camera instance (set-by-type can't distinguish two chase cameras):

```diff
     func addCamera(_ camera: Camera, _ isCurrentCamera: Bool = true) {
         CameraManager.RegisterCamera(camera: camera)
         if (isCurrentCamera) {
-            CameraManager.SetCamera(camera.cameraType)
+            CameraManager.SetCamera(camera)
         }
     }
```

In `doUpdate()`, insert between the ClickSelect block and the ResetScene block:

```diff
             }
         }
 
+        InputManager.HasDiscreteCommandDebounced(command: .CycleCamera) {
+            // Update-thread mutation: keeps cascade fitting, viewMatrix, and
+            // cameraPosition on the same camera for the whole tick.
+            CameraManager.CycleCamera()
+        }
+
         InputManager.HasMultiInputCommand(command: .ResetScene) {
```

### 7. `ToyFlightSimulator Shared/Scenes/FlightboxWithPhysics.swift`

```diff
     var attachedCamera = AttachedCamera(fieldOfView: 75.0,
                                         near: 0.01,
                                         far: 1_000_000.0)
+    /// Free-fly camera, slot 1 in the 'C' cycle (chase camera is slot 0).
+    /// Unparented, so CameraManager.Update drives it.
+    let debugCamera = DebugCamera()
     var sun = Sun(modelType: .Sphere)
```

In `buildScene()`, after `let jetPos = aircraftStartPosition`:

```diff
         let jetPos = aircraftStartPosition
 
+        // Cycle target; the chase camera stays the default view. Registered
+        // AFTER the chase camera (which buildScene registers via
+        // applyAircraftSwap → addCamera) so cycle order is chase → free. +Z is
+        // forward, so the -Z offset spawns it behind the jet looking at it.
+        debugCamera.setPosition(jetPos + float3(0, 5, -40))
+        addCamera(debugCamera, false)
+
         setupDefaultSky()
```

(The jet spawns at `[0, 100, 0]` — don't copy `FreeCamFlightboxScene`'s ground-level position. Tune the −40 during manual verification.)

This ships a two-slot cycle, but the mechanism is N-ready with **zero further manager changes**: a scene that later adds a chase camera on an enemy jet (`let enemyCamera = AttachedCamera(...)`; `addCamera(enemyCamera, false)`; `enemyCamera.attach(to: enemyJet, ...)`) or an orbiting tower camera (a future `OrbitCamera: Camera` subclass — unparented, so `CameraManager.Update` drives it, and its `doUpdate` must start with the same `guard isActiveCamera` if it consumes input; a pure timer-driven orbit can skip the guard) just makes more `addCamera(_, false)` calls, in the order the slots should cycle. `SandboxScene` already constructs a second camera (its debug `addCamera` is commented out) and is the natural testbed for a 3-slot cycle.

### 8. New test — `ToyFlightSimulatorTests/Managers/CameraManagerCycleTests.swift`

The test target is a `PBXFileSystemSynchronizedRootGroup`, so a new file under `ToyFlightSimulatorTests/` joins the target automatically — no pbxproj edit.

```swift
//
//  CameraManagerCycleTests.swift
//  ToyFlightSimulatorTests
//
//  Created by Albertino Padin on 7/12/26.
//

import Testing
@testable import ToyFlightSimulator

/// Exercises the pure cycle rule (`CameraManager.nextCameraIndex`) only.
/// These tests run app-hosted (like SceneManagerRegisterTests) while the
/// game's update thread owns the live CameraManager registry — mutating
/// `CurrentCamera`/`_cameras` here would hijack the running scene's camera,
/// so the stateful `CycleCamera()`/`SetCamera(at:)` wrappers are covered by
/// manual runtime verification instead.
@Suite("CameraManager cycle rule", .tags(.scenes))
struct CameraManagerCycleTests {

    @Test("Two cameras alternate (the classic Attached/Debug toggle)")
    func twoCamerasAlternate() {
        #expect(CameraManager.nextCameraIndex(after: 0, count: 2) == 1)
        #expect(CameraManager.nextCameraIndex(after: 1, count: 2) == 0)
    }

    @Test("N cameras advance in registration order and wrap")
    func nCamerasAdvanceAndWrap() {
        #expect(CameraManager.nextCameraIndex(after: 0, count: 3) == 1)
        #expect(CameraManager.nextCameraIndex(after: 1, count: 3) == 2)
        #expect(CameraManager.nextCameraIndex(after: 2, count: 3) == 0)
    }

    @Test("Fewer than two cameras is a no-op")
    func fewerThanTwoCamerasIsNoOp() {
        #expect(CameraManager.nextCameraIndex(after: 0, count: 1) == nil)
        #expect(CameraManager.nextCameraIndex(after: nil, count: 0) == nil)
    }

    @Test("No current camera is a no-op (pre-scene / mid-teardown)")
    func noCurrentCameraIsNoOp() {
        #expect(CameraManager.nextCameraIndex(after: nil, count: 3) == nil)
    }

    @Test("Out-of-range current index still lands in range (defensive modulo)")
    func outOfRangeCurrentWrapsIntoRange() {
        // Unreachable through the public API (firstIndex is always < count);
        // pins the defensive behavior of the raw rule.
        #expect(CameraManager.nextCameraIndex(after: 5, count: 3) == 0)
    }
}
```

### 9. Doc updates (anchor by content, not line number)

`AGENTS.md` (line 154, macOS shortcuts bullet):

```diff
-- macOS shortcuts: `Y` stats overlay (including active renderer), `H` Metal HUD, `Esc` menu/pause, and `Cmd+R` deferred reset. Aircraft controls include `G` gear and `F` for the legacy F-18 flaps. `CameraManager` supports multiple camera types, but no current input path toggles them.
+- macOS shortcuts: `Y` stats overlay (including active renderer), `H` Metal HUD, `Esc` menu/pause, `C` camera cycle, and `Cmd+R` deferred reset. Aircraft controls include `G` gear and `F` for the legacy F-18 flaps. The `C` key is `DiscreteCommand.CycleCamera`, polled debounced on the update thread in `GameScene.doUpdate`; it walks registered cameras in registration order (slot order — `CameraManager.SetCamera(at:)` is the direct-selection hook for future number-row/F-key bindings) and no-ops in single-camera scenes. Inactive cameras skip their input `doUpdate` via `Camera.isActiveCamera` — `Mouse.GetD*` reads are consume-and-zero, so an unguarded inactive camera would steal deltas from the active one.
```

`CLAUDE.md` Input section (final sentences):

```diff
-... Commands: `DiscreteCommands` (fire, toggle gear/flaps), `ContinuousCommands` (pitch, roll, yaw, move). Debouncing for discrete commands.
+... Commands: `DiscreteCommands` (fire, toggle gear/flaps, cycle camera), `ContinuousCommands` (pitch, roll, yaw, move). Debouncing for discrete commands.
```

`CLAUDE.md` Camera System section (final sentence):

```diff
-... Toggle with 'C' key.
+... 'C' key (`DiscreteCommand.CycleCamera`, debounced on the update thread in `GameScene.doUpdate`) cycles registered cameras in registration order; CameraManager's registry is an ordered identity-deduped array (registration order = cycle order = slot indices for `SetCamera(at:)` direct selection), scenes opt in by registering extra cameras via `addCamera(_, false)` (FlightboxWithPhysics adds a DebugCamera), and inactive cameras skip input via `isActiveCamera`.
```

`CLAUDE.md` Debugging section ('C' key bullet):

```diff
-- **'C' key**: Toggle debug/attached camera. Debug: WASD + mouselook. Attached: follows aircraft
+- **'C' key**: Cycle registered cameras in registration order (no-op in single-camera scenes). Debug: WASD + mouselook. Attached: follows aircraft
```

## Future: direct slot selection (number row / F keys) — design notes only, not in this change

Everything funnels into `CameraManager.SetCamera(at:)`; the remaining work is purely input plumbing:

- **Number row (recommended first)**: `Keycodes.one`–`.zero` already exist, and `InputManager.HandleKeyPressedDebounced(keyCode:_:)` already debounces **any** `Keycodes` case (its `keysPressed` table is built from `allCases`) — zero InputManager changes needed. Sketch, in `GameScene.doUpdate()` next to the CycleCamera poll:

  ```swift
  private static let cameraSlotKeys: [Keycodes] =
      [.one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .zero]

  for (slot, key) in Self.cameraSlotKeys.enumerated() {
      InputManager.HandleKeyPressedDebounced(keyCode: key) {
          CameraManager.SetCamera(at: slot)   // out-of-range slot = no-op
      }
  }
  ```

  The number row is currently unbound (discrete: p/l/space/n/m/j/f/g; continuous: w/a/s/d/e/q/arrows; raw camera keys: i/j/k/l) — no conflicts.
- **F keys**: `Keycodes` needs new cases first (macOS virtual key codes: F1 `0x7A`, F2 `0x78`, F3 `0x63`, F4 `0x76`, F5 `0x60`, F6 `0x61`, F7 `0x62`, F8 `0x64`, F9 `0x65`, F10 `0x6D`, F11 `0x67`, F12 `0x6F`); `keysPressed` picks them up automatically via `allCases`. Caveat: by default macOS routes the F row to media functions — plain F1 adjusts brightness and never reaches `keyDown` unless the user holds `fn` or enables "Use F1, F2, etc. keys as standard function keys". That's why the number row should land first.
- **If non-keyboard devices should ever select cameras** (controller D-pad, HOTAS hat), add per-slot `DiscreteCommand` cases instead of the raw-keycode loop, so the existing controller/joystick debounce plumbing applies.
- Slot legibility is the scene author's job: registration order = slot order, so keep a scene's `addCamera` calls together and commented (slot 0 = player chase, slot 1 = free cam, slot 2 = enemy chase, …).

## Verification

1. Builds (macOS Debug + iOS Simulator — the iOS build proves the shared enum/camera-manager changes compile off-macOS; tvOS is pre-broken, don't gate on it):
   ```bash
   xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
   xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator iOS" -sdk iphonesimulator -configuration Debug
   ```
2. Scoped test run (full local suite hangs at app-host launch — known; CI runs the full suite):
   ```bash
   xcodebuild test -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug -parallel-testing-enabled NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -only-testing:"ToyFlightSimulatorTests/CameraManagerCycleTests"
   ```
3. Manual (macOS app, default FlightboxWithPhysics scene; user-driven — automated keystrokes are blocked):
   - Press `C` → view cuts to the free camera behind the spawn point; WASD/arrows/right-drag fly it (note: the jet also still responds — documented quirk).
   - Press `C` again → wraps back to the chase view, which must **not** have drifted, re-aimed, or lost zoom while the free camera was active (proves the `isActiveCamera` guards).
   - Resize the window while in the chase view, press `C` → free camera renders with correct (non-squashed) projection immediately (aspect refresh in the selection funnel).
   - Swap aircraft while in the free-cam view → snaps to the new jet's chase view (accepted behavior); press `C` twice → chase → free → chase, confirming the chase camera kept slot 0 across the swap.
   - Cmd+R reset → cycle still works. In FreeCamFlightbox scene, `C` does nothing (single camera).
   - (Optional N>2 spot-check: uncomment `addCamera(debugCamera)` in `SandboxScene` — as `addCamera(debugCamera, false)` — and confirm `C` walks all registered cameras and wraps.)

## Scope / risks

- Seven small source edits + one new test file + doc updates. Same file set as the original two-camera draft; only `CameraManager.swift` grew (registry re-keyed from `[CameraType: Camera]` to ordered `[Camera]`).
- Registry re-key blast radius is minimal and fully enumerated: `RegisterCamera`/`SetCamera` have exactly one caller (`GameScene.addCamera`), nothing else reads `_cameras`, and `Camera.cameraType` survives (still constructed in `SceneManagerRegisterTests.swift:26`), so no existing test changes.
- The `isActiveCamera` guards are behavior-neutral in every existing scene (verified: no scene registers a non-current camera today). If a future scene wants a registered non-current camera that self-animates on input, the guards change that — no such scene exists; a self-animating-but-input-free camera (timer-driven orbit) is unaffected.
- `SetCamera` semantics change from by-type to by-instance/slot is strictly safer (a by-type miss used to nil `CurrentCamera`); `CameraManager.Update` order becomes deterministic (was dictionary-values order).
- Independent of the `renderer_switch_semaphore_wiring_fix` plan; land as its own commit.
