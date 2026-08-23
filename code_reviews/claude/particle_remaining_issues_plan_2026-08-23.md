# Particle System — Plan for the Three Remaining Issues

**Date:** 2026-08-23
**Follow-up to:** `code_reviews/claude/particle_unborn_slots_2026-08-20.md` (§4 "doubled again by
sharing", §6.2 cross-scene persistence, §6.4 pause) and
`debugging/claude/afterburner_plume_strobing_collapse.md` (§6 deliberately-out-of-scope items 1 and 3).
**Issues:** (A) shared-emitter double stepping, (B) particles ignoring pause, (C) cross-scene pool
persistence.
**Scope:** `Afterburner.swift`, `ParticleEmitter.swift`, `ParticleEmitterObject.swift`,
`ParticleRendering.swift`, `UpdateThread.swift`, `SceneManager.swift`, `Engine.swift`,
`GameTime.swift`, `FlightboxScene.swift`, `F22.swift`, `DrawManager.DrawParticles`,
`Node.computeParticles`, verified at `cbbebed`.
**Status:** Fully applied. Issue A applied 2026-08-23 (A1–A3 + the regression tests, `37beab2`),
which also closes Issue C; Issue B (B1+B2) applied later the same day. Field notes from applying
are marked **Applied** inline below.

---

## TL;DR

**A and C are the same bug wearing two hats, and get one structural fix.** Both trace to
`Afterburner.afterburnerEmitter` being a `static let` (`Afterburner.swift:15`): its lifetime is the
*process*, so (A) every live instance dispatches `compute_particle` over the one shared buffer —
the shared simulation advances n·dt per frame — and (C) `currentParticles` and the buffer survive
`TeardownScene`, so a rebuilt scene (or a mid-scene aircraft swap back to the F-22) starts with the
previous plume fully formed. Fix: **per-instance emitters** (diff A1), the pattern `Fire` already
uses — each nozzle owns its pool, integrates exactly 1·dt, and the pool dies with the object. Draw
and compute cost are *unchanged* (each nozzle already drew the full shared pool at its own
transform); the only costs are +1.12 MB for the second buffer and a birthRate retune (A2) to keep
the ramp speed.

**B's documented mechanism is wrong, but the defect is real — it just lives at resume, not during
the pause.** Verified against the code: `SceneManager.Paused = true` also pauses the MTKView
(`Engine.PauseView`, `Engine.swift:92-96`), which stops `draw(in:)`, which stops the
render→update handshake — in steady-state pause *nothing* dispatches compute, so the plume does
not literally keep burning (§6.4's "the render loop keeps dispatching compute" holds only for the
frame or two before the async `isPaused = true` lands). The real leak: `UpdateThread`'s
`updatePreviousTime` goes stale while both loops are parked, and `Paused` is already `false` again
when the first post-resume tick runs — so that tick computes **dt = the entire pause duration**,
`GameTime.UpdateTime` accepts it, and particles (plus physics and `TotalGameTime`) integrate the
whole pause in one step. The same mechanism makes the *first-ever* tick integrate machine uptime
(`updatePreviousTime` starts at 0; `DispatchTime` uptime is measured from boot). Fix: clamp the
tick dt at its source (B2), plus a cheap pause gate on the particle compute encode for the
straggler frames (B1).

Apply as two independent commits: **A1+A2+A3+tests**, then **B1+B2**.

---

## Issue A — shared-emitter double stepping

### What happens today

- `Afterburner.afterburnerEmitter` is a `static let` shared by all instances
  (`Afterburner.swift:11-15`); the F-22 mounts two (`F22.swift:13-14`).
- `Node.computeParticles` walks the scene graph and calls `computeUpdate` on every
  `ParticleEmitterEntity` (`Node.swift:211-222`), so each nozzle encodes its own
  `dispatchThreads` over the **same** buffer with the same `GameTime.DeltaTime`
  (`ParticleEmitterObject.swift:29-48`). The shared simulation advances 2·dt per frame: particles
  fly at an effective 200 m/s instead of the descriptor's physical 100 m/s, and the recycle cycle
  runs at 2× real time. (Plume *length* is invariant — speed·life cancels — which is why this was
  tolerable; the doc at the `static let` documents exactly this.)
- Both instances also call `emit()` every tick (`ParticleEmitterObject.update()`), feeding the one
  pool at 2 × 20 = 40 spawns/tick.
- `off()` resets the *shared* pool (`Afterburner.swift:25-28`) — today both nozzles toggle
  together so it's invisible, but any future independent user (engine-out damage, the FlightboxScene
  standalone) would kill every other afterburner's plume.
