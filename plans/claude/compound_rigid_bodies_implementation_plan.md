# Compound Rigid Bodies — Implementation Plan (append-only)

**Started:** 2026-07-19
**Source of truth for design decisions:** `research/claude/compound_rigid_bodies_research_combined.md` (§4 is the phase outline this plan executes; §2–§3 hold the argued verdicts).
**Supporting docs:** `research/claude/compound_rigid_bodies_research_2026-07-14.md` (type definitions §2.3, F-22 spec §2.3, overlay sketch §2.7), `research/codex/compound_rigid_bodies_and_articulated_landing_gear_research_2026-07-14.md`.

## How this document works

- **Append-only by phase.** Each phase gets planned here in detail *before* implementation, in its own section. New phases are appended at the end; earlier phase sections are never rewritten.
- **Corrections** to an already-written section go in a dated `> **Addendum (YYYY-MM-DD):**` block appended to that section — the original text stays.
- **Checkboxes** (`- [ ]`) are the one exception to append-only: they get ticked in place as steps land.
- Every step cites the research-doc section it implements so the "why" is one hop away.

**Verification commands** (from CLAUDE.md; the local full `xcodebuild test` hangs at app-host launch — use the scoped pattern):

```bash
# Build
xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" \
  -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Scoped logic-suite run after building (Metal-free suites only; CI runs the full suite)
xcodebuild test-without-building -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" \
  -sdk macosx -configuration Debug -only-testing:"ToyFlightSimulatorTests/<SuiteName>" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

---

# Phase 0 — Debug overlay, units contract, parity harness

Implements combined doc **§4.1**. Everything in this phase is **behavior-neutral for the running game**: no physics semantics change, no render-path change. Phase 0 exists so that (a) every collider/strut number in Phases A/B can be eyeballed against the real model before physics consumes it, and (b) Phase A's response-path rewrite diffs against a recorded baseline instead of against memory.

**Deliverables:**
1. A translucent collider overlay on the player aircraft, toggled with the **X** key, showing the proposed compound spec (red) next to the legacy 2 m physics sphere (yellow).
2. The units contract (model units × uniform node scale = world meters) enforced by a debug assertion and sanity-checked against the CGTrader F-22.
3. A Metal-free, deterministic trajectory-capture harness with committed golden baselines for the current physics behavior.

**Non-goals (deferred):** `WorldCollider` + narrow phase (Phase A), any `RigidBody.colliders` storage (Phase A), strut visualization as `Line`s (Phase B, when `SuspensionStrut` exists), iOS menu toggle for the overlay (X-key macOS only for now), wireframe/depth-ignoring overlay rendering (Codex's ring-buffered version — later, if ever).

### Deviations from the research docs (deliberate, small)

| Deviation | Why |
|---|---|
| The **data-only half of A1** (`ColliderShape`, `ColliderGroup`, `LocalCollider`) is pulled forward into Phase 0 | The overlay's entire purpose is rendering *proposed specs* before physics exists; defining the real vocabulary now means the overlay and specs are written once, against the final types. Phase A's A1 shrinks to: add `WorldCollider`, the reserved `material` field, and the `RigidBody` integration. |
| `SphereRigidBody`/`PlaneRigidBody` inits relax to `GameObject?` + `RigidBody` gains detached-position storage | Not in either research doc. Required for a Metal-free parity harness: the current narrow phase force-casts to these `final` classes (`PhysicsWorld.collided`), so `TestRigidBody` doubles cannot traverse the collision path, and both inits currently demand a non-optional `GameObject` (→ Metal). Behavior-neutral: every production call site passes non-nil. |
| Overlay also draws the **legacy collision sphere** (yellow) | One glance shows what the compound replaces — directly motivates spec tuning. Costs ~10 lines. |
| Struts-as-`Line`s omitted from the Phase 0 overlay | Combined doc §4.1 mentions them, but strut specs are Phase B data (`SuspensionStrut`); drawing them before the type exists would invent throwaway structure. The overlay grows a strut layer in Phase B. |

---

## Step 0.1 — Collider vocabulary, data-only

- [x] New file `ToyFlightSimulator Shared/Physics/Collision/ColliderShape.swift` (add to all three app targets, like the rest of Shared)

Taken verbatim from the original research doc §2.3, minus `WorldCollider` (Phase A — it's narrow-phase output, nothing in Phase 0 consumes it) and minus the reserved `material` field (Phase A):

```swift
import simd

