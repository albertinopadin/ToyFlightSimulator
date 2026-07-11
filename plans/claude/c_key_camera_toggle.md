# Implement the 'C' key Debug/Attached camera toggle

Status: **proposed — awaiting review** (2026-07-10). No code changed yet.

## Problem

CLAUDE.md documents a 'C' key that toggles between the debug (free-fly) and attached (chase) cameras, but no such input path exists — and git pickaxe across all history (`toggleCamera`, `SetCamera`, `.c` keycode variants, `--all`) shows it **never** existed. The doc was aspirational.

Verified current state:
- `Keycodes.c = 0x08` is defined (`Keycodes.swift:26`) but referenced nowhere.
- `DiscreteCommand` (`InputManager.swift:10-23`) has no camera case; `keyboardMappingsDiscrete` (lines 108-117) maps p/l/space/n/m/j/f/g only.
- The only `CameraManager.SetCamera` caller is scene-build (`GameScene.addCamera`, `GameScene.swift:81-86`). `CameraManager` has no toggle method.
- **No scene registers both cameras**: `FlightboxWithPhysics` (default scene) registers only the persistent `AttachedCamera`; `FreeCamFlightboxScene` only a `DebugCamera`. A toggle would have nothing to switch to.
- **Input bleed (bidirectional), verified — must be fixed as part of this work.** `Mouse.GetDX/GetDY/GetDWheel` are consume-and-zero reads. If a `DebugCamera` were simply registered non-current, `CameraManager.Update` (which updates every **unparented** registered camera, `CameraManager.swift:29-36`) would run its `doUpdate` each tick, where it unconditionally consumes arrows/a/d, the `Pitch`/`Roll`/`MoveFwd`/`MoveSide` continuous commands, and mouse deltas (`DebugCamera.swift:18-61`) — stealing input from the flying player. Conversely `AttachedCamera` is **parented**, so scene-graph traversal updates it regardless of which camera is current, and its `doUpdate` (`AttachedCamera.swift:72-101`) would keep consuming right-drag/wheel/i-j-k-l while the debug camera is active, silently re-aiming the chase view.

## Fix overview