- Both nozzles render the **same** particle pattern, mirrored at two transforms
  (`DrawManager.DrawParticles` binds the shared buffer per instance, `DrawManager.swift:386-408`)
  — cloned plumes, correlated flicker.

### Fix A1 — per-instance emitters (`Afterburner.swift`)

The whole class, before → after:

```diff
 final class Afterburner: ParticleEmitterObject {
-    // Shared by ALL Afterburner instances (the F-22 mounts two): one pool and
-    // buffer, drawn once per instance at that instance's transform — but each
-    // instance also dispatches the compute update, so the shared simulation
-    // advances n·deltaTime per frame when n instances are live.
-    static let afterburnerEmitter = ParticleEmitter.afterburner(size: CGSize(width: 20, height: 20))
-                                                                
     init(name: String) {
-        super.init(name: name, emitter: Self.afterburnerEmitter)
+        // Per-instance emitter (same pattern as Fire): each nozzle owns its
+        // pool and buffer, so the simulation advances exactly 1·deltaTime per
+        // frame no matter how many afterburners are live, off() resets only
+        // this nozzle, and the pool dies with the object at scene teardown /
+        // aircraft swap instead of carrying a full plume into the next scene.
+        super.init(name: name, emitter: ParticleEmitter.afterburner(size: CGSize(width: 20, height: 20)))
     }
     
     func on() {
         self.shouldEmit = true
     }
     
     func off() {
         self.shouldEmit = false
         self.emitter.reset()
     }
 }
```

### Fix A2 — keep the ramp speed (`ParticleEmitter.swift`, `afterburner(descriptor:)`)

A per-instance pool has one feeder where the shared pool had two, so without a retune each
nozzle's plume would take ~4.2 s to reach full density instead of ~2.1 s (10 000 slots ÷
spawns/s at 120 fps). Restore the observed ramp by folding the lost feeder into `birthRate`:

```diff
     static func afterburner(descriptor: ParticleDescriptor) -> ParticleEmitter {
         return ParticleEmitter(descriptor,
                                texture: "fire",
                                // Pool size IS the steady-state plume density: recycling
                                // never kills particles, so a live emitter always fills
                                // its pool (birthRate only sets the ramp-up speed). 10k
                                // keeps blended-point overdraw manageable.
                                particleCount: 10_000,
-                               birthRate: 20,
+                               // 40 preserves the pre-per-instance ramp (~2.1 s to
+                               // saturation at 120 fps): the shared pool used to be
+                               // fed by BOTH F-22 nozzles at 20/tick each; a
+                               // per-instance pool has a single feeder.
+                               birthRate: 40,
                                birthDelay: 0,
                                blending: true)
     }
```

(10 000 % 40 == 0, and the `emit()` batch clamp added in `d2c14a9` covers non-multiples anyway.)

### Fix A3 — delete the dead FlightboxScene emitter (`FlightboxScene.swift:17`)

`FlightboxScene.afterburner` is constructed but never `addChild`'d — it never updates, emits,
computes, or draws. While the emitter was a shared static this property was free; with
per-instance emitters it would allocate a dead 10 000-slot pool (1.12 MB) every scene build:

```diff
     var pl2 = PointLightObject()
-    let afterburner = Afterburner(name: "Afterburner")
```

### Effects (verified against the draw/compute paths)

| | Before (shared) | After (per-instance) |
|---|---|---|
| Sim rate | 2·dt per frame (200 m/s effective) | 1·dt — the descriptor's physical 100 m/s |
| Recycle cycle | 0.05 s wall (2× real time) | 0.1 s wall (matches `life`) |
| Drawn points (2 nozzles) | 2 × 10 000 = 20 000 (each drew the full shared pool) | 2 × 10 000 = 20 000 — unchanged |
| Compute threads/frame | 2 dispatches × 10 000 over one buffer | 2 × 10 000 over two buffers — unchanged |
| Buffer memory | 1.12 MB | 2.24 MB for an F-22 (+1.12 MB) |
| Texture memory | one cached "fire" texture | unchanged (`TextureLoader` by-name cache) |
| Nozzle patterns | identical clones | independent random patterns (decorrelated flicker — a visual improvement) |
| `off()` | resets every afterburner's plume | resets only its own nozzle |

