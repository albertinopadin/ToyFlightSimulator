# ToyFlightSimulator — `flight_model` Simplification Suggestions

**Generated:** 2026-05-15
**Scope:** `git diff main...flight_model` (1802 lines, 24 files)
**Status:** Suggestions only — nothing applied. Companion doc to `flight_model_review_2026-05-14.md` (which covers correctness/risk); this doc focuses on **simplification / quality / reuse / efficiency** of the new code.

Three parallel review passes:

1. **Reuse** — newly written code that duplicates existing helpers
2. **Quality** — hacky patterns, leaky abstractions, dead/commented code, stale TODOs
3. **Efficiency** — hot-path waste in the new physics composition layer

Findings are ranked. Each item gives a file path, the diagnosis, and a concrete fix.

---

## TL;DR — What I'd Do First

If you only want a few high-leverage cleanups, in this order:

1. **Q1** — Delete dead `applyGravity` method + commented call + ~7 commented prints in `EulerSolver` (~25 LOC of noise)
2. **Q2** — Drop three WHAT-comments and double `getFwdVector()` call in `F22.doUpdate`
3. **E1** — `collidedWith.removeAll(keepingCapacity: true)` — one-line per-frame allocation fix
4. **Q3** — Delete the stale `// TODO: below should be part of a Collider...` in `GameObject.getAABB`
5. **R1** — Return the `PlaneRigidBody` from `GameScene.addGround(...)` so callers stop force-unwrapping `addGround().rigidBody!` (3 sites)
6. **R2** — Restore `shouldUpdateOnPlayerInput && hasFocus` guard inside `F22.doUpdate`'s force path (currently dropped when a rigid body is attached)

Everything else is incremental; the larger items (solver loop fusion, AABB caching, factory pattern for `RigidBody`) probably belong inside the planned ECS / data-oriented refactor rather than this branch.

---

# Section 1 — Quick-Win Cleanups (low-risk, in-scope)

These are pure deletions / one-line fixes. Each is independently safe.

## Q1 — Dead `applyGravity` method + commented call + commented prints [HIGH]

**File:** `ToyFlightSimulator Shared/Physics/Solver/EulerSolver.swift`

After the force-based rewrite, `applyGravity` is no longer called — only the line-10 commented call references it, and the method body is unreachable (`grep -rn applyGravity` confirms no other callers). The `resolveCollisions` body also carries ~7 commented-out `print` statements left over from debugging.

**Before:**
```swift
public static func step(deltaTime: Float, gravity: float3, entities: inout [any PhysicsEntity]) {
//        applyGravity(deltaTime: deltaTime, gravity: gravity, entities: &entities)
    applyForces(deltaTime: deltaTime, gravity: gravity, entities: &entities)
    ...
}

public static func applyGravity(deltaTime: Float, gravity: float3, entities: inout [PhysicsEntity]) {
    for i in 0..<entities.count {
        if !entities[i].isStatic && entities[i].shouldApplyGravity {
            let entityVelo: float3 = [entities[i].velocity.x + gravity.x * deltaTime, ...]
            entities[i].velocity = entityVelo
        }
    }
}
```

**After:** delete the commented call (line 10) and the entire `applyGravity` method (lines 17-27). Also delete the 7 commented-out `print(...)` lines inside `resolveCollisions` (50, 64-65, 67, 82-83, 97, 111).

**Why:** `applyGravity` is now a misleading second source of truth for gravity integration; `applyForces` is the only path. Commented-out prints rot — if you need them back, `git log` has them.

---

## Q2 — F22.doUpdate: double `getFwdVector()` + WHAT comments [MEDIUM]

**File:** `ToyFlightSimulator Shared/GameObjects/F22.swift:44-53`

```swift
override func doUpdate() {
    if let rigidBody {
        // Using forces:
        // Engine:
        let engineForce: float3 = getFwdVector() * self.engineThrust * InputManager.ContinuousCommand(.MoveFwd) * 10.0
        // Extremely simplified lift:
        let lift: Float = max(0, dot(rigidBody.velocity, getFwdVector())) * 100.0
        let liftVector: float3 = getUpVector() * lift
        rigidBody.force += engineForce + liftVector
```