1. New `DiscreteCommand.ToggleCamera` mapped to `.c`.
2. `CameraManager.ToggleCamera()` built on a pure, Metal-free `toggledCameraType` rule (unit-testable — same pattern as `FlightboxWithPhysics.swappedEntities`, `SceneManager.subtreeNodes`, `AttachedCamera.scaleStrippedInverse`).
3. Poll it debounced in `GameScene.doUpdate()` — the **update thread**, so shadow-cascade fitting, view matrix, and `_sceneConstants.cameraPosition` all see the same camera within one tick (a main-thread toggle from the `MacGameUIView` timer could swap cameras between the cascade fit and the scene-constants read, and wouldn't exist on iOS). Same precedent as `Aircraft.handleGearToggle` and the existing ClickSelect/ResetScene handling in that method.
4. Register a non-current `DebugCamera` in `FlightboxWithPhysics` so the default scene has a toggle target.
5. Guard both cameras' `doUpdate` with a new `Camera.isActiveCamera` to kill the input bleed. Per-camera guard, not a `CameraManager.Update` filter — a filter can't reach the parented `AttachedCamera`. Behavior-neutral today: in every existing scene the registered camera *is* the current camera.

Known/accepted behavior (documented, not "fixed" here):
- While flying the debug camera, the **aircraft** still consumes stick/throttle input (`Aircraft` has no active-camera concept) — same class of behavior `FreeCamFlightboxScene` avoids via `shouldUpdateOnPlayerInput: false`.
- Swapping aircraft while in debug view snaps back to the chase view (`applyAircraftSwap` → `addCamera(attachedCamera)` → `SetCamera(.Attached)`; the `.Debug` registry slot is untouched). Reasonable — a swap implies "look at my new jet".
- `BallPhysicsScene`/`PhysicsStressTestScene` don't call `super.doUpdate()`, so the toggle is dead there — harmless, both are single-camera scenes where it would no-op anyway.
- Toggling to a camera runs its input from the **next** tick (`CameraManager.Update` ran earlier in the same tick) — deterministic 1-tick latency, imperceptible.
- Scene reset / renderer switch are clean: `teardownScene()` → `CameraManager.RemoveAllCameras()`, and the rebuilt scene re-registers fresh cameras.

## Diffs

### 1. `ToyFlightSimulator Shared/Managers/InputManager.swift`

```diff
     case ToggleFlaps
     case ToggleGear
+    case ToggleCamera
     
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
+        .ToggleCamera: .c
     ]
```

No controller/joystick mapping (the debounce helper's other device branches guard-let and no-op). `DiscreteCommand` is never `switch`ed over anywhere, so iOS/tvOS compile untouched; iOS never feeds hardware-key state, so the mapping is dormant there.

### 2. `ToyFlightSimulator Shared/Managers/CameraManager.swift`

```diff
     public static func SetCamera(_ cameraType: CameraType) {
         CurrentCamera = _cameras[cameraType]
     }
+
+    /// Pure toggle rule, unit-testable without touching the live registry
+    /// (tests run app-hosted; mutating the real registry would hijack the
+    /// running scene's camera). Flips .Attached ↔ .Debug when the other
+    /// type is registered; nil means stay put.
+    static func toggledCameraType(from current: CameraType?,
+                                  registered: Set<CameraType>) -> CameraType? {
+        guard let current else { return nil }
+        let other: CameraType = (current == .Attached) ? .Debug : .Attached
+        return registered.contains(other) ? other : nil
+    }
+
+    /// Flips between the registered Debug and Attached cameras ('C' key).
+    /// No-op in single-camera scenes. Call on the update thread only, like
+    /// every other gameplay CurrentCamera mutation.
+    public static func ToggleCamera() {
+        guard let nextType = toggledCameraType(from: CurrentCamera?.cameraType,
+                                               registered: Set(_cameras.keys)),
+              let nextCamera = _cameras[nextType] else { return }
+        // The inactive camera missed any window resizes (SetAspectRatio only
+        // updates the current camera) — bring its projection current:
+        nextCamera.setAspectRatio(Renderer.AspectRatio)
+        CurrentCamera = nextCamera
+    }
```

(`CameraType` is already `Hashable` — it keys `_cameras`.)

### 3. `ToyFlightSimulator Shared/GameObjects/Cameras/Camera.swift`

```diff
 class Camera: GameObject {
     // Cameras live in CameraManager, not in SceneManager's batched collections.
     override var objectType: GameObjectType { .none }
 
+    /// Whether this camera is the one the scene currently renders through.
+    /// Input-driven cameras guard doUpdate on this so an inactive registered
+    /// camera neither drifts with the shared flight-control axes nor
+    /// destructively consumes Mouse.GetDX/GetDY/GetDWheel (consume-and-zero
+    /// reads that would steal deltas from the active camera).
+    var isActiveCamera: Bool { CameraManager.CurrentCamera === self }
+
     var fieldOfView: Float!
```

### 4. `ToyFlightSimulator Shared/GameObjects/Cameras/DebugCamera.swift`

```diff
     override func doUpdate() {
+        // Registered but not rendering (e.g. chase view active): consume no input.
+        guard isActiveCamera else { return }
+
         if Keyboard.IsKeyPressed(.leftArrow) || Keyboard.IsKeyPressed(.a) {
```

### 5. `ToyFlightSimulator Shared/GameObjects/Cameras/AttachedCamera.swift`

```diff
     override func doUpdate() {
+        // Parented cameras update via scene-graph traversal even when not
+        // current — without this guard the chase camera would keep consuming
+        // right-drag/wheel/i-j-k-l input while the debug camera is active.
+        guard isActiveCamera else { return }
+
         if Mouse.IsMouseButtonPressed(button: .RIGHT) {
```

### 6. `ToyFlightSimulator Shared/Scenes/GameScene.swift` — poll in `doUpdate()`

Insert between the ClickSelect block and the ResetScene block:

```diff
             }
         }
 
+        InputManager.HasDiscreteCommandDebounced(command: .ToggleCamera) {
+            // Update-thread mutation: keeps cascade fitting, viewMatrix, and
+            // cameraPosition on the same camera for the whole tick.
+            CameraManager.ToggleCamera()
+        }
+
         InputManager.HasMultiInputCommand(command: .ResetScene) {
```

### 7. `ToyFlightSimulator Shared/Scenes/FlightboxWithPhysics.swift`

```diff
     var attachedCamera = AttachedCamera(fieldOfView: 75.0,
                                         near: 0.01,
                                         far: 1_000_000.0)
+    /// Free-fly camera for the 'C' toggle. Registered non-current in
+    /// buildScene; unparented, so CameraManager.Update drives it.
+    let debugCamera = DebugCamera()
     var sun = Sun(modelType: .Sphere)
```

In `buildScene()`, after `let jetPos = aircraftStartPosition`:

```diff
         let jetPos = aircraftStartPosition
 
+        // 'C' toggle target; the chase camera stays the default view. +Z is
+        // forward, so the -Z offset spawns it behind the jet looking at it.
+        debugCamera.setPosition(jetPos + float3(0, 5, -40))
+        addCamera(debugCamera, false)
+
         setupDefaultSky()
```

(The jet spawns at `[0, 100, 0]` — don't copy `FreeCamFlightboxScene`'s ground-level position. Tune the −40 during manual verification.)

### 8. New test — `ToyFlightSimulatorTests/Managers/CameraManagerToggleTests.swift`

The test target is a `PBXFileSystemSynchronizedRootGroup`, so a new file under `ToyFlightSimulatorTests/` joins the target automatically — no pbxproj edit.

```swift
//
//  CameraManagerToggleTests.swift
//  ToyFlightSimulatorTests
//
//  Created by Albertino Padin on 7/10/26.
//

import Testing
@testable import ToyFlightSimulator

/// Exercises the pure toggle rule (`CameraManager.toggledCameraType`) only.
/// These tests run app-hosted (like SceneManagerRegisterTests) while the
/// game's update thread owns the live CameraManager registry — mutating
/// `CurrentCamera`/`_cameras` here would hijack the running scene's camera,
/// so the stateful `ToggleCamera()` wrapper is covered by manual runtime
/// verification instead.
@Suite("CameraManager toggle rule", .tags(.scenes))
struct CameraManagerToggleTests {

    @Test("Attached flips to Debug when both are registered")
    func attachedFlipsToDebug() {
        #expect(CameraManager.toggledCameraType(from: .Attached,
                                                registered: [.Attached, .Debug]) == .Debug)
    }

    @Test("Debug flips back to Attached")
    func debugFlipsToAttached() {
        #expect(CameraManager.toggledCameraType(from: .Debug,
                                                registered: [.Attached, .Debug]) == .Attached)
    }

    @Test("Single registered camera is a no-op")
    func singleRegisteredCameraIsNoOp() {
        #expect(CameraManager.toggledCameraType(from: .Attached, registered: [.Attached]) == nil)
        #expect(CameraManager.toggledCameraType(from: .Debug, registered: [.Debug]) == nil)
    }

    @Test("No current camera is a no-op")
    func noCurrentCameraIsNoOp() {
        #expect(CameraManager.toggledCameraType(from: nil,
                                                registered: [.Attached, .Debug]) == nil)
    }
}
```

### 9. Doc updates (anchor by content, not line number)

`AGENTS.md` (line 153, macOS shortcuts bullet):

```diff
-- macOS shortcuts: `Y` stats overlay (including active renderer), `H` Metal HUD, `Esc` menu/pause, and `Cmd+R` deferred reset. Aircraft controls include `G` gear and `F` for the legacy F-18 flaps. `CameraManager` supports multiple camera types, but no current input path toggles them.
+- macOS shortcuts: `Y` stats overlay (including active renderer), `H` Metal HUD, `Esc` menu/pause, `C` Debug/Attached camera toggle, and `Cmd+R` deferred reset. Aircraft controls include `G` gear and `F` for the legacy F-18 flaps. The `C` toggle is `DiscreteCommand.ToggleCamera`, polled debounced on the update thread in `GameScene.doUpdate`; it no-ops in scenes registering a single camera. Inactive cameras skip their input `doUpdate` via `Camera.isActiveCamera` — `Mouse.GetD*` reads are consume-and-zero, so an unguarded inactive camera would steal deltas from the active one.
```

`CLAUDE.md` line 191 (Input section):

```diff
-... Commands: `DiscreteCommands` (fire, toggle gear/flaps), `ContinuousCommands` (pitch, roll, yaw, move). Debouncing for discrete commands.
+... Commands: `DiscreteCommands` (fire, toggle gear/flaps/camera), `ContinuousCommands` (pitch, roll, yaw, move). Debouncing for discrete commands.
```

`CLAUDE.md` line 194 (Camera System, final sentence):

```diff
-... Toggle with 'C' key.
+... Toggle with 'C' key (`DiscreteCommand.ToggleCamera`, debounced on the update thread in `GameScene.doUpdate`); scenes must register both cameras for it to act (FlightboxWithPhysics does), and inactive cameras skip input via `isActiveCamera`.
```

`CLAUDE.md` line 270 (Debugging) is accurate post-fix as written; optionally append "(no-op in single-camera scenes)".

## Verification

1. Builds (macOS Debug + iOS Simulator — the iOS build proves the shared enum/camera changes compile off-macOS; tvOS is pre-broken, don't gate on it):
   ```bash
   xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
   xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator iOS" -sdk iphonesimulator -configuration Debug
   ```
2. Scoped test run (full local suite hangs at app-host launch — known; CI runs the full suite):
   ```bash
   xcodebuild test -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug -parallel-testing-enabled NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -only-testing:"ToyFlightSimulatorTests/CameraManagerToggleTests"
   ```
3. Manual (macOS app, default FlightboxWithPhysics scene; user-driven — automated keystrokes are blocked):
   - Press `C` → view cuts to the free camera behind the spawn point; WASD/arrows/right-drag fly it (note: the jet also still responds — documented quirk).
   - Press `C` again → back to the chase view, which must **not** have drifted, re-aimed, or lost zoom while debug was active (proves the `isActiveCamera` guards).
   - Resize the window, press `C` twice → no squashed projection (aspect-ratio refresh on toggle).
   - Swap aircraft while in debug view → snaps to the new jet's chase view (accepted behavior).
   - Cmd+R reset → toggle still works. In FreeCamFlightbox scene, `C` does nothing (single camera).

## Scope / risks

- Seven small source edits + one new test file + doc updates. The `isActiveCamera` guards are behavior-neutral in every existing scene (verified: no scene registers a non-current camera today).
- If a future scene wants a registered non-current camera that self-animates on input, the guards change that — no such scene exists.
- Independent of the `renderer_switch_semaphore_wiring_fix` plan; land as its own commit.