/// Convex collision primitives, in the cost order every surveyed engine
/// documents (sphere < capsule < box). Dimensions are authored in the owning
/// model's local space and scaled by the GameObject's uniform scale when
/// world-space colliders are computed.
enum ColliderShape: Equatable {
    /// Ball of the given radius.
    case sphere(radius: Float)
    /// Segment along local Y from -halfHeight to +halfHeight, inflated by
    /// radius (total height = 2·(halfHeight + radius)). Orient with the
    /// collider's localRotation (e.g. Y→Z for a fuselage along +Z).
    case capsule(radius: Float, halfHeight: Float)
    /// Oriented box with the given half extents.
    case box(halfExtents: float3)

    func scaled(by s: Float) -> ColliderShape {
        switch self {
            case .sphere(let r):         return .sphere(radius: r * s)
            case .capsule(let r, let hh): return .capsule(radius: r * s, halfHeight: hh * s)
            case .box(let he):           return .box(halfExtents: he * s)
        }
    }
}

/// Which functional part of the object a collider represents, so contact
/// consumers (crash detection, landing logic) can tell a wheel strike from
/// a belly strike without geometry queries.
enum ColliderGroup {
    case airframe      // fuselage/wings/tail — contact here means structural impact
    case landingGear   // reserved for future wheel colliders (suspension covers ground contact)
    case structure     // buildings, towers, scenery
}

/// One primitive rigidly attached to a body at a local offset — the per-child
/// entry of a compound (Bullet btCompoundShape child, Unity child collider,
/// Jolt compound sub-shape).
struct LocalCollider {
    var name: String
    var shape: ColliderShape
    var localPosition: float3
    var localRotation: simd_quatf
    var group: ColliderGroup
    /// Cheap runtime on/off (Jolt MutableCompoundShape's role). Disabled
    /// colliders generate no contacts, don't contribute to the AABB, and the
    /// overlay skips them.
    var isEnabled: Bool

    init(name: String,
         shape: ColliderShape,
         localPosition: float3 = .zero,
         localRotation: simd_quatf = simd_quatf(real: 1, imag: .zero),
         group: ColliderGroup = .airframe,
         isEnabled: Bool = true) { ... }
}
```

Phase A will append to this file (`WorldCollider`, `material`), not restructure it.

> **Addendum (2026-07-19):** Step 0.1 is implemented, with one improvement over the pseudocode above: a documented `simd_quatf.identity` constant now lives in `Math/Transform.swift` (alongside the existing `float4x4.identity`), and `LocalCollider.localRotation`'s default reads `.identity` instead of the raw `simd_quatf(real: 1, imag: .zero)` spelling — which existed only because simd ships no identity-quaternion constant. (Related footgun, documented on the constant: the auto-imported `simd_quatf()` default init is the invalid ZERO quaternion — never use it.) Later phases should spell identity rotations as `.identity` too. Target membership is automatic (the project uses filesystem-synchronized folders), so the "add to all three app targets" note in 0.1 is a no-op.

## Step 0.2 — Placeholder aircraft specs

- [x] New file `ToyFlightSimulator Shared/Physics/Collision/AircraftColliderSpec.swift`

Mirrors the `AircraftThumbnailSpec.spec(for:)` pattern (one spec per `AircraftType`, central file). Phase 0 authors **only** the CGTrader F-22 (the default player aircraft); other types return `[]` — the overlay shows their legacy sphere and logs "no compound spec yet" rather than us inventing numbers we can't eyeball this phase.

```swift
/// Compound collider specs per player-selectable aircraft. Authored in MODEL
/// units; the node's uniform scale (3.0 for F22_CGTrader in FlightboxWithPhysics)
/// converts to world meters at runtime — see the units contract (plan §0.5).
/// Numbers are PLACEHOLDERS until tuned with the X-key debug overlay.
enum AircraftColliderSpec {
    static func spec(for type: AircraftType) -> [LocalCollider] {
        switch type {
            case .f22_cgtrader: return f22CGTrader
            default:            return []   // authored when each aircraft gets its Phase A body
        }
    }