Three problems:

1. `getFwdVector()` reads `modelMatrix.columns.2` and `normalize()`s (sqrt + 3 divides) **twice per frame**. Cache it.
2. `// Using forces:` / `// Engine:` / `// Extremely simplified lift:` are WHAT-comments — the identifiers `engineForce`/`lift`/`liftVector` already say this. Per CLAUDE.md "Default to writing no comments. Only add one when the WHY is non-obvious."
3. `engineThrust * 10.0` — `engineThrust` is `let = 70`. Either fold the constant (`70_000`, with a comment that it's lbs) or rename the property to `engineThrust10x` (silly) or drop the magic `10.0` factor.

**After:**
```swift
if let rigidBody {
    let fwd = getFwdVector()
    let engineForce = fwd * engineThrust * InputManager.ContinuousCommand(.MoveFwd) * 10.0
    let lift = max(0, dot(rigidBody.velocity, fwd)) * 100.0
    rigidBody.force += engineForce + getUpVector() * lift
```

(The `10.0` and `100.0` magic numbers are correctness-domain decisions, not simplifications — leave them but consider hoisting to named constants.)

---

## Q3 — Stale TODO comment in GameObject.getAABB [LOW]

**File:** `ToyFlightSimulator Shared/GameObjects/GameObject.swift:17`

```swift
// TODO: below should be part of a Collider...
// Default AABB implementation for GameObjects
func getAABB() -> AABB { ... }
```

The composition refactor *was* the move that should have closed this TODO. The function is still on `GameObject` (with `SphereRigidBody`/`PlaneRigidBody` overriding via their own `getAABB` and chaining to `gameObject?.getAABB()`). Either:

- **Now:** move the default `getAABB` body onto `RigidBody.getAABB` directly (it currently does `gameObject?.getAABB() ?? AABB(center: .zero, radius: .zero)` — bouncing through `GameObject` to get a generic `halfExtents = scale * 0.5` AABB is unnecessary indirection).
- **Defer:** drop the TODO; it's task-rot without an owner.

I'd vote drop-the-TODO unless the move is being done in this branch.

---

## Q4 — RigidBody.init: 3-space indentation [TRIVIAL]

**File:** `ToyFlightSimulator Shared/Physics/World/RigidBody.swift:47-48`

```swift
       // Register with object this is attached to:
       gameObject.rigidBody = self
```

Both lines are indented with 7 spaces (3-space inner indent) where the rest of the file uses 4. Reformat to 8 spaces.

---

## E1 — `collidedWith.removeAll()` reallocates dict storage every frame [MEDIUM]

**File:** `ToyFlightSimulator Shared/Physics/World/PhysicsEntity.swift:42`

```swift
mutating func resetCollisions() {
    collidedWith.removeAll()
}
```

`removeAll()` without `keepingCapacity: true` discards the backing storage. Next frame's first collision insert reallocates. Called once per entity per frame from `PhysicsWorld.update`.

**Fix:** `collidedWith.removeAll(keepingCapacity: true)`

For the 500-sphere stress test this is 500 reallocs/frame → 0.

---

# Section 2 — Medium-effort Cleanups

## R1 — `addGround` swallows the rigid body, forcing `addGround().rigidBody!` at every call site [HIGH]

**File:** `ToyFlightSimulator Shared/Scenes/GameScene.swift:94-107` (and callers)

`addGround` creates a `Quad` *and* attaches a `PlaneRigidBody` to it, but returns only the `Quad`. Three callers then need the rigid body for the entities array and write:

```swift
let ground = addGround(...)
entities.append(ground.rigidBody!)   // ← force-unwrap of a body we just created
```

Callers: `FlightboxWithPhysics.swift:18`, `BallPhysicsScene.swift:~97`, `PhysicsStressTestScene.swift`.

**Fix:** return `(Quad, PlaneRigidBody)` (or just the rigid body — the scene only needs to retain the `Quad` via the scene-graph parent). Eliminates 3 force-unwraps.

**Why:** the new composition design implies `RigidBody` lifetime is tied to `GameObject`. The force-unwrap reads as "I know I just attached one" — that's an API signaling failure.

---

## R2 — F22 force path drops `shouldUpdateOnPlayerInput && hasFocus` guard [HIGH — also a correctness bug]

**File:** `ToyFlightSimulator Shared/GameObjects/F22.swift:44-67`

`Aircraft.doUpdate` (line 52) guards rotation/translation input on `shouldUpdateOnPlayerInput && hasFocus`. The new F22 force-path branch (`if let rigidBody { … }`) reimplements the rotation/side-move code and the gear toggle **without that guard**. Effect: an `F22(shouldUpdateOnPlayerInput: false)` constructed for a free-cam scene (e.g., `FreeCamFlightboxScene.swift:48`) with a rigid body attached will still spin and apply thrust from input.

**Fix (minimal):** add the guard inside the `if let rigidBody {` block:

```swift
if let rigidBody {
    if shouldUpdateOnPlayerInput && hasFocus {
        let fwd = getFwdVector()
        let engineForce = ...
        rigidBody.force += engineForce + getUpVector() * lift
        // rotations, side-move, gear toggle
    }
    animator?.update(deltaTime: Float(GameTime.DeltaTime))
}
```

**Fix (cleaner):** extract `Aircraft.applyPlayerAttitudeInput(deltaTurn:)`, `Aircraft.applyPlayerSideMove(deltaMove:)`, `Aircraft.handleGearToggle()` helpers. Then `F22.doUpdate` becomes:

```swift
override func doUpdate() {
    if let rigidBody, shouldUpdateOnPlayerInput && hasFocus {
        applyEngineAndLiftForces(rigidBody)
        let deltaTurn = Float(GameTime.DeltaTime) * _turnSpeed
        let deltaMove = Float(GameTime.DeltaTime) * _moveSpeed
        applyPlayerAttitudeInput(deltaTurn: deltaTurn)
        applyPlayerSideMove(deltaMove: deltaMove)
        handleGearToggle()
        animator?.update(deltaTime: Float(GameTime.DeltaTime))
    } else {
        super.doUpdate()
    }
    updateAfterburners()
}
```

Eliminates the copy-paste between `Aircraft.doUpdate` and the F22 force branch; restores the guard for free; makes the force path purely additive.

---

## R3 — `FreeCamFlightboxScene` reinvents `setupDefaultSky()` [MEDIUM]

**File:** `ToyFlightSimulator Shared/Scenes/FreeCamFlightboxScene.swift` (inline switch on `_rendererType`)

```swift
if _rendererType == .OrderIndependentTransparency {
    addChild(SkySphere(textureType: .Clouds_Skysphere))
} else {
    addChild(SkyBox(textureType: .SkyMap))
}
```

`GameScene.setupDefaultSky()` exists for this — but `setupDefaultSky` only adds a skybox for `SinglePassDeferredLighting`, whereas this scene wants the skybox fallback for *any* non-OIT renderer. The right move is to generalize `setupDefaultSky` to accept a `nonOITFallback: SkyType = .none` (or expose two named overloads), not to leave the duplicated switch.

---

## Q5 — Per-frame `print` in `EulerSolver.resolveCollisions` (live, not commented) [LOW]

**File:** `EulerSolver.swift:62`

```swift
// Hack to prevent infinite bouncing:
let relativeVelo = (entities[i].velocity - entities[j].velocity).magnitude
```

The `// Hack to prevent infinite bouncing:` comment is actually a legitimate WHY (explains the threshold below). Keep it. Mentioning here only because Q1 will pass nearby and you might be tempted to delete it — don't.

Also: `PhysicsWorld.swift:130,166` have live `print("[getCollisionVector] Collision plane/plane")` / `print("[collided] Check plane/plane")` calls fired from broad-phase pair-checking. These are pre-existing on `main` but **the new composition refactor moved `entities` through more code paths**, so they may fire more often. Worth either gating behind a debug flag or deleting.

---

## E2 — `for var entity in entities { entity.resetCollisions() }` creates per-iteration existential copies [LOW]

**File:** `ToyFlightSimulator Shared/Physics/World/PhysicsWorld.swift:46-49`

```swift
for var entity in entities {
    entity.resetCollisions()
}
```

`PhysicsEntity` is a protocol; the array stores existential boxes. `for var entity in` copies each existential into a mutable local. Since every conforming type is now a class (`RigidBody`), the mutation propagates through the class reference anyway — but the existential copy + `mutating` boxing is pure overhead.

Two options:

**(a) Cheap:** switch to an index walk to drop the per-element copy:

```swift
for i in entities.indices {
    entities[i].resetCollisions()
}
```

(Still goes through the protocol, but no per-iteration mutable copy.)

**(b) Cleaner:** drop `mutating` from `resetCollisions`/`zeroForce` in the extension. Because `RigidBody` is a class, dictionary mutation via the reference doesn't need `mutating` — but Swift requires it at the protocol level because of the `get set` requirement. So this option requires either narrowing the protocol surface or moving these methods to a concrete `RigidBody` method.

Pick (a). Trivial change, removes the warning-flavored `for var`.

---

# Section 3 — Larger refactors (defer or hold for ECS work)

These came out of the efficiency / quality passes but are big enough that I'd punt them to the planned ECS / data-oriented refactor (`fa35867 Add Claude research + plan for ECS / Data-Oriented Design refactor`). Listed for the record:

## D1 — Fuse `applyForces` + `moveObjects` + `zeroForces` into a single loop

Currently the Euler step walks `entities` three times per frame for these three operations. They're all per-entity pure transforms with no cross-entity reads. Fusing into one loop drops 2× the array-bounds checks and `isStatic` branches. Also eliminates a redundant pass over static bodies inside `zeroForces` (which writes `.zero` to a field that's never read).

