# Compound Rigid Bodies — Implementation Plan

**Started:** 2026-07-19 · **Revised:** 2026-08-27 (post-meterization + external review — see Changelog)
**Source of truth for design decisions:** `research/claude/compound_rigid_bodies_research_combined.md` (§4 is the phase outline this plan executes; §2–§3 hold the argued verdicts).
**Supporting docs:** `research/claude/compound_rigid_bodies_research_2026-07-14.md` (type definitions §2.3, F-22 spec §2.3, overlay sketch §2.7), `research/codex/compound_rigid_bodies_and_articulated_landing_gear_research_2026-07-14.md`.

## How this document works

- **Steps are living text.** They get edited in place to stay true to the current contract. (The original
  append-only rule was retired 2026-08-27: it had begun actively obscuring the contract — the executable
  steps still described the pre-meterization scale-3 units world.)
- **History** lives in two places: dated `> **Addendum (YYYY-MM-DD):**` blocks are kept where they still
  explain a *why*; every substantive revision gets a **Changelog** entry below.
- **Checkboxes** (`- [ ]`) get ticked in place as steps land.
- Every step cites the research-doc section it implements so the "why" is one hop away.

## Changelog

- **2026-08-28** — **Step 0.4 landed** (all five files; macOS Debug build green; X cycle verified
  visually in-app), together with **0.3b's code half** (`Node.parent` and
  `SubMeshGameObject.parentMeshGameObject` → `weak`; `NodeOwnershipTests` still owed) and one extra
  same-class fix found during review: `Mesh.parentModel` → `weak` (write-only strong back-reference;
  the Model ↔ Mesh cycle would have leaked each bespoke capsule volume's one-off Model per overlay
  show). Deviations recorded in the 0.4 addendum: `cubeMeshSize` naming (listing updated), overlay
  track landed before the parity track (0.6/0.7), `logWorldDimensions` prints filled in during review
  so 0.5's in-app anchor check is still pending.
- **2026-08-27** — Phase 0 revision incorporating the Codex verification review. Every finding was
  re-verified against the tree before adoption (ModelIO semantics were measured directly, not taken on
  faith — see 0.5):
  1. **Units contract rewritten for landed meterization** (see `plans/claude/meter_scale_implementation_plan_2026-07-23.md`):
     colliders are authored in post-import engine-local **meters**; aircraft run at scale **1.0**
     (`FlightboxWithPhysics.applyAircraftSwap`). All scale-3 arithmetic deleted; step 0.2 re-authored
     with meter placeholders (fuselage capsule now spans nose→tail ≈ 18.9 m, resolving the old
     17.1 m-vs-nose→tail contradiction in favor of nose→tail); the sanity anchor is now 18.9 m at ×1.
  2. **Capsule mesh mapping corrected from measurement**: `MDLMesh(capsuleWithExtent: [x, y, z])` treats
     x/z as the **radius** and y as the **total cap-to-cap length**, so `capsuleMeshParams` must return
     `2·(halfHeight + radius)`, not `2·halfHeight`. The planned one-time *visual* calibration is replaced
     by a CPU bounding-box regression test. (Bonus finding: `sphereWithExtent` is also radius-semantics —
     `SphereMesh(radius:)` builds a 2× mesh. Latent today; the overlay never uses `SphereMesh`; pinned by
     the same test.)
  3. **New step 0.3b**: `Node.parent` (and `SubMeshGameObject.parentMeshGameObject`) become `weak`.
     With both strong, every detached ≥2-node subtree is a retain cycle — aircraft swaps AND
     `teardownScene()` (which only detaches top-level children) leak the old aircraft plus its
     afterburner emitters today. The overlay lifecycle rules in 0.4 are rewritten on top of this fix.
  4. **Overlay gains a hull-hidden mode** (X cycles off → volumes-over-hull → volumes-only): depth-tested
     translucent volumes can reveal overfit (protrusion) but never underfit (fully-contained volumes are
     occluded, and back-face culling hides them from inside too). The old "accepted limitation" was
     stronger than the tool could verify.
  5. **Parity plan corrected**: Phase A's slop+β positional correction (research combined doc §3.3/§4.2)
     diverges from the *first contact* in every scenario including the dynamic/dynamic head-on pair, so
     the old "identical" expectations were wrong. Verification is split into a routing-only commit (exact
     golden match) and a response commit (reviewed regolden + semantic asserts); chaotic cluster/stress
     goldens are shortened and backed by long-run invariants; `SplitMix64` derives Floats directly
     instead of through `Float.random(in:using:)`.
  6. **Step 0.6 redesigned**: explicit `init(detachedAt:)` standalone mode instead of relaxing production
     inits to `GameObject?` — the old design silently changed the *tested* released-weak-reference
     fallback behavior (`RigidBodyTests.rigidBodyToleratesNilGameObject`).
  7. **Verification commands fixed**: the macOS scheme's Build action builds only the app (verified in the
     .xcscheme), so `build` + `test-without-building` was unreliable; use `build-for-testing` +
     `test-without-building`, or serial `xcodebuild test`. 0.8 additionally gains NodeTests for the 0.3
     rotation dirty-flag fixes, which landed untested.
  Plus smaller items: pre-Phase-A design corrections recorded (per-world step/scratch state,
  world-collider cache invalidation, world-transform contract), `worldSpan` → `worldDimensions`,
  exhaustive `AircraftType` switch in the spec, finite/positive dimension asserts.

**Verification commands** (corrected 2026-08-27 — the scheme's Build action builds the app only, so a
plain `build` does NOT produce the test bundle):

```bash
# Build tests + app
xcodebuild build-for-testing -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" \
  -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Scoped suite run (add -only-testing for one suite); serial per project rule
xcodebuild test-without-building -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" \
  -sdk macosx -configuration Debug -parallel-testing-enabled NO \
  -only-testing:"ToyFlightSimulatorTests/<SuiteName>" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Or the one-step full suite (serial matches CI and avoids app-host deadlocks)
xcodebuild test -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" \
  -sdk macosx -configuration Debug -parallel-testing-enabled NO \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Note: `-parallel-testing-enabled NO` serializes test *bundles/clones*, not Swift Testing's in-process
concurrency — parameterized `@Test` cases still run concurrently inside one process. Test designs (and
the physics engine itself — see the pre-Phase-A corrections) must not rely on process-wide statics.

---

# Phase 0 — Debug overlay, units contract, parity harness

Implements combined doc **§4.1**. Everything in this phase is **behavior-neutral for the running game**,
with one deliberate exception: step 0.3b fixes the scene-graph ownership direction, so detached subtrees
now deallocate (that IS the observable change, and it's what the step's tests pin). No physics semantics
change, no render-path change. Phase 0 exists so that (a) every collider/strut number in Phases A/B can
be eyeballed against the real model before physics consumes it, and (b) Phase A's response-path rewrite
diffs against a recorded baseline instead of against memory.

**Deliverables:**
1. A collider overlay on the player aircraft, cycled with the **X** key through three states —
   off → translucent volumes over the hull → volumes with the hull hidden — showing the proposed
   compound spec (red) next to the legacy 2 m physics sphere (yellow).
2. The units contract (collider dimensions are post-import engine-local **meters**; `uniformScale` is a
   pass-through multiplier that is 1.0 for every meterized aircraft) enforced by a debug assertion and
   sanity-checked against the CGTrader F-22.
3. A Metal-free, deterministic trajectory-capture harness with committed golden baselines for the current
   physics behavior, plus the verification protocol Phase A will follow against them.

**Non-goals (deferred):** `WorldCollider` + narrow phase (Phase A), any `RigidBody.colliders` storage
(Phase A), strut visualization as `Line`s (Phase B, when `SuspensionStrut` exists), iOS menu toggle for
the overlay (X-key macOS only for now), a depth-disabled x-ray/wireframe overlay *pass* (a real
render-path change touching multiple renderers — the hull-hidden mode in 0.4 covers the underfit-tuning
need without one).

### Deviations from the research docs (deliberate, small)

| Deviation | Why |
|---|---|
| The **data-only half of A1** (`ColliderShape`, `ColliderGroup`, `LocalCollider`) is pulled forward into Phase 0 | The overlay's entire purpose is rendering *proposed specs* before physics exists; defining the real vocabulary now means the overlay and specs are written once, against the final types. Phase A's A1 shrinks to: add `WorldCollider`, the reserved `material` field, and the `RigidBody` integration. |
| `RigidBody` + `SphereRigidBody`/`PlaneRigidBody` gain explicit **`init(detachedAt:)` standalone inits** | Not in either research doc. Required for a Metal-free parity harness: the current narrow phase force-casts to these `final` classes (`PhysicsWorld.collided`), so `TestRigidBody` doubles cannot traverse the collision path, and the production inits demand a non-optional `GameObject` (→ Metal). Production call sites keep the non-optional inits; attached-body behavior (including the tested released-weak fallbacks) is untouched. |
| Overlay also draws the **legacy collision sphere** (yellow) | One glance shows what the compound replaces — directly motivates spec tuning. Costs ~10 lines. |
| Overlay gets a **hull-hidden mode** backed by a small `SceneManager` hide/unhide hook | Not in the research docs' overlay sketch. Depth-tested translucency cannot reveal an underfit collider (see 0.4); reliable visual fitting is Phase 0's main purpose, so the tool must be able to show volumes unoccluded. Chosen over a depth-disabled x-ray *render pass* because it reuses the existing registration machinery and touches zero renderers. |
| Struts-as-`Line`s omitted from the Phase 0 overlay | Combined doc §4.1 mentions them, but strut specs are Phase B data (`SuspensionStrut`); drawing them before the type exists would invent throwaway structure. The overlay grows a strut layer in Phase B. |

---

## Step 0.1 — Collider vocabulary, data-only ✅

- [x] New file `ToyFlightSimulator Shared/Physics/Collision/ColliderShape.swift` (add to all three app targets, like the rest of Shared)

Taken verbatim from the original research doc §2.3, minus `WorldCollider` (Phase A — it's narrow-phase
output, nothing in Phase 0 consumes it) and minus the reserved `material` field (Phase A):

```swift
import simd

