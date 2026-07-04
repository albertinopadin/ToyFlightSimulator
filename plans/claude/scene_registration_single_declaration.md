# Unifying SceneManager Register/Unregister from a single declaration

**Status:** Implemented 2026-07-04 (§5 hardened Option A: `GameObjectType` + `registeredObjectType`)
**Source:** Finding 2.7 in `code_reviews/claude/post_1704e81_commit_range_review_2026-06-29.md`
**Files involved:** `ToyFlightSimulator Shared/Managers/SceneManager.swift`, `GameObjects/GameObject.swift`, `Scenes/GameScene.swift`, plus one-line overrides in the handful of specially-batched GameObject subclasses.

---

## 1. The problem, restated from the code

`SceneManager.Register` (SceneManager.swift:299) and `SceneManager.unregisterSingle`
(SceneManager.swift:516) each contain a hand-written type switch that maps a
GameObject to the batched collection it lives in:

| Type | Register does | unregisterSingle does |
|---|---|---|
| `SkyBox` / `SkySphere` | `RegisterSky` → `skyData` | skip |
| `LightObject` | nothing (LightManager owns lights) | skip |
| `Camera` | never reaches Register (`GameScene.registerChildObject` filters it) | skip |
| `Icosahedron` | `icosahedrons.append` | `icosahedrons.removeAll { $0.id == … }` |
| `Line` | `lines.append` | `lines.removeAll { … }` |
| `ParticleEmitterObject` | `particleObjects.append` | `particleObjects.removeAll { … }` |
| `Tessellatable` (protocol) | `tessellatables.append` | **intentionally omitted** (NOTE comment) |
| `SubMeshGameObject` | side effect on parent's `ModelData`, then `RegisterObject` | falls to `default` |
| everything else | `RegisterObject` → `modelDatas` / `transparentObjectDatas` | `removeRenderable` (mirrors) |

The mapping is **stated twice**, and nothing but reviewer discipline keeps the two
statements in agreement. Both switches end in `default:`, so a future type that
registers into a *new* collection compiles cleanly, registers fine, and silently
fails to unregister — an orphan whose ModelConstants `writeFrameSnapshot` keeps
writing every frame and which never deallocates. The `tessellatables` omission
shows the drift has already started (documented today, but only by a comment).

Two latent soft spots fall out of the same double-statement structure and are worth
naming, because the options below differ in whether they fix them:

1. **Removal re-derives what registration decided.** `removeRenderable`
   (SceneManager.swift:543) reads `gameObject.isTransparent` *at removal time* to
   pick between `modelDatas` and `transparentObjectDatas`. But `isTransparent` is a
   live computed property (`GameObject.swift:36` — `useObjectColor && objectColor.w < 1.0`)
   and `setColor(_:)` is public. An object registered opaque whose alpha is later
   set below 1.0 will be *removed from the wrong dictionary* — same orphan symptom
   as the drift hazard, no compiler or assertion in the way.
2. **The skip-list is also mirrored.** `unregisterSingle`'s
   `case is Camera, is SkyBox, is SkySphere, is LightObject: break` must track both
   `Register`'s cases *and* the `is Camera` filter in `GameScene.registerChildObject:42`.
   Three places currently encode "cameras are not batched."

Useful constraints discovered while reading the code (any design must respect these):

- **Single choke points.** `Register` has exactly one caller
  (`GameScene.registerChildObject:43`) and `Unregister` one (`RemoveObject:480`).
  Retrofitting either option is contained.
- **Registration isn't a pure append for every type.** `RegisterSubMeshObject`
  first mutates the *parent* model's `MeshData` (hides the extracted submesh from
  the parent's draw list) and that side effect is intentionally never undone.
  Sky registration is a singleton hack (`skyData.gameObjects` append is guarded by
  `isEmpty`; meshDatas always append). Any "one declaration" scheme must keep room
  for these asymmetries without pretending they're symmetric.