Non-effects, stated to save the next reader the worry:

- **The phase-collapse fix (F1/F2) is rate-independent** — the strobing sim was validated at both
  120 and 60 fps effective step rates; halving the step to 1·dt changes nothing about
  remainder-carry or the life spread.
- **The narrow `{position, age, scale}` store-back and its banner stay.** Each buffer still has
  `emit()` (update thread) racing up to 3 in-flight frames of its own dispatches, and the
  per-instance `off() → reset() → on()` low-index respawn window is unchanged
  (`F22.doUpdate` still calls `off()` every tick below 0.8 throttle).
- **`emitter.position` stays [0, 0, 0]** — nozzle placement rides the node transform via
  `modelConstants`; nothing writes `emitter.position` at runtime. (Per-instance emitters make any
  future per-nozzle use of it safe, where the shared emitter made it a cross-nozzle hazard.)
- Emitter construction timing is unchanged: instances are built during scene build (F22 property
  init), never mid-encode on the render thread, so no `SetScene`-style warm-up is needed.

**Applied (2026-08-23):** as proposed, with one cosmetic deviation — A1 builds the per-instance
emitter as a local in `init` rather than inline in the `super.init` call (equivalent; the
`static let` is gone). Field note on A2: a manual A/B at the throttle confirmed birthRate 20 vs
40 is barely distinguishable in-game — consistent with the density-saturation argument above
(the knob only sets time-to-full-density, and blended 20 px points saturate perceived density
well before 10 000 live particles), so it's a forgiving knob and 40 was kept purely for parity
with the pre-change ramp. Not worth deeper tuning; the knob that *does* change the look remains
`particleCount` (unborn-slots §6.5).

---

## Issue B — particles ignoring pause

### Corrected diagnosis (the §6.4 mechanism doesn't match the code)

Walking the actual pause plumbing at `cbbebed`:

1. ESC → `SceneManager.Paused = true` (`MacGameUIView.swift:60`; iOS mirrors it). The setter
   writes `_paused` **synchronously**, then `Engine.PauseView(true)` hops through
   `DispatchQueue.main.async` to set `metalView.isPaused = true` (`Engine.swift:92-96`).
2. `GameView` is a plain `MTKView` (no custom draw driver, `enableSetNeedsDisplay` default
   false), so `isPaused = true` genuinely stops `draw(in:)` → `Renderer.render` stops signaling
   `updateSemaphore` → the update thread parks in `UpdateThread.main`'s wait. **In steady-state
   pause, no compute is dispatched and nothing advances.** §6.4's "the render loop keeps
   dispatching compute, so the plume keeps burning during pause" is wrong for the steady state.
3. What *does* leak, in two places:
   - **Straggler frames.** Between the synchronous `_paused = true` and the async
     `isPaused = true` landing, a frame or two still render. Those frames' update ticks skip
     everything under the `!Paused` guard (`SceneManager.swift:228`) — so `GameTime.DeltaTime`
     stays frozen at its last pre-pause value, *not* zero — while the render thread still encodes
     the particle pass with that stale dt (`ParticleEmitterObject.computeUpdate` reads
     `GameTime.DeltaTime` at encode time). One or two frames of unpaused sim; minor, but it is
     the kernel of truth in §6.4.
   - **The resume spike — the real bug.** `updatePreviousTime` (`UpdateThread.swift`) keeps its
     pre-pause value while the thread is parked. On unpause, ESC flips `Paused = false` *before*
     the view resumes, so the first tick computes
     `dt = now − updatePreviousTime = the entire pause duration` and `GameTime.UpdateTime(dt)`
     **accepts it**. That frame's particle pass binds a dt of seconds-to-minutes: every particle
     ages the whole pause in one step (post-F1, `fmod` scrambles the ages mod life — the plume
     looks exactly as if it had kept burning through the pause), `TotalGameTime` jumps (visible
     as `pl2`'s orbit snapping in FlightboxScene), and physics integrates the whole pause as one
     Euler/Verlet step. The same arithmetic makes the **first-ever tick** integrate machine
     uptime, since `updatePreviousTime` starts at 0 and `DispatchTime.now().uptimeNanoseconds`
     counts from boot — a latent launch spike that the ground clamp in `F22.doUpdate` has been
     quietly absorbing.

So "particles ignore pause" is really "the frame clock ignores pause (and launch, and
breakpoints)"; particles are just its most visible consumer. Fix both ends:

### Fix B1 — pause-gate the particle compute encode (`ParticleRendering.swift`)

One guard at the single point all three particle-capable renderers share:

```diff
 extension ParticleRendering {
     func encodeParticleComputePass(into commandBuffer: MTLCommandBuffer) {
+        // Freeze the plume while paused. Steady-state pause parks both loops
+        // (Paused also pauses the MTKView, which stops draw and therefore the
+        // update handshake), but Engine.PauseView flips metalView.isPaused via
+        // DispatchQueue.main.async — the frame or two that still draws in that
+        // window would advance the simulation with the stale, non-zero
+        // GameTime.DeltaTime the paused update ticks no longer refresh.
+        // Skipping the whole encode (rather than binding dt = 0) also skips
+        // the encoder + scene-graph walk; DrawParticles still runs, so the
+        // frozen plume stays visible behind the menu.
+        guard !SceneManager.Paused else { return }
         encodeComputePass(into: commandBuffer, label: "Particle Compute Pass") { computeEncoder in
             let particleComputePipelineState = Graphics.ComputePipelineStates[.Particle]
```

Reading `SceneManager.Paused` from the render thread matches existing idiom — `shouldEmit` and
`currentParticles` already cross the same boundary, and `_paused` is a `nonisolated(unsafe)` Bool
written by the UI thread. A mid-frame flip costs at most one frozen/advanced frame either way.

### Fix B2 — clamp the tick delta at its source (`UpdateThread.swift`)

```diff
 final class UpdateThread: TFSThread {
     public let updateSemaphore = DispatchSemaphore(value: 0)
     /// Signaled after the update finishes writing ring buffer + scene constants,
     /// so the render thread knows it can safely read the freshly written data.
     public let updateDoneSemaphore = DispatchSemaphore(value: 0)
     private var updatePreviousTime: UInt64 = 0
+    /// Longest wall-clock gap a single tick may integrate. The thread parks
+    /// whenever rendering stops (menu pause via metalView.isPaused, window
+    /// occlusion, the debugger) and updatePreviousTime goes stale, so the
+    /// first tick after resume would otherwise integrate the entire gap —
+    /// the whole pause as one physics/particle step, and on the first-ever
+    /// tick the machine's uptime since boot (updatePreviousTime starts at 0
+    /// and DispatchTime uptime is measured from boot). 100 ms = 3 frames at
+    /// the slowest supported refresh rate (FPS_30): real hitches pass
+    /// through untouched, stalls are truncated to a normal-sized step.
+    private static let maxDeltaTime: Double = 0.1
 
     override func main() {
         while true {
             _ = updateSemaphore.wait(timeout: .distantFuture)
 
             let currentTime = DispatchTime.now().uptimeNanoseconds
-            let updateDeltaTime = Double(currentTime - updatePreviousTime) / 1e9
+            let updateDeltaTime = min(Double(currentTime - updatePreviousTime) / 1e9,
+                                      Self.maxDeltaTime)
             updatePreviousTime = currentTime
             SceneManager.Update(deltaTime: updateDeltaTime)
```