/// Convex collision primitives, in the cost order every surveyed engine
/// documents (sphere < capsule < box). Dimensions are authored in the owning
/// model's post-import local space — which meterization makes METERS — and
/// multiplied by the GameObject's uniform scale (1.0 for meterized aircraft)
/// when world-space colliders are computed.
enum ColliderShape: Equatable {
    /// Ball of the given radius.
    case sphere(radius: Float)
    /// Segment along local Y from -halfHeight to +halfHeight, inflated by
    /// radius (total height = 2·(halfHeight + radius)). Orient with the
    /// collider's localRotation (e.g. Y→Z for a fuselage along +Z).
    case capsule(radius: Float, halfHeight: Float)
    /// Oriented box with the given half extents.
    case box(halfExtents: float3)

    func scaled(by s: Float) -> ColliderShape { ... }

    /// Debug validation: every dimension finite and > 0 (capsule halfHeight
    /// may be 0 — that's a legal sphere-equivalent). Asserted in
    /// LocalCollider.init and unit-tested per authored spec.
    var hasFinitePositiveDimensions: Bool { ... }
}

/// Which functional part of the object a collider represents ...
enum ColliderGroup { case airframe, landingGear, structure }

/// One primitive rigidly attached to a body at a local offset — the per-child
/// entry of a compound (Bullet btCompoundShape child, Unity child collider,
/// Jolt compound sub-shape).
struct LocalCollider {
    var name: String
    var shape: ColliderShape
    var localPosition: float3
    var localRotation: simd_quatf
    var group: ColliderGroup
    /// Cheap runtime on/off (Jolt MutableCompoundShape's role).
    var isEnabled: Bool