    /// From research doc §2.3 (three primitives ≈ the whole airframe).
    private static let f22CGTrader: [LocalCollider] = [
        LocalCollider(name: "fuselage",
                      shape: .capsule(radius: 0.45, halfHeight: 2.4),
                      localPosition: [0, 0.10, 0.20],
                      // Capsule axis is local Y; rotate Y→Z so it runs nose–tail.
                      localRotation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]),
                      group: .airframe),
        LocalCollider(name: "wings",
                      shape: .box(halfExtents: [2.2, 0.06, 0.9]),
                      localPosition: [0, 0.05, -0.4],
                      group: .airframe),
        LocalCollider(name: "empennage",
                      shape: .box(halfExtents: [1.0, 0.45, 0.5]),
                      localPosition: [0, 0.35, -2.2],
                      group: .airframe),
    ]
}
```

Tuning these numbers against the model **is** a Phase 0 exit criterion; the tuned values get committed here with a short comment noting they were overlay-verified.

> **Addendum (2026-07-20):** Step 0.2 is implemented (numbers exactly as above, still untuned). Two spelling improvements over the pseudocode: the fuselage rotation reads `simd_quatf(angle: .halfPi, axis: X_AXIS)` — `Float.halfPi` is a new documented constant in `Math/Math.swift` beside `toRadians`, and `X_AXIS` the existing global — instead of raw `.pi / 2, axis: [1, 0, 0]`; later phases should use these spellings. Also settled: no per-file `import simd` is needed anywhere in the target — the bridging header `TFSCommon.h` imports `<simd/simd.h>`, making simd types and their overlay inits visible target-wide (ColliderShape.swift's explicit `import simd` is optional consistency, not a requirement). The macOS Debug build is green with 0.1 + 0.2 in the tree, which is why both file checkboxes above are now ticked — and it retroactively confirms the 0.1-era "no member 'identity'" diagnostics were SourceKit single-file artifacts (the same indexer now claims this file can't find `AircraftType`).

## Step 0.3 — Small support APIs (Node / GameObject)

- [x] `Node.setRotation(_ q: simd_quatf)` — the overlay must pose children from `LocalCollider.localRotation`. Node already stores a rotation matrix and converts `simd_quatf → simd_float4x4` internally (`setRotation(angle:axis:)`, Node.swift:297); this is one line through the existing `rotationMatrix` setter (which handles the dirty-flagging):

```swift
func setRotation(_ q: simd_quatf) { rotationMatrix = simd_float4x4(q) }
```

- [x] `Node.uniformScale` — the units-contract accessor (combined doc §4.1: "world meters = model units × the node's uniform scale (`scale.x`; assert uniformity in debug builds)"). Written once here, reused by Phase A's `worldColliders(frame:)`:

```swift
/// Uniform-scale contract for physics colliders: spec dimensions are model
/// units, world meters = model units × this. Debug-asserts the scale is
/// actually uniform so a stray setScale(x,y,z) can't silently skew colliders.
var uniformScale: Float {
    let s = getScale()
    assert(abs(s.x - s.y) <= 1e-4 * max(1, abs(s.x)) &&
           abs(s.x - s.z) <= 1e-4 * max(1, abs(s.x)),
           "Non-uniform scale \(s) on '\(getName())' breaks the collider units contract")
    return s.x
}
```

- [x] `GameObject.init(name:model:)` — capsule colliders need **bespoke mesh dimensions** (a capsule cannot be non-uniformly scaled without distorting its hemispherical caps, which would mislead exactly the length-tuning the overlay exists for). `CapsuleMesh(radius:length:)` already takes dimensions and `Model(name:mesh:)` already exists; what's missing is a `GameObject` init that accepts a prebuilt `Model` instead of a `ModelType`:

```swift
/// For runtime-built one-off models (debug collider volumes with bespoke
/// capsule dimensions). Mirrors init(name:modelType:) exactly, minus the
/// library lookup.
init(name: String, model: Model) {
    self.model = model
    super.init(name: name)
}
```

Mesh construction on the update thread is established practice (scene resets rebuild whole scenes there), so building a `CapsuleMesh` at toggle time is fine.

> **Addendum (2026-07-20):** Step 0.3 is implemented, with one **correction** to the text above: the claim that the `rotationMatrix` setter "handles the dirty-flagging" was wrong — that setter was a bare `_rotationMatrix` store, so the one-line `setRotation(_:)` silently never took effect (the cached local/world matrices were never invalidated). Fixed at the root: `Node.rotationMatrix`'s setter now routes through `updateModelMatrixAndMarkTransformDirty`, which also repairs a latent order-dependence in `F18.weaponReleaseSetup` (its direct `rotationMatrix =` assignment only worked because the `setScale` on the next line happened to dirty the node). `setRotation(_ q:)` additionally calls `afterRotation()` so both `setRotation` overloads fire the subclass hook identically (no overrides exist today — this is parity, not a behavior change). macOS Debug build green with 0.3 in the tree.

## Step 0.4 — The collider debug overlay

- [ ] New file `ToyFlightSimulator Shared/Physics/Debug/ColliderDebugOverlay.swift`
- [ ] New `DiscreteCommand` case + key mapping in `InputManager`
- [ ] Toggle handler + overlay ownership in `GameScene`; swap/reset hooks in `FlightboxWithPhysics`

### Registration rules this must obey (the part that's easy to get wrong)

- Overlay volumes are parented to the **aircraft**, not the scene root. `GameScene.addChild` is the only auto-registering path, so the overlay must call `SceneManager.Register(volume)` itself after `aircraft.addChild(volume)`.
- `setColor` with alpha < 1 **before** registering — `Register` resolves `objectType` (→ transparent collection) at registration time.
- Toggle-off must use `removeFromScene()` (removeChild + Unregister) per the scene-graph rule; a bare `removeChild` leaves frozen ghost renderables.
- Aircraft swap: `applyAircraftSwap` calls `SceneManager.RemoveObject(prevAc)`, which unregisters the prev aircraft's **whole subtree** — overlay volumes included. The overlay must then just drop its stale references and re-attach to the new aircraft if it was visible. It must NOT call `removeFromScene()` on those stale refs.
- Scene teardown (`Cmd+R` / menu reset): same story via `TeardownScene`; the overlay just resets its bookkeeping.

### Pure mapping helper (unit-testable, Metal-free)

Per the Metal-free-test-design rule, the shape→child-transform math is a pure enum the tests can hit without constructing GameObjects:

```swift
/// Maps ColliderShape (model units) onto the engine's debug meshes.
/// Child transforms are in the PARENT's model space — the parent's uniform
/// scale converts everything to world size via normal matrix composition,
/// so these functions never see the scale.
enum ColliderOverlayMapping {
    /// ModelType.Sphere is ObjModel("sphere"), radius 1.0 in model space
    /// (established by scene usage: setScale(r) pairs with collisionRadius r
    /// everywhere; verified visually in step 0.5).
    static let sphereMeshRadius: Float = 1.0
    /// ModelType.Cube wraps CubeMesh(size: 1.0) = MDLMesh(boxWithExtent: [1,1,1])
    /// → side 1.0, half-extent 0.5.
    static let cubeMeshSide: Float = 1.0

