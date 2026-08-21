# Afterburner Plume Strobing / Collapse Into Cubic Bursts

**Date:** 2026-08-21
**Symptom:** the afterburner starts as a correct-looking, elongated stream of particles, but
after a few seconds it "strobes" and collapses into a sequence of short cubic-like bursts
instead of a continuous stream.
**Evidence:** `debugging/screenshots/InitialAfterburner.png` (correct) vs
`debugging/screenshots/AfterburnerAfterSomeTime_{1,2}.png` (collapsed), captured on the
fixed live-prefix build.
**Verified at:** `d2c14a9` (`Particles.metal`, `ParticleEmitter.swift`,
`ParticleEmitterObject.swift`, `Afterburner.swift`, `F22.swift`, `MacGameUIView.swift`).
**Companion:** `code_reviews/claude/particle_unborn_slots_2026-08-20.md` (the live-prefix
dispatch investigation; this bug is independent of that fix and predates it).

---

## TL;DR

The plume collapses because **`compute_particle` resets an expired particle's age to
exactly `0`, discarding the expiry overshoot**. Every particle stepping by the same global
`dt` and snapping to the same `0` means (a) ages can only ever take a handful of discrete
values — the plume is secretly a few bands, never a continuum — and (b) any two particles
that expire in the *same frame* acquire identical ages **forever** (equal lives, equal
steps → they never separate again). Once the pool saturates (~2.1 s at the default
120 fps) no fresh phases enter, so merging is monotonic: a CPU simulation of the exact
kernel math collapses all 10 000 particles onto **one single phase within ~10 s** — one
0.8 × 0.8 × ~0.7 m box of particles (the spawn volume) teleporting along the plume at
~20 Hz. That is the strobing cubic burst.

**Fix (three small, independent diffs, §5):**
1. **F1 — carry the phase remainder in the kernel** (`age = fmod(age, life)`, re-enter at
   the phase-correct offset). The keystone: merging becomes impossible.
2. **F2 — spread lives** (`lifeRange = -0.02...0.02`): recycle cycles decorrelate, so
   tick-cohorts disperse into a true continuum (the dormant `fire()` already does this,
   which is why it never showed the bug).
3. **F3 — randomize spawn phase in `emit()`** (age ~ U[0, life), position pre-integrated):
   the plume is continuous from the first frame instead of quantized to the tick grid.

Validated by simulation (§4, script alongside this doc): current code → 1 phase / 5%
plume coverage at t = 30 s; F1+F2+F3 → ~1150 phases / 100% coverage, indefinitely, at both
120 and 60 fps.

---

## 1. The cadence that sets the stage

- Default refresh rate is **120 fps** (`MacGameUIView.swift:16`, `.FPS_120`), and the
  update thread runs in lockstep with the render loop (one tick per frame).
- `Afterburner.afterburnerEmitter` is a **`static let` shared by both** F-22 afterburner
  instances. Each instance dispatches `compute_particle` every frame
  (`Node.computeParticles` walks the scene graph), so the shared simulation advances
  **2·dt ≈ 16.7 ms per frame**. Both dispatches bind the same `GameTime.DeltaTime`.
- Each instance also calls `emit()` every tick → 2 × 20 = **40 spawns/tick**, all with
  `age = 0`. The 10 000-slot pool saturates in 10 000 / (40 × 120) ≈ **2.1 s**, after
  which `emit()` early-returns and **no new ages ever enter the pool**.
- Afterburner descriptor: `speed = 100`, `life = 0.1`, **`lifeRange = 0...0`** — every
  particle has *exactly* the same life. Plume length = speed × life = 10 m; one recycle
  cycle is 0.1 s of sim time = **only ~6 frames** of 2·dt stepping.

## 2. Root cause — the age lattice and irreversible phase merging

### 2a. Ages live on a lattice: the plume was always bands, never a stream

Every born particle receives the same `age += dt` twice per frame, and expiry snaps age to
exactly `0`. So at frame *n*, a particle's age is precisely

```
age = S(n) − S(r)        where S = cumulative sim time, r = frame of its last reset/spawn
```