- **`Tessellatable` is a protocol**, not a class — the declaration mechanism can't
  rely purely on subclass overrides for it.
- **`TeardownScene` mass-clears the collections wholesale** (SceneManager.swift:178-184).
  Whatever per-object state a design adds must tolerate being staled by that path.

---

## 2. What "drive both directions from one declaration" means

The hazard exists because the type→collection mapping is written down twice. The fix
is to write it down **once**, and make both add and remove *derive* from that single
statement so they cannot disagree. There are two fundamentally different places the
single statement can live:

- **Option A — a declarative value.** Each GameObject *declares* (via an overridable
  property) which batch it belongs to, as a case of a small closed enum. Register and
  Unregister both switch on that enum — and because the enum is closed and the
  switches have **no `default`**, the compiler forces every new batch to be handled
  in both directions before the code compiles. The declaration is data; the compiler
  is the enforcement.
- **Option B — a runtime undo artifact.** `Register` returns a **removal token**
  that captures, at registration time, exactly how to undo the insertion it just
  performed. Unregister doesn't re-derive anything — it replays the token. The
  declaration is the paired append+undo written adjacently in one place; locality is
  the enforcement.

---

## 3. Option A — each GameObject declares the collection it belongs to

### 3.1 The declaration

One closed enum names every batch destination (following the codebase's `XType`
idiom — `AircraftType`, `ModelType`, `SceneType`, `RendererType`). The
`renderables` case carries the opaque/transparent split as an associated value so
it can be resolved once:

```swift
//  GameObjectType.swift (new, or top of GameObject.swift)

/// The registration category of a GameObject — which SceneManager collection it
/// batches into. This is the single source of truth consulted by BOTH Register
/// and Unregister: `add(_:to:)` and `remove(_:from:)` switch exhaustively over
/// these cases with NO `default`, so adding a case here without handling both
/// directions is a compile error.
enum GameObjectType {
    /// Not batched by SceneManager (cameras; lights live in LightManager).
    case none
    /// The singleton sky slot (`skyData`). Reset wholesale in TeardownScene.
    case sky
    case icosahedrons
    case lines
    case particles
    case tessellatables
    /// `modelDatas` / `transparentObjectDatas`, split by `transparent`.
    case renderables(transparent: Bool)
}
```

The override point lives on `GameObject`. The base implementation absorbs the two
non-class dispatches (the `Tessellatable` protocol check and the transparency
split), so new plain types and new `Tessellatable` conformers get correct behavior
with **zero** SceneManager changes and zero overrides:

```swift
//  GameObject.swift

/// The registration category of this object — SceneManager batches it into a
/// collection based on this value. Subclasses that live in a side collection
/// override this; the base handles Tessellatable conformers and the
/// opaque/transparent split automatically.
var objectType: GameObjectType {
    if self is Tessellatable { return .tessellatables }
    return .renderables(transparent: isTransparent)
}
```

Each specially-batched class states its membership once, next to its own code:

```swift
//  Icosahedron.swift
override var objectType: GameObjectType { .icosahedrons }

//  Line.swift
override var objectType: GameObjectType { .lines }

//  ParticleEmitterObject.swift
override var objectType: GameObjectType { .particles }

//  SkyBox.swift and SkySphere.swift
override var objectType: GameObjectType { .sky }

//  LightObject.swift  (PointLightObject and Sun inherit it)
override var objectType: GameObjectType { .none }

//  Camera.swift
override var objectType: GameObjectType { .none }
```

### 3.2 The two derived directions