    init(...) {
        assert(shape.hasFinitePositiveDimensions,
               "Collider '\(name)' has non-finite or non-positive dimensions")
        ...
    }
}
```

Phase A will append to this file (`WorldCollider`, `material`), not restructure it.

> **Addendum (2026-07-19):** Step 0.1 is implemented, with one improvement over the pseudocode above: a documented `simd_quatf.identity` constant now lives in `Math/Transform.swift` (alongside the existing `float4x4.identity`), and `LocalCollider.localRotation`'s default reads `.identity` instead of the raw `simd_quatf(real: 1, imag: .zero)` spelling — which existed only because simd ships no identity-quaternion constant. (Related footgun, documented on the constant: the auto-imported `simd_quatf()` default init is the invalid ZERO quaternion — never use it.) Later phases should spell identity rotations as `.identity` too. Target membership is automatic (the project uses filesystem-synchronized folders), so the "add to all three app targets" note in 0.1 is a no-op.

> **Addendum (2026-08-27):** `hasFinitePositiveDimensions` + the `LocalCollider.init` assert are a
> review-driven addition (landed with the 0.2 re-author); the 2026-07-19 implementation predates them.

## Step 0.2 — Placeholder aircraft specs ✅

- [x] New file `ToyFlightSimulator Shared/Physics/Collision/AircraftColliderSpec.swift`
  *(originally landed 2026-07-20 in pre-meterization model units; re-authored in meters 2026-08-27 —
  numbers remain placeholders until overlay-tuned in 0.5)*

Mirrors the `AircraftThumbnailSpec.spec(for:)` pattern (one spec per `AircraftType`, central file).
Phase 0 authors **only** the CGTrader F-22 (the default player aircraft); other types return `[]` — the
overlay shows their legacy sphere and logs "no compound spec yet" rather than us inventing numbers we
can't eyeball this phase. The switch is **exhaustive with no `default`** (same convention as
SceneManager's registration switches): adding an `AircraftType` case forces a conscious authored-or-empty
decision here at compile time.

**Units:** dimensions and offsets are post-import engine-local units, which meterization
(`realWorldLength: 18.92` in `ModelLibrary.makeLibrary()`) makes **meters**. `FlightboxWithPhysics`
builds aircraft at scale 1.0, so world meters = spec meters × `uniformScale` = spec meters. The
placeholder numbers are the pre-meterization values × 3 (the scale the old contract assumed), with the
fuselage capsule then stretched to span nose→tail — real F-22: length 18.92 m, wingspan 13.56 m:

```swift
private static let f22CGTrader: [LocalCollider] = [
    LocalCollider(name: "fuselage",
                  // Total 2·(8.1 + 1.35) = 18.9 m — spans nose→tail (real 18.92 m).
                  shape: .capsule(radius: 1.35, halfHeight: 8.1),
                  localPosition: [0, 0.3, 0.6],
                  // Capsule axis is local Y; rotate Y→Z so it runs nose–tail.
                  localRotation: simd_quatf(angle: .halfPi, axis: X_AXIS),
                  group: .airframe),
    LocalCollider(name: "wings",
                  // 13.2 m span vs 13.56 m real wingspan.
                  shape: .box(halfExtents: [6.6, 0.18, 2.7]),
                  localPosition: [0, 0.15, -1.2],
                  group: .airframe),
    LocalCollider(name: "empennage",
                  shape: .box(halfExtents: [3.0, 1.35, 1.5]),
                  localPosition: [0, 1.05, -6.6],
                  group: .airframe),
]
```

Tuning these numbers against the model **is** a Phase 0 exit criterion; the tuned values get committed
here with a short comment noting they were overlay-verified.

> **Addendum (2026-07-20, historical):** the original landing settled two spellings that still hold — use
> `.halfPi` / `X_AXIS` (documented constants) rather than raw `.pi / 2, axis: [1, 0, 0]`, and no per-file
> `import simd` is needed anywhere in the target (the bridging header `TFSCommon.h` imports
> `<simd/simd.h>` target-wide). The model-unit numbers that landing carried (capsule total 5.7 units ≈
> 66% of the fuselage) are superseded by the meter re-author above.

## Step 0.3 — Small support APIs (Node / GameObject) ✅

- [x] `Node.setRotation(_ q: simd_quatf)` — the overlay must pose children from `LocalCollider.localRotation`. One line through the existing `rotationMatrix` setter.
- [x] `Node.uniformScale` — the units-contract accessor (combined doc §4.1), written once here, reused by Phase A's `worldColliders(frame:)`:

```swift
/// Uniform-scale contract for physics colliders: spec dimensions are model
/// units, world meters = model units × this. Debug-asserts the scale is
/// actually uniform so a stray setScale(x,y,z) can't silently skew colliders.
var uniformScale: Float { ... }
```

- [x] `GameObject.init(name:model:)` — capsule colliders need **bespoke mesh dimensions** (a capsule cannot be non-uniformly scaled without distorting its hemispherical caps). Mirrors `init(name:modelType:)` minus the library lookup. Mesh construction on the update thread is established practice (scene resets rebuild whole scenes there).

> **Addendum (2026-07-20):** Step 0.3 is implemented, with one **correction** to the original text: the claim that the `rotationMatrix` setter "handles the dirty-flagging" was wrong — that setter was a bare `_rotationMatrix` store, so the one-line `setRotation(_:)` silently never took effect (the cached local/world matrices were never invalidated). Fixed at the root: `Node.rotationMatrix`'s setter now routes through `updateModelMatrixAndMarkTransformDirty`, which also repairs a latent order-dependence in `F18.weaponReleaseSetup` (its direct `rotationMatrix =` assignment only worked because the `setScale` on the next line happened to dirty the node). `setRotation(_ q:)` additionally calls `afterRotation()` so both `setRotation` overloads fire the subclass hook identically. macOS Debug build green with 0.3 in the tree. **(2026-08-27:** these fixes landed without tests — 0.8 now includes NodeTests pinning both the quaternion overload and direct `rotationMatrix =` dirty propagation.)

## Step 0.3b — Scene-graph ownership fix: `Node.parent` becomes `weak` *(added 2026-08-27)*

- [x] `Node.parent` → `weak var parent: Node?` *(landed 2026-08-28, same commit as 0.4)*
- [x] `SubMeshGameObject.parentMeshGameObject` → `weak` (same commit — it's the same class of back-reference)
- [ ] Back-reference audit + deallocation tests (below) — **still owed**; tracked in 0.8 (`NodeOwnershipTests`)

> **Addendum (2026-08-28):** the two weak flips landed with 0.4 (whose lifecycle rules assume them). A
> third back-reference of the same class surfaced while landing 0.4 and was flipped in the same commit:
> `Mesh.parentModel` (strong, and **write-only** — no reader anywhere in the tree) made every
> Model ↔ Mesh pair a retain cycle. Library models mask it (process-lifetime cache), but 0.4's bespoke
> capsule volumes are the first runtime-built one-off Models — each overlay show would have leaked a
> Model + CapsuleMesh (MTLBuffers included) per cycle. `NodeOwnershipTests` remain owed before 0.3b is
> done.

**Why this is in Phase 0:** the overlay parents render-only volumes to the aircraft, and its lifecycle
rules (0.4) depend on what happens to a detached subtree. Today `Node.parent` is **strong**
(Node.swift), so parent ↔ child references form a retain cycle in every subtree with ≥ 2 nodes.
`SceneManager.RemoveObject(prevAc)` detaches the aircraft from the scene root and unregisters the
subtree, but the internal aircraft ↔ afterburner (and aircraft ↔ overlay-volume) links survive — the
island never deallocates. `GameScene.teardownScene()` has the same hole: `removeAllChildren()` nils
`parent` for *top-level* children only. Net: **every aircraft swap and every scene reset currently leaks
the old aircraft subtree**, per-instance afterburner particle pools included. The fix is the standard
scene-graph ownership direction: parents own children (strong `children` array), children point back
weakly.

Audit checklist (call sites that must keep their subject alive by other means — all verified owners
exist today, the audit re-confirms at implementation time):
- `GameScene` root: owned by `SceneManager.CurrentScene` (static) ✓
- Cameras: `CameraManager` registry array owns them; scenes also hold `attachedCamera`/`debugCamera`
  properties ✓ (`AttachedCamera.attach(to:)` detaches-then-reattaches; unaffected)
- Lights: `LightManager` + scene child both hold them ✓
- Overlay volumes: `ColliderDebugOverlay.volumes` while shown; aircraft's `children` while attached ✓
- `SubMeshGameObject.parentMeshGameObject`: with `Node.parent` weak, this **strong** back-reference
  would become the F-18's remaining cycle (aircraft.children → SMGO strong, SMGO.parentMeshGameObject →
  aircraft strong) — hence it flips to weak in the same commit. The parent F-18 is owned by the scene.
- Weapons/`SubMeshGameObject`s that reparent to the scene root on release: scene owns them post-release ✓

Tests (Metal-free, plain `Node`s — the cycle mechanics don't need GameObjects; new Swift Testing suite
`NodeOwnershipTests`, `.tags(.gameObjects)`):
- parent + child island: drop the last external strong ref to the parent → BOTH deallocate (this fails
  before the fix — it's the red test that motivates the change)
- 3-deep chain detached from a root: island deallocates
- child removed via `removeChild` then re-added elsewhere: parent pointer correct, no premature dealloc
  while the new parent lives
- `parent` reads nil after the parent deallocates (weak zeroing observed, no crash)

**Behavior note:** this is the one deliberate behavior change in Phase 0 — detached subtrees now
deallocate (and their `deinit`s run). Nothing in the tree relies on resurrecting a detached-but-leaked
subtree (verified by audit); the existing swap/reset flows only ever re-add freshly constructed objects.

## Step 0.4 — The collider debug overlay ✅

*(2026-08-27: fleshed out from sketch to full implementation code — the earlier draft left `cycle`
bodiless and the wiring as fragments. Code below is presented per file, path first. One naming
correction along the way: the discrete command is `CycleColliderOverlay`, not `ToggleColliderOverlay` —
it's a three-state cycle, and `CycleCamera` already established the verb.)*

Files touched, in landing order (each has a full listing below):

- [x] **File 1 (edit):** `ToyFlightSimulator Shared/Managers/SceneManager.swift` —
  `SetRenderableHidden(_:_:)` hide/unhide hook (single node, non-recursive) + `rehideExtractedSubmeshes(of:)`
- [x] **File 2 (new):** `ToyFlightSimulator Shared/Physics/Debug/ColliderDebugOverlay.swift` —
  `ColliderOverlayMapping` (pure, unit-tested) + `ColliderDebugOverlay` (scene-graph work)
- [x] **File 3 (edit):** `ToyFlightSimulator Shared/Managers/InputManager.swift` —
  `DiscreteCommand.CycleColliderOverlay` + X-key mapping
- [x] **File 4 (edit):** `ToyFlightSimulator Shared/Scenes/GameScene.swift` —
  overlay ownership, `playerAircraftType`, X handler in `doUpdate`, reset in `teardownScene`
- [x] **File 5 (edit):** `ToyFlightSimulator Shared/Scenes/FlightboxWithPhysics.swift` —
  re-home hook at the end of `applyAircraftSwap`

### Registration rules this must obey (the part that's easy to get wrong)

- Overlay volumes are parented to the **aircraft**, not the scene root. `GameScene.addChild` is the only
  auto-registering path, so the overlay must call `SceneManager.Register(volume)` itself after
  `aircraft.addChild(volume)`.
- `setColor` with alpha < 1 **before** registering — `Register` resolves `objectType` (→ transparent
  collection) at registration time.
- User-initiated hide (X back to off) must use `removeFromScene()` (removeChild + Unregister) per the
  scene-graph rule; a bare `removeChild` leaves frozen ghost renderables.
- Aircraft swap: `applyAircraftSwap` calls `SceneManager.RemoveObject(prevAc)`, which unregisters the
  prev aircraft's **whole subtree** — overlay volumes included. The overlay then drops its references
  and re-applies its mode to the new aircraft. With 0.3b in place, dropping the refs is also what lets
  the detached island (old aircraft + volumes) deallocate; calling `removeFromScene()` on those stale
  refs would be redundant scene-graph surgery on an already-dead subtree — don't.
- Scene teardown (`Cmd+R` / menu reset): same story via `TeardownScene`; the overlay resets its
  bookkeeping (mode → off; the rebuilt scene starts clean).
- Hull-hidden state is exactly "the aircraft's own renderable registration is temporarily absent" (see
  the hook below), so subtree Unregister during a swap and wholesale teardown both handle it with **no
  special cases** — an unregistered node is a no-op for both.

### File 1 — SceneManager: the hull-hide hook

**Path:** `ToyFlightSimulator Shared/Managers/SceneManager.swift` *(edit — add the two methods below
inside `SceneManager`, alongside the existing `Register`/`Unregister` block)*

Depth-tested translucent volumes reveal **overfit** (portions protruding from the hull) but not
**underfit**: a volume fully inside the hull is occluded from outside, and from inside the volume its
faces are back-face-culled (global clockwise-front + cull-back), so flying the camera through doesn't
help. Since reliable visual fitting is this phase's main purpose, the overlay needs to show volumes
unoccluded — done by temporarily hiding the hull, not by a new render pass:

```swift
    // MARK: - Debug-overlay support (ColliderDebugOverlay)

    /// Temporarily removes ONE node's own renderable registration
    /// (non-recursive — children like afterburner emitters stay registered
    /// and drawn). Reuses the marker-captured add/remove machinery, so
    /// "hidden" is indistinguishable from "not currently registered": subtree
    /// Unregister (aircraft swap) and TeardownScene need no special cases —
    /// an unregistered node is a no-op for both. Update-thread only, like all
    /// registration traffic.
    static func SetRenderableHidden(_ gameObject: GameObject, _ hidden: Bool) {
        if hidden {
            // Already hidden, or never registered → no-op.
            guard let marker = gameObject.registeredObjectType else { return }
            remove(gameObject, from: marker)
            gameObject.registeredObjectType = nil
        } else if gameObject.registeredObjectType == nil {
            Register(gameObject)
            rehideExtractedSubmeshes(of: gameObject)
        }
    }

    /// F-18 caveat: un-hiding can rebuild the model's ModelData from scratch
    /// (CreateModelData), which resurrects submeshes that SubMeshGameObject
    /// registration had hidden in the parent's draw lists — that side effect
    /// is deliberately not undone on unregister, and re-registering the
    /// PARENT doesn't re-run it. So re-run the hide pass for every extracted
    /// submesh in the subtree. hideSubmeshInParentModel is idempotent (a
    /// submesh already absent from the opaque lists is skipped), so
    /// over-calling is harmless — e.g. when a second live instance of the
    /// same Model kept the ModelData alive and nothing was actually rebuilt.
    private static func rehideExtractedSubmeshes(of gameObject: GameObject) {
        for node in subtreeNodes(of: gameObject) {
            if let subMeshChild = node as? SubMeshGameObject {
                hideSubmeshInParentModel(subMeshChild)
            }
        }
    }