Distinct ages ↔ distinct recent reset frames *r*. With a ~6-frame cycle there can only be
**~6–12 distinct age values in the entire pool, ever**. Rendered distance = zSpeed × age,
so the plume is really ~6 bands spaced 2·dt·speed ≈ 1.67 m apart.

Why it *looks* continuous at first: each band is smeared ~0.5–1 m by the spawn box
(±0.4/±0.4/±0.1 m) and the unnormalized direction spread (z ∈ 0.95…1.05 → ±5% of
distance), and during the 2-s ramp fresh `age = 0` cohorts enter every tick, keeping ~12
phases alive (sim: 88% plume coverage). At 120 fps the bands nearly touch → "elongated
stream". (At 60 fps the spacing doubles to 3.3 m — banding would be visible even fresh.)

### 2b. `age = 0` merges phases irreversibly

Two cohorts that cross `age > life` in the **same frame** both reset to exactly `0`. From
then on they receive identical steps and have identical lives → **identical age forever**.
Merging is one-way; nothing ever splits a merged cohort apart.

Real frame times jitter (2·dt ≈ 16.7 ms ± noise, occasional hitches), so a cycle is
sometimes 6 steps and sometimes 7 — cohorts drift past each other and keep landing in
shared reset frames. After saturation (no fresh cohorts), the distinct-phase count can
only decrease: ~12 → 6 → 3 → **1**. (With hypothetical zero jitter it would instead freeze
as 6 static bands — still broken, just differently.)

### 2c. What the collapsed state looks like

