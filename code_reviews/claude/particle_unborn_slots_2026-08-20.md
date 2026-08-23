# Particle Investigation — Does `compute_particle` Operate on Uninitialized Memory?

**Date:** 2026-08-20
**Question:** `compute_particle` is dispatched over the whole particle buffer. Does it read
`Particle` slots that were never initialized, and is that a problem?
**Scope:** `ParticleEmitter.swift`, `ParticleEmitterObject.swift`, `Afterburner.swift`,
`Fire.swift`, `Particles.metal`, `DrawManager.DrawParticles`, `ParticleRendering`,
`Node.computeParticles`, `TFSCommon.h` (`struct Particle`), verified at `19b8913` (the C11
commit).
**Status (2026-08-21):** Fixed in `d2c14a9` — §5 live-prefix dispatch, the §6.1 batch
clamp, §6.3 per-lane direction spread, and the §6.5 density knob (pool 100 000 → 10 000)
are applied; the kernel comments now carry the born-particle rationale instead of the
unborn-slot one.
**Status (2026-08-23):** §4's shared-emitter double-stepping and §6.2's cross-scene pool
persistence fixed — emitters are per-instance now (no shared `static let`); see
`particle_remaining_issues_plan_2026-08-23.md`. §6.4 (pause) remains open there, with a
corrected diagnosis (the leak is the post-resume tick, not compute running during pause).
**Status (2026-08-23, later):** §6.4 fixed too — `encodeParticleComputePass` skips while
paused and `UpdateThread` clamps a tick's dt to 100 ms. Every finding in this doc is now
resolved.

---

## TL;DR

**Yes, every dispatch processes never-emitted slots — but no, it is not undefined-memory UB,
and nothing wrong is ever rendered.** The buffer is created with `makeBuffer(length:)`, which
Apple documents as zero-filling ("Creates a buffer the method clears with zero values" —
checked against the current MTLDevice docs, 2026-08-20). So unborn slots are not *undefined*
memory; they are zero-valued structs that are **not valid particles** (`life == 0`,
`speed == 0`, `direction == 0`). The kernel runs full particle math on them every frame —
including a division by zero (`age / life` → `+inf`) whose `mix()` result is NaN — and four
stacked defenses keep that invisible (§3). The real costs are wasted GPU work (§4) and
fragility: the NaN containment depends on statement order inside the kernel, which is exactly
the kind of thing an innocent refactor breaks (it is now commented in the kernel; the review's
C11 "reorder" suggestion would have done it).

**Recommended fix:** dispatch `emitter.currentParticles` threads instead of
`emitter.particleCount` (§5). One-line change; eliminates the unborn-slot processing entirely,
removes the reliance on zero-fill, cuts dispatch width from 100 000 to the live count, and as
a bonus closes most of the spawn-vs-in-flight-dispatch race window that P5's narrow store-back
guards against.

---

## 1. How particles are initialized and emitted (the lifecycle)

**Allocation** (`ParticleEmitter.init`): one `MTLBuffer` of
`Particle.stride(particleCount)` bytes via `Engine.Device.makeBuffer(length:)` — default
options, i.e. `.storageModeShared`, zero-filled per the documentation. `struct Particle`
(TFSCommon.h:235-248) has stride 112 B (three padded `vector_float3`s, one `vector_float4`,
seven floats), so the afterburner's 100 000-slot pool is ~11.2 MB.

**Birth** (`ParticleEmitter.emit()`, update thread, called from
`ParticleEmitterObject.update()` every tick while `shouldEmit`): writes `birthRate` (20)
consecutive slots starting at `currentParticles`, filling **every** field (position,
startPosition, size, direction, speed, scale, startScale, endScale, age = 0, life, color),
then bumps `currentParticles`. Slots are therefore initialized contiguously from index 0 —
`[0, currentParticles)` is exactly the set of ever-born slots.

**Death: there is none.** `compute_particle` resets an expired particle to `startPosition`
with `age = 0` — recycling in place. `currentParticles` never decreases while emitting, so
every live emitter ramps to `particleCount` and stays there (that is the steady state, which
is why the saturation log added in `19b8913` fires once, not per tick). Only
`Afterburner.off()` → `reset()` zeroes the count.