```

Two corrections to the earlier sketch, both simplifications:
- `hideSubmeshInParentModel` **stays `static private`** — the sketch said "exposed internally" because
  it imagined the overlay calling it, but the re-hide pass lives inside `SceneManager` itself, so
  nothing outside the type needs it.
- The subtree walk uses the existing pure `subtreeNodes(of:)` instead of the sketch's
  `children.compactMap` — extracted submeshes nested deeper than direct children (mirroring how
  `registerChildObject` recurses grandchildren) are covered too.

This must be handled now even though only the F-22 has a spec this phase: without it, toggling
hull-hide on an F-18 would double-draw its control surfaces.

### File 2 — the overlay itself

**Path:** `ToyFlightSimulator Shared/Physics/Debug/ColliderDebugOverlay.swift` *(new file; target
membership is automatic — the project uses filesystem-synchronized folders, per the 0.1 addendum)*

Two types in one file. `ColliderOverlayMapping` is the pure, Metal-free half — per the
Metal-free-test-design rule, all the shape→transform math the tests need to hit lives here
(`ColliderOverlayMappingTests`, 0.8) without constructing GameObjects. `ColliderDebugOverlay` does the
scene-graph work and is deliberately **not** unit-tested (constructing GameObjects pulls in Metal); it
also carries `logWorldDimensions`, which is step 0.5's units log. `import Foundation` is for
`String(format:)` only (simd comes in target-wide via the bridging header). Complete file:

```swift
//
//  ColliderDebugOverlay.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/27/26.
//

import Foundation

/// Maps ColliderShape (meters) onto the engine's debug meshes.
/// Child transforms are in the PARENT's model space — the parent's uniform
/// scale (1.0 for meterized aircraft) composes via the normal matrix
/// hierarchy, so the mesh-facing functions never see the scale.
/// (worldDimensions reports WORLD sizes for the 0.5 units log, so it alone
/// takes the parent scale as a parameter.)
enum ColliderOverlayMapping {
    /// ModelType.Sphere is ObjModel("sphere"), radius exactly 1.0 (measured —
    /// see meter_scale_units_research_2026-07-20.md). NOT SphereMesh, whose
    /// MDLMesh(sphereWithExtent:) call is radius-semantics and builds 2× the
    /// requested size (measured 2026-08-27; latent, pinned by MeshBoundsTests).
    static let sphereMeshRadius: Float = 1.0
    /// ModelType.Cube wraps CubeMesh(size: 1.0) = MDLMesh(boxWithExtent: [1,1,1]);
    /// box extent IS full extent (measured) → side 1.0, half-extent 0.5.
    static let cubeMeshSize: Float = 1.0

    /// Scale for a volume built from the unit meshes above. Capsules return
    /// .one: their mesh is built bespoke at exact dimensions and must never
    /// be scaled (non-uniform scale distorts the hemispherical caps).
    static func childScale(for shape: ColliderShape) -> float3 {
        switch shape {
            case .sphere(radius: let r):
                return float3(repeating: r / sphereMeshRadius)
            case .box(halfExtents: let he):
                // Per-axis; non-uniform is fine for render-only children.
                return (2.0 * he) / cubeMeshSize
            case .capsule:
                return .one
        }
    }

    /// MEASURED (2026-08-27, ModelIO on macOS 26; locked by MeshBoundsTests):
    /// MDLMesh(capsuleWithExtent: [x, y, z]) treats x/z as the RADIUS (not
    /// diameter) and y as the TOTAL cap-to-cap length — extent [2,6,2] yields
    /// bounds ±[2,3,2]; [1,2,1] degenerates to the unit sphere. So
    /// CapsuleMesh(radius:length:) builds exactly radius r, total length L,
    /// and a collider capsule (halfHeight = cylinder half-segment) maps as:
    static func capsuleMeshParams(radius: Float, halfHeight: Float) -> (radius: Float, length: Float) {
        (radius, 2 * (halfHeight + radius))
    }

    /// Axis-aligned LOCAL dimensions of a collider × the parent's uniform
    /// scale, for the units log (0.5). Deliberately not "worldSpan": it
    /// ignores rotation/translation, so it reports sizes, not extents.
    /// longestAxisMeters is the 0.5 sanity anchor (fuselage capsule → 18.9).
    static func worldDimensions(of collider: LocalCollider,
                                parentScale: Float) -> (dims: String, longestAxisMeters: Float) {
        switch collider.shape.scaled(by: parentScale) {
            case .sphere(radius: let r):
                return ("sphere ø \(formatMeters(2 * r))", 2 * r)
            case .capsule(radius: let r, halfHeight: let hh):
                let total = 2 * (hh + r)   // the same cap-to-cap span capsuleMeshParams renders
                return ("capsule ø \(formatMeters(2 * r)) × \(formatMeters(total)) end-to-end", total)
            case .box(halfExtents: let he):
                let full = 2 * he
                return ("box \(formatMeters(full.x)) × \(formatMeters(full.y)) × \(formatMeters(full.z))",
                        max(full.x, full.y, full.z))
        }
    }

    private static func formatMeters(_ value: Float) -> String {
        String(format: "%.2f m", value)
    }
}

/// Render-only volumes visualizing an aircraft's collider spec (red) and its
/// legacy physics sphere (yellow). Owns no physics state; update-thread only
/// (all scene-graph mutation happens in doUpdate — same rule as CycleCamera).
///
/// X cycles: off → volumesOverHull (translucent, catches OVERFIT via
/// protrusion) → volumesOnly (hull hidden, catches UNDERFIT — end caps and
/// silhouettes visible; A/B against volumesOverHull for placement) → off.
final class ColliderDebugOverlay {
    enum Mode {
        case off
        case volumesOverHull
        case volumesOnly

        var next: Mode {
            switch self {
                case .off:             return .volumesOverHull
                case .volumesOverHull: return .volumesOnly
                case .volumesOnly:     return .off
            }
        }
    }