    static func childScale(for shape: ColliderShape) -> float3 {
        switch shape {
            case .sphere(let r): return float3(repeating: r / sphereMeshRadius)
            case .box(let he):   return (2.0 * he) / cubeMeshSide   // per-axis, non-uniform is fine for render-only children
            case .capsule:       return .one                        // bespoke mesh built at exact dims — never scaled
        }
    }

    /// CapsuleMesh(radius:length:) wraps MDLMesh(capsuleWithExtent: [r, length, r]).
    /// Whether `length` means the cylinder segment or the cap-to-cap total is
    /// settled by the one-time visual calibration (step 0.5); this function is
    /// the single place that encodes the verdict.
    /// Current assumption: length = cylinder segment = 2·halfHeight.
    static func capsuleMeshParams(radius: Float, halfHeight: Float) -> (radius: Float, length: Float) {
        (radius, 2 * halfHeight)
    }

    /// World-space center + axis-aligned span of a collider, for the units log
    /// (step 0.5). Pure: takes the parent's world position/rotation/scale.
    static func worldSpan(of collider: LocalCollider,
                          parentScale: Float) -> (dims: String, longestAxisMeters: Float) { ... }
}
```

### The overlay class

```swift
/// Translucent render-only volumes visualizing an aircraft's collider spec
/// (red) and its legacy physics sphere (yellow). Owns no physics state;
/// update-thread only (all scene-graph mutation happens in doUpdate).
final class ColliderDebugOverlay {
    static let specColor: float4   = [1, 0, 0, 0.3]    // research doc §2.7
    static let legacyColor: float4 = [1, 1, 0, 0.25]