`Register` resolves the declaration once; `add` and `remove` sit **adjacent in the
file** and switch exhaustively. Note what disappears: the `default:` cases, the
hand-mirrored skip-list, and the "tessellatables intentionally not handled" hole
(implementing its removal is now a one-liner, so there's no reason to leave it out).

```swift
//  SceneManager.swift

static func Register(_ gameObject: GameObject) {
    // Registration-flow side effect, not batch membership: a SubMeshGameObject
    // hides its submesh in the parent model's draw lists. Intentionally never
    // undone on unregister (today's behavior — see RegisterSubMeshObject).
    if let subMeshObject = gameObject as? SubMeshGameObject {
        hideSubmeshInParentModel(subMeshObject)   // body of today's RegisterSubMeshObject,
    }                                             // minus the trailing RegisterObject call

    add(gameObject, to: gameObject.objectType)
}

/// `add(_:to:)` and `remove(_:from:)` are deliberately adjacent, and both
/// switch over GameObjectType with no `default` — the compiler keeps them in
/// lockstep. Do not add a `default` case to either switch; exhaustiveness IS
/// the drift protection.
private static func add(_ gameObject: GameObject, to objectType: GameObjectType) {
    switch objectType {
        case .none:
            break
        case .sky:
            RegisterSky(gameObject)
        case .icosahedrons:
            // Force-casts encode the invariant "only Icosahedron declares
            // .icosahedrons"; a mismatch is a programmer error and should
            // crash in development rather than mis-batch silently.
            icosahedrons.append(gameObject as! Icosahedron)
        case .lines:
            lines.append(gameObject as! Line)
        case .particles:
            particleObjects.append(gameObject as! ParticleEmitterObject)
        case .tessellatables:
            tessellatables.append(gameObject as! Tessellatable)
        case .renderables(let transparent):
            addRenderable(gameObject, transparent: transparent)
    }
}

private static func remove(_ gameObject: GameObject, from objectType: GameObjectType) {
    switch objectType {
        case .none:
            break
        case .sky:
            // Sky is singleton-managed and reset wholesale in TeardownScene;
            // nothing is removed per-object (mirrors today's behavior).
            break
        case .icosahedrons:
            icosahedrons.removeAll { $0.id == gameObject.id }
        case .lines:
            lines.removeAll { $0.id == gameObject.id }
        case .particles:
            particleObjects.removeAll { $0.id == gameObject.id }
        case .tessellatables:
            tessellatables.removeAll { $0.id == gameObject.id }
        case .renderables(let transparent):
            removeRenderable(gameObject, transparent: transparent)
    }
}
```

`addRenderable`/`removeRenderable` are today's `RegisterObject`/`removeRenderable`
with the transparency decision hoisted out into the passed-in flag (in plain
Option A the flag is re-derived at each end; see §5 for the refinement that
captures it once).

`unregisterSingle` shrinks to:

```swift
private static func unregisterSingle(_ node: Node) {
    guard let gameObject = node as? GameObject else { return }
    remove(gameObject, from: gameObject.objectType)
}
```

A side benefit: `GameScene.registerChildObject`'s `is Camera` filter becomes
redundant (`Camera` now declares `.none`), so "cameras are not batched" is stated
once, on `Camera`, instead of three times.

**Variant considered and rejected:** making the enum cases carry the typed object
(`case icosahedron(Icosahedron)`) would remove the force-casts, but the moment the
resolved value is stored on the object (§5) it becomes a self-retain cycle
(`object → enum payload → object`). A payload-free enum plus documented casts is
simpler and safe to store.

### 3.3 Pros / cons

**Pros**

- **Compile-time lockstep — the strongest available guarantee for exactly the
  hazard in the finding.** Add a `GameObjectType` case and both `add` and `remove`
  fail to compile until handled. This is the only mechanism (of the two) the
  compiler checks; drift becomes impossible rather than unlikely.
- New types that reuse an existing batch need **no SceneManager change at all** —
  a one-line override, or nothing (base implementation covers plain renderables and
  Tessellatable conformers, preserving today's automatic protocol dispatch).
- No new runtime machinery: no closures, no lifetime rules, no interaction with
  `TeardownScene`'s wholesale clears. The collections, DrawManager reads, existing
  tests, and threading story are untouched.
- Matches the codebase idiom (closed enums + exhaustive switches: `RendererType`,
  `SceneType`, `RenderPipelineStateType`, `AnimationLayerID`…). Low review surface.
- The `tessellatables` hole and the skip-list mirroring disappear as a natural
  consequence, not as extra work.

**Cons**

- There are still two switches; the guarantee rests on **never adding `default`**
  to them. A future hand that adds `default: break` to silence a compiler error
  quietly restores the hazard (mitigated by the comment, the adjacency, and the
  small size of the enum — but it's convention, not physics).
- A scene-batching concern moves onto `GameObject`. It's one small computed
  property, and the codebase already blends concerns this way (`isTransparent`,
  `rigidBody`), but it is a coupling.
- Force-casts in `add` encode the "only X declares .x" invariant at runtime, not
  compile time. A wrong override crashes in development (loudly, which is the
  point) rather than failing to compile.
- Plain Option A still re-derives `objectType` at unregister time, so the
  `setColor`-flips-`isTransparent` soft spot (§1 item 1) survives unless the §5
  refinement is added.

---

## 4. Option B — registration hands back a removal token

### 4.1 The token

`Register` becomes the *only* authority on where things went: it performs the
insertion and returns a closure that undoes exactly that insertion. Unregister
replays the closure; there is no second switch anywhere.

```swift
//  SceneManager.swift

/// Opaque undo handle returned by Register. Calling `remove()` reverses
/// exactly the insertion that produced it — no type re-dispatch, no
/// re-derivation of object state at removal time.
struct SceneRegistrationToken {
    fileprivate let removal: () -> Void
    func remove() { removal() }
}
```

The natural home for the token is the object itself (no global side-table to key,
prune, and clear on teardown):

```swift
//  GameObject.swift

/// Undo handle from SceneManager.Register; consumed by Unregister.
/// nil ⇒ not currently registered.
var sceneRegistration: SceneRegistrationToken?
```

### 4.2 Registration builds the undo next to the do

```swift
static func Register(_ gameObject: GameObject) {
    if let subMeshObject = gameObject as? SubMeshGameObject {
        hideSubmeshInParentModel(subMeshObject)   // side effect; still not undone
    }

    let token: SceneRegistrationToken
    switch gameObject {
        case is SkyBox, is SkySphere:
            RegisterSky(gameObject)
            token = SceneRegistrationToken {}   // sky is reset wholesale at teardown
        case is LightObject:
            token = SceneRegistrationToken {}   // lights live in LightManager

        case let icosahedron as Icosahedron:
            icosahedrons.append(icosahedron)
            // Capture the id, NOT the object: the token is stored on the node,
            // so a closure capturing `icosahedron` would be a retain cycle
            // (node → token → closure → node) and the subtree would leak.
            let id = icosahedron.id
            token = SceneRegistrationToken { icosahedrons.removeAll { $0.id == id } }

        case let line as Line:
            lines.append(line)
            let id = line.id
            token = SceneRegistrationToken { lines.removeAll { $0.id == id } }

        case let particleObject as ParticleEmitterObject:
            particleObjects.append(particleObject)
            let id = particleObject.id
            token = SceneRegistrationToken { particleObjects.removeAll { $0.id == id } }

        case let tessellatable as Tessellatable:
            tessellatables.append(tessellatable)
            let id = tessellatable.id
            token = SceneRegistrationToken { tessellatables.removeAll { $0.id == id } }

        default:
            let model = gameObject.model                 // `let` on GameObject — stable
            let transparent = gameObject.isTransparent   // captured at registration:
            let id = gameObject.id                       // removal can't disagree later
            addRenderable(gameObject, model: model, transparent: transparent)
            token = SceneRegistrationToken {
                removeRenderable(id: id, model: model, transparent: transparent)
            }
    }
    gameObject.sceneRegistration = token
}

/// Removal by captured identity — deliberately does not read the (possibly
/// since-mutated) object.
private static func removeRenderable(id: String, model: Model, transparent: Bool) {
    if transparent {
        transparentObjectDatas[model]?.gameObjects.removeAll { $0.id == id }
        if transparentObjectDatas[model]?.gameObjects.isEmpty == true {
            transparentObjectDatas[model] = nil
        }
    } else {
        modelDatas[model]?.gameObjects.removeAll { $0.id == id }
        if modelDatas[model]?.gameObjects.isEmpty == true {
            modelDatas[model] = nil
        }
    }
}
```

### 4.3 Unregister stops being a switch at all

```swift
static func Unregister(_ node: Node) {
    for subtreeNode in subtreeNodes(of: node) {
        guard let gameObject = subtreeNode as? GameObject else { continue }
        gameObject.sceneRegistration?.remove()
        gameObject.sceneRegistration = nil
    }
}
```

`unregisterSingle` is deleted. Cameras, lights, plain `Node`s, and anything never
registered simply have no token — the skip-list vanishes. The `isTransparent`
soft spot is fixed by construction (the flag was captured when it was decided).
Stale tokens after `TeardownScene`'s wholesale clear are harmless (`removeAll`
finds no match), and the tokens die with the scene graph anyway.

### 4.4 Pros / cons

**Pros**

- **Register is the single authority in the strongest sense**: the undo is authored
  in the same diff hunk, adjacent to the do. A new collection whose case appends
  but returns an empty token is visible in one screenful of code review.
- Unregister collapses to four lines. The skip-list, the second switch, and the
  drift surface are all *gone* — there is nothing to keep in lockstep.
- Registration-time capture of `transparent`/`model`/`id` makes removal immune to
  any post-registration mutation of the object (fixes §1 item 1 for free).
- Double-registration and double-unregistration become naturally detectable
  (`sceneRegistration != nil` / token already consumed).

**Cons**

- **No compiler enforcement.** Nothing stops `token = SceneRegistrationToken {}`
  on a path that actually inserted something. The guarantee is locality and
  convention — better than today's 200-lines-apart mirroring, but weaker than
  Option A's exhaustiveness, and the finding's hazard is precisely the case the
  author forgot about.
- **Closure-capture subtlety is a permanent tax.** Every future case author must
  remember "capture the id, never the object" or silently create a retain cycle —
  exactly the class of ownership bug this codebase carefully engineers around
  elsewhere (weak `RigidBody.gameObject`, scratch-buffer reuse). The compiler
  won't flag it, and a leak from a swapped-out aircraft subtree would look just
  like the orphan bug this refactor is meant to kill.
- Removal logic becomes anonymous. "Where does an Icosahedron get removed?" is now
  inside a closure built at registration — not a named, greppable, breakpointable
  function. Debugging a mis-removal means inspecting captured state.
- Two removal mechanisms coexist (token replay for swaps, wholesale `removeAll` in
  `TeardownScene`), which is conceptually mushier even though it's safe.
- Slightly more moving parts for the same behavior: a token type, a stored
  property with lifetime rules, and id-based removal helpers duplicating the
  object-based ones.

---

## 5. Recommendation: Option A, hardened with B's one genuinely better idea

**Go with Option A** — the closed `GameObjectType` enum declared on `GameObject`,
with adjacent exhaustive `add`/`remove` switches and no `default`. The reasoning:

1. **The finding's hazard is "a future type drifts silently."** Compile-time
   exhaustiveness is the only mechanism on the table that the machine checks;
   Option B's protection is disciplined adjacency, which is what already failed
   (that's how the `tessellatables` hole happened). When choosing between "the
   compiler refuses" and "the reviewer probably notices," take the compiler.
2. **Option B's costs land in the worst place.** Its closure-capture rule
   (id-not-object) is unenforced, and getting it wrong produces leaks in the
   aircraft-swap path — the exact symptom class (orphaned subtrees) this refactor
   exists to eliminate. A safety mechanism whose own failure mode reproduces the
   original bug is a poor trade.
3. **Fit.** The enum-plus-exhaustive-switch shape is this codebase's native idiom;
   Option A's entire diff is mechanical and reviewable in one sitting, touches no
   threading, no lifetimes, and no teardown behavior.

**Borrow one thing from B: capture the resolved type at registration.** Plain A
still re-derives `objectType` at unregister time, which preserves the
`setColor`-flips-`isTransparent` wrong-dictionary bug. Store the resolved value
instead — it's B's registration-time-capture semantics expressed as a value, with
no closures and no cycle risk (the enum is payload-free):

```swift
//  GameObject.swift
/// Set by SceneManager.Register with the objectType actually registered under;
/// consumed and cleared by Unregister. nil ⇒ not currently registered.
/// Capturing this at registration means unregistration never re-derives state
/// that may have changed since (e.g. isTransparent via setColor).
var registeredObjectType: GameObjectType?
```

```swift
//  SceneManager.swift
static func Register(_ gameObject: GameObject) {
    if let subMeshObject = gameObject as? SubMeshGameObject {
        hideSubmeshInParentModel(subMeshObject)
    }
    guard gameObject.registeredObjectType == nil else {
        assertionFailure("Double-registering \(gameObject.getName())")
        return
    }
    let objectType = gameObject.objectType   // resolved exactly once
    add(gameObject, to: objectType)
    gameObject.registeredObjectType = objectType
}

private static func unregisterSingle(_ node: Node) {
    guard let gameObject = node as? GameObject,
          let objectType = gameObject.registeredObjectType else { return }  // never / no longer registered
    remove(gameObject, from: objectType)
    gameObject.registeredObjectType = nil
}
```

This hardened form keeps Option A's compiler guarantee and additionally gets:

- removal from the collection registration *actually* chose, regardless of later
  `setColor`/property mutation;
- the skip-list fully subsumed (`registeredObjectType == nil` covers cameras,
  lights, plain Nodes, and already-unregistered objects uniformly);
- free double-registration detection (today a double `addChild` double-draws);
- `TeardownScene` compatibility for free — cleared collections belong to a scene
  graph that is discarded wholesale, so stale `registeredObjectType` markers die
  with their nodes, and even a stray late Unregister just no-op-removes.

Cost over plain A: one stored optional enum per GameObject and two lines in
Register. That's the whole price of closing both soft spots from §1.

### Interim step

If this refactor doesn't happen immediately, land the review's minimal guard now —
an `assertionFailure` on the unhandled-but-registered `Tessellatable` case in
`unregisterSingle` — so the existing hole at least fails loudly in Debug. The
refactor then deletes that guard along with the switch it patches.

---

## 6. Migration sketch

Small, independently compilable steps:

1. Add `GameObjectType` + `GameObject.objectType` (base implementation) +
   `registeredObjectType`. Add the six one-line overrides (`Icosahedron`, `Line`,
   `ParticleEmitterObject`, `SkyBox`, `SkySphere`, `LightObject`, `Camera`).
2. In SceneManager: extract `hideSubmeshInParentModel` from `RegisterSubMeshObject`;
   add `add(_:to:)` / `remove(_:from:)` (adjacent, exhaustive, no `default`);
   rewrite `Register` and `unregisterSingle` as above. Delete the old switches,
   `RegisterSubMeshObject`'s wrapper, and the skip-list.
3. Drop the now-redundant `is Camera` filter in `GameScene.registerChildObject`
   (behavior covered by `Camera.objectType == .none` + the `registeredObjectType`
   guard).
4. Thread `transparent:` through `addRenderable`/`removeRenderable` signatures so
   the split is decided only at registration.

**Testing reality check** (per the project's Metal-free test constraint): the
exhaustiveness guarantee is compile-time — that *is* the test for the drift hazard,
and it's the point of the design. GameObjects aren't constructible in the logic
suite (Model → Metal), so register/unregister roundtrip coverage stays in the
app-hosted suite on CI; the existing pure `subtreeNodes` tests are unaffected. If
runtime coverage of the bookkeeping is wanted later, `registeredObjectType` get/set
logic could be exercised through a seam, but it isn't required for the guarantee
this refactor exists to provide.