    /// Research doc §2.7 colors. Alpha < 1 is load-bearing: it makes
    /// isTransparent true, which routes the volumes into the transparent
    /// collection at registration — hence setColor BEFORE Register.
    static let specColor: float4   = [1, 0, 0, 0.3]
    static let legacyColor: float4 = [1, 1, 0, 0.25]

    private(set) var mode: Mode = .off
    private var volumes: [GameObject] = []
    private weak var host: GameObject?

    /// X-key entry point (GameScene.doUpdate): advance the mode on `target`.
    func cycle(on target: GameObject, spec: [LocalCollider]) {
        assert(mode == .off || host === target,
               "[ColliderDebugOverlay] host changed without hostWasReplaced — swap wiring is missing")
        apply(mode.next, on: target, spec: spec)
    }

    /// Aircraft swap (FlightboxWithPhysics.applyAircraftSwap): the old host's
    /// subtree was already detached AND unregistered wholesale by
    /// SceneManager.RemoveObject — our volumes included, and a hidden hull
    /// needed no special case ("hidden" is just "not registered"). Dropping
    /// our refs is what lets the detached island (old aircraft + volumes)
    /// deallocate (0.3b); calling removeFromScene() on the stale refs would
    /// be redundant scene-graph surgery on an already-dead subtree — don't.
    /// Then re-apply the surviving mode to the new host.
    func hostWasReplaced(by newTarget: GameObject?, spec: [LocalCollider]) {
        let previousMode = mode
        reset()
        if previousMode != .off, let newTarget {
            apply(previousMode, on: newTarget, spec: spec)
        }
    }

    /// Bookkeeping-only clear — no scene-graph calls. Callers guarantee the
    /// volumes' subtree is already gone (swap) or being torn down wholesale
    /// (teardownScene).
    func reset() {
        volumes.removeAll()
        host = nil
        mode = .off
    }

    /// Single mutation point for mode transitions. Hull hidden-ness is
    /// applied LAST on the way in and FIRST on the way out, so no partial
    /// transition can strand a hidden aircraft.
    private func apply(_ newMode: Mode, on target: GameObject, spec: [LocalCollider]) {
        guard newMode != mode else { return }

        if newMode == .off {
            SceneManager.SetRenderableHidden(target, false)   // un-hide FIRST
            for volume in volumes {
                // Per the scene-graph rule: removeChild + Unregister. A bare
                // removeChild would leave frozen ghost renderables.
                volume.removeFromScene()
            }
            reset()
            return
        }

        if mode == .off {   // entering: build, attach, register, log
            host = target
            buildVolumes(on: target, spec: spec)
            logWorldDimensions(spec, on: target)
        }
        mode = newMode

        // LAST (see doc comment above):
        SceneManager.SetRenderableHidden(target, newMode == .volumesOnly)
    }

    /// One volume per enabled spec collider, plus the yellow legacy-sphere
    /// ghost. Ordering rules (see "Registration rules" above): setColor
    /// BEFORE Register; target.addChild — plain Node reparenting, because
    /// GameScene.addChild is the only auto-registering path and the volumes
    /// hang off the aircraft, not the scene root — THEN SceneManager.Register.
    private func buildVolumes(on target: GameObject, spec: [LocalCollider]) {
        if spec.isEmpty {
            print("[ColliderDebugOverlay] no compound spec for \(target.getName()) yet — legacy sphere only")
        }

        for collider in spec where collider.isEnabled {
            let volume = makeVolume(for: collider.shape, name: "ColliderOverlay_\(collider.name)")
            volume.setColor(Self.specColor)
            volume.setPosition(collider.localPosition)
            volume.setRotation(collider.localRotation)
            volume.setScale(ColliderOverlayMapping.childScale(for: collider.shape))
            attach(volume, to: target)
        }

        // The legacy physics sphere sits on the body origin (SphereRigidBody
        // has no local offset), so the ghost keeps the default zero position.
        // collisionRadius is WORLD meters and the ghost is a CHILD of the
        // aircraft, so the parent's scale divides back out — 1.0 for
        // meterized aircraft, kept explicit so a deliberately scaled aircraft
        // still ghosts correctly.
        if let sphereBody = target.rigidBody as? SphereRigidBody {
            let ghost = GameObject(name: "ColliderOverlay_legacySphere", modelType: .Sphere)
            ghost.setColor(Self.legacyColor)
            ghost.setScale(sphereBody.collisionRadius /
                           (ColliderOverlayMapping.sphereMeshRadius * target.uniformScale))
            attach(ghost, to: target)
        }
    }

    private func attach(_ volume: GameObject, to target: GameObject) {
        target.addChild(volume)
        SceneManager.Register(volume)
        volumes.append(volume)
    }

    /// Sphere/box volumes reuse the unit library models; capsules get a
    /// bespoke mesh at exact dimensions through GameObject(name:model:)
    /// (0.3). Mesh construction on the update thread is established practice
    /// — scene resets rebuild whole scenes there.
    private func makeVolume(for shape: ColliderShape, name: String) -> GameObject {
        switch shape {
            case .sphere:
                // OBJ sphere, radius exactly 1.0 — never SphereMesh (2× quirk).
                return GameObject(name: name, modelType: .Sphere)
            case .box:
                return GameObject(name: name, modelType: .Cube)
            case .capsule(radius: let radius, halfHeight: let halfHeight):
                let p = ColliderOverlayMapping.capsuleMeshParams(radius: radius, halfHeight: halfHeight)
                let mesh = CapsuleMesh(radius: p.radius, length: p.length)
                return GameObject(name: name, model: Model(name: name, mesh: mesh))
        }
    }

    /// Step 0.5's units log, printed on every overlay show. Sanity anchor:
    /// the fuselage capsule must read ≈ 18.90 m at scale 1.0 (real F-22:
    /// 18.92 m).
    private func logWorldDimensions(_ spec: [LocalCollider], on target: GameObject) {
        guard !spec.isEmpty else { return }
        let scale = target.uniformScale
        print("[ColliderDebugOverlay] \(target.getName()) collider world dimensions (uniformScale \(scale)):")
        for collider in spec where collider.isEnabled {
            let (dims, _) = ColliderOverlayMapping.worldDimensions(of: collider, parentScale: scale)
            print("  \(collider.name): \(dims)")
        }
        if let sphereBody = target.rigidBody as? SphereRigidBody {
            print("  legacy sphere: ø \(String(format: "%.2f m", 2 * sphereBody.collisionRadius)) (world)")
        }
    }
}
```

Implementation notes, tied to the registration rules above:
- `cycle`'s assert pins the wiring invariant: a host change while visible must arrive via
  `hostWasReplaced`, never via `cycle` — otherwise volumes would be attached to a second aircraft
  while the first still holds the old set.
- The loop applies `childScale` uniformly; for capsules it returns `.one`, so the bespoke mesh is
  never scaled and the loop needs no special case.
- The mode-`.off` branch un-hides against `target` (== `host` by the assert) *before* touching the
  volumes, mirroring "hull state LAST" on the way in — whichever direction a future edit bails out
  of, the aircraft is never left hidden.
- The scene-teardown path never reaches `apply`: `GameScene.teardownScene` calls bare `reset()`
  because the whole subtree (and every batched collection) is being dropped wholesale anyway.

### File 3 — InputManager: the X key

**Path:** `ToyFlightSimulator Shared/Managers/InputManager.swift` *(edit — two touch points)*

Key: **X** (free; taken today: p l space n m j f g c w a s d q e y h arrows, Cmd+R). Keyboard-only —
no controller/joystick mapping (debug affordance); `HasDiscreteCommandDebounced` already skips devices
with no mapping for a command, so nothing else changes.

The `DiscreteCommand` enum gains one case, grouped with the other Toggle*/Cycle* commands:

```swift
enum DiscreteCommand {
    case FireMissileAIM9
    case FireMissileAIM120
    case DropBomb
    case JettisonFuelTank

    case ResetLoadout

    case ToggleFlaps
    case ToggleGear
    case CycleCamera
    /// Collider debug overlay: off → volumesOverHull → volumesOnly → off.
    case CycleColliderOverlay