    private(set) var isVisible = false
    private var volumes: [GameObject] = []
    private weak var host: GameObject?

    func toggle(on target: GameObject, spec: [LocalCollider]) {
        isVisible ? hide() : show(on: target, spec: spec)
    }

    func show(on target: GameObject, spec: [LocalCollider]) {
        guard !isVisible else { return }
        let scale = target.uniformScale               // asserts uniformity (units contract)

        for collider in spec where collider.isEnabled {
            let volume = makeVolume(for: collider.shape, name: "collider_\(collider.name)")
            volume.setColor(Self.specColor)           // BEFORE Register → transparent collection
            volume.setPosition(collider.localPosition) // model units; parent scale applies via hierarchy
            volume.setRotation(collider.localRotation)
            volume.setScale(ColliderOverlayMapping.childScale(for: collider.shape))
            target.addChild(volume)                   // aircraft ≠ scene root → no auto-registration…
            SceneManager.Register(volume)             // …so register explicitly
            volumes.append(volume)
        }

        // Legacy collision sphere (what the compound replaces). collisionRadius
        // is WORLD units today, so compensate the parent scale to render true size.
        if let sphereRB = target.rigidBody as? SphereRigidBody {
            let ghost = GameObject-from-.Sphere-model…
            ghost.setColor(Self.legacyColor)
            ghost.setScale(float3(repeating: sphereRB.collisionRadius / scale))
            target.addChild(ghost); SceneManager.Register(ghost); volumes.append(ghost)
        }

        logWorldDimensions(spec, scale: scale)        // step 0.5 sanity anchor, printed on every show
        host = target
        isVisible = true
    }

    func hide() {
        for volume in volumes { volume.removeFromScene() }  // removeChild + Unregister, per scene-graph rule
        reset()
    }

    /// Aircraft swap / scene reset: the old host's subtree (volumes included)
    /// was already removed AND unregistered wholesale — drop refs only, then
    /// re-attach to the new host if we were visible.
    func hostWasReplaced(by newTarget: GameObject?, spec: [LocalCollider]) {
        let wasVisible = isVisible
        reset()
        if wasVisible, let newTarget { show(on: newTarget, spec: spec) }
    }

    /// Bookkeeping-only clear (no scene-graph calls — used when the subtree is already gone).
    func reset() { volumes.removeAll(); host = nil; isVisible = false }

    private func makeVolume(for shape: ColliderShape, name: String) -> GameObject {
        switch shape {
            case .sphere: return GameObject(name: name, modelType: .Sphere)
            case .box:    return GameObject(name: name, modelType: .Cube)
            case .capsule(let r, let hh):
                let p = ColliderOverlayMapping.capsuleMeshParams(radius: r, halfHeight: hh)
                return GameObject(name: name,
                                  model: Model(name: name, mesh: CapsuleMesh(radius: p.radius, length: p.length)))
        }
    }
}
```

### Input + scene wiring

Key: **X** (free; taken today: p l space n m j f g c w a s d q e y h arrows, Cmd+R). Handled on the **update thread** via the `CycleCamera` debounce pattern in `GameScene.doUpdate` — NOT in `MacGameUIView`'s main-thread timer (scene-graph mutation must stay on the update thread).

```swift
// InputManager.swift
enum DiscreteCommand {
    ...
    case ToggleColliderOverlay      // new
}
keyboardMappingsDiscrete: [... , .ToggleColliderOverlay: .x]

// GameScene.swift — base class owns the overlay so any scene with a player
// aircraft gets the toggle for free
let colliderOverlay = ColliderDebugOverlay()
/// Set by scenes that support aircraft swapping (FlightboxWithPhysics);
/// keys the overlay's spec lookup.
internal var playerAircraftType: AircraftType? = nil