**Simulation** (`ParticleEmitterObject.computeUpdate`, render thread, per frame): binds the
buffer + `deltaTime` and dispatches — **`width: emitter.particleCount`**, i.e. all 100 000
slots, born or not. This is the mismatch under investigation.

**Draw** (`DrawManager.DrawParticles`): `instanceCount: emitter.currentParticles` — only born
slots are ever rendered.

## 2. What the kernel does to a zero-filled unborn slot each frame

With `p = {0}`: velocity is `0`, so position stays put; `p.age += dt` → `age = dt`; then

```
float age = p.age / p.life;               // dt / 0  = +inf
p.scale = mix(p.startScale, p.endScale, age);  // 0 + inf·(0−0) = NaN
if (p.age > p.life) {                     // dt > 0 → true
    p.position = p.startPosition;         // 0
    p.age = 0;
    p.scale = p.startScale;               // overwrites the NaN with 0
}
```

Store-back writes `{position: 0, age: 0, scale: 0}` — the slot ping-pongs `age` between `0`
and `dt` forever and the NaN exists only in a register. IEEE inf/NaN arithmetic is
well-defined in Metal's fast-math for this pattern in practice, but the *containment* is pure
statement order.

## 3. Why nothing wrong is visible — four stacked defenses

1. **Zero-fill at allocation** — the one Apple guarantees. Without it (e.g. if the buffer
   ever moves to an `MTLHeap`, whose sub-allocations are NOT zero-filled), unborn slots would
   hold true garbage: huge/NaN positions and colors integrated and stored every frame.
