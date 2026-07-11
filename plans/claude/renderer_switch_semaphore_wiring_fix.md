# Fix: runtime renderer switch leaves the new renderer's update semaphores unwired

Status: **implemented** (2026-07-11). One deviation from the proposal: the regression test's identity asserts compare two factory-constructed renderers against each other instead of against `Engine.renderer` — the suite can run before the host app's `makeCoordinator` installs `Engine.renderer` (launch-timing race, caught on the first test run). Cross-instance identity proves the same invariant (all factory results share the one UpdateThread's channels) deterministically.

## Problem

Switching renderers at runtime via the in-app menu silently freezes the simulation. The image keeps rendering, but physics, camera, animation, and input stop — the update thread never runs again.

## Verified evidence

- `UpdateThread` owns the two handshake semaphores as `let` instance properties and is the **only** caller of `SceneManager.Update` (`ToyFlightSimulator Shared/Core/Threads/UpdateThread.swift:10-28`). Its `main()` loops: `updateSemaphore.wait` → `SceneManager.Update` → `updateDoneSemaphore.signal`. There is exactly one instance, `Engine.updateThread` (private static, `Engine.swift:34`).
- `Renderer` holds **optional** references, `nil` after init (`ToyFlightSimulator Shared/Display/Renderer.swift:25-26`):
  ```swift
  public var updateSemaphore: DispatchSemaphore?
  public var updateDoneSemaphore: DispatchSemaphore?
  ```
  `Renderer.render()` (`Renderer.swift:124-146`) uses optional chaining: `updateSemaphore?.signal()` then `updateDoneSemaphore?.wait(...)`. With `nil` semaphores both are **silent no-ops** — the render thread doesn't block, it just stops driving the update thread.
- The wiring happens in exactly one place, `Engine.Start` (`Engine.swift:43-45`):
  ```swift
  Engine.renderer = Engine.InitRenderer(type: rendererType)
  Engine.renderer!.updateSemaphore = Engine.updateThread.updateSemaphore
  Engine.renderer!.updateDoneSemaphore = Engine.updateThread.updateDoneSemaphore
  ```
- The runtime switch paths never re-wire. Both `MacMetalViewWrapper.updateNSView` (macOS, lines 48-66) and `IOSMetalViewWrapper.updateUIView` (iOS, lines 42-52) do:
  ```swift
  SceneManager.TeardownScene()
  let newRenderer = Engine.InitRenderer(type: rendererType)   // semaphores nil
  newRenderer.metalView = nsView                              // becomes MTKView delegate
  Engine.renderer = newRenderer
  SceneManager.SetScene(Preferences.StartingSceneType, rendererType: rendererType)
  SceneManager.Paused = true
  ```
  `Engine.InitRenderer` (`Engine.swift:55-71`) is a pure factory switch — it constructs and returns, touching no semaphores.
- Consequence after a live switch: the new renderer's `updateSemaphore?.signal()` no-ops, so the singleton `UpdateThread` stays parked on `wait(.distantFuture)` forever. The render thread keeps drawing (nil `wait` doesn't block) — a **frozen world**, not a hang.
- Git history: the handshake was introduced in `ae36f01` ("Fix camera-aircraft desync…"); the wrapper switch paths predate it and were never updated. Longstanding gap, not a recent regression.
- `RendererTests.testUpdateSemaphoreSignaling` (`ToyFlightSimulatorTests/RendererTests.swift:62-96`) already documents the reference-wiring contract.

## Fix

Wire the semaphores inside `Engine.InitRenderer` itself. It is the single factory used by `Engine.Start` and both wrapper switch paths, so every constructed renderer — initial or runtime-switched, both platforms — comes back connected, with **zero changes to the wrappers**. The now-redundant explicit wiring in `Engine.Start` is removed so there is one source of truth.