    case Pause
    case ClickSelect
}
```

and `keyboardMappingsDiscrete` gains one entry:

```swift
    nonisolated(unsafe) private static var keyboardMappingsDiscrete: [DiscreteCommand: Keycodes] = [
        .Pause: .p,
        .ResetLoadout: .l,
        .FireMissileAIM9: .space,
        .FireMissileAIM120: .n,
        .DropBomb: .m,
        .JettisonFuelTank: .j,
        .ToggleFlaps: .f,
        .ToggleGear: .g,
        .CycleCamera: .c,
        .CycleColliderOverlay: .x
    ]
```

### File 4 — GameScene: ownership, X handler, teardown

**Path:** `ToyFlightSimulator Shared/Scenes/GameScene.swift` *(edit — three touch points)*

The base class owns the overlay so any scene that sets `playerAircraft` + `playerAircraftType` gets
the X cycle for free. The handler runs on the **update thread** via the `CycleCamera` debounce pattern
in `doUpdate` — NOT in `MacGameUIView`'s main-thread timer (scene-graph mutation must stay on the
update thread).

Properties, next to the existing `playerAircraft`:

```swift
    internal var playerAircraft: Aircraft? = nil

    /// Keys the collider overlay's spec lookup. Scenes that assign
    /// playerAircraft set this alongside it (FlightboxWithPhysics: on every
    /// swap). nil ⇒ the X key is a no-op in this scene.
    internal var playerAircraftType: AircraftType? = nil

    /// Debug collider overlay (X key) — base-class-owned so every
    /// player-aircraft scene gets the cycle without per-scene wiring.
    let colliderOverlay = ColliderDebugOverlay()
```

In `doUpdate()`, next to the `CycleCamera` handler:

```swift
        InputManager.HasDiscreteCommandDebounced(command: .CycleColliderOverlay) {
            // Update-thread scene-graph mutation, same rule as CycleCamera.
            guard let aircraft = playerAircraft, let type = playerAircraftType else { return }
            colliderOverlay.cycle(on: aircraft, spec: AircraftColliderSpec.spec(for: type))
        }
```

`teardownScene()` gains its final line:

```swift
    func teardownScene() {
        SceneManager.Paused = true
        LightManager.RemoveAllLights()
        CameraManager.RemoveAllCameras()
        removeAllChildren()
        // The subtree is going away wholesale (SceneManager.TeardownScene
        // clears every batched collection right after this returns) —
        // bookkeeping-only reset, no scene-graph surgery on the dying
        // subtree. With 0.3b, dropping these refs is what lets the detached
        // volumes deallocate. The rebuilt scene starts with the overlay off.
        colliderOverlay.reset()
    }
```

### File 5 — FlightboxWithPhysics: the swap hook

**Path:** `ToyFlightSimulator Shared/Scenes/FlightboxWithPhysics.swift` *(edit — end of
`applyAircraftSwap(_:installEntities:)`)*

Two lines after the existing `addChild(playerAircraft)` — the order matters: `hostWasReplaced`
re-registers volumes on the new aircraft and may re-hide its hull, so the aircraft must already be in
the scene graph. Existing tail of the method shown for placement:

```swift
            if let prevAc {
                SceneManager.RemoveObject(prevAc)
            }

            addChild(playerAircraft)

            // Overlay survives the swap in whatever mode it was in.
            // RemoveObject above already detached + unregistered the old
            // subtree (overlay volumes included); hostWasReplaced drops the
            // stale refs and re-applies the mode to the new aircraft.
            // buildScene's initial call runs with the overlay off, so this
            // reduces to bookkeeping there.
            playerAircraftType = aircraft
            colliderOverlay.hostWasReplaced(by: playerAircraft,
                                            spec: AircraftColliderSpec.spec(for: aircraft))
```

A depth-disabled x-ray/wireframe overlay *pass* (volumes visible through the hull simultaneously) stays
deferred — it's a genuine render-path change across four renderers; the two visible modes cover both
failure directions for tuning.

> **Addendum (2026-08-28) — landed.** All five files are in, macOS Debug build green, and the X cycle
> was verified visually in the running game (FlightboxWithPhysics). Notes from the landing:
> 1. **Naming deviation from the listing above (adopted, listing updated):** the cube constant is
>    `cubeMeshSize`, not `cubeMeshSide` — it mirrors the `CubeMesh(size:)` parameter it documents.
> 2. **Ordering deviation:** 0.4 landed before 0.6/0.7 (and with 0.3b's tests still owed). Allowed —
>    the overlay and parity tracks are declared independent; 0.3b's *code* (the part 0.4's lifecycle
>    rules assume) landed in the same commit.
> 3. **Extra fix:** `Mesh.parentModel` → `weak` (see the 0.3b addendum) so the bespoke capsule volume's
>    one-off Model actually deallocates when the overlay is cycled off.
> 4. The first landing had `logWorldDimensions` computing dimensions but not printing them; the print
>    statements were filled in during review. **0.5's in-app anchor check (fuselage ≈ 18.9 m in the
>    log) has therefore not run yet** — it needs one more in-app X press.
> 5. The full exit-criterion-1 checklist (swap while visible, Cmd+R while visible, renderer switch,
>    ghost-free repeated cycling) is still open — only the basic cycle has been eyeballed so far.

## Step 0.5 — Units contract: sanity anchor + mesh-mapping regression

**Contract (post-meterization):** collider dimensions and offsets are authored in post-import
engine-local units = **meters** (import folds `realWorldLength / nativeLength` into the basis transform;
`ModelLibrary` registers the CGTrader F-22 at 18.92 m). `Node.uniformScale` remains in the world-collider
math as an optional gameplay multiplier — every meterized aircraft runs at 1.0, and the debug assert
(uniformity) plus Phase A's `scaled(by:)` path keep colliders correct if a scene ever scales an aircraft
deliberately. The old "model units × 3.0 = world meters" contract is dead; nothing may reintroduce it.

- [ ] `logWorldDimensions` (the code ships inside 0.4's `ColliderDebugOverlay`; this checkbox is the
  in-app verification) prints, on every overlay show, one line per collider: name, shape,
  world-space dimensions (spec meters × `uniformScale`). **Sanity anchor:** fuselage capsule total
  = 2·(8.1 + 1.35)·1.0 = **18.9 m** against the real jet's 18.92 m. If the printed number and the
  on-screen capsule disagree with the model's visible nose-tail span, the spec numbers (or the import
  meterization) are wrong — fix before Phase A consumes them.
- [x] **Capsule mesh mapping settled by measurement, not by eye** *(2026-08-27)*:
  `MDLMesh(capsuleWithExtent: [x, y, z])` → x/z = radius, y = total cap-to-cap length (extent [2,6,2]
  bounds ±[2,3,2]; [1,5,1] → ±[1,2.5,1]; [1,2,1] → unit sphere). Box extent is full-extent
  (boxWithExtent [1,2,3] → ±[0.5,1,1.5]); sphere extent is radius-semantics (sphereWithExtent [2,2,2] →
  radius 2 — the latent `SphereMesh(radius:)` 2× quirk; the overlay uses the OBJ `.Sphere` model,
  radius 1.0, and must never use `SphereMesh`). The verdict is encoded in
  `ColliderOverlayMapping.capsuleMeshParams` = `(radius, 2·(halfHeight + radius))` and locked by a
  CPU-side bounding-box regression test (0.8 `MeshBoundsTests` — constructs `MDLMesh` with a nil
  allocator, no Metal, and asserts the three shapes' bounds), replacing the previously planned one-time
  visual calibration.
- [x] `Node.uniformScale` assertion active in debug builds (step 0.3) — this *is* the enforcement of the
  contract; Codex's full `assetToBodyMeters` transform stays deferred per combined doc §4.1.

## Step 0.6 — Metal-free parity enabler: explicit detached bodies (behavior-neutral)

*(Redesigned 2026-08-27 — the original "relax inits to `GameObject?` + fallback storage" would have
silently changed tested behavior: `RigidBodyTests.rigidBodyToleratesNilGameObject` pins that an attached
body whose weak `gameObject` was released answers `getPosition() == .zero` and treats `setPosition` as a
no-op. Routing those through fallback storage flips both expectations and erases the distinction between
"intentional standalone body" and "attached body whose object died unexpectedly".)*

- [ ] `Physics/World/RigidBody.swift`: explicit standalone mode

```swift
/// Standalone-mode storage (parity-harness bodies built with init(detachedAt:)).
/// Attached bodies never touch this: a released weak gameObject keeps the
/// tested .zero / no-op fallbacks — that state is a bug signal, not a mode.
private let isStandalone: Bool
private var standalonePosition: float3 = .zero