This is the fix that actually stops pause time from reaching the simulation: after resume, the
first tick advances at most 100 ms regardless of how long the menu was open. It also fixes the
launch spike and turns debugger stops / window drags / App Nap into non-events for physics.
`GameTime.TotalGameTime` becomes "time simulated" rather than "wall time including stalls" —
which is what its consumers (animation phases, `pl2`'s orbit) actually want.

### Alternatives considered

- **Make `GameTime.DeltaTime` return 0 while paused** — doesn't address the leak: during steady
  pause nothing reads it (both loops are parked), and on the resume tick `Paused` is already
  false. Also risks zero-dt divisions in future consumers.
- **Reset `updatePreviousTime` on unpause instead of clamping** — the writer would be the UI
  thread poking the update thread's private clock (racy), or a `wasPaused` flag on the update
  thread — which is unreliable because a paused tick between `Paused = true` and the view pause
  is not guaranteed to happen (async timing). The clamp needs no cross-thread choreography and
  additionally fixes the launch/debugger/hitch spikes.
- **B1 alone** — leaves the resume spike, which is the bigger half. **B2 alone** — leaves the
  straggler frames advancing a nominally-paused sim (and any future render-while-paused mode
  would silently regress). Both are two-line changes; take both.

**Applied (2026-08-23, later):** both diffs as proposed (guard placed before the encoder is
created; the clamp bounds only the delta while the clock still advances to now, so stalled time
is dropped rather than carried). Full suite green via the serial flow. The §Verification steps
for B (pause 30 s mid-burn → frozen plume behind the menu → resume with no aircraft lurch, no
`TotalGameTime` snap, plume advancing ≤ 100 ms) remain the in-game acceptance check.

---

## Issue C — cross-scene pool persistence

### How A1 closes it

The persistence mechanism was purely the `static let`: `TeardownScene`
(`SceneManager.swift:196-225`) clears `particleObjects` and `GameScene.teardownScene` removes all
children, dropping every `ParticleEmitterObject` — but the emitter and its buffer lived on in the
static, `currentParticles` intact, so the next scene's first frame drew a fully-formed plume at
the new aircraft's position. With per-instance emitters the ownership chain is
`scene → F22 → Afterburner → emitter → buffer`; teardown releases the scene graph, the emitters
deallocate with their objects, and a rebuilt scene ignites from `currentParticles == 0` with the
age-0 nozzle grow-out.

The same fix covers the *intra*-scene variant the original report didn't name: a
`FlightboxWithPhysics` aircraft swap away from the F-22 and back
(`applyAircraftSwap` → `SceneManager.RemoveObject` unregisters the subtree, afterburners
included) currently also resurrects the old shared pool mid-flight; per-instance emitters make
the swap build fresh, empty pools.

### Considered, not proposed: a teardown sweep

`TeardownScene` could defensively run `particleObjects.forEach { $0.emitter.reset() }` before
`removeAll()`. Rejected: with per-instance emitters it's dead code (the objects it would reset
are deallocating), and it would paper over — rather than surface — any future reintroduction of
a shared emitter. The regression tests below encode the ownership guarantee instead, which is the
structural style this codebase prefers (cf. the exhaustive `GameObjectType` switches).

**Applied (2026-08-23):** closed by A1 as described; the teardown sweep stays not-proposed.

---

## Tests

New file `ToyFlightSimulatorTests/GameObjects/AfterburnerEmitterTests.swift` (Swift Testing,
`.gameObjects` tag). These construct `Afterburner` → `GameObject` → `Assets.Models[.None]` and
`ParticleEmitter` → `Engine.Device.makeBuffer` + `TextureLoader`, so they are **app-hosted-only**
(no Metal-free double exists for the buffer); that's fine — they depend only on the self-contained
`Engine.Device` lazy static, not on `Engine.renderer`, so the app-hosted launch race doesn't bite.
Cross-instance identity, not live-engine state, is the assertion style.

```swift
//
//  AfterburnerEmitterTests.swift
//  ToyFlightSimulatorTests
//

import Testing
import Foundation
@testable import ToyFlightSimulator

/// Afterburner pools must be per-instance: a shared (static) emitter makes the
/// simulation integrate n·dt per frame with n instances live, lets one
/// nozzle's off() reset every other nozzle, and carries a full plume across
/// scene teardowns and aircraft swaps (the pool outlives its objects).
/// See code_reviews/claude/particle_remaining_issues_plan_2026-08-23.md.
@Suite("Afterburner per-instance emitter", .tags(.gameObjects))
struct AfterburnerEmitterTests {

    @Test("two instances own distinct emitters (no shared pool)")
    func emittersAreDistinct() {
        let left = Afterburner(name: "left")
        let right = Afterburner(name: "right")
        #expect(left.emitter !== right.emitter)
        #expect(left.emitter.particleBuffer !== right.emitter.particleBuffer)
    }

    @Test("a fresh instance starts with an empty pool even after another has emitted")
    func freshInstanceStartsEmpty() {
        // Models the teardown → rebuild (and aircraft-swap) path: the old
        // scene's afterburner has a populated pool; the new scene's must not
        // inherit it.
        let oldScene = Afterburner(name: "old scene afterburner")
        oldScene.emitter.emit()
        #expect(oldScene.emitter.currentParticles > 0)

        let newScene = Afterburner(name: "new scene afterburner")
        #expect(newScene.emitter.currentParticles == 0)
    }
}
```