Why this is safe (verified):
- **No mid-frame switch.** `updateNSView`/`updateUIView` and the MTKView `draw(in:)` callback both run on the main thread, so a switch can't interleave with an in-flight handshake.
- **No count imbalance.** Within each `render()` call the signal/wait pair completes before returning, so between frames both semaphores sit at 0 with the update thread parked. The semaphores are `let`s on the singleton `UpdateThread`; pointing a new renderer at the same instances can't corrupt counts.
- **Ordering.** `updateThread` is a static `let`; its semaphores exist before `start()` is ever called, so wiring during `Engine.Start`'s `InitRenderer` call (before the thread has done anything) is fine.
- **No caller wants an unwired renderer.** Tests that need isolated semaphores construct `Renderer(type:)` directly (see `testUpdateSemaphoreSignaling`) — unaffected.
- **tvOS** doesn't reference `Engine.InitRenderer` (its `GameViewController` is already broken separately — stale `Renderer(metalKitView:)` call); no compile impact.

Alternative considered and rejected: a new `Engine.SetRenderer(type:metalView:)` that constructs + wires + installs. Centralizes "ownership" more visibly but requires editing three call sites (both wrappers + `Start`) for no additional safety, and would still leave `InitRenderer` public as a footgun unless also made private. The factory-wires approach is the minimal change that makes the bug unrepresentable through the existing API.

## Diffs

### 1. `ToyFlightSimulator Shared/Core/Engine.swift`

```diff
     public static func Start(rendererType: RendererType) {
         updateThread.start()
         audioThread.start()
         
         DrawManager.InitializeRingBuffers()
         
         Engine.renderer = Engine.InitRenderer(type: rendererType)
-        Engine.renderer!.updateSemaphore = Engine.updateThread.updateSemaphore
-        Engine.renderer!.updateDoneSemaphore = Engine.updateThread.updateDoneSemaphore
     }
```

```diff
+    /// Every renderer constructed here comes back wired to the shared
+    /// UpdateThread's semaphores. The runtime renderer-switch paths in the
+    /// platform view wrappers (updateNSView / updateUIView) install this
+    /// result directly as `Engine.renderer` — an unwired renderer silently
+    /// skips the render↔update handshake (`updateSemaphore?.signal()` /
+    /// `updateDoneSemaphore?.wait()` are nil no-ops) and freezes the
+    /// simulation after a live switch.
     public static func InitRenderer(type: RendererType) -> Renderer {
+        let renderer: Renderer
         switch type {
             case .OrderIndependentTransparency:
                 // Does not work if gameView.depthStencilPixelFormat = .depth32Float_stencil8
-                return OITRenderer()
+                renderer = OITRenderer()
             case .SinglePassDeferredLighting:
-                return SinglePassDeferredLightingRenderer()
+                renderer = SinglePassDeferredLightingRenderer()
             case .TiledDeferred:
-                return TiledDeferredRenderer()
+                renderer = TiledDeferredRenderer()
             case .TiledDeferredMSAA:
-                return TiledMultisampleRenderer()
+                renderer = TiledMultisampleRenderer()
             case .TiledMSAATessellated:
-                return TiledMSAATessellatedRenderer()
+                renderer = TiledMSAATessellatedRenderer()
             case .ForwardPlusTileShading:
-                return ForwardPlusTileShadingRenderer()
+                renderer = ForwardPlusTileShadingRenderer()
         }
+        renderer.updateSemaphore = updateThread.updateSemaphore
+        renderer.updateDoneSemaphore = updateThread.updateDoneSemaphore
+        return renderer
     }
```

`updateThread` stays `private`. No changes to `Renderer.swift`, `UpdateThread.swift`, `MacMetalViewWrapper.swift`, or `IOSMetalViewWrapper.swift`.

### 2. Regression test — `ToyFlightSimulatorTests/RendererTests.swift`