// Existing internal init(gameObject: GameObject?, ...) unchanged (isStandalone = false).

/// Parity-harness bodies: the REAL physics classes, no GameObject, no Metal.
/// Internal — production code constructs attached bodies only.
internal init(detachedAt position: float3, collisionShape: CollisionShape = .Sphere, ...) {
    // same stored-property init, gameObject = nil, isStandalone = true,
    // standalonePosition = position, no back-registration
}

func setPosition(_ position: float3) {
    if isStandalone { standalonePosition = position }
    else { gameObject?.setPosition(position) }
}

func getPosition() -> float3 {
    isStandalone ? standalonePosition : (gameObject?.getPosition() ?? .zero)
}
```

- [ ] `Physics/World/BasicRigidBodies.swift`: detached convenience inits on the `final` subclasses
  (production inits keep their **non-optional** `GameObject`):

```swift
// SphereRigidBody
init(detachedAt position: float3, collisionRadius: Float = 1.0) {
    super.init(detachedAt: position)
    self.collisionRadius = collisionRadius
    self.collisionShape = .Sphere
}
// PlaneRigidBody
init(detachedAt position: float3, collisionNormal: float3 = [0, 1, 0]) {
    super.init(detachedAt: position)
    self.collisionNormal = collisionNormal.normalize()
    self.collisionShape = .Plane
}
```

Why this is required: the parity harness must drive the **real collision path** (`PhysicsWorld.collided`
/ `getCollisionData` force-cast to the `final` classes `SphereRigidBody`/`PlaneRigidBody`, so
`TestRigidBody` can't traverse it), and it must do so Metal-free (constructing any `GameObject` pulls in
`Assets.Models` → Metal; see the project's Metal-free-test-design rule). With detached bodies:
`SphereRigidBody.getAABB()` reads `getPosition()` + `collisionRadius`, `PlaneRigidBody.getAABB()` reads
`getPosition()` — both work on standalone storage, so broad phase, narrow phase, response, and both
solvers all run without a scene. (`getState()` still returns nil for standalone bodies — it needs the
node's basis vectors; the harness exercises collision/solver paths, not flight models.) Existing
`PhysicsWorldSmokeTests` (GameObject-backed) keep guarding the attached path; the released-weak tests
keep guarding the fallbacks.

## Step 0.7 — Parity harness + golden baselines

- [ ] `ToyFlightSimulatorTests/TestSupport/SeededRandom.swift` — seedable `SplitMix64: RandomNumberGenerator`, **plus direct Float derivation** (Swift's default RNG is unseedable, and `Float.random(in:using:)`'s u64→Float mapping is a stdlib implementation detail — goldens outlive toolchains, so the harness owns the mapping):

```swift
struct SplitMix64: RandomNumberGenerator { ... next() -> UInt64 ... }