Both tests fail against today's `static let` (the second sees the shared `currentParticles` > 0)
and pass under A1 — they encode issues A's precondition and C's guarantee directly. Run via the
serial app-hosted flow (`build-for-testing` + `test-without-building -parallel-testing-enabled NO`).

**Applied (2026-08-23):** both tests in place and green via the serial flow (full suite green,
0 failures). Applying surfaced a scheme/test-plan misconfiguration: running the suite from the
Xcode IDE launched THREE host-app instances, because `ToyFlightSimulator macOS.xctestplan`
(`"parallelizable" : true`) and the scheme's `TestableReference` (`parallelizable = "YES"`)
enabled process-level parallel distribution — Xcode clones the app-hosted runner per worker and
each clone launches the host app. That is the in-IDE equivalent of the parallel `xcodebuild test`
the CI flag `-parallel-testing-enabled NO` exists to prevent (MTKView/CAMetalLayer drawable
deadlocks in the app-hosted suite — see CLAUDE.md, Testing). Both settings now have
parallelization off, so IDE runs use a single host instance and match CI. Swift Testing's
in-process concurrency is a separate axis and is unaffected (tests within the one process still
run concurrently, as they do under the CI flag). Note the scheme file is gitignored
(`**/xcshareddata`), so the tracked `.xctestplan` is the setting of record — the scheme defers
to its referenced test plan, and the scheme-side edit is local belt-and-braces only.

B is not unit-tested: B1's observable is a skipped encoder (no seam short of a command-buffer
mock) and B2 lives inside the thread loop. If a seam is ever wanted, extract
`UpdateThread.clampedDelta(now:previous:)` as a pure static and test the clamp — not required for
this change.

---

## Verification plan (manual, macOS Debug)

1. **A:** In `FlightboxWithPhysics`, select the **Sketchfab F-22** via the aircraft picker — the
   default CGTrader F-22 mounts no afterburners. Hold throttle > 0.8: plume ignites from the
   nozzle, densifies over ~2 s, and animates at half the former churn rate (physical 100 m/s;
   length still ~8–12 m). The two nozzles' patterns are visibly independent, and 30+ s of burn
   shows no banding/strobing regression (the collapse fix is step-rate-independent, but confirm
   against `debugging/screenshots/AfterburnerAfterSomeTime_{1,2}.png` anyway).
2. **B:** Mid-burn, ESC to pause for ~30 s — plume frozen behind the menu. Unpause: the aircraft
   must not lurch, `pl2`-style time-driven motion must not snap, and the plume must resume from
   its frozen state (advancing ≤ 100 ms), not look like it burned through the pause.
3. **C:** Mid-burn, Cmd+R (deferred reset) — the rebuilt scene's afterburner must ignite from an
   empty pool (grow-out from the nozzle), never flash a full-length plume on frame one. Repeat
   via menu renderer switch (teardown + rebuild on the main thread) and via aircraft swap
   f22 → f35 → f22.
4. Toggle throttle across 0.8 repeatedly: per-nozzle reset/re-ignition unchanged (store-back race
   banner still applies).
5. Run the app-hosted test suite serially; `AfterburnerEmitterTests` green.

## After applying

- Update **Status** headers: `particle_unborn_slots_2026-08-20.md` (§6.2, §6.4 resolved — §6.4
  with the corrected resume-spike mechanism) and `afterburner_plume_strobing_collapse.md` (§6
  out-of-scope items 1 and 3 now fixed; item 2's race note unchanged).
- The `Afterburner.swift` shared-emitter comment is deleted by A1; no other comment references
  sharing (`Particles.metal`'s store-back banner is per-buffer and stays accurate).
- Optional: CLAUDE.md's Particles line still says "Afterburner (1200, forward)" — stale since the
  10k retune; worth correcting to "per-instance 10k pools" while touching the area.