Append inside `final class RendererTests` (XCTest, matching the file's style):

```diff
         // Clearing detaches the channel entirely.
         renderer.updateSemaphore = nil
         XCTAssertNil(renderer.updateSemaphore)
     }
+
+    func testInitRendererReturnsWiredRenderer() {
+        // Regression: the runtime renderer-switch paths (MacMetalViewWrapper.
+        // updateNSView / IOSMetalViewWrapper.updateUIView) install
+        // Engine.InitRenderer's result directly as Engine.renderer. If the
+        // factory returned an unwired renderer, render() would silently skip
+        // the update handshake (nil-chained semaphores) and the simulation
+        // would freeze after a live renderer switch.
+        // .ForwardPlusTileShading: its init is a bare super.init(type:) —
+        // no offscreen allocations (TiledDeferred's init allocates a
+        // ~268 MB 4096²×4 shadow texture array).
+        let renderer = Engine.InitRenderer(type: .ForwardPlusTileShading)
+        XCTAssertNotNil(renderer.updateSemaphore)
+        XCTAssertNotNil(renderer.updateDoneSemaphore)
+
+        // Every factory result must share the ONE UpdateThread's channels —
+        // that's what keeps a runtime-switched renderer driving the same
+        // update loop as the renderer it replaced. Cross-instance identity
+        // proves it without depending on host-app launch timing
+        // (Engine.renderer may not be installed yet when this suite runs).
+        // The NotNil asserts above keep nil === nil from passing vacuously.
+        // Never signal these here: they are the live update thread's channels.
+        let second = Engine.InitRenderer(type: .OrderIndependentTransparency)
+        XCTAssertTrue(renderer.updateSemaphore === second.updateSemaphore)
+        XCTAssertTrue(renderer.updateDoneSemaphore === second.updateDoneSemaphore)
+    }
 }
```

(As proposed, the asserts compared against `Engine.renderer?.updateSemaphore`; that failed on the first run because the suite starts before the host app's SwiftUI wrapper has run `Engine.Start`'s install — see Status note.)

### 3. Doc updates — `AGENTS.md` (anchor by content; line numbers shift)

Runtime flow, step 2 (line 35):

```diff
-2. `Engine.Start` starts the long-lived `UpdateThread` and `AudioThread`, creates three ModelConstants ring buffers, creates the renderer, and connects `updateSemaphore`/`updateDoneSemaphore`.
+2. `Engine.Start` starts the long-lived `UpdateThread` and `AudioThread`, creates three ModelConstants ring buffers, and creates the renderer via `Engine.InitRenderer`, which wires `updateSemaphore`/`updateDoneSemaphore` into every renderer it constructs (initial and runtime-switched).
```

Input/UI section (line 150):

```diff
-- Both active wrappers contain a runtime renderer-switch path using teardown → new renderer → `SetScene`, but see the semaphore wiring hazard below before relying on it.
+- Both active wrappers contain a runtime renderer-switch path using teardown → new renderer → `SetScene`; the new renderer comes back from `Engine.InitRenderer` already wired to the update-thread semaphores.
```

High-Risk Areas bullet (line 189) — replace the hazard with the surviving invariant:

```diff
-- The wrapper renderer-switch path calls `Engine.InitRenderer` directly but does not reconnect the new renderer's `updateSemaphore`/`updateDoneSemaphore`; `Engine.Start` only wires the initial renderer. Treat live switching as incomplete until that ownership is centralized or the new renderer is wired safely.
+- Renderer construction must go through `Engine.InitRenderer` — it wires `updateSemaphore`/`updateDoneSemaphore` into every instance it returns. A hand-constructed `XxxRenderer()` installed as `Engine.renderer` bypasses wiring and freezes the simulation (direct `Renderer(type:)` construction is for tests only).
```

CLAUDE.md needs no edit for this fix (it documents the handshake, which is unchanged, and never documented the hazard).

## Verification

1. Builds:
   ```bash
   xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
   xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator iOS" -sdk iphonesimulator -configuration Debug
   ```
2. Scoped test run (full local suite hangs at app-host launch — known; CI runs the full suite):
   ```bash
   xcodebuild test -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug -parallel-testing-enabled NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -only-testing:"ToyFlightSimulatorTests/RendererTests"
   ```
3. Manual (macOS app; automated keystrokes are blocked by Accessibility, so user-driven):
   - Launch, confirm the jet responds to arrow keys.
   - Esc → menu → switch renderer (e.g. TiledMSAATessellated → TiledDeferred) → Esc to unpause.
   - **Expected post-fix:** jet still flies, physics objects still move, `Y` stats overlay shows scene updates ticking. (Pre-fix: image renders but the world is frozen.)
   - Switch back; also swap aircraft after a renderer switch to exercise the update-thread mailbox path.

## Scope / risks

- Two-file code change + one test + AGENTS.md. No behavior change for the initial-launch path (same wiring, moved).
- Independent of the `c_key_camera_toggle` plan; land as its own commit.