extension SplitMix64 {
    /// Uniform in [0, 1): top 24 bits → Float. Bypasses Float.random(in:using:).
    mutating func unitFloat() -> Float { Float(next() >> 40) * 0x1p-24 }
    mutating func float(in range: ClosedRange<Float>) -> Float {
        range.lowerBound + (range.upperBound - range.lowerBound) * unitFloat()
    }
}
```

- [ ] `ToyFlightSimulatorTests/Physics/PhysicsParityTests.swift` — scenarios + runner + comparisons (`.tags(.physics)`, Swift Testing)
- [ ] `ToyFlightSimulatorTests/Physics/Baselines/*.json` — committed goldens (test-target membership irrelevant; loaded via `#filePath`)

### What the harness is for, and how Phase A verifies against it

Record the **current** engine's trajectories now. Phase A then lands in **two separately verified
commits**:

1. **A-routing** (behavior-preserving): narrow-phase routing / "one narrow phase per pair" / plumbing
   refactors. **Must match every golden unchanged** (within tolerance). Any diff = a routing bug.
2. **A-response** (deliberate behavior change): rest-latch removal, impulse-discard removal, restitution
   velocity threshold, approach guard, slop+β positional correction (β ≈ 0.2, slop ≈ 5 mm — combined doc
   §3.3), ×2-correction fix. **Every scenario diverges from its first contact onward** — positional
   correction changes the post-contact state in all branches, dynamic/dynamic included. Verification =
   flip the characterization asserts deliberately + assert the semantic invariants below + regenerate
   goldens via `TFS_REGEN_PHYSICS_BASELINES=1` with the diff reviewed like code.

Scenario table (all Metal-free via 0.6 detached bodies; fixed seeds, e.g. `0xF22_0001` per scenario, live
next to the definitions; cluster/grid run broad phase **on** because response applies in pair order —
pair *ordering* is part of the locked-in behavior):

| Scenario | Setup | Solver / broad phase | Golden steps @ dt | A-response expectation (A-routing must match ALL goldens) |
|---|---|---|---|---|
| `single_bounce_verlet` | sphere r=0.5, m=1, e=0.9, dropped from y=5 onto y=0 plane (e=0.9) | HeckerVerlet / off | 300 @ 1/60 | identical through free fall; diverges at first ground contact (correction + threshold). Semantics: apex sequence decreasing, settles ≤ slop, `shouldApplyGravity` stays true |
| `single_bounce_euler` | same | NaiveEuler / off | 300 @ 1/60 | same |
| `rest_latch` | sphere r=0.5, e=0.2, dropped from y=3 | HeckerVerlet / off | 600 @ 1/60 | **changes wholesale** — documents the latch |
| `head_on_pair` | two spheres r=0.5, m=1, e=1, closing at ±5 m/s on X | HeckerVerlet / off | 120 @ 1/60 | identical until impact; **diverges at first contact** (pen/2-each teleport → slop+β correction). Semantics: e=1 velocity swap, exact symmetry \|vA\|=\|vB\| preserved |
| `ball_cluster_16` | 16 spheres r=0.4, m=1, e=0.9, seeded positions in [-7,7]×[1,10]×[-7,0] (BallPhysicsScene distribution), plane e=1 | HeckerVerlet / **on** | golden **180** @ 1/60; invariant run 600 | full regolden expected |
| `stress_grid_50` | 50 spheres r=0.3, e=0.8, grid + seeded jitter + seeded initial velocities (PhysicsStressTestScene distribution), plane e=0.9 | HeckerVerlet / **on** | golden **120** @ 1/60; invariant run 600 | full regolden expected |

**Chaos policy:** multi-body contact ordering amplifies float noise exponentially, so the cluster/stress
goldens cover only the first seconds (above), and the remainder of each 600-step run asserts **invariants
that hold for current AND Phase A behavior**: every position/velocity finite; no tunneling
(y ≥ plane − r − ε for every sphere); speed bounded by a generous initial+gravity budget. Invariants are
asserted from day one — they're the part of the contract that survives regoldens.

### Harness pseudocode

```swift
struct PhysicsBaseline: Codable {
    struct BodyTrack: Codable {
        var samples: [[Float]]        // [x,y,z] every `sampleEvery` steps (t=0 included)
        var finalVelocity: [Float]
        var finalShouldApplyGravity: Bool   // makes the rest-latch visible in the data
    }
    var scenario: String, solver: String, useBroadPhase: Bool
    var dt: Float, steps: Int, sampleEvery: Int
    var tracks: [BodyTrack]           // index-aligned with scenario body order
}

enum ParityRunner {
    static func run(_ scenario: ParityScenario) -> PhysicsBaseline {
        let (world, bodies) = scenario.build()        // SphereRigidBody(detachedAt:) / PlaneRigidBody(detachedAt:)
        // step, sample every sampleEvery, run invariant checks every step past the golden window
    }

    /// Baselines live in-repo next to the tests; #filePath keeps this working
    /// both locally and on the CI checkout.
    static var baselinesDir: URL { ... }

    /// TFS_REGEN_PHYSICS_BASELINES=1 (mirrors TFS_REGEN_THUMBNAILS) rewrites
    /// the golden instead of comparing, then fails the test with a "re-run
    /// without the flag" message so a regen can never silently pass CI.
    static func assertMatchesGolden(_ fresh: PhysicsBaseline, named: String) {
        // compare metadata exactly; samples/velocities with tolerance 1e-4
        // on mismatch: report first divergent (body, step) + values   // makes Phase A diffs readable
    }
}

@Suite("Physics parity", .tags(.physics))
struct PhysicsParityTests {
    @Test(arguments: ParityScenario.all)
    func matchesGolden(_ s: ParityScenario) { ... }

    @Test func harnessIsDeterministic() {
        // Two fresh runs of the seeded cluster must agree bit-for-bit —
        // validates the harness itself (seeding, no hidden global state).
        #expect(ParityRunner.run(.ballCluster16) == ParityRunner.run(.ballCluster16))
    }

    @Test("CURRENT behavior: rest latch freezes gravity (Phase A flips this)")
    func restLatchCharacterization() {
        let result = ParityRunner.run(.restLatch)
        #expect(result.tracks[0].finalShouldApplyGravity == false)   // the one-way latch, documented
        #expect(velocity ≈ .zero)
    }
}
```

Tolerance note: same-machine reruns should be exact; 1e-4 absorbs toolchain/FMA variance between local
and CI for the short/simple scenarios. If CI diverges beyond that on the cluster/stress goldens even at
their shortened windows, shorten further or regen on CI's toolchain and note it in the Changelog.
Parameterized cases run concurrently in-process (see the note under Verification commands) — each
scenario builds its own `PhysicsWorld` and bodies, and nothing in the harness may touch process-wide
state.

## Step 0.8 — Unit tests (Metal-free, Swift Testing, `.physics` / `.utils` / `.gameObjects` tags)

- [ ] `ColliderShapeTests`: `scaled(by:)` for all three shapes; `hasFinitePositiveDimensions` (rejects
  NaN/∞/negative, accepts halfHeight 0); `LocalCollider` defaults (identity rotation, `.airframe`, enabled)
- [ ] `AircraftColliderSpecTests`: f22_cgtrader returns 3 enabled colliders with expected names/groups
  and **unique names**; all dimensions finite/positive; unauthored types return `[]` (exhaustive switch —
  compile-time enforced, test documents it); **fuselage total length = 2·(8.1+1.35) ≈ 18.9 m at scale
  1.0** (the sanity anchor, as a test so it can't rot)
- [ ] `MeshBoundsTests` (`.utils`): pins measured ModelIO semantics with nil-allocator `MDLMesh` —
  capsule extent [1,5,1] → bounds ±[1,2.5,1] (x/z=radius, y=total); box [1,2,3] → ±[0.5,1,1.5]
  (full extent); sphere [2,2,2] → ±2 (radius semantics — documents the latent `SphereMesh` 2× quirk)
- [ ] `ColliderOverlayMappingTests`: sphere child scale = radius; box child scale = 2·halfExtents
  (non-uniform); capsule child scale = 1 and `capsuleMeshParams(radius:halfHeight:)` =
  `(radius, 2·(halfHeight + radius))`; `worldDimensions` numbers
- [ ] `NodeOwnershipTests` (0.3b): weak-parent deallocation suite as specified there
- [ ] `NodeTests` additions (XCTest, existing file): direct `rotationMatrix =` assignment dirties the
  cached local/world matrices (modelMatrix reflects it with no other setter call); `setRotation(_ q:)`
  equivalent to `setRotation(angle:axis:)` for the same rotation and fires the same dirty path — pins
  the 0.3 root fix and the F18 order-dependence repair
- [ ] `RigidBody` detached-mode tests (in existing `RigidBodyTests`): `init(detachedAt:)` set/get
  round-trips; detached `SphereRigidBody`/`PlaneRigidBody` AABBs correct; **existing attached-path and
  released-weak tests unchanged and green** (that's the point of the redesign)
- [ ] `PhysicsParityTests` as in step 0.7 (determinism + goldens + invariants + rest-latch characterization)
- [ ] Overlay class itself: **not** unit-tested (constructs GameObjects → Metal; per project rule the
  logic lives in the pure mapping enum instead). Manual verification checklist below.

## Phase 0 exit criteria

1. - [ ] **Overlay works in-app** (manual, FlightboxWithPhysics, macOS): X cycles off → volumes-over-hull
   → volumes-only → off; volumes-only hides the F-22 hull but keeps afterburners visible; repeated
   cycling leaves no ghost renderables and no stranded-hidden aircraft; overlay survives: aircraft swap
   while visible (re-attaches to the new aircraft in the same mode), Cmd+R reset while visible (comes
   back clean on next X), renderer switch.
2. - [ ] **Spec numbers eyeballed and committed**: overfit checked in volumes-over-hull (nothing
   protrudes that shouldn't), underfit checked in volumes-only (capsule end caps reach nose and tail,
   wings box reaches the wingtips, empennage box covers the tails — A/B cycling against the hull for
   placement) — tuned values recorded in `AircraftColliderSpec` with overlay screenshots in
   `debugging/screenshots/`.
3. - [ ] **Units anchor holds**: overlay log prints fuselage total ≈ **18.9 m at scale 1.0** (vs 18.92 m
   real F-22); `MeshBoundsTests` + `ColliderOverlayMappingTests` green (the measured capsule mapping
   can't rot).
4. - [ ] **Parity baselines committed**: all scenario goldens recorded, parity suite green against them
   on a clean re-run (determinism + invariants included), runnable Metal-free via the corrected
   `build-for-testing` / `test-without-building` pattern.
5. - [ ] **No unintended behavior change**: full existing test suite green in CI; `PhysicsWorldSmokeTests`
   (attached-body path) untouched and green; game plays identically with the overlay off. The one
   deliberate change is 0.3b's ownership fix — detached subtrees (old aircraft after a swap/reset) now
   deallocate, pinned by `NodeOwnershipTests`.

**Implementation order within Phase 0:** 0.1 ✓ → 0.2 ✓(re-authored) → 0.3 ✓ → 0.3b (code ✓, tests
owed) → 0.4 ✓ → 0.5 (in-app anchor check pending) → **0.6** → **0.7** (baselines locked before any
later phase touches physics) → 0.8 interleaved throughout. 0.3b preceded the overlay because 0.4's
lifecycle rules assume it; the overlay steps (0.4/0.5) landed before the parity steps (0.6/0.7) — the
two tracks are independent and either order was allowed; both before Phase A starts.

---

# Pre-Phase-A design corrections (recorded 2026-08-27, before Phase A is planned)

Corrections to the declared source-of-truth design (combined doc §3.4/§4.2 sketches) that Phase A's plan
section must adopt when it's appended:

1. **No static step/scratch state.** The §4.2 sketch declares
   `PhysicsWorld.currentStepIndex` as `static` and keys per-step scratch caches off it. Step indices,
   contact scratch arrays, and world-collider scratch must be **per-`PhysicsWorld` instance** state:
   parameterized Swift Testing parity cases run concurrently in one process (serial
   `-parallel-testing-enabled NO` does not serialize in-process Swift Testing), so multiple live
   `PhysicsWorld`s are the *norm* in tests, not an edge case.
2. **World-collider cache invalidation.** A once-per-step world-pose snapshot goes stale the moment
   response positional correction moves a body mid-step (any multi-contact step). Either recompute the
   corrected body's world colliders after each positional correction, or version the cache per body
   (bump on `setPosition`) — decide in Phase A planning; a blanket once-per-step cache is wrong.
3. **World-transform contract.** The physics path composes poses from `getPosition()` /
   `getRotationMatrix()`, which are **local**. That's valid only while rigid-body owners are scene-root
   children (true for every current owner). Phase A must either build world colliders from the actual
   world transform (`getWorldPosition()` + world rotation) or debug-assert
   `gameObject.parent is GameScene` when a body with colliders is registered. The assert is the cheap
   Phase A answer; revisit if bodies ever nest.
4. **Two-commit verification split** (defined in 0.7): A-routing must match the Phase 0 goldens exactly;
   A-response regoldens with reviewed diffs + semantic asserts. No single commit may both refactor
   routing and change response behavior.

---

*(Phase A plan will be appended here.)*