Don't do this here — solver semantics need a regression test before changing iteration order, and the planned ECS refactor will rebuild the loop with SoA layout anyway.

## D2 — Cache AABBs per frame for broadphase SAP

`BroadPhaseCollisionDetector` calls `getAABB()` for every entity in its inner SAP loop. With composition, every `SphereRigidBody.getAABB()` now does `getPosition() → gameObject?.getPosition() ?? .zero` — a weak optional chain through the existential. For 500 spheres × 60Hz × ~N inner-loop calls, this is hundreds of thousands of atomic weak-reference loads where there were zero pre-refactor (when `Sphere` *was* the entity).

**Fix:** cache `[AABB]` once per step indexed by entity order. Or give `RigidBody` a stored `cachedAABB: AABB` and update it in a single sweep at the start of `PhysicsWorld.update`. The latter is closer to ECS.

## D3 — `unowned(unsafe) gameObject` instead of `weak`

`GameObject` strongly owns `RigidBody` via `var rigidBody: RigidBody?`, so the back-reference can never outlive its target. `weak` requires atomic ref-count loads on every access; `unowned(unsafe)` is a plain pointer load. For solver hot paths this is a measurable win.

Don't apply this until D2 is in place — the bigger win is eliminating the per-frame access entirely.

## D4 — `RigidBody.init` registration side-effect → factory pattern