// in doUpdate(), next to the CycleCamera handler:
InputManager.HasDiscreteCommandDebounced(command: .ToggleColliderOverlay) {
    guard let aircraft = playerAircraft, let type = playerAircraftType else { return }
    colliderOverlay.toggle(on: aircraft, spec: AircraftColliderSpec.spec(for: type))
}

// in teardownScene():
colliderOverlay.reset()   // subtree is being torn down wholesale; drop refs only

// FlightboxWithPhysics.applyAircraftSwap(_:installEntities:) — after addChild(playerAircraft):
playerAircraftType = aircraft
colliderOverlay.hostWasReplaced(by: playerAircraft,
                                spec: AircraftColliderSpec.spec(for: aircraft))
```

**Known rendering limitation (accepted):** overlay volumes are depth-tested translucent geometry, so portions inside the hull are occluded by it. Tuning works from outside silhouettes (that's where fit matters) plus the debug camera ('C' to cycle, WASD+mouselook to fly through). A depth-ignoring wireframe pass is the eventual nicer tool (Codex's version) — explicitly out of scope.

## Step 0.5 — Units contract: calibration + sanity anchor

- [ ] `logWorldDimensions` prints, on every overlay show, one line per collider: name, shape, world-space dimensions (model dims × `uniformScale`). For the F-22 fuselage capsule at scale 3.0: total length = 2·(2.4 + 0.45)·3 = **17.1 m** against the real jet's 18.9 m — the combined doc §4.1 sanity anchor. If the printed number and the on-screen capsule disagree with the model's visible nose-tail span, the spec numbers (or the capsule-length assumption, below) are wrong — fix before Phase A consumes them.
- [ ] **One-time capsule calibration:** `MDLMesh(capsuleWithExtent: [r, length, r], ...)`'s exact interpretation of `length` (cylinder segment vs cap-to-cap total) is not trusted from documentation. Verify visually once: render a capsule collider next to a sphere collider of the same radius at a known offset and check where the caps end (or measure against the cube). Encode the verdict in `ColliderOverlayMapping.capsuleMeshParams` and note it in a comment. All capsule tuning afterward inherits the correct mapping.
- [ ] `Node.uniformScale` assertion active in debug builds (step 0.3) — this *is* the enforcement of the contract; Codex's full `assetToBodyMeters` transform stays deferred per combined doc §4.1.

> **Addendum (2026-07-20):** A dedicated investigation into making 1 scene unit = 1 real meter now exists: `research/claude/meter_scale_units_research_2026-07-20.md`. Measured facts that bear on this step: the CGTrader F-22 model is 8.615 native units nose-to-tail (so the placeholder capsule's 5.7-unit total covers only ~66% of the fuselage — expect the overlay to show it short), `sphere.obj` is radius exactly 1.0 (confirming `ColliderOverlayMapping.sphereMeshRadius` by measurement), and physics constants are already SI. That doc recommends landing import-time meterization **before** this step's collider tuning, so `AircraftColliderSpec` numbers get authored once, in meters, and this step's "world m = model units × scale" arithmetic collapses to "model units are meters, scale = 1." If meterization is adopted first, re-read this step with that lens; the 17.1 m anchor check still applies, just with scale 1.0.

## Step 0.6 — Metal-free parity enabler (behavior-neutral)

- [ ] `Physics/World/BasicRigidBodies.swift`: both inits take `GameObject?`

```diff
-    init(gameObject: GameObject, collisionRadius: Float = 1.0) {
+    init(gameObject: GameObject?, collisionRadius: Float = 1.0) {
```
(same for `PlaneRigidBody`; bodies unchanged — `RigidBody.init` already accepts `GameObject?` for exactly this reason, per its doc comment.)

- [ ] `Physics/World/RigidBody.swift`: position falls back to local storage when detached

```diff
+    /// Position storage for detached (test-double) bodies. Production bodies
+    /// always have a gameObject and never touch this.
+    private var detachedPosition: float3 = .zero

     func setPosition(_ position: float3) {
-        self.gameObject?.setPosition(position)
+        if let gameObject { gameObject.setPosition(position) }
+        else { detachedPosition = position }
     }

     func getPosition() -> float3 {
-        self.gameObject?.getPosition() ?? .zero
+        self.gameObject?.getPosition() ?? detachedPosition
     }
```

Why this is required: the parity harness must drive the **real collision path** (`PhysicsWorld.collided` / `getCollisionData` force-cast to the `final` classes `SphereRigidBody`/`PlaneRigidBody`, so `TestRigidBody` can't traverse it), and it must do so Metal-free (constructing any `GameObject` pulls in `Assets.Models` → Metal; see the project's Metal-free-test-design rule). With this enabler, real sphere/plane bodies run detached: `SphereRigidBody.getAABB()` reads `getPosition()` + `collisionRadius`, `PlaneRigidBody.getAABB()` reads `getPosition()` — both work on the fallback storage, so broad phase, narrow phase, response, and both solvers all run without a scene. Existing `PhysicsWorldSmokeTests` (GameObject-backed) keep guarding the attached path.

## Step 0.7 — Parity harness + golden baselines

- [ ] `ToyFlightSimulatorTests/TestSupport/SeededRandom.swift` — seedable `SplitMix64: RandomNumberGenerator` (Swift's default RNG is unseedable; scene layouts must be reproducible)
- [ ] `ToyFlightSimulatorTests/Physics/PhysicsParityTests.swift` — scenarios + runner + comparisons (`.tags(.physics)`, Swift Testing)
- [ ] `ToyFlightSimulatorTests/Physics/Baselines/*.json` — committed goldens (test-target membership irrelevant; loaded via `#filePath`)

### What the harness is for

Record the **current** engine's trajectories now; then, during Phase A:
- refactor steps that must be behavior-preserving (A3's "one narrow phase per pair" routing) are verified against these baselines unchanged;
- the **intentional** behavior changes (rest-hack removal, impulse-discard removal, ×2 position-correction fix) show up as explicit, reviewed re-baselines instead of silent drift.

So scenarios are split by expectation, and the ones that will change carry characterization asserts that Phase A will flip *deliberately*:

| Scenario | Setup (all Metal-free via detached bodies) | Solver / broad phase | Steps @ dt | Phase A expectation |
|---|---|---|---|---|
| `single_bounce_verlet` | sphere r=0.5, m=1, e=0.9, dropped from y=5 onto y=0 plane (e=0.9) | HeckerVerlet / off | 300 @ 1/60 | early bounces identical; terminal micro-bounce region changes (restitution threshold) |
| `single_bounce_euler` | same | NaiveEuler / off | 300 @ 1/60 | same |
| `rest_latch` | sphere r=0.5, e=0.2, dropped from y=3 | HeckerVerlet / off | 600 @ 1/60 | **changes wholesale** — this documents the latch |
| `head_on_pair` | two spheres r=0.5, m=1, e=1, closing at ±5 m/s on X | HeckerVerlet / off | 120 @ 1/60 | identical (impulse above discard threshold, no statics involved) |
| `ball_cluster_16` | 16 spheres r=0.4, m=1, e=0.9, seeded positions in [-7,7]×[1,10]×[-7,0] (BallPhysicsScene distribution), plane e=1 | HeckerVerlet / **on** | 600 @ 1/60 | partial change (rest/low-speed regions) |
| `stress_grid_50` | 50 spheres r=0.3, e=0.8, grid + seeded jitter + seeded initial velocities (PhysicsStressTestScene distribution), plane e=0.9 | HeckerVerlet / **on** | 600 @ 1/60 | partial change |

Fixed seeds (e.g. `0xF22_0001` per scenario) live next to the scenario definitions. The cluster/grid scenarios intentionally run with broad phase **on** — response is applied in pair order, so pair *ordering* is part of the behavior being locked in.

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
        let (world, bodies) = scenario.build()        // detached SphereRigidBody/PlaneRigidBody
        var tracks = bodies.map { BodyTrack(samples: [$0.getPosition().asArray], ...) }
        for step in 1...scenario.steps {
            world.update(deltaTime: scenario.dt)
            if step % scenario.sampleEvery == 0 { append positions }
        }
        finalize velocities + shouldApplyGravity
        return baseline
    }

    /// Baselines live in-repo next to the tests; #filePath keeps this working
    /// both locally and on the CI checkout.
    static var baselinesDir: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Baselines")
    }

    /// TFS_REGEN_PHYSICS_BASELINES=1 (mirrors TFS_REGEN_THUMBNAILS) rewrites
    /// the golden instead of comparing, then fails the test with a "re-run
    /// without the flag" message so a regen can never silently pass CI.
    static func assertMatchesGolden(_ fresh: PhysicsBaseline, named: String) {
        if ProcessInfo.processInfo.environment["TFS_REGEN_PHYSICS_BASELINES"] == "1" {
            write JSON (sortedKeys + prettyPrinted for stable diffs); Issue.record("regenerated — commit and re-run")
            return
        }
        let golden = load(named)
        compare metadata exactly; compare samples/velocities with tolerance 1e-4
        on mismatch: report first divergent (body, step) + values   // makes Phase A diffs readable
    }
}

@Suite("Physics parity", .tags(.physics))
struct PhysicsParityTests {
    @Test(arguments: ParityScenario.all)
    func matchesGolden(_ s: ParityScenario) { ParityRunner.assertMatchesGolden(ParityRunner.run(s), named: s.name) }

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

Tolerance note: same-machine reruns should be exact; 1e-4 absorbs toolchain/FMA variance between local and CI. If CI ever diverges beyond that, regen on CI's toolchain and note it here as an addendum.

## Step 0.8 — Unit tests (Metal-free, Swift Testing, `.physics` / `.utils` tags)

- [ ] `ColliderShapeTests`: `scaled(by:)` for all three shapes (dims scale, sphere stays sphere, etc.); `LocalCollider` defaults (identity rotation, `.airframe`, enabled)
- [ ] `AircraftColliderSpecTests`: f22_cgtrader returns 3 enabled colliders with expected names/groups; unauthored types return `[]`; fuselage world length at scale 3.0 ≈ 17.1 (the sanity anchor, as a test so it can't rot)
- [ ] `ColliderOverlayMappingTests`: sphere child scale = radius; box child scale = 2·halfExtents (non-uniform); capsule child scale = 1 + `capsuleMeshParams` reflects the calibrated verdict; `worldSpan` numbers
- [ ] `RigidBody` detached-position tests (in existing `RigidBodyTests`): set/get round-trips with nil gameObject; attached path still proxies to the node; detached `SphereRigidBody`/`PlaneRigidBody` AABBs correct
- [ ] `PhysicsParityTests` as in step 0.7 (determinism + goldens + rest-latch characterization)
- [ ] Overlay class itself: **not** unit-tested (constructs GameObjects → Metal; per project rule the logic lives in the pure mapping enum instead). Manual verification checklist below.

## Phase 0 exit criteria

1. - [ ] **Overlay works in-app** (manual, FlightboxWithPhysics, macOS): X shows red compound volumes + yellow legacy sphere on the F-22; X again removes them; repeated toggling leaves no ghost renderables (volumes never freeze in place after removal); overlay survives: aircraft swap while visible (re-attaches to the new aircraft), Cmd+R reset while visible (comes back clean on next X), renderer switch.
2. - [ ] **Spec numbers eyeballed and committed**: fuselage capsule spans nose→tail, wings box spans the wingtips, empennage box covers the tails — tuned values recorded in `AircraftColliderSpec` with the overlay screenshot(s) dropped in `debugging/screenshots/` for the record.
3. - [ ] **Units anchor holds**: overlay log prints fuselage ≈ 17.1 m at scale 3.0 (vs 18.9 m real F-22) and the capsule-length calibration verdict is encoded + commented in `ColliderOverlayMapping`.
4. - [ ] **Parity baselines committed**: all scenario goldens recorded, parity suite green against them on a clean re-run (determinism test included), runnable Metal-free via the scoped `test-without-building` invocation.
5. - [ ] **No behavior change**: full existing test suite green in CI; `PhysicsWorldSmokeTests` (attached-body path) untouched and green; game plays identically with the overlay off.

**Implementation order within Phase 0:** 0.1 → 0.2 → 0.3 → 0.6 → 0.7 (baselines locked before any later phase touches physics) → 0.4 → 0.5 → 0.8 interleaved throughout. The parity steps (0.6/0.7) and the overlay steps (0.3/0.4/0.5) are independent and can land in either order; both before Phase A starts.

---

*(Phase A plan will be appended here.)*
