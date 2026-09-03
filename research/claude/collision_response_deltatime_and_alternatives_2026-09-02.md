# Collision response and `deltaTime`: why the impulse ignores the step, where the step still leaks in, and the alternatives

**Date:** 2026-09-02
**Scope:** `ToyFlightSimulator Shared/Physics/CollisionResponse/HeckerCollisionResponse.swift` (the A-response commit `d62cf8b`), its two call paths in `PhysicsWorld` / `EulerSolver` / `VerletSolver`, and the literature on collision response methods.
**Companion docs:** `research/claude/compound_rigid_bodies_research_combined.md` (§3.2 rest-hack replacement, A5 diff, Phase B fixed step), `plans/claude/compound_rigid_bodies_implementation_plan_simplified.md`.

---

## 0. Short answers

**Q1. `applyCollisionResponse` never touches `deltaTime`. Is that correct?**
Yes, for the impulse. The impulse `j = -(1 + e) · (v_rel · n) / (1/mA + 1/mB)` is a *change in momentum*, and by definition a change in momentum is already a force integrated over time (`J = ∫F dt`). The restitution law it enforces (`v⁺ · n = -e · v⁻ · n`, Newton's hypothesis) is a relation between velocities immediately before and after an event of zero duration, so no step size belongs in it. Every reference implementation surveyed below (Hecker 1997, Baraff 1997, Box2D v2 and v3, Bullet, Jolt, Fiedler, Gaul) computes the restitution impulse from velocities without `dt`; where a step does enter their contact solve it is only through an optional position-error bias (Box2D-Lite's Baumgarte term, Bullet's ERP), and every one of them multiplies *forces* by `dt` in the integrator instead. The rule is: forces × dt, impulses not. TFS follows it: `EulerSolver.applyForces` and `VerletSolver.step` scale `force / mass + g` by `deltaTime`; the response does not.

**Q2. Is it because the relative velocity on line 107 "encodes" a delta time?**
Not in the sense that velocity carries a hidden step. Velocity is a rate (m/s) and knows nothing about the step that produced it; the impulse is `dt`-free because the *law* is `dt`-free, not because the input smuggles a `dt` in. Dimensional analysis settles it: `j` has units kg·m/s, `j · invMass` has units m/s, and it is added straight to a velocity. If you rewrote the response as a force, `F = j / dt`, the Euler integrator would immediately compute `v += (F / m) · dt = j / m`; the `dt` cancels, which is exactly why the impulse form skips it.

There *is* a true statement hiding inside the intuition, and it matters for resting contact: for a body sitting on the ground, the approach velocity the impulse cancels is precisely the `g · dt` that this step's gravity integration added. So the support impulse comes out as `j = m · g · dt`, proportional to the step. That is not a bug or a coincidence; it is the definition of impulse applied to a steady normal force `N = m g`, whose impulse over one step is `N · dt`. The same formula therefore handles both regimes without special-casing: an impact (approach velocity set by the fall, independent of `dt` to first order) gets a `dt`-independent impulse; rest (approach velocity created by one step of gravity) gets a `dt`-proportional impulse. Section 2.4 works this through.

**Q3. So is the response completely step-independent?**
No. The impulse is, but four things around it depend on the step, and Phase B's fixed step is what makes them constant:

1. The restitution threshold (1 m/s) is compared against an approach velocity that, at rest, equals `g · dt`. At the `UpdateThread` clamp of 0.1 s that is 0.981 m/s, a 2 % margin. Above that a resting body would start to bounce (§3.1).
2. Position correction removes `β = 0.2` of the excess penetration *per step*, so the correction rate per second scales with frame rate (§3.2).
3. On the `HeckerVerlet` path (the one every scene uses) the resting penetration settles at `slop + ½ g dt² / β`: 6.7 mm at 120 Hz, 11.8 mm at 60 Hz (this is the 2026-08-31 golden, y ≈ 0.488 for a 0.5 m sphere), 25 cm at the 0.1 s clamp (§3.3).
4. Discrete detection lets a falling body penetrate by up to `v · dt` before the impulse is computed with a velocity that includes up to one extra step of gravity; with `e` near 1 the bounce apex creeps upward (§3.4).

Methods that make `dt` *explicit* in the response exist and are catalogued in §4: the Baumgarte velocity bias `(β / dt) · C` (Box2D-Lite, Bullet's ERP, Havok), speculative contacts `v_n ≥ -d / dt` (Firth, Box2D v3, Jolt), position-based dynamics `v = Δx / dt` with compliance `α / dt²` (Müller, Macklin), soft constraints whose coefficients are functions of `h` (Catto 2011, ODE ERP/CFM, Box2D v3 `b2MakeSoft`), and penalty springs whose stability bound is set by `dt`. None of them puts `dt` into the restitution impulse itself.

---

## 1. What the code does today

### 1.1 The two pipelines

`PhysicsWorld.update(deltaTime:)` (`World/PhysicsWorld.swift`) chooses one of two orders:

| Mode | Order per step | Where the response sits relative to gravity |
|---|---|---|
| `.NaiveEuler` (`EulerSolver.step`) | `applyForces` (v += (F/m + g)·dt) → narrow phase + `applyCollisionResponse` per pair → `moveObjects` (x += v·dt) → `zeroForces` | Impulse acts on a velocity that already contains this step's gravity kick; the corrected velocity is what moves the body. Same order as Box2D v2 (`b2Island::Solve`: integrate velocities → solve velocity constraints → integrate positions). |
| `.HeckerVerlet` (`heckerVerletUpdate`) | `HeckerCollisionResponse.resolveCollisions` → `VerletSolver.step` (x += v·dt + ½a·dt²; v += ½(a_old + a_new)·dt) → `zeroForces` | Impulse acts on the velocity left by the previous step (which contains a full `g·dt`); the position update then still adds `½ g dt²` of sink from the carried acceleration. |

Every shipped scene constructs `PhysicsWorld(updateType: .HeckerVerlet)` (`FlightboxWithPhysics.swift:26`, `FreeCamFlightboxScene.swift:18`, `BallPhysicsScene.swift:59`, `PhysicsStressTestScene.swift:121`); `.NaiveEuler` is the protocol default and the comparison path. The step they pass is the raw frame delta, `Float(GameTime.DeltaTime)`, which `UpdateThread` clamps to `maxDeltaTime = 0.1` s (`Core/Threads/UpdateThread.swift:27`).

### 1.2 The response, step by step

`applyCollisionResponse` (`HeckerCollisionResponse.swift:84-125`) consumes the deepest contact of the pair:

| Step | Code | Depends on `dt`? |
|---|---|---|
| 1. Position correction | `correction = β · max(0, depth − slop) / invMassSum`, applied to positions split by inverse mass (`β = 0.2`, `slop = 5 mm`) | Per-step fraction, no `dt` in the formula. This is the Box2D v2 position-solver form (`b2_baumgarte · (separation + b2_linearSlop)`, no `inv_dt`) and Randy Gaul's "positional correction", not the velocity-bias form. |
| 2. Approach guard | `approach = dot(vA − vB, n)`; return if `approach ≥ 0` | No. Identical to Hecker's collision criterion ("A collision occurs when a point on one body touches a point on another body with a negative relative normal velocity") and Gaul's `if(velAlongNormal > 0) return;`. |
| 3. Restitution gate | `e = -approach > 1.0 m/s ? min(eA, eB) : 0` | Indirectly: at rest `-approach = g·dt` (§3.1). |
| 4. Impulse | `j = -(1 + e) · approach / invMassSum`; `vA += n · j · invMassA`; `vB -= n · j · invMassB` | No. This is Hecker's Eq. 6 with `n` unit length, i.e. the point-mass reduction of his Eq. 9 (no `(r⊥·n)²/I` terms yet). |

The `deltaTime:` parameter on both `resolveCollisions` overloads is accepted and ignored; the doc comment records this as deliberate ("deltaTime-independent by design until Phase B's fixed step (β is per-step, matching the legacy correction's shape)").

---

## 2. The physics: why an impulse has no `dt` in it

### 2.1 Impulse is integrated force

Hecker, Part 3 ("Impulsive Behavior"): "An impulse can change velocities directly, without waiting — the way a force must — for integration to do it. You can think of an impulse as a really huge force integrated over a really short period of time. The force is so large and the amount of time so small that we're no longer dealing with an almost infinite force over an infinitesimal period of time, but with a perfectly finite impulse. And, as force changes the momentum over time (remember F = ṗ), our impulse changes the momentum instantaneously, which in turn changes our velocity."

He is explicit that a force cannot do the job: "A force won't stop the bodies from interpenetrating because a force can't instantaneously change a velocity. That is, a force takes time to change a velocity — it can only do so via integration over time [...] Yet our objects are already touching, so we don't have any extra time to allow the force to do its work."

Baraff's SIGGRAPH notes say the same with the limit spelled out: "An impulse is a vector quantity, just like a force, but it has the units of momentum. Applying an impulse produces an instantaneous change in the velocity of a body. To determine the effects of a given impulse J, we imagine a large force F that acts for a small time interval Δt. If we let F go to infinity and Δt go to zero in such a way that F Δt = J then we can derive the effect of J on a body's velocity." The Newcastle tutorial gives the one-line algebra: `J = FΔt = maΔt = m(Δv/Δt)Δt = mΔv`.

So the `Δt` of the *contact* is inside `j` already, and it is unrelated to the simulation step. Catto (GDC 2009) states the relation between the two worlds in one slide: "Given the time step, impulse and force are interchangeable. P = hF" — meaning a constraint impulse over a step of length `h` corresponds to a constraint force `P/h`. That conversion is where a step would appear if the code wanted forces; it doesn't.

### 2.2 The restitution law is kinematic

Hecker, Part 3, on the model: "The collision model we'll use is called 'Newton's Law of Restitution for Instantaneous Collisions with No Friction.' The easiest part of this model to understand is the 'instantaneous' part. The model assumes the collision process takes no time. Since 'no time' is a very small amount of time, all of our regular noncollision forces go away during the collision, and only the collision impulses are calculated. Thus, noncollision forces such as gravity are not taken into account during the collision, although they're in effect as usual before and after the collision."

Eq. 3 is `v_AB2 · n = -e · v_AB1 · n`; Baraff writes it as `v⁺_rel = -ε v⁻_rel` and calls it "the empirical law for frictionless collisions". Both sides are velocities. Solving Hecker's Eqs. 4a/4b (`v_A2 = v_A1 + j n / M_A`, `v_B2 = v_B1 − j n / M_B`) against Eq. 3 gives Eq. 6:

```
j = -(1 + e) · (v_AB1 · n) / ( n·n · (1/M_A + 1/M_B) )
```

and, with rotation, Eq. 9 adds `(r_AP⊥ · n)² / I_A + (r_BP⊥ · n)² / I_B` to the denominator (Part 4, Figure 4 gives the 3-D form with `I⁻¹`). No `h` anywhere. TFS's `invMassSum` denominator is Eq. 6 with `n` unit length; the combined research doc §3.1 already notes that the angular terms are what Phase D adds.

The Bender/Erleben/Trinkle STAR adds the caveat that matters once friction and off-centre impacts exist (Phase D): Newton's hypothesis is stated on velocities, Poisson's on the compression/restitution impulses, and "While simple and intuitive, this approach can unfortunately generate energy during oblique collisions. To prevent such unrealistic outcomes, Stronge developed an energy-based collision law that imposes a condition that prevents energy generation." For a frictionless point-mass response the three coincide, so today's `min(eA, eB)` Newton form is fine.

### 2.3 Units check on the TFS code

- `relativeVelocity` (line 107): m/s.
- `approach`: m/s.
- `invMassSum`: 1/kg.
- `j = -(1+e) · approach / invMassSum`: (m/s) · kg = kg·m/s = N·s. An impulse.
- `j · invMassA`: m/s, added to `entityA.velocity`. Consistent.

Multiplying `j` by `dt` would produce kg·m and make every bounce 60× too weak at 60 Hz; dividing by `dt` would turn it into a force that the integrator would then re-multiply by `dt`. Either "fix" would be wrong.

### 2.4 Resting contact: the one place the step is genuinely inside the velocity

Consider the `.NaiveEuler` order with a sphere at rest on the plane, `e = 0` because the approach speed is below the threshold:

1. `applyForces`: `v_n ← 0 − g·dt`.
2. Narrow phase: depth ≈ slop, so `correction ≈ 0`.
3. `approach = -g·dt < 0`, `e = 0`, `j = -(1 + 0)(−g·dt) · m = m·g·dt`; `v_n ← 0`.
4. `moveObjects`: `x += v·dt` with `v_n = 0`. The body does not sink.

The impulse this step is `m·g·dt`, and the sum of impulses over a second is `m·g`: exactly the normal force. This is what the combined research doc §3.2 meant by "the per-step support impulse (≈ m·g·dt) that resting requires; that impulse IS the normal force integrated over the step", and it is why the old `minDeltaVeloSquared` discard broke resting. Guendelman, Bridson and Fedkiw describe the same equilibrium for their contact stage: "gravity is integrated into the velocity, and then the contact resolution algorithm correctly stops the objects so that they remain still. Thus, nothing happens in the last (position update) step, and we repeat the process."

So "the velocity encodes `dt`" is true *here*, and only here: the velocity being cancelled was manufactured by integrating gravity over the step, so the impulse inherits the factor. That is a property of the state fed into the formula, not of the formula, and it is precisely the behaviour a step-scaled support force must have. Nothing in the response needs to know the step to get it right. The same mechanism is why the restitution threshold exists at all (§3.1): with `e > 0` this `g·dt` approach would be reflected every step, and the body would vibrate. Guendelman et al. name the phenomenon: "This is the same phenomenon that causes objects sitting on the ground to vibrate as they are incorrectly subjected to a number of elastic collisions. Thus, many authors use ad hoc threshold velocities in an attempt to prune these cases out of the collision modeling algorithm and instead treat them with a contact model."

### 2.5 What Hecker actually does about time, and what he leaves out

Hecker's own loop (Part 3, Listing 1) never lets an interpenetrating configuration reach the response. It integrates a full step, and "if there's interpenetration at the new configuration, we subdivide the time interval and try again. The algorithm amounts to doing a binary search of the time step looking for the time of collision." He lists the alternatives he did not take, one of which is what TFS does: "Other solutions to this problem include using the previous integration parameters to help estimate when the collision occured, trying to predict ahead of time where the collision will occur, or even trying to use the interpenetrating coordinates and hoping it doesn't look too bad. Also, this discrete collision routine doesn't catch 'tunneling'." He also admits the tolerance: "there's really no such thing as the exact collision time when you're working numerically on a computer. We're forced to use a tolerance value for collision detection, within which we agree to say we're colliding."

The bisection is where `DeltaTime` appears in Hecker's algorithm: it is a *search variable* for the contact time, not an ingredient of `j`. Baraff uses the same device ("If at time t₀ + Δt we detect inter-penetration, we inform the ODE solver that we wish to restart back at time t₀, and simulate forward to time t₀ + Δt/2 [...] The method of bisection is a little slow, but its easy to implement and quite robust"), and myPhysicsLab still does ("We then back up in time to just before the collision – so the objects are not overlapping – and apply an impulse to reverse the collision. [...] Collisions are resolved between time steps of the differential equation solver").

Hecker's articles also never solve rest. Part 3: "If it's equal to 0, the points are neither colliding nor separating — a situation called contact — and we'll have to deal with that problem in a future column." Part 4's postlude lists what the series never covered: "Contact. Our objects currently can't rest on the ground, which is pretty vital for a real game engine." and "Multiple simultaneous collision points. If you drop a box flat onto the ground, all four corners should hit at the same time." His site adds that "Both samples are relatively unstable because I'm using the simplest Euler integrator" and "The most obvious thing the samples are missing is inter-body collisions." The file header cites Gdmphys3 and the "Realistic Collision Response" video; the parts of TFS that go beyond Hecker (slop, β correction, restitution threshold, approach guard) are the engine-derived fixes catalogued in §4.5–4.6, which is where the step dependence lives.

---

## 3. Where the step leaks into today's behaviour

The numbers below use `g = 9.81 m/s²`, `β = 0.2`, `slop = 5 mm`, and TFS's `maxDeltaTime = 0.1 s` clamp.

| Frame rate | `dt` | `g·dt` (rest approach speed) | `½ g dt²` (Verlet sink/step) | Verlet-path steady depth `slop + ½g dt²/β` | β e-folding time (4.5 steps) |
|---|---|---|---|---|---|
| 120 Hz | 8.33 ms | 0.082 m/s | 0.34 mm | 6.7 mm | 37 ms |
| 60 Hz | 16.7 ms | 0.164 m/s | 1.36 mm | 11.8 mm | 75 ms |
| 30 Hz | 33.3 ms | 0.327 m/s | 5.45 mm | 32 mm | 149 ms |
| 0.1 s clamp | 100 ms | 0.981 m/s | 49 mm | 250 mm | 448 ms |

### 3.1 The restitution threshold is a `g·dt` comparison in disguise

At rest the approach speed is `g·dt`, so the threshold must exceed the largest `g·dt` the solver can see or resting bodies bounce. TFS's 1.0 m/s clears the 0.1 s clamp by 0.02 m/s. The engines that use a fixed 1 m/s (Box2D `b2_velocityThreshold`, Box2D v3 `restitutionThreshold = 1.0 · b2_lengthUnitsPerMeter`, Jolt `mMinVelocityForRestitution = 1.0`) all run fixed steps of 1/60 s or smaller, where `g·dt ≤ 0.16 m/s` and the margin is 6× or more. Bullet's default is 0.2 m/s (`m_restitutionVelocityThreshold`, "if the relative velocity is below this threshold, there is zero restitution"), which only works because Bullet's default step is 1/60 s. Unity/PhysX defaults to 2 m/s ("Bounce Threshold"). Allen Chou uses ~0.5 m/s. Müller et al. 2020 make the dependence explicit: "To avoid jittering we set e = 0 if |vn| is small. We use a threshold of |vn| ≤ 2|g|h, where g is gravity. This value corresponds to two times the velocity the prediction step adds due to gravitational acceleration."

The threshold also has a gameplay cost that is independent of `dt`: Box2D issue #601 asked for it to be runtime-configurable because "some games need to alter b2_velocityThreshold - notably pool/billiards type games, to get the right ball bounce direction at low velocities"; Box2D 2.4.1 answered with a per-fixture `restitutionThreshold`. Two engines avoid needing a large threshold by keeping gravity out of the bounce decision: Guendelman et al. process collisions *before* integrating gravity (§4.10), and Jolt subtracts the velocity that this step's forces added before deciding on and scaling the bounce (`normal_velocity_bias = mCombinedRestitution * (normal_velocity - force_delta_velocity)` in `ContactConstraintManager.cpp`).

### 3.2 β is per step, so correction speed is per frame

`correction = β · max(0, depth − slop)` removes a fixed fraction per step. The remaining excess after `n` steps is `(1 − β)ⁿ`, so the e-folding time is `≈ 4.5 · dt`: 37 ms at 120 Hz, 75 ms at 60 Hz. This is the same shape as Box2D v2's position solver (`C = b2Clamp(b2_baumgarte * (separation + b2_linearSlop), -b2_maxLinearCorrection, 0)`, applied to positions, no `inv_dt`) and Randy Gaul's `correction = max(penetration − slop, 0) / (A.inv_mass + B.inv_mass) · percent · n` with `percent = 0.2`, `slop = 0.01`; those engines run at a fixed rate, so "per step" and "per unit time" coincide. The velocity-bias alternative (§4.5) puts `1/dt` in explicitly: Catto 2014 writes the biased contact constraint as `C = v·n − (β/Δt)·s`, and Bullet's ERP path solves for `vA − vB = −penetration·erp/dt` (Coumans, in the "Bullet restitution question" thread, describes the solver as targeting `velocityBodyA-velocityBodyB = -PenetrationDepth/Dt`). Either way, once the step is fixed the distinction vanishes; until then, TFS's correction is `5×` faster in wall-clock at 120 Hz than at 30 Hz.

### 3.3 The Verlet path settles deeper, by `½ g dt² / β`

On `.HeckerVerlet` the response runs first, zeroes the normal velocity and applies the correction, and *then* `VerletSolver.step` moves the body by `½·a·dt²` with `a` = last step's gravity (the carried `entity.acceleration`). At equilibrium the correction balances the sink: `β · (d − slop) = ½ g dt²`, so `d = slop + ½ g dt² / β`. At 60 Hz that is `0.005 + 0.00136 / 0.2 = 0.0118 m`, which is exactly the `y ≈ 0.488` recorded for the 0.5 m sphere in `CollisionResponseTests.restingKeepsGravity` ("β-equilibrium ≈ slop + per-step-sink/β ≈ 1–2 cm at 60 Hz [...] y ≈ 0.488, |v| ≈ 0.1635 (exactly g·dt)"). The `|v| = g·dt` there is the §2.4 support impulse read the other way: the Verlet step re-adds `g·dt` after the response zeroed it. On the `.NaiveEuler` path the corrected velocity is what moves the body, so the steady depth is `slop` at any rate. The rendered position is stable in both modes (the sink and the correction happen inside one update), but the Verlet number scales with `dt²`: 25 cm at the 0.1 s clamp.

This is the classic velocity-Verlet-plus-impulse mismatch: the impulse edits `v` at the top of the step while the position update still trusts the carried `a(t)`. The Bullet forum thread on a Verlet floor reaches the same diagnosis ("gravity will cause a velocity into the ground. The particle will fall below the ground") and the same two fixes: either move the point to the surface rather than reflecting it, or "back up to the exact time of collision". Reordering the Verlet path to Box2D's order (half-kick → response → drift) or running the response between the velocity update and the position update would make the two paths agree; Phase B's fixed `h` makes the residual `½ g h² / β` a constant 1.7 mm at 120 Hz.

### 3.4 Discrete detection and restitution: energy creep with `e ≈ 1`

Because the narrow phase only sees end-of-step positions, a ball falling at speed `v` is detected up to `v·dt` deep and its impulse uses a velocity that may contain up to one extra `g·dt` beyond the true impact speed; with `e = 1` the next apex is slightly higher every bounce, and the β correction adds a little more. Catto (2005) names the two sources: "Overlap can occur for a couple reasons. First, using discrete collision detection means that contact is not recognized until the bodies suddenly overlap. Second, numerical integration of the equations of motion is usually not accurate enough to prevent the bodies from drifting into each other." Hecker and Baraff avoid it by backing up to the contact time (§2.5); Guendelman et al. avoid the gravity half of it by ordering (§4.10); Box2D v3 removes it for the restitution pass by storing the relative normal velocity *before* velocity integration (`b2_stagePrepareContacts` precedes `b2_stageIntegrateVelocities`) and applying restitution against that stored value (§4.8). TFS's `min(eA, eB)` with restitution 0.2 on the test ball keeps the creep negligible; the stress scenes with high `e` are where it would show.

### 3.5 The step itself is variable

`physicsWorld.update(deltaTime: Float(GameTime.DeltaTime))` consumes the frame delta, so all four effects above change with the refresh-rate picker (30–120 Hz) and with hitches up to the 0.1 s clamp. Fiedler's warning applies verbatim: "The behavior of your physics simulation depends on the delta time you pass in." Catto's 2005 paper made the same point about the solver family TFS is heading toward: "Our time stepping method supports variable time steps within the region of stability. However, precise repeatability requires a fixed time step." Box2D's manual says simply "you should use a fixed time step." The combined research doc already promotes the accumulator to a Phase B prerequisite (D4); this document adds the specific quantities it will freeze.

---

## 4. Alternative collision response algorithms

### 4.1 Overview

| Method | Level | Where `dt` appears | How rest is handled | Strengths | Weaknesses | Representative users |
|---|---|---|---|---|---|---|
| Instantaneous impulse + back-up to time of impact (Hecker 1997, Baraff 1997, myPhysicsLab) | velocity | bisection of the step to find `t_c`; never in `j` | Not by the impulse; Baraff adds an acceleration-level QP/LCP for contact forces, Hecker defers it | Exact restitution, no penetration, physically clean | Cost of backing up scales with collision count; one contact at a time; resting contact needs a separate solver; tunneling still possible | textbooks, myPhysicsLab, early Box2D TOI bullets |
| Impulse-only with microcollisions (Mirtich & Canny 1995) | velocity | conservative advancement to the collision time; threshold tied to the collision envelope | Trains of tiny impulses; a resting block "is actually experiencing many rapid tiny collisions with the table" | One code path for colliding, sliding, rolling, resting; simple, robust, parallel | Creep down ramps (needs the microcollision fix), enormous collision counts for dense contact, hard to stack | research simulators |
| Penalty / spring-damper (Moore & Wilhelms 1988; Fiedler; Newcastle) | acceleration | stability bound `k` vs `dt` (≥ 4 steps per oscillation period); force × dt in the integrator | Spring compresses under weight; rest = equilibrium compression | Trivial to implement; forces integrate like any other | Reactive not predictive (needs penetration to act); stiff k explodes explicit integrators; mass-dependent tuning; "notoriously hard to work with" (Bender et al.) | old game code, deformables, contact compliance layers |
| Acceleration-level LCP / QP (Baraff 1989/1994) | acceleration | none in the force solve; the ODE solver steps around it | Exact contact forces with `f ≥ 0`, `d̈ ≥ 0`, `f·d̈ = 0` | Exact resting contact, no drift | Needs a QP/LCP solver; Painlevé inconsistencies with friction; "only remained interactive for small sized configurations (below 100 interacting objects or so)" | Maya, early ODE |
| Velocity-level time stepping (Stewart–Trinkle 1996, Anitescu–Potra 1997) | velocity/impulse | the whole step is one impulse problem; `h` in the LCP's right-hand side | Rest is the impulse that zeroes the normal velocity each step | Handles simultaneous impact, no Painlevé, provable existence | Direct LCP solvers scale poorly; iterative versions converge slowly | robotics; ancestor of PGS engines |
| Sequential impulses / PGS with Baumgarte + slop + accumulated clamping + warm starting (Catto 2005/2006/2009) | velocity | bias `(β/h)·C` in the velocity constraint; force→impulse via `P = hF` | Same per-step support impulse as TFS; warm-started accumulated impulse converges over frames | Robust, cheap, stacks with iterations, friction cones fall out naturally | Baumgarte "can lead to energy creation and jitter"; convergence-limited for mass ratios and long chains; iteration count changes stiffness | Box2D-Lite/v2, Bullet, Jolt, Havok, PhysX |
| Position-correction variants: split impulse / pseudo-velocities / NGS / post-projection (Coumans 2008, Catto 2014, Cline & Pai 2003) | position (after velocity solve) | none in the correction (a per-step fraction, as in TFS) | as above | Does not add momentum/kinetic energy; "gives the best quality" (Gregorius) | A second solver pass; split impulse "sucks for joints" (forum consensus); must not be mixed with Baumgarte | Box2D v2 NGS, Bullet split impulse, Jolt position steps |
| Soft constraints (Catto 2011; ODE ERP/CFM) | velocity | `β`, `γ` (or `biasRate`, `massScale`, `impulseScale`) are functions of `h` and the spring's `ω`, `ζ` | Contact behaves as a critically-damped implicit spring | Stable at any stiffness; tunable in Hz and damping ratio instead of `k`; mass-independent | Adds springiness that needs a relax pass; parameters must be recomputed if `h` changes | Box2D v3, Jolt springs, ODE, Bullet CFM |
| Soft Step: sub-stepping + relax + restitution after relax (Catto Solver2D 2024, Box2D 3.0; Macklin et al. 2019) | velocity, substepped | `h = dt / substeps` everywhere above; restitution uses the pre-step relative velocity, no `h` | as PGS but converges far better per unit cost | "handles higher mass ratios, longer chains of bodies, larger stacks"; energy from softness removed by relax; bounce decided on the pre-gravity velocity | More body passes per frame; contact points must persist across substeps | Box2D 3.x |
| Speculative contacts (Firth 2011, Catto 2013) | velocity | explicitly: constraint `v_n ≥ −d / dt` (`remove = relNv + d/timeStep`; Box2D `bias = s · inv_h`; Jolt `max(0, −penetration/dt)`) | Contact activates one step early, so rest is reached without penetration | No tunneling for the common cases, cheap, stable | "Ghost collisions" on rotating/near-miss geometry; no restitution on the speculative contact unless handled separately | LittleBigPlanet, Box2D v3, Jolt |
| Collision-before-gravity ordering + shock propagation (Guendelman et al. 2003; Erleben 2007) | velocity | `Δt` in the predicted positions `x' = x + Δt(v + Δt g)` | Contact pass with `e = 0` immediately after the gravity update | "clean separation of collision from contact without the need for threshold velocities"; stacks via shock propagation | Two detection passes per step; bottom-up ordering is a heuristic | PhysBAM, film |
| Position-based: Verlet projection, PBD, XPBD, rigid-body XPBD (Jakobsen 2001; Müller 2007; Macklin 2016; Müller 2020) | position | explicitly: `v = (x − x_prev) / dt`, compliance `α̃ = α / dt²`, restitution threshold `2·g·h` | Projection out of the surface; velocity follows | "Unconditionally stable"; no drift; trivial rest; substeps beat iterations | Plain PBD stiffness depends on iterations and step (fixed by XPBD); restitution and friction need an extra velocity pass; derived velocities "simply reflect the penetration depth" after a collision unless corrected | cloth/soft bodies, Nvidia Flex/Warp, some rigid-body engines |

### 4.2 Instantaneous impulse with back-up to the time of impact

This is the method Hecker teaches and Baraff formalizes. Baraff: "Unless the ball's downward velocity is halted instantaneously, the ball will inter-penetrate the floor somewhat. In rigid body dynamics then, we consider collisions as occurring instantaneously. [...] Colliding contact requires an instantaneous change in velocity. Whenever a collision occurs, the state of a body [...] undergoes a discontinuity in the velocity. The numerical routines that solve ODE's do so under the assumption that the state Y(t) always varies smoothly." Hence: "If a collision occurs at time t_c, we tell the ODE solver to stop. We then take the state at this time [...] and compute how the velocities of bodies involved in the collision must change." Resting contact is a different problem: "Resting contact clearly doesn't require us to stop and restart the ODE solve at every instant; from the ODE solver's point of view, contact forces are just a part of the force returned by ComputeForceandTorque." Baraff classifies contacts by a velocity tolerance (`vrel < −THRESHOLD` colliding, `|vrel| ≤ THRESHOLD` resting, otherwise separating) and solves the resting forces as a QP: "For resting contact, we compute the f_i's subject to not one, but three conditions" (`f ≥ 0`, `d̈ ≥ 0`, `f·d̈ = 0`), warning that "Quadratic programming codes aren't terribly common though [...] and are much harder to implement."

Pros: restitution is exact, penetration never happens, the impulse is `dt`-free by construction. Cons: the back-up cost grows with the number of collisions (Jakobsen: "this is not very practical from a real-time point of view since the code could potentially run very slowly when there are a lot of collisions"), Hecker's version handles "a single collision between two bodies" and "a single collision point", and rest needs a separate solver. The lisyarus write-up reaches the same verdict experimentally: event-based collisions were "perfect, quite literally [...] The only problem is that it is slow as hell."

### 4.3 Impulse-only simulation with microcollisions

Mirtich and Canny push impulses all the way: "In contrast to constraint-based methods, impulse-based dynamics involves no explicit constraints on the configurations of the moving objects [...] all modes of continuous contact are handled via trains of impulses applied to the objects whether they be resting, sliding or rolling on one another. Under impulse-based simulation a block resting on a table is actually experiencing many rapid tiny collisions with the table." Rest is detected with a threshold "defined precisely" as the velocity a resting object acquires falling through the collision envelope, and a microcollision model is applied because otherwise "the block will tend to creep down ramp because of the time it spends in a ballistic phase." Guendelman et al. summarize the drawback set: the same equations blur collision and contact, and threshold velocities are needed to prune the elastic bounces. Bender et al.: "The impulse-based paradigms is simple to implement, however, stable stacking is often difficult to achieve." TFS's legacy response (before the A-response commit) was effectively an ad-hoc version of this, which is why it needed the rest latch.

### 4.4 Penalty (spring-damper) response

The response force is `F = −k·d − c·(n · v_rel)` applied through `F = ma` (Newcastle Tutorial 6; Fiedler's `F = n k d − b n (n·v)`). Because it is a force, `dt` enters the same way as gravity: `v += (F/m)·dt`. Fiedler: "springs are reactive not predictive [...] collision response using springs requires allowing some amount of penetration before it acts to correct it", and "there is a fundamental limit to how large you can make your spring k before your simulation will explode. At this point you need to either decrease your timestep or reduce your spring k." Catto's rule of thumb for semi-implicit Euler: "take at least 4 time steps per period of oscillation." Jakobsen: "it is hard to choose suitable spring constants such that, on one hand, objects don't penetrate too much and, on the other hand, the resulting system doesn't get unstable." Bender et al.: "The disadvantage of the method is that constraints can only be fulfilled approximately. An accurate solution is only possible for a very large value of α which leads to stiff differential equations. [...] Penalty-based paradigms are notoriously hard to work with, since it requires extensive parameter tweaking [...] making stable stacking nearly impossible to simulate." The one place TFS will legitimately use a spring-damper is the Phase B landing-gear suspension, which is a real spring with a real stiffness, sized against the fixed `h` (combined doc §4.3). Note that soft constraints (§4.7) are the way to get spring behaviour without the stability bound.

### 4.5 Sequential impulses (PGS) with Baumgarte stabilization

Catto's 2005/2006/2009 material is the direct ancestor of Box2D, Bullet, Jolt and Havok. The 2006 slides open with the diagnosis TFS hit: "Impulses are good at making things bounce. Many attempts to use impulses leads to bouncy simulations (aka jitter)." and the cure, "The 5 Step Program (for taking the jitter out of impulses): Accept penetration. Remember the past. Apply impulses early and often. Pursue the true impulse." The step order (2009): "Step 1: Integrate applied forces, yielding tentative velocities. Step 2: Apply impulses sequentially for all constraints, to correct the velocity errors. Step 3: Use the new velocities to update the positions." TFS's `.NaiveEuler` path is this order with one impulse per pair and no iteration.

Where `dt` appears: the position error is fed back as a velocity bias. Catto 2005: "A Baumgarte scheme is used to push the bodies apart when they overlap. The velocity constraint is augmented with a feedback term proportional to the penetration depth. J_n V = −β C_n [...] The solution is C_n(t) = C_n(0) e^{−βt}"; 2009: "Feed the position error back into the velocity constraint. New velocity constraint: Jv + (β/h)·C = 0"; 2014: "The velocity bias involves a tuning factor beta, the signed distance s, and the time step." The slop is the same idea as TFS's: "Bias Impulse: Give the normal impulse some extra oomph. Proportional to the penetration. Allow some slop. Be gentle." with a bias factor of 0.1–0.3. Havok's blog gives the general scaling: "Tau is proportional to dt², reflecting the relationship between position correction and acceleration [...] Damping is proportional to dt". ODE calls the same knob ERP ("what proportion of the joint error will be fixed during the next simulation step"; 0.2 default), and Bullet's ERP path makes Coumans's `−PenetrationDepth/Dt` target.

The known cost: energy. Catto 2014: "the velocity bias adds kinetic energy to the simulation and this is may cause instabilities"; Solver2D: "This is a cheap, yet crude way to deal with overlap. The main complaint is that it is not physically accurate and it can lead to energy creation and jitter if not tuned carefully."; Coumans: "Baumgarte sometimes adds unwanted energy/velocity due to deep penetration correction."; Gregorius: "If the penetration is deep this can go terrible wrong and your objects gain a lot of momentum and shoot off." Newcastle Tutorial 7: "Too much (enough velocity to correct the positional error in a single timestep), and the system will explode [...] Usually a factor of between 0.1-0.3 times the velocity needed to solve the positional error in a single time step works well." Tuning advice (Catto 2009): "If your simulation has instabilities, set the bias factor to zero and check the stability. Increase the bias factor slowly until the simulation becomes unstable. Use half of that value."

Two further pieces TFS does not have yet, both `dt`-free: accumulated-impulse clamping ("Clamping corrective impulses is wrong! You should clamp the total impulse applied over the time step.") and warm starting ("save the lambdas from the previous time step. Use the stored lambdas as the initial guess for the new step. Benefit: improved stacking."). Both become necessary the moment the solver iterates over several contacts (Phase D). Tonge et al. explain why iteration without them jitters: "By stopping early we introduce residual energy into the system, which can cause objects near rest to jitter."

### 4.6 Position-correction variants: split impulse, pseudo-velocities, NGS, post-projection

The energetic behaviour of Baumgarte led every engine to separate the *velocity* fix from the *position* fix. Catto 2014: "We can remove the stability problems by using pseudo velocities in the position correction. These pseudo velocities are not part of the state and don't persist across frames. [...] I still use the scaling factor beta because nonlinearities can cause the solver to overshoot. I typically use a beta value of 0.2. This method is also called NGS, non-linear Gauss Seidel." Box2D v2's `SolvePositionConstraints` is that pass, and it modifies positions directly with no `dt`. Bullet 2.69 added split impulse ("penetration recovery won't add momentum"); Coumans: "If you enable split impulse, it will only affect contact constraints with deep penetrations." (default threshold −0.04 m) and "Split impulse is not implemented for non-contact joints." Gregorius: "Pseudo velocities and split impulses are the same", "Post-projection gives the best quality, but is the most expensive", and "You should not mix Baumgarte Stabilization and Post-Projection. Just use one or the other!" (his 2015 contact talk phrases the two options as "target for a small separating velocity proportional to the penetration depth per tick (exponential decay) - This is called Baumgarte stabilization" versus "run a full solver sweep over the contacts again, but now solving the position error directly - This is called position projection"). Cline and Pai's post-stabilization is the formal version in a complementarity framework, claimed to "effectively eliminate the drift problem [...] and require no parameter tweaking". Erik Onarheim's summary of the practical advice: "Erin Catto suggests not feeding the position correction term into the actual velocities because it introduces more artificial kinetic energy into the system."

TFS's β correction is already on this side of the line: it edits positions, not velocities, so it adds no kinetic energy. What it lacks is the second sweep (it corrects one deepest contact per pair, once) and a max-correction clamp (`b2_maxLinearCorrection = 0.2 m`).

### 4.7 Soft constraints

Catto's 2011 talk replaces springs with constraints that are stable at any stiffness: "springs have two big problems. First, numerical instability can cause stiff springs can blow up and send your simulation to Neptune. Second, the spring stiffness k is difficult to tune." The soft constraint modifies the velocity constraint with two constants: "The constant beta serves to feed back the position error to the velocity [...] This sometimes called Baumgarte stabilization [...] With this adjustment, the system can now store energy, like a spring." and gamma "feeds the constraint force into the velocity constraint" to soften it; "the softness parameters can be related to the damping and spring constants", derived by matching implicit Euler. Because the derivation matches an implicit integrator over a step, the coefficients depend on `h`. Box2D v3 (`solver.h`, v3.0.0):

```c
static inline b2Softness b2MakeSoft( float hertz, float zeta, float h )
{
    if ( hertz == 0.0f ) return ( b2Softness ){ 0.0f, 1.0f, 0.0f };
    float omega = 2.0f * b2_pi * hertz;
    float a1 = 2.0f * zeta + h * omega;
    float a2 = h * omega * a1;
    float a3 = 1.0f / ( 1.0f + a2 );
    return ( b2Softness ){ omega / a1, a2 * a3, a3 };   // biasRate, massScale, impulseScale
}
```

with defaults `contactHertz = 30`, `contactDampingRatio = 10`, `jointHertz = 60`, `jointDampingRatio = 2`, `contactPushoutVelocity = 3 m/s`. ODE's manual gives the same equivalence for its two knobs: `ERP = h·k_p / (h·k_p + k_d)`, `CFM = 1 / (h·k_p + k_d)`, "the same effect as a spring-and-damper system simulated with implicit first order integration." So soft constraints are the principled `dt`-dependent response: the step appears, but as part of an implicit integration whose stability does not depend on it.

### 4.8 Soft Step: sub-stepping, relaxation, restitution after relax

Catto's Solver2D experiment (2024) compared PGS, PGS+NGS, PGS+soft, TGS variants and XPBD, and produced Box2D 3.0's default. Its two ingredients beyond §4.7: sub-stepping ("It has long been known that smaller time steps are more effective than more iterations. This is based on the Taylor Series. As the step size gets smaller, the approximation improves and non-linearities fade away.") and relaxation ("When we apply Baumgarte Stabilization or soft constraints we may be adding some undesirable springiness to the constraints. The idea is to relax that extra energy in the velocities and constraint impulses. [...] Solve constraints and apply Baumgarte Stabilzation or the soft constraint spring and damper. Then solve the constraints again, but don't apply any form of stabilization or softness."). Box2D 3.0's release post: "This solver is more stable in almost every way than version 2.4. It handles higher mass ratios, longer chains of bodies, larger stacks, and so on. It is based on soft constraints and sub-stepping." The manual recommends 4 sub-steps and a fixed step.

The v3.0.0 source shows exactly where the step sits. Stage order (`solver.h`): `b2_stagePrepareJoints, b2_stagePrepareContacts, b2_stageIntegrateVelocities, b2_stageWarmStart, b2_stageSolve, b2_stageIntegratePositions, b2_stageRelax, b2_stageRestitution, b2_stageStoreImpulses`. `b2PrepareContactsTask` stores `relativeVelocity = dot(normal, vrB − vrA)` *before* velocities are integrated, so the value carries no gravity from this step. In the solve, `inv_h` appears only in the speculative branch (`specBias = s · inv_h` for separation `s > 0`); the overlap branch uses `softBias = max(biasRate · s, minBiasVel)` with the soft coefficients from `b2MakeSoft`. `b2ApplyRestitutionTask` runs after relax, skips a point if `relativeVelocity + threshold > 0` or if `maxNormalImpulse == 0`, and otherwise applies `impulse = −mass · (vn + restitution · relativeVelocity)` with the accumulated clamp. That design answers both of this document's questions at once: the restitution impulse has no `h` in it, and the gravity kick never reaches the bounce decision. Macklin et al. 2019 give the theory for why sub-steps beat iterations: "the effect of external forces on positions is proportional to Δt² [...] halving the time step will result in a quarter of the position error", and their abstract: "performing a single large time step with n constraint solver iterations is less effective than computing n smaller time steps, each with a single constraint solver iteration." Müller et al. 2020 add the one drawback: "substepping [...] does not damp out high frequency vibrations due to reduced numerical damping."

### 4.9 Speculative contacts

Firth's LittleBigPlanet write-up: "compute the closest distance d between the two objects; the idea is that we want to remove exactly the right amount of velocity from A such that it will be exactly in touching contact with B on the next frame." The constraint is `remove = relNv + d/timeStep; if (remove < 0) apply impulse`, i.e. `v_n ≥ −d / dt`. This is the one response formulation where `dt` is *supposed* to be in the impulse, because the impulse is sized by a distance that must be covered in one step. Jolt's `ContactConstraintManager.cpp` has `speculative_contact_velocity_bias = max(0.0f, -penetration / inDeltaTime)`; Box2D v3 has `bias = s · inv_h`; Jolt's `mSpeculativeContactDistance` and Box2D's speculative margin decide how far ahead contacts are created. Advantages: no tunneling for slow-ish objects, contacts that "keep the solver involved" instead of flickering on and off, and rest without penetration. Disadvantages listed by Firth and Catto (GDC 2013): "ghost collisions" on rotating or grazing geometry, and no bounce on a speculative contact unless restitution is handled separately (Jolt falls back to the speculative bias when the approach speed is below `mMinVelocityForRestitution`; Box2D v3 runs its restitution stage separately). Catto's 2013 talk frames the underlying problem: "Physics engines usually operate in the same way. The engine executes discrete time steps, usually of a fixed size, that march the simulation forward in time. When we do this, the physics engine can miss events that happen in between frames." Box2D 2.x handled fast bodies with time-of-impact sub-stepping; 3.0 relies on speculative contacts for the general case and keeps a separate continuous pass only for bodies moving fast against statics and for flagged bullets.

### 4.10 Collision-before-gravity ordering and shock propagation

Guendelman, Bridson and Fedkiw reorder the step so the restitution pass never sees the gravity kick: "We propose the following time sequencing: Collision detection and modeling. Advance the velocities using equation 2. Contact resolution. Advance the positions using equation 1." Collisions are detected against predicted positions `x' = x + Δt(v + Δt g)` "and apply collision impulses to (and using) the current velocity v", contacts against `x' = x + Δt v'` with the gravity-updated velocity and `e = 0`. "All objects at rest have zero velocities (up to round-off error), so in the collision processing stage we do not get an elastic bounce [...] The key to the algorithm is that contact modeling occurs directly after the velocity is updated with gravity." The paper's stated benefit is exactly the threshold question of §3.1: "A novel aspect of our approach is the clean separation of collision from contact without the need for threshold velocities." Shock propagation then stabilizes stacks by processing contacts bottom-up with the lower body frozen (Erleben 2007 gives the velocity-level, fixed-step version). Cost: two prediction/detection passes per step and a heuristic ordering.

### 4.11 Position-based methods

Jakobsen's Verlet scheme handles collisions by projection: "Offending points are simply projected out of the obstacle [...] The beauty of the Verlet integration scheme is that the corresponding changes in velocity will be handled automatically." Here `dt` is structural: velocity is `(x − x_prev)/dt`, so moving a position *is* editing the velocity. Müller et al. 2007 generalize it (PBD): "The scheme is unconditionally stable. This is because the integration steps [...] do not extrapolate blindly into the future as traditional explicit schemes do but move the vertices to a physically valid configuration", with restitution and friction "handled by manipulating the velocities of colliding vertices" in a post-pass. Macklin et al. 2016 (XPBD) fixed the parameter problem: in PBD "the effective constraint stiffness is now dependent on both the time step and the number of constraint projections performed"; XPBD's compliance is folded with the step as `α̃ = α / Δt²`, giving "time step and iteration count independent" stiffness. Müller et al. 2020 bring it to rigid bodies with a velocity pass for restitution and dynamic friction, the `2|g|h` restitution threshold quoted in §3.1, and a warning that the derived velocities "are only meaningful if no collisions have occured during the last time step. Otherwise they simply reflect the penetration depth which is dependent on the time discretization of the trajectory" (their Eq. 34 replaces the derived normal velocity with `−e · v̄_n` from the pre-update velocity). Catto's Solver2D notes that XPBD is "much different than the other solvers" and did not beat the soft step on rigid-body tests, but the Ten Minute Physics summary is a fair statement of the trade: impulse-based gives "controlled velocity update, no overshooting" but "Drift: consistent velocities do not guarantee consistent positions"; position-based gives "controlled position change, unconditionally stable, no drift" at the price of a separate velocity pass for bounce and friction.

### 4.12 Restitution laws (for Phase D)

The Bender STAR's summary is the reference: Newton's hypothesis (`v⁺_n = −ε v⁻_n`, what TFS uses), Poisson's (`p^r_n = ε p^c_n` on the compression/restitution impulses), and Stronge's energetic coefficient; the first two "can unfortunately generate energy during oblique collisions" once friction and lever arms are involved. Anitescu and Potra's LCP uses Poisson's hypothesis for that reason. For today's frictionless point-mass response they coincide.

---

## 5. Engine parameter survey

| Engine | Restitution threshold | Slop | Correction | Correction touches velocity? | `dt` in bias | Velocity used for the bounce decision |
|---|---|---|---|---|---|---|
| TFS today | 1.0 m/s | 5 mm | β = 0.2 of excess depth per step, positions | No | No | post-gravity (Euler path: this step; Verlet path: previous step) |
| Box2D v2.4 (`b2_settings.h`) | `b2_velocityThreshold = 1.0` m/s (2.4.1: per-fixture) | `b2_linearSlop = 0.005` m | NGS: `b2_baumgarte = 0.2` per step, clamp `b2_maxLinearCorrection = 0.2` m; TOI 0.75 | No | No (position solver) | post-gravity (`InitializeVelocityConstraints` after velocity integration) |
| Box2D v3.0 (`types.c`, `solver.h`) | `restitutionThreshold = 1.0` m/s | `b2_linearSlop` + speculative margin | soft constraint `contactHertz 30`, `ζ 10`, `pushout 3 m/s`, then relax; 4 sub-steps | Yes, but relaxed away | Yes: `b2MakeSoft(hertz, ζ, h)`; speculative `s·inv_h` | pre-gravity (`relativeVelocity` stored in prepare) |
| Bullet (`btContactSolverInfo.h`) | `m_restitutionVelocityThreshold = 0.2` m/s | `m_linearSlop = 0` | `m_erp2 = 0.2` velocity bias; split impulse on, threshold −0.04 m | ERP yes; split no | Yes: `erp·penetration/dt` | post-gravity |
| Jolt (`PhysicsSettings.h`) | `mMinVelocityForRestitution = 1.0` m/s | `mPenetrationSlop = 0.02` m | `mBaumgarte = 0.2` in the position steps (10 velocity + 2 position steps); speculative distance 0.02 m | No | Speculative: `−penetration/dt` | post-gravity, but `force_delta_velocity` is subtracted before restitution |
| ODE | `bounce_vel` ("The minimum incoming velocity necessary for bounce") | — | `ERP = 0.2` default | Yes | Yes: ERP/CFM ↔ `h·k_p`, `k_d` | post-gravity |
| Unity / PhysX | Bounce Threshold 2 m/s | — | — | — | — | — |
| Müller et al. 2020 | `2·g·h` | — | XPBD compliance `α/h²`, position pass | position level | Yes | pre-update velocity |
| Randy Gaul ImpulseEngine | none (e = min) | 0.01 m | percent 0.2 of excess, positions | No | No | post-gravity |
| Allen Chou | ~0.5 m/s | ~0.5 mm | Baumgarte velocity bias | Yes | Yes | post-gravity |

---

## 6. Implications for TFS

1. **Do not add `dt` to the impulse.** Line 118 is correct as written, and so are the approach guard and the inverse-mass split. If a future reviewer proposes `j * deltaTime` or `j / deltaTime`, §2.3 is the counter-argument.

2. **Phase B's fixed step is what makes §3 constant.** With `h = 1/120 s`, the rest approach speed is 0.082 m/s (12× under the threshold), the Verlet-path steady depth is 6.7 mm, and the β correction's e-folding time is a fixed 37 ms. Until then the four effects vary with the refresh-rate picker and with hitches.

3. **Make the threshold's dependence explicit rather than implicit.** Two cheap options, either of which removes the 2 % margin at the 0.1 s clamp: (a) `restitutionVelocityThreshold = max(1.0, 2 · g · h)` per Müller et al.; (b) decide restitution on the pre-gravity normal velocity, the Box2D v3 / Jolt / Guendelman approach. On the Euler path that is `approach + g·dt`-style bookkeeping (store `dot(v, n)` before `applyForces`, or subtract `dot(a·dt, n)`); on the Verlet path the velocity handed to the response already includes the previous step's `g·dt`, so the same subtraction applies. Option (b) also fixes the §3.4 energy creep for bouncy stress-scene balls.

4. **Bring the Verlet path into the Box2D order** (velocity half-kick → response → drift → second half-kick), or accept and document `slop + ½ g h²/β` as the resting depth. The existing golden (y ≈ 0.488 at 60 Hz) is that formula; a 120 Hz run should land at y ≈ 0.4933 if the analysis is right, which is a good `dt`-sensitivity regression to pin before Phase B lands.

5. **Phase D solver choice.** The literature's current consensus for a game engine is velocity-level sequential impulses with accumulated-impulse clamping and warm starting, position error handled by a separate pass (NGS/pseudo-velocities) or by soft constraints plus relax, and restitution applied as its own pass from the pre-solve relative velocity. Keep the impulse `dt`-free there too; let `h` live only in `b2MakeSoft`-style coefficients and in any speculative bias. Bender et al.'s closing observation is the safe default: "For interactive simulators some common trends appear to be velocity-based constraint-based paradigms using fixed time-stepping methods."

6. **Test anchors already in the tree.** `CollisionResponseTests.restingKeepsGravity` (|v| = g·dt, y = slop + ½g dt²/β) and `separatingContactGetsNoImpulse` pin the two facts this document leans on. Adding the same rest test at `dt = 1/120` and asserting `y` moves only by the predicted 5 mm would make the §3.3 dependence visible in CI, and would fail loudly if anyone ever multiplies the impulse by `dt`.

---

## 7. References

All URLs below were visited during this research. Entries marked *(fetched, text extracted locally)* were downloaded and converted to text with a PDFKit script because the fetch tool cannot read PDF bodies; entries marked *(failed)* did not load and are listed for completeness only.

### Hecker (supplied by the project owner)
- https://chrishecker.com/images/e/e7/Gdmphys3.pdf — "Physics, Part 3: Collision Response", Game Developer, Feb/Mar 1997 *(fetched, text extracted locally)*
- https://chrishecker.com/images/b/bb/Gdmphys4.pdf — "Physics, Part 4: The Third Dimension", June 1997 *(fetched, text extracted locally)*
- https://chrishecker.com/images/d/df/Gdmphys1.pdf — "Physics, Part 1: The Next Frontier" (Euler integration) *(fetched, text extracted locally)*
- https://chrishecker.com/images/c/c2/Gdmphys2.pdf — "Physics, Part 2: Angular Effects" *(fetched, text extracted locally)*
- https://chrishecker.com/Rigid_Body_Dynamics — index page; notes on the Euler sample and missing inter-body collisions
- https://chrishecker.com/Physics_References — Hecker's reading list (Baraff, Moore & Wilhelms, Platt & Barr)
- https://www.gamedeveloper.com/programming/collision-response-bouncy-trouncy-fun — turned out to be Jeff Lander's 2000 column, not Hecker's; visited, not used

### Baraff, Mirtich, Guendelman, Erleben, surveys
- https://www.cs.cmu.edu/~baraff/sigcourse/notesd2.pdf — Baraff, "Rigid Body Simulation II — Nonpenetration Constraints", SIGGRAPH '97 course notes *(fetched, text extracted locally)*
- https://graphics.stanford.edu/courses/cs468-03-winter/Papers/ibsrb.pdf — Mirtich & Canny, "Impulse-based Simulation of Rigid Bodies", I3D 1995 *(fetched, text extracted locally)*
- https://people.eecs.berkeley.edu/~jfc/papers/95/ibsrb95.pdf — same paper, Berkeley mirror *(failed: connection refused)*
- https://graphics.stanford.edu/papers/rigid_bodies-sig03/rigid_bodies.pdf — Guendelman, Bridson, Fedkiw, "Nonconvex Rigid Bodies with Stacking", SIGGRAPH 2003 *(fetched, text extracted locally)*
- https://www.cs.ubc.ca/~rbridson/docs/rigid_bodies.pdf — same paper, UBC mirror *(fetched)*
- https://animation.rwth-aachen.de/media/papers/2012-EG-STAR_Rigid_Body_Dynamics.pdf — Bender, Erleben, Trinkle, "Interactive Simulation of Rigid Body Dynamics in Computer Graphics", CGF 2014 *(fetched, text extracted locally)*
- https://www.cs.cmu.edu/afs/cs/academic/class/15462-s13/www/lec_slides/Jakobsen.pdf — Jakobsen, "Advanced Character Physics", GDC 2001 *(fetched, text extracted locally)*
- http://www.richardtonge.com/papers/Tonge-2012-MassSplittingForJitterFreeParallelRigidBodySimulation-preprint.pdf — Tonge et al., SIGGRAPH 2012 *(fetched, text extracted locally)*

### Catto / Box2D
- https://box2d.org/files/ErinCatto_IterativeDynamics_GDC2005.pdf — "Iterative Dynamics with Temporal Coherence" *(fetched, text extracted locally)*
- https://box2d.org/files/ErinCatto_SequentialImpulses_GDC2006.pdf — "Fast and Simple Physics using Sequential Impulses" *(fetched, text extracted locally)*
- https://box2d.org/files/ErinCatto_ModelingAndSolvingConstraints_GDC2009.pdf *(fetched, text extracted locally)*
- https://box2d.org/files/ErinCatto_SoftConstraints_GDC2011.pdf — "Soft Constraints: Reinventing the Spring" *(fetched, text extracted locally)*
- https://box2d.org/files/ErinCatto_ContinuousCollision_GDC2013.pdf *(fetched, text extracted locally)*
- https://box2d.org/files/ErinCatto_UnderstandingConstraints_GDC2014.pdf *(fetched, text extracted locally)*
- https://box2d.org/files/ErinCatto_NumericalMethods_GDC2015.pdf *(fetched, text extracted locally)*
- https://box2d.org/posts/2024/02/solver2d/ — "Solver2D" blog post
- https://box2d.org/posts/2024/08/releasing-box2d-3.0/ — Box2D 3.0 release post
- https://box2d.org/documentation/md_simulation.html — Box2D v3 simulation manual
- https://github.com/erincatto/box2d/blob/main/docs/simulation.md — same manual, source
- https://github.com/erincatto/box2d/blob/4c1d67187801e64f38d25478e71fc4fa0e065999/include/box2d/b2_settings.h — Box2D v2.4 settings (`b2_velocityThreshold`, `b2_linearSlop`, `b2_baumgarte`, `b2_maxLinearCorrection`)
- https://www.iforce2d.net/src/conveyors/b2ContactSolver.cpp — Box2D v2 contact solver (restitution bias, position solver)
- https://raw.githubusercontent.com/erincatto/box2d/v3.0.0/src/contact_solver.c — v3.0.0 prepare / solve / restitution stages
- https://raw.githubusercontent.com/erincatto/box2d/v3.0.0/src/solver.h — v3.0.0 stage enum and `b2MakeSoft`
- https://raw.githubusercontent.com/erincatto/box2d/v3.0.0/src/types.c — v3.0.0 `b2DefaultWorldDef`
- https://raw.githubusercontent.com/erincatto/box2d/v3.0.0/src/solver.c — v3.0.0 substep loop
- https://raw.githubusercontent.com/erincatto/box2d/main/src/contact_solver.c — current main (restitution folded into the wide solve)
- https://raw.githubusercontent.com/erincatto/box2d/main/src/solver.c — current main
- https://github.com/erincatto/box2d/issues/601 — runtime-configurable `b2_velocityThreshold` (billiards)
- https://github.com/erincatto/solver2d — Solver2D repository
- https://raw.githubusercontent.com/erincatto/solver2d/main/README.md — Solver2D README (points to the blog post)

### Bullet
- https://github.com/bulletphysics/bullet3/blob/master/src/BulletDynamics/ConstraintSolver/btContactSolverInfo.h — solver defaults
- https://pybullet.org/Bullet/phpBB3/viewtopic.php?t=5477 — "Bullet restitution question" (Coumans, Gregorius)
- https://pybullet.org/Bullet/phpBB3/viewtopic.php?t=3795 — "Should I use split impulse?"
- https://pybullet.org/Bullet/phpBB3/viewtopic.php?t=9082 — "Contact penetration resolution" (Baumgarte vs split vs post-projection)
- https://pybullet.org/Bullet/phpBB3/viewtopic.php?t=1644 — "Position Correction" *(failed: timeout)*
- https://pybullet.org/Bullet/phpBB3/viewtopic.php?t=13282 — "J impulse is wrong in all Physics Engines"
- https://pybullet.org/Bullet/phpBB3/viewtopic.php?t=4686 — "Difficulties with very basic floor with velocity verlet"

### Jolt, Havok, ODE, Unity
- https://github.com/jrouwe/JoltPhysics/blob/master/Jolt/Physics/PhysicsSettings.h — defaults
- https://raw.githubusercontent.com/jrouwe/JoltPhysics/master/Jolt/Physics/Constraints/ContactConstraintManager.cpp — restitution and speculative bias code
- https://jrouwe.github.io/JoltPhysics/ — architecture overview
- https://raw.githubusercontent.com/jrouwe/JoltPhysics/master/Docs/Architecture.md — architecture source
- https://www.havok.com/blog/how-havoks-constraint-solver-works-pgs-baumgarte/ — tau ∝ dt², damping ∝ dt
- https://ode.org/ode-latest-userguide.html — ERP/CFM, `bounce_vel`
- https://docs.unity3d.com/6000.3/Documentation/Manual/collider-surface-bounce.html — Bounce Threshold

### Position-based dynamics and sub-stepping
- https://matthias-research.github.io/pages/publications/posBasedDyn.pdf — Müller et al., "Position Based Dynamics", 2007 *(fetched, text extracted locally)*
- https://matthias-research.github.io/pages/publications/XPBD.pdf — Macklin, Müller, Chentanez, "XPBD", 2016 *(fetched, text extracted locally)*
- https://mmacklin.com/smallsteps.pdf — Macklin et al., "Small Steps in Physics Simulation", SCA 2019 *(fetched, text extracted locally)*
- https://matthias-research.github.io/pages/publications/PBDBodies.pdf — Müller et al., "Detailed Rigid Body Simulation with Extended Position Based Dynamics", 2020 *(fetched, text extracted locally)*
- https://matthias-research.github.io/pages/tenMinutePhysics/09-xpbd.pdf — Ten Minute Physics XPBD notes *(fetched, text extracted locally)*
- https://www.physicsbasedanimation.com/2019/08/01/small-steps-in-physics-simulation/
- https://www.physicsbasedanimation.com/2020/10/03/detailed-rigid-body-simulation-with-extended-position-based-dynamics/

### Tutorials, blogs, forums
- https://gafferongames.com/post/fix_your_timestep/ — Fiedler, "Fix Your Timestep!"
- https://gafferongames.com/post/collision_response_and_coulomb_friction/ — Fiedler, impulse response
- https://gafferongames.com/post/spring_physics/ — Fiedler, penalty springs
- https://code.tutsplus.com/how-to-create-a-custom-2d-physics-engine-the-basics-and-impulse-resolution--gamedev-6331t — Gaul, impulse resolution and positional correction
- https://allenchou.net/2014/01/game-physics-stability-slops/ — Chou, penetration and restitution slop
- https://allenchou.net/2013/12/game-physics-resolution-contact-constraints/ — Chou, contact constraint with `β/Δt` bias
- https://erikonarheim.com/posts/understanding-collision-constraint-solvers/ — Onarheim
- http://vodacek.zvb.cz/archiv/286.html — mirror of Firth, "Speculative Contacts" (2011)
- https://wildbunny.co.uk/blog/2011/03/25/speculative-contacts-an-continuous-collision-engine-approach-part-1/ — original *(failed: 404)*
- https://media.steampowered.com/apps/valve/2015/DirkGregorius_Contacts.pdf — Gregorius, "Robust Contact Creation", GDC 2015 *(fetched, text extracted locally)*
- https://www.myphysicslab.com/develop/docs/Engine2D.html — back-up-in-time collisions, contact force solver
- https://forum.godotengine.org/t/how-to-calculate-impulses-considering-delta-time/81701 — impulses vs forces and delta
- https://lisyarus.github.io/blog/posts/perfect-collisions.html — "The quest for perfect collisions"
- https://research.ncl.ac.uk/game/mastersdegree/gametechnologies/previousinformation/physics6collisionresponse/2017%20Tutorial%206%20-%20Collision%20Response.pdf — Newcastle, projection/impulse/penalty *(fetched, text extracted locally)*
- https://research.ncl.ac.uk/game/mastersdegree/gametechnologies/previousinformation/physics7solvers/2017%20Tutorial%207%20-%20Solvers.pdf — Newcastle, Baumgarte tuning *(fetched, text extracted locally)*
- https://en.wikipedia.org/wiki/Collision_response — impulse definition and formula
- https://digitalrune.github.io/DigitalRune-Documentation/html/138fc8fe-c536-40e0-af6b-0fb7e8eb9623.htm — CCD background
- https://www.toptal.com/game/video-game-physics-part-ii-collision-detection-for-solid-objects — discrete vs continuous detection
- https://www.toptal.com/developers/game/video-game-physics-part-iii-constrained-rigid-body-simulation — constraint solvers overview
- https://www.gamedev.net/forums/topic/652181-jittering-due-to-gravity-and-restitution/ *(failed: 403)*
- https://raphaelpriatama.medium.com/sequential-impulses-explained-from-the-perspective-of-a-game-physics-beginner-72a37f6fea05 *(failed: 403)*

### Search results consulted but not opened
- https://pybullet.org/Bullet/phpBB3/viewtopic.php?t=7117 — "Bullet 2.77 Restitution issue"
- https://pybullet.org/Bullet/phpBB3/viewtopic.php?t=878 — "Split Impulses and Joints"
- https://pybullet.org/Bullet/phpBB3/viewtopic.php?t=2187 — Bullet 2.69 release (split impulse)
- https://pybullet.org/Bullet/phpBB3/viewtopic.php?t=11675 — "Non-linear Gauss-Seidel solver"
- https://github.com/erincatto/box2d/issues/601 companion: https://github.com/pybox2d/pybox2d/issues/75
- https://dl.acm.org/doi/10.1145/192161.192168 — Baraff 1994, "Fast contact force computation for nonpenetrating rigid bodies"
- https://onlinelibrary.wiley.com/doi/abs/10.1002/(SICI)1097-0207(19960815)39:15%3C2673::AID-NME972%3E3.0.CO;2-I — Stewart & Trinkle 1996
- https://link.springer.com/article/10.1023/A:1008292328909 — Anitescu & Potra 1997
- https://ieeexplore.ieee.org/document/1242171/ — Cline & Pai 2003, post-stabilization
- https://dl.acm.org/doi/10.1145/1243980.1243986 — Erleben 2007, velocity-based shock propagation
- https://www.sciencedirect.com/science/article/abs/pii/0045782572900187 — Baumgarte 1972
- https://arxiv.org/pdf/1601.03545 — "The Painlevé paradox in contact mechanics"
- https://www.researchgate.net/publication/304883246_Impact_models_and_coefficient_of_restitution_A_review — Newton/Poisson/Stronge review
- https://mastodon.gamedev.place/@erin_catto/111891102035414836 — Catto announcing Solver2D
- https://box2d.org/publications/ — index of Catto's talks