2. **Kernel statement order** — the reset overwrites the NaN `scale` before store-back
   (commented in the kernel as of `19b8913`; the review's C11 "reorder the reset before the
   scale computation" note would have removed this defense, which is why it was declined).
3. **Draw count** — `instanceCount: currentParticles`, so unborn slots are never rasterized
   regardless of their contents.
4. **Full rewrite at birth** — `emit()` writes every field, so whatever the kernel did to a
   slot before birth is erased the moment it matters.

## 4. The costs that remain

- **Wasted dispatch width.** Every frame, per `ParticleEmitterObject`, the GPU runs 100 000
  threads to update `currentParticles` live slots (0 → 100 000 over ~42 s of afterburner at
  60 fps with two emitters). Early in the ramp that is ~1000× more threads than particles,
  each doing a 112 B load + ~24 B of stores over 11.2 MB of buffer.
- **Doubled again by sharing.** `Afterburner.afterburnerEmitter` is a `static let` shared by
  ALL instances; the F-22 mounts two, and `Node.computeParticles` dispatches per instance —
  so the one shared buffer gets 200 000 thread-updates per frame, and the shared simulation
  integrates **2·dt per frame** (effective 200 m/s / 0.05 s life; plume length is invariant
  because speed·life cancels, but cycle rate and compute double). Pre-existing behavior
  (it was `age += 2` per frame before C11), now visible in physical units — commented at the
  `static let` as of `19b8913`.
- **Fragility**, per §3: two of the four defenses (order, zero-fill) are non-obvious and
  refactor-sensitive.

## 5. Recommended fix — dispatch only the live prefix

```swift
// ParticleEmitterObject.computeUpdate
-            let threadsPerGrid = MTLSize(width: emitter.particleCount, height: 1, depth: 1)
+            // Born slots are exactly [0, currentParticles): emit() fills contiguously from
+            // 0 and expiry recycles in place (count never shrinks while emitting).
+            let threadsPerGrid = MTLSize(width: emitter.currentParticles, height: 1, depth: 1)
```

`dispatchThreads` already handles non-threadgroup-multiple widths (nonuniform threadgroups).
Effects:

- Unborn slots are never touched by the GPU → defenses 1 and 2 in §3 stop being
  load-bearing (keep the kernel comment anyway; the math is still order-sensitive for
  *born* particles' expiry frame).
- Dispatch cost tracks the live count instead of the cap.
- **Race improvement:** the store-back race that P5's narrow `{position, age, scale}`
  write-set guards against — `emit()` writing fresh spawns while earlier frames' dispatches
  are still in flight — mostly disappears during the growing phase, because an in-flight
  grid was encoded with the *old* count and therefore never covers the slots `emit()` is
  writing. The exception is `off()` → `reset()` → `on()` within the ≤ 3 frames-in-flight
  window: spawns then reuse LOW indices that still-executing grids cover. So **keep the
  narrow store-back and its banner**; this change shrinks the window, it doesn't close it.
- `currentParticles` is read on the render thread while the update thread writes it, like
  `shouldEmit` already is — encode happens after the frame's update handshake, so the value
  is current; a stale-low read would merely skip a spawn's first compute frame.

Not applied as part of the investigation itself; since applied — see **Status** in the
header.

## 6. Adjacent findings (initialization/emission path, found while verifying)

1. **Latent CPU out-of-bounds write in `emit()`** — the only true memory-safety hazard
   found. The guard is `currentParticles >= particleCount`, but the loop then writes a full
   `birthRate` batch unconditionally. If `particleCount` were ever NOT a multiple of
   `birthRate`, the final batch would write past the buffer end via the raw
   `bindMemory` pointer — heap corruption, no bounds check anywhere. Today it is safe by
   coincidence: 100 000 % 20 == 0 and 1200 % 5 == 0 (sharing doesn't break it — each call
   uses the emitter's own `birthRate`). Cheap hardening:
   `let batch = min(birthRate, particleCount - currentParticles)`.
2. **Cross-scene pool persistence.** The `static let` emitter outlives scenes:
   `TeardownScene` drops the `ParticleEmitterObject`s but not the emitter, so
   `currentParticles` and the buffer contents survive into the next scene — a rebuilt
   afterburner starts with the previous scene's full plume mid-flight (drawn immediately at
   the new aircraft's position). `Afterburner.off()` resets, but nothing on the teardown
   path does. FlightboxScene's standalone `Afterburner` shares the same pool as the F-22's
   two. **Fixed 2026-08-23:** emitters are per-instance (the pool dies with its object;
   FlightboxScene's dead standalone deleted) — see
   `particle_remaining_issues_plan_2026-08-23.md`.
3. **`direction` spread is diagonal, not conical.**
   `particleDescriptor.direction + Float.random(in: directionRange)` adds ONE scalar to all
   three components (SIMD broadcast), so the spawn spread moves the direction along
   `(1,1,1)` only. Per-axis randoms (`float3.random`-style, one per component) are almost
   certainly the intent.
4. **Particles ignore pause.** `GameTime.UpdateTime` is gated on `!Paused`, so `DeltaTime`
   goes stale (not zero) while the menu is open — and the render loop keeps dispatching
   compute, so the plume keeps burning during pause. Pre-existing (pre-C11 `age += 1`
   ignored pause the same way); a fix belongs with pause plumbing (skip
   `encodeParticleComputePass` while paused, or bind 0), not with C11.
   **Fixed 2026-08-23, with a corrected diagnosis:** steady-state pause actually parks BOTH
   loops (Paused also pauses the MTKView, stopping draw and the update handshake), so the
   real leaks were (i) a stale-dt straggler frame or two while the async view-pause lands
   and (ii) the post-resume tick integrating the entire pause (and, on the first-ever tick,
   machine uptime) in one step. `encodeParticleComputePass` now skips while paused, and
   `UpdateThread` clamps a tick's dt to 100 ms — see
   `particle_remaining_issues_plan_2026-08-23.md`, Issue B.
5. **Saturated-pool draw cost.** At the new 100 000 cap, steady state is 100 000 blended
   20 px points along a 10 m plume — substantial overdraw on the MSAA renderers. If that
   density wasn't the goal, the knob that actually controls steady-state density is
   `particleCount` (the pool always fills; `birthRate` only sets the ramp speed).