`RigidBody.init` mutates the `gameObject` passed in (`gameObject.rigidBody = self`). Callers throw away the local because the registration *is* the API. F22's `didSet` observer on `rigidBody` only fires *because* of this side-effect, which makes the two coupled "secret protocols" load-bearing.

Fix: replace `SphereRigidBody(gameObject: jet, collisionRadius: 5)` with `jet.attachSphereCollider(radius: 5)` (or `jet.attachRigidBody(.sphere(radius: 5))`). Then F22's mass/restitution can be set on the rigid body explicitly at the call site, the `override var rigidBody { didSet }` observer goes away, and the construction order is obvious from the code.

This is invasive (touches every scene that wires up a physics object) but unlocks D5.

## D5 — Drop `weak let` novelty

`RigidBody.gameObject: weak let GameObject?` compiles fine on Swift 6.1+ (SE-0481). The headline of the refactor commit was "weak let" — but there's no behavioral difference vs `weak var` (the reference auto-nils either way). Once D4 lands the back-pointer can become `unowned` (D3) and the `let` vs `var` distinction is moot.

Don't touch this in isolation — purely cosmetic.

## D6 — Move `PhysicsEntityStub` to `TestSupport/`

Currently lives in `ToyFlightSimulatorTests/Physics/PhysicsSolverTests.swift`. Reasonable to keep there for now (only one test file uses it). Promote to `TestSupport/PhysicsEntityStub.swift` when a second test file wants the no-MetalKit stub (e.g., when adding integration tests that can't link `Engine.Device`).

## D7 — Scene helpers: `makeRandomSphere`, `addStandardSun`

`BallPhysicsScene.swift` and `PhysicsStressTestScene.swift` each carry ~30 LOC of near-identical sphere-fountain + sun-setup boilerplate (only intensities differ). Could fold into `GameScene.makeRandomSphere(at:radius:color:mass:restitution:) -> (Sphere, SphereRigidBody)` and `GameScene.addStandardSun(brightness:ambient:diffuse:)`. Defer until a third scene wants the same pattern.

## D8 — Generic over RigidBody subclasses for scene's `entities: [PhysicsEntity]` boilerplate

Every physics scene reimplements the `entities.append(ground.rigidBody!) … physicsWorld.setEntities(entities)` ritual. `GameScene` could own an optional `physicsWorld: PhysicsWorld?` and `addPhysicsEntity(_ go: GameObject)` that auto-registers `go.rigidBody`. Combines well with D4.

---

# Section 4 — Flagged but skip (false positives)

For the record, items the review passes raised that aren't real:

- **`weak let gameObject: GameObject?` doesn't compile.** It does — Swift 6.1+ (SE-0481), Xcode 26.2 builds fine, tests green. The agents were guessing about an older Swift version.
- **Per-frame `print` in `VerletSolver.zeroAcceleration`.** Already removed in this branch — agents pulled it from the prior review doc's N1 finding without checking the current file.
- **`PhysicsEntityStub` duplicates `RigidBody` field-for-field.** Intentional. The stub exists specifically so `PhysicsSolverTests` doesn't need `Engine.Device` / MetalKit. Using a real `RigidBody` would force tests to link the renderer.
- **`PlaneRigidBody.getAABB` if/else cascade is duplicated.** It's a verbatim port of the pre-refactor `PlanePhysicsEntity.getAABB` extension — not new duplication. Refactor opportunity, but not a "this branch introduced duplicated code" finding.
- **`BroadPhaseCollisionDetector.lastFramePositions` never cleared on `setEntities`.** Pre-existing on `main`. Out of scope for this branch.
- **`HeckerCollisionResponse` rebuilds an ID→index dict every frame.** Pre-existing on `main`. Out of scope.
- **CI workflow comment is too long.** It's WHY (parallel mode keeps NSApplication runloop alive → runner hangs); the explanation is load-bearing for future maintainers. Keep it.

---

# Section 5 — Where Each Item Came From

Cross-reference for traceability:

| Item | Agent | Notes |
|------|-------|-------|
| Q1 | Quality #7, Reuse (implied) | EulerSolver dead code |
| Q2 | Quality #7, Efficiency E8/E9 | F22 doUpdate |
| Q3 | Quality #13 | TODO breadcrumb |
| Q4 | Quality #3 | Indent |
| Q5 | (review doc N1) | Live prints in collision paths |
| E1 | Efficiency M1 | keepingCapacity |
| E2 | Efficiency E3 | for var entity |
| R1 | Quality #12 | addGround force-unwrap |
| R2 | Reuse #4, Quality #4, Efficiency M3 | F22 force-path guards |
| R3 | Reuse #1 | setupDefaultSky |
| D1 | Efficiency E1 | Solver fusion |
| D2 | Efficiency E5 | AABB cache |
| D3 | Efficiency E6 | unowned vs weak |
| D4 | Quality #3 | Init side-effect |
| D5 | Quality #2 | weak let novelty |
| D6 | Reuse #6 | Stub relocation |
| D7 | Reuse #7, #8 | Scene helpers |
| D8 | Reuse #10 | Physics-scene boilerplate |