One surviving phase = all 10 000 particles at the same age: a clump the shape of the spawn
volume (0.8 × 0.8 m cross-section, ~0.2 m + ±5%·distance ≈ 0.7 m deep — the "short
cubic-like burst"), drawn once per nozzle, jumping 1.67 m down the plume each frame and
wrapping every ~6 frames → a ~20 Hz strobe. `AfterburnerAfterSomeTime_2.png` shows exactly
this: one compact blob per nozzle instead of a stream.

### 2d. Why `fire()` never showed it

The fire descriptor has `lifeRange = -0.83...1.17` — a huge life spread. Unequal lives
mean merged pairs cross expiry in *different* frames next cycle and separate again;
phases keep re-decorrelating. The afterburner's `lifeRange = 0...0` is the outlier.

## 3. Simulation evidence

`afterburner_plume_strobing_collapse_sim.swift` (next to this doc) models the exact
emit/kernel math in 1-D: 10 000-slot pool, 2 × 20 spawns/tick, two dispatches per frame
with a shared jittered dt (σ = 0.4 ms, 0.3% 25 ms hitches), Float arithmetic, kernel
statement order. `swiftc -O … && ./…` to reproduce. Metrics over born particles:
**phases** = distinct ages (0.1 ms buckets), **cov** = % of 0.25 m bins occupied along
[0, 10] m, **clump** = % of particles in the densest bin.

| t (s) | A current kernel | B F1 only | C F1+F2 | D F1+F2+F3 | E F2 only | F F3 only |
|------:|-----------------|-----------|---------|------------|-----------|-----------|
|   1   | 11 · 82% · 12%  | 112 · 100% | 1079 · 100% | 1100 · 100% | 15 · 88% | 106 · 90% |
|   3   | 6 · 50% · 13%   | 222 · 100% | 1152 · 100% | 1147 · 100% | 15 · 95% | 5 · 42% |
|   5   | 3 · 28% · 40%   | 222 · 100% | 1151 · 100% | 1153 · 100% | 15 · 90% | 3 · 22% |
|  10   | **1 · 5% · 96%** | 221 · 100% | 1157 · 100% | 1156 · 100% | 15 · 88% | 2 · 18% |
|  30   | **1 · 10% · 43%** | 224 · 100% | 1158 · 100% | 1136 · 100% | 15 · 90% | 1 · 5% |

(cells: phases · coverage · [clump for A]; 60 fps runs G/H in the script tell the same
story: baseline collapses to 1 phase, F1+F2+F3 holds ~1150 phases / 100% coverage.)

Readings:
- **A** reproduces the report: fine through the ramp, collapsed within seconds of
  saturation, terminally a single strobing clump.
- **B (F1 alone)** already cures the collapse — remainder-carry conserves phase
  differences, and the ~250 ramp ticks fold mod 0.1 s into ~220 well-spread phases. But
  each tick-cohort (40 particles) stays fused at one phase → slight graininess
  (clump 4–5% vs ideal 2.5%).
- **C/D** reach ~1150 phases ≈ per-particle decorrelation — visually a continuum.
- **E (life spread but `age = 0`)** proves spread alone is insufficient: the lattice
  argument still caps it at ~15 phases → permanent banding.
- **F (spawn phase but `age = 0`)** proves spawn jitter alone is erased at each
  particle's *first* expiry (~0.1 s) — collapses like A.

So: **F1 is the keystone; F2 turns "no collapse" into "true continuum"; F3 covers
ignition and the ramp.**

## 4. Why this is invisible in the code

The reset looks like the obvious thing (`age = 0`, back to start) and every *individual*
particle behaves correctly under it. The defect is collective and only emergent: it needs
equal lives, a shared global step, saturation cutting off fresh phases, and a few hundred
frames of jitter-driven merging. It's the particle-system analog of the accumulator-timer
bug (`t = 0` instead of `t -= interval`) — except here the discarded remainder is each
particle's identity relative to its peers.

## 5. The fix

Three independent diffs against `d2c14a9`. Apply F1 at minimum; F1+F2+F3 recommended.

### F1 — kernel: carry the phase remainder (`Particles.metal`)

Replaces the integrate → scale → reset body of `compute_particle`. Also retires the
"scale-then-reset order is load-bearing" containment: the `life > 0` guards make the
never-emitted-slot defense explicit instead of order-dependent.

```diff
     // One coalesced device→thread load instead of ~14 per-field reads (P5).
     Particle p = particles[id];
     float3 pVelocity = p.speed * p.direction;
-    p.position += pVelocity * deltaTime;
     p.age += deltaTime;
 
-    // Scale-then-reset order is load-bearing, don't swap: the reset overwrites
-    // scale with startScale, so the expiry frame renders the respawn (never the
-    // extrapolated mix). The order also contains the inf/NaN math a zero-filled
-    // never-emitted slot would produce (life == 0 → age/life = +inf → NaN mix).
-    // The dispatch now covers only the born prefix [0, currentParticles) (see
-    // ParticleEmitterObject.computeUpdate), so that path is normally never
-    // taken — the ordering keeps it harmless if the dispatch width ever
-    // regresses to the whole pool. Resetting first would store NaN scales.
-    float age = p.age / p.life;
-    p.scale = mix(p.startScale, p.endScale, age);
-    
-    if (p.age > p.life) {
-        p.position = p.startPosition;
-        p.age = 0;
-        p.scale = p.startScale;
-    }
+    if (p.age > p.life && p.life > 0.0f) {
+        // Expiry: carry the phase remainder — NEVER reset age to exactly 0.
+        // age = 0 merges every particle that expires in the same frame onto one
+        // shared phase forever (identical steps + identical lives never
+        // re-separate), which collapses the whole pool into a few strobing
+        // clumps within seconds of pool saturation — see
+        // debugging/claude/afterburner_plume_strobing_collapse.md. fmod keeps
+        // each particle's fractional phase and also absorbs a multi-life hitch
+        // (deltaTime > life) in one step. Re-enter at the phase-correct offset,
+        // not at the nozzle.
+        p.age = fmod(p.age, p.life);
+        p.position = p.startPosition + pVelocity * p.age;
+    } else {
+        p.position += pVelocity * deltaTime;
+    }
+
+    // life == 0 (never-emitted slot) short-circuits to t = 0 instead of
+    // inf/NaN. Such slots aren't dispatched since d2c14a9; the guard keeps
+    // them harmless if the dispatch width ever regresses to the whole pool
+    // (this replaces the old order-dependent scale-then-reset containment).
+    float t = (p.life > 0.0f) ? (p.age / p.life) : 0.0f;
+    p.scale = mix(p.startScale, p.endScale, t);
```

Notes:
- Position stays exactly on the `position = startPosition + velocity·age` invariant —
  the wrap re-derives it, so integration drift also self-corrects once per cycle.
- The expiry frame now renders at the small remainder offset (≤ ~1.7 m from the nozzle,
  scale near `startScale`) instead of exactly at the nozzle — visually identical.
- The narrow `{position, age, scale}` store-back and its banner are unaffected.

### F2 — descriptor: spread lives (`ParticleEmitter.swift`, `afterburner(size:)`)

```diff
         descriptor.life = 0.1
-        descriptor.lifeRange = 0...0
+        // Spread lives ±20% so recycle cycles decorrelate: with identical lives
+        // every particle wraps in lockstep and any shared phase persists
+        // forever; unequal lives make phases precess past each other into a
+        // uniform continuum (fire() already relies on the same property).
+        descriptor.lifeRange = -0.02...0.02
```

Per-particle plume length becomes 8–12 m — a naturally ragged flame edge instead of a
hard cutoff (a bonus, not a cost).

### F3 — emit(): random initial phase (`ParticleEmitter.swift`)

Replaces the `age`/`life` assignments at the bottom of the spawn loop (direction and
speed are already written by this point):

```diff
-            particlePointer.pointee.age = 0
-            particlePointer.pointee.life = particleDescriptor.life + Float.random(in: particleDescriptor.lifeRange)
+            // Random initial phase: with age = 0 an entire tick's batch shares
+            // one age and marches as a single sheet, so the plume is born
+            // quantized to the tick grid. A uniform phase in [0, life) spreads
+            // spawns along the full plume; pre-integrate position so the drawn
+            // distance matches the phase from the first frame (the kernel
+            // preserves position == startPosition + velocity·age thereafter).
+            let life = particleDescriptor.life + Float.random(in: particleDescriptor.lifeRange)
+            let age = Float.random(in: 0..<max(life, .ulpOfOne))
+            particlePointer.pointee.age = age
+            particlePointer.pointee.life = life
+            particlePointer.pointee.position = particlePointer.pointee.startPosition +
+                particlePointer.pointee.direction * particlePointer.pointee.speed * age
```

Side effects: at ignition the full plume appears immediately (pre-placed along its
length) rather than growing over 0.1 s, and the multi-second pool ramp densifies
uniformly instead of nozzle-first. `emit()` is shared, so the dormant `fire()` gets the
same treatment — for a looping flame that is equally desirable.

## 6. Deliberately out of scope

- **Shared-emitter double-stepping (2·dt)** — documented at the `static let` in
  `Afterburner.swift`; plume length is invariant to it and the fix works with or without
  it. Per-instance emitters would be a separate design change.
- **`off()` → `reset()` → `on()` respawn race** — unchanged; the narrow store-back
  banner still covers it. (`F22.doUpdate` calls `off()` every tick below 0.8 throttle,
  so reset-while-in-flight remains a normal event.)
- **Particles ignoring pause** (§6.4 of the unborn-slots doc) — unchanged.
- **A tempting simplification for later:** with F1+F3 the kernel maintains
  `position ≡ startPosition + velocity·age` exactly, and `scale` is also a pure function
  of `age` — the vertex shader could derive both and the compute store-back could shrink
  to `{age}` alone (or the whole kernel could disappear into the vertex stage). That
  would eliminate most of the store-back race surface. Not part of this fix.

## 7. Verification plan

1. macOS Debug build; fly `FlightboxWithPhysics`, hold throttle > 0.8 for 30+ s.
2. Expect: continuous 8–12 m plumes at ignition, after 5 s, and after 30 s — no banding,
   no strobing, no collapse into blobs (compare `AfterburnerAfterSomeTime_{1,2}.png`).
3. Toggle the afterburner off/on repeatedly (throttle across 0.8) — plume should
   re-ignite full-length and stay continuous.
4. Optionally re-run `afterburner_plume_strobing_collapse_sim.swift` after any tuning
   change to `life`/`lifeRange`/pool size to confirm phase counts stay high.
