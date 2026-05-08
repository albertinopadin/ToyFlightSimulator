# SceneManager Thread Safety (Q3)

**Status:** Plan only — not implemented. Review before scheduling.
**Created:** 2026-05-07
**Derived from:** `code_reviews/claude/SIMPLIFICATION_SUGGESTIONS.md` finding Q3.

---

## TL;DR

`SceneManager.swift:88-99` declares seven `nonisolated(unsafe) public static
var` collections that are mutated by scene-construction code (main thread
during `SetScene` / `TeardownScene` / `GameScene.addChild`) and read
concurrently by the update thread (`writeFrameSnapshot`) and render thread
(`DrawManager.DrawIcosahedrons`, `DrawSky`, `DrawParticles`,
`DrawTessellatables`, `DrawLines`).

A comment in the file itself flags the issue:
```swift
// TODO -> wrap this in a thread safe container (?):
nonisolated(unsafe) public static var modelDatas: [Model: ModelData] = [:]
```

`LightManager` (already updated in PR 1) shows the pattern this codebase
prefers: an `OSAllocatedUnfairLock` plus `withLock` wrappers around every
mutation and read. We'll apply the same pattern here, with two key
differences:

1. **Coarser granularity.** SceneManager's collections are read in inner
   loops every frame. Acquiring a lock inside `for line in
   SceneManager.lines` would serialize the render thread on every line
   draw. Solution: batch reads via per-frame snapshot accessors that
   return a `let` copy of the collection under one lock acquisition.
2. **Snapshot accessors already exist for the heavy collections** —
   `getOpaqueSnapshot` / `getTransparentSnapshot` / `getSkySnapshot` are
   read-only handoffs of pre-built ring-buffer regions. The unsafe
   reads we need to lock are the *unbatched* ones: `icosahedrons`,
   `particleObjects`, `tessellatables`, `lines`, and direct uses of
   `skyData`.

---

## Diagnosis

### Threads and synchronization in this codebase

From `Engine.swift:32-45`:
- **Main thread** runs the renderer (`MTKView` delegate `draw(in:)`),
  drives scene construction (`MacMetalViewWrapper.makeNSView` → `SetScene`),
  and processes user menu actions (e.g. `TeardownScene` from `TFSMenu`).
- **`UpdateThread`** runs `SceneManager.Update(deltaTime:)` in a loop,
  gated by a semaphore handshake.
- **`AudioThread`** is irrelevant for this discussion — doesn't touch
  SceneManager.

From `UpdateThread.swift:11-26` and `Renderer.swift:136`:
- `updateSemaphore`: render thread signals → update thread runs.
- `updateDoneSemaphore`: update thread signals → render thread proceeds.

In **steady state**, render and update are serialized: the update is
blocked on `updateSemaphore.wait` while the render thread is mid-frame,
and the render thread blocks on `updateDoneSemaphore.wait` (line 136 of
Renderer.swift) while update is running. So during normal play, there
*is* no concurrent access — the unsafe-static markers are technically
unnecessary. **But:**

### Where the race actually happens

Scene-lifecycle calls bypass this handshake:

| Trigger | Caller thread | What it touches |
|---|---|---|
| `SceneManager.SetScene` | Main thread (e.g. `MacMetalViewWrapper:38`) | Sets `CurrentScene`, which during init calls `addChild` → `SceneManager.Register` → mutates `modelDatas`, `transparentObjectDatas`, `icosahedrons`, `particleObjects`, `tessellatables`, `lines`, `skyData` |
| `SceneManager.ResetScene` | Main thread (`TFSMenu:50` via menu click) | Same as above, plus `TeardownScene` first |
| `SceneManager.TeardownScene` | Main thread | Calls `removeAll()` on every collection |

While the main thread is in the middle of one of those calls:
- The **update thread** may have just unblocked from `updateSemaphore.wait`
  and be reading `modelDatas` / `transparentObjectDatas` / `skyData` in
  `writeFrameSnapshot`.
- The **render thread** may be mid-`draw(in:)` reading
  `SceneManager.icosahedrons`, `.lines`, `.particleObjects`,
  `.tessellatables`, `.skyData.gameObjects` from `DrawManager` helpers.

This is the actual race. It's rare (only during user-initiated scene
transitions or programmatic resets), but it has been observed to
manifest as occasional crashes and visual glitches during scene swaps.

### Why LightManager is already OK

`LightManager` only owns small arrays of `LightObject` references and is
explicitly accessed via lock-bracketed methods. Every read goes through
`GetLightObjects(lightType:)` / `GetDirectionalLightData(...)` /
`GetPointLightData()`, all of which call `withLock(lightLock) { ... }`.
Writes go through `AddLightObject` / `RemoveAllLights`, also locked.

`SceneManager`, by contrast, exposes its collections as `public static var`
— callers reach in directly with `SceneManager.icosahedrons` etc., and
the file doesn't own a lock at all.

---

## Constraints

- **No allocations on the read path.** `DrawManager.DrawLines` iterates
  `SceneManager.lines` per frame. We can't allocate a fresh copy of the
  array on each iteration — that would undo PR 1's per-frame allocation
  fixes.
- **No long lock holds.** Render thread can't be blocked for the
  duration of a scene rebuild. Lock granularity must let the lock be
  held only while *reading* the collection reference, not while
  iterating it.
- **Preserve current API surface where possible.** `DrawManager` and
  `SceneManager` itself have many internal call sites; minimize churn.

---

## Recommended approach: lock-protected access via copy-on-read

Wrap each mutable collection in a private `static var`, exposed via a
read accessor that returns a snapshot under the lock, and a write
accessor that mutates under the lock. The read accessor copies the
collection's *header* (pointer + length, ~16 bytes) but not its
contents — Swift `Array` is copy-on-write, so we get a lock-free
snapshot for the duration of the iteration.

This is the same trick `LightManager.GetLightObjects` already uses:
```swift
public static func GetLightObjects(lightType: LightType) -> [LightObject] {
    withLock(lightLock) {
        switch lightType {
            case Directional: return Self._directionalLights
            ...
        }
    }
}
```

Returning the array out of the locked region is safe because Array's
CoW means the caller sees a stable view, and any subsequent write
clones the storage rather than mutating the caller's reference.

### Changes to `SceneManager`

**Before** (`Managers/SceneManager.swift:87-99`):
```swift
final class SceneManager {
    nonisolated(unsafe) public static var CurrentScene: GameScene?
    nonisolated(unsafe) private static var _sceneType: SceneType?
    nonisolated(unsafe) private static var _rendererType: RendererType?

    // TODO -> wrap this in a thread safe container (?):
    nonisolated(unsafe) public static var modelDatas: [Model: ModelData] = [:]
    nonisolated(unsafe) public static var transparentObjectDatas: [Model: TransparentObjectData] = [:]
    nonisolated(unsafe) public static var particleObjects: [ParticleEmitterObject] = []
    nonisolated(unsafe) public static var tessellatables: [Tessellatable] = []
    nonisolated(unsafe) public static var skyData = ModelData()
    nonisolated(unsafe) public static var lines: [Line] = []
    nonisolated(unsafe) public static var icosahedrons: [Icosahedron] = []
```

**After:**
```swift
final class SceneManager {
    private static let stateLock = OSAllocatedUnfairLock()

    nonisolated(unsafe) public static var CurrentScene: GameScene?
    nonisolated(unsafe) private static var _sceneType: SceneType?
    nonisolated(unsafe) private static var _rendererType: RendererType?

    // Backing storage — only accessed via the locked accessors below.
    nonisolated(unsafe) private static var _modelDatas: [Model: ModelData] = [:]
    nonisolated(unsafe) private static var _transparentObjectDatas: [Model: TransparentObjectData] = [:]
    nonisolated(unsafe) private static var _particleObjects: [ParticleEmitterObject] = []
    nonisolated(unsafe) private static var _tessellatables: [Tessellatable] = []
    nonisolated(unsafe) private static var _skyData = ModelData()
    nonisolated(unsafe) private static var _lines: [Line] = []
    nonisolated(unsafe) private static var _icosahedrons: [Icosahedron] = []

    // Locked read accessors. Each returns a Swift CoW snapshot — safe to
    // iterate without holding the lock; subsequent writes won't affect
    // the returned reference.
    public static var modelDatas: [Model: ModelData] {
        stateLock.withLock { _modelDatas }
    }
    public static var transparentObjectDatas: [Model: TransparentObjectData] {
        stateLock.withLock { _transparentObjectDatas }
    }
    public static var particleObjects: [ParticleEmitterObject] {
        stateLock.withLock { _particleObjects }
    }
    public static var tessellatables: [Tessellatable] {
        stateLock.withLock { _tessellatables }
    }
    public static var skyData: ModelData {
        stateLock.withLock { _skyData }
    }
    public static var lines: [Line] {
        stateLock.withLock { _lines }
    }
    public static var icosahedrons: [Icosahedron] {
        stateLock.withLock { _icosahedrons }
    }
```

**Note:** `OSAllocatedUnfairLock` already has a `withLock` method on
recent Apple platforms. The local `withLock(_:_:)` wrapper used by
`LightManager` is from `Utils/TFSLock.swift` — confirm which one is
available before settling on a syntax.

### Changes to write paths

The write paths inside `SceneManager` itself need to take the lock and
mutate the underscore-prefixed backing fields.

**Before** (`SceneManager.swift:155-174` — `TeardownScene`):
```swift
public static func TeardownScene() {
    CurrentScene?.teardownScene()

    // Clear all collections to prevent memory leaks
    modelDatas.removeAll()
    transparentObjectDatas.removeAll()
    particleObjects.removeAll()
    tessellatables.removeAll()
    skyData = ModelData()
    lines.removeAll()
    icosahedrons.removeAll()

    // Clear ring buffer snapshots:
    opaqueSnapshots = [[:], [:], [:]]
    transparentSnapshots = [[:], [:], [:]]
    skySnapshots = [nil, nil, nil]

    _sceneType = nil
    _rendererType = nil
}
```

**After:**
```swift
public static func TeardownScene() {
    CurrentScene?.teardownScene()

    stateLock.withLock {
        _modelDatas.removeAll()
        _transparentObjectDatas.removeAll()
        _particleObjects.removeAll()
        _tessellatables.removeAll()
        _skyData = ModelData()
        _lines.removeAll()
        _icosahedrons.removeAll()

        // Snapshots share the same lock since they're mutated alongside
        // the main collections during teardown.
        opaqueSnapshots = [[:], [:], [:]]
        transparentSnapshots = [[:], [:], [:]]
        skySnapshots = [nil, nil, nil]
    }

    _sceneType = nil
    _rendererType = nil
}
```

**Before** (`Register` and helpers, lines 272-406):
The `Register` switch dispatches to `RegisterObject`, `RegisterSky`, etc.,
which each mutate one or more collections directly:
```swift
static func Register(_ gameObject: GameObject) {
    switch gameObject {
        case is SkyBox, is SkySphere:
            RegisterSky(gameObject)
        case is LightObject:
            print("[DrawMgr RegisterObject] got LightObject")
        case let icosahedron as Icosahedron:
            icosahedrons.append(icosahedron)        // ← unlocked
        case let line as Line:
            lines.append(line)                       // ← unlocked
        case let particleObject as ParticleEmitterObject:
            particleObjects.append(particleObject)   // ← unlocked
        case let tessellatable as Tessellatable:
            tessellatables.append(tessellatable)     // ← unlocked
        case let subMeshGameObject as SubMeshGameObject:
            RegisterSubMeshObject(subMeshGameObject)
        default:
            RegisterObject(gameObject)
    }
}
```

**After** — wrap the whole switch in one lock acquisition:
```swift
static func Register(_ gameObject: GameObject) {
    stateLock.withLock {
        switch gameObject {
            case is SkyBox, is SkySphere:
                _RegisterSky_locked(gameObject)
            case is LightObject:
                print("[SceneManager Register] got LightObject")
            case let icosahedron as Icosahedron:
                _icosahedrons.append(icosahedron)
            case let line as Line:
                _lines.append(line)
            case let particleObject as ParticleEmitterObject:
                _particleObjects.append(particleObject)
            case let tessellatable as Tessellatable:
                _tessellatables.append(tessellatable)
            case let subMeshGameObject as SubMeshGameObject:
                _RegisterSubMeshObject_locked(subMeshGameObject)
            default:
                _RegisterObject_locked(gameObject)
        }
    }
}
```

The `_xxx_locked` variants are the existing `RegisterObject` / `RegisterSky` /
`RegisterSubMeshObject` bodies, renamed to make the locking discipline
explicit. They reach directly into the underscore-prefixed backing fields
and **must not** call back into a public locked accessor (would deadlock
on a non-recursive lock).

### Render-thread reads (no behavior change at call site)

Because the `public static var` accessors keep their old names but now
return CoW snapshots under a brief lock, **DrawManager call sites need
no changes**:

```swift
// DrawManager.swift:289-300 — unchanged at call site, but now safe:
guard !SceneManager.icosahedrons.isEmpty else { return }
...
for ico in SceneManager.icosahedrons {
    _icosahedronUniformsScratch.append(ico.modelConstants)
}
```

The first read takes the lock, returns a snapshot; the second read
takes the lock again, returns another snapshot. In the rare case a
write happens between the two reads, the second snapshot reflects the
new state — but the loop iterates the second snapshot consistently.
**Caveat:** the `guard !.isEmpty` and the `for in` use *different*
snapshots. If correctness depends on them seeing the same state, hoist
to a local:
```swift
let snap = SceneManager.icosahedrons
guard !snap.isEmpty else { return }
for ico in snap { ... }
```
This is the only meaningful call-site change; the rest of `DrawManager`
already uses each accessor exactly once per draw call.

### Update-thread reads in `writeFrameSnapshot`

`writeFrameSnapshot` (`SceneManager.swift:193-253`) iterates
`modelDatas`, `transparentObjectDatas`, and `skyData` directly. It runs
on the update thread and must be coordinated with the lock.

**Before:**
```swift
private static func writeFrameSnapshot(frameIndex: Int) {
    DrawManager.BeginFrameForUpdate(frameIndex: frameIndex)

    var opaque: [Model: RingBufferRegion] = [:]
    opaque.reserveCapacity(modelDatas.count)
    for (model, modelData) in modelDatas {
        ...
    }
    ...
}
```

**After** — take a single snapshot of all three at the top, then iterate
without holding the lock:
```swift
private static func writeFrameSnapshot(frameIndex: Int) {
    DrawManager.BeginFrameForUpdate(frameIndex: frameIndex)

    // Take a coherent snapshot of all read state under one lock.
    let (opaqueSrc, transparentSrc, sky) = stateLock.withLock {
        (_modelDatas, _transparentObjectDatas, _skyData)
    }

    var opaque: [Model: RingBufferRegion] = [:]
    opaque.reserveCapacity(opaqueSrc.count)
    for (model, modelData) in opaqueSrc {
        ...
    }
    opaqueSnapshots[frameIndex] = opaque

    var transparent: [Model: RingBufferRegion] = [:]
    transparent.reserveCapacity(transparentSrc.count)
    for (model, objData) in transparentSrc {
        ...
    }
    transparentSnapshots[frameIndex] = transparent

    if !sky.gameObjects.isEmpty {
        ...
    } else {
        skySnapshots[frameIndex] = nil
    }

    DrawManager.finishUpdateWrites(frameIndex: frameIndex)
}
```

This is a single ~50-nanosecond `OSAllocatedUnfairLock` acquisition per
frame on the update thread. Negligible.

`opaqueSnapshots` / `transparentSnapshots` / `skySnapshots` themselves
remain `nonisolated(unsafe)` because the existing comment still holds:
they're written by the update thread (in this function, between
`BeginFrameForUpdate` and `finishUpdateWrites`) and read by the render
thread (via `getOpaqueSnapshot` etc.) only after a frame completes —
the `inFlightSemaphore` already provides the memory ordering. The lock
acquisition ordering also separates these from the source collections.

### `Paused` setter

`Paused` is a single-field property gated by `_paused: Bool`. It's
accessed from both the menu (main thread) and from `Update` (update
thread). Today it's `nonisolated(unsafe)` and reads/writes are
non-atomic but Swift `Bool` reads are typically aligned word reads,
which are atomic on Apple Silicon and Intel Mac. **Recommendation:** out
of scope for this PR — leave as-is, possibly tighten later. Mention in
the commit message that this was intentional.

### `CurrentScene`, `_sceneType`, `_rendererType`, `nextFrameIndex`

- `CurrentScene` is read by both threads (`SetSceneConstants` etc. on
  render thread, `Update` on update thread). Set during `SetScene`.
  Same race as the collections. Bring under the same lock.
- `_sceneType`, `_rendererType` are only read by `ResetScene` (main
  thread). No concurrent access. Leave as-is.
- `nextFrameIndex` is set by the render thread before signaling the
  update semaphore. Update thread reads it after waking from the
  semaphore. Memory ordering provided by the semaphore. Leave as-is.

---

## Migration order

Land in **two PRs** to keep the diff reviewable:

### PR A — Refactor SceneManager state behind a lock

**Touched files (1):**
- `ToyFlightSimulator Shared/Managers/SceneManager.swift`

**Steps:**
1. Add `private static let stateLock = OSAllocatedUnfairLock()`.
2. Rename each `public static var <name>` to `private static var _<name>`
   (`nonisolated(unsafe)` retained on the underscore-prefixed backing).
3. Add a `public static var <name>` computed property returning the
   locked snapshot.
4. Rename `RegisterObject`, `RegisterSky`, `RegisterSubMeshObject`,
   `registerTransparentObject`, `CreateModelData`,
   `CreateTransparentObjectData` to `_*_locked` variants that mutate the
   underscore-prefixed backing.
5. Rewrite the public `Register(_:)` to take the lock once and dispatch.
6. Wrap `TeardownScene` mutations in a single `withLock` block.
7. Rewrite `writeFrameSnapshot` to take a snapshot tuple under one lock,
   then iterate without holding the lock.
8. Update `SubmeshCount` to use the locked snapshot:
   ```swift
   public static var SubmeshCount: Int {
       let snapshot = modelDatas  // one lock acquisition
       var total = 0
       for (_, data) in snapshot {
           for md in data.meshDatas {
               total += md.opaqueSubmeshes.count + md.transparentSubmeshes.count
           }
       }
       return total
   }
   ```
9. Bring `CurrentScene` under the lock too (consistent with the rest).

**Verification:**
- macOS Debug build clean.
- Full test suite passes.
- Manual test: switch scenes via menu (Cmd+1, 2, 3, etc. depending on
  binding), reset scene multiple times. No crashes, no visual artifacts
  during the swap.
- Optional: enable Thread Sanitizer (Edit Scheme → Diagnostics → Thread
  Sanitizer) and run the app with a few scene swaps. TSAN should report
  zero data races on these fields.

### PR B — Audit and lock the snapshot fields

**Touched files (1):**
- `ToyFlightSimulator Shared/Managers/SceneManager.swift`

**Optional follow-up.** The triple-buffered snapshot arrays
(`opaqueSnapshots`, `transparentSnapshots`, `skySnapshots`) and
`nextFrameIndex` are currently safe by the `inFlightSemaphore` /
`updateDoneSemaphore` handshake. But the safety reasoning is
non-obvious and depends on the renderer correctly using the
semaphores. If you want defense in depth, fold them into the same lock.
The cost is one more locked read per frame on each draw helper — ~50 ns
per call, several calls per frame. Negligible but real.

**Skip this PR if:** semaphore-based ordering is well-understood and
documented in code. The `// uniformsLock removed: ring buffer snapshots
eliminate shared mutable state between threads.` comment at line 124
already documents the reasoning.

---

## Risks and edge cases

### Lock recursion
`OSAllocatedUnfairLock` is **non-recursive**. If any locked block calls
back into a public accessor (which itself takes the lock), it
deadlocks. The migration must be careful to:
- Have public accessors call only locked-internal helpers.
- Never call into `LightManager` etc. while holding `stateLock` — those
  have their own locks and lock ordering must be one-way.

Mitigation: enforce by naming convention (`_*_locked` for internal,
public accessors only call lock once at top).

### Re-entrancy via `GameScene.addChild` → `SceneManager.Register`
`GameScene.addChild(_:)` (`GameScene.swift:33-36`) calls
`registerChildObject(child)` → `SceneManager.Register(childObj)` which
takes the lock. This is fine — `addChild` doesn't hold any lock. But
beware: if `SceneManager.Register` ever needs to invoke a method on the
GameObject that itself triggers another `SceneManager.Register`, that's
a lock re-entry deadlock. Currently no such recursion exists; verify
by grep when implementing.

### Performance
- **Update thread:** one lock acquisition per `writeFrameSnapshot` call
  (60 Hz). ~50 ns. Imperceptible.
- **Render thread:** one lock acquisition per draw helper call. The
  helpers we care about are `DrawIcosahedrons`, `DrawSky`,
  `DrawParticles`, `DrawTessellatables`, `DrawLines` — five
  acquisitions per frame at 60 fps = 300/s. Imperceptible.
- **Main thread (scene transition):** lock held briefly during the
  `Register` switch, briefly during `TeardownScene`. Worst case scene
  has tens of GameObjects → tens of `Register` calls each acquiring +
  releasing → still microseconds total. Imperceptible.

### Behavior change
None expected. The lock is a guard, not a coordination primitive — it
serializes accesses but doesn't introduce new wait points beyond the
brief lock acquisitions. Steady-state frame timing unchanged.

---

## Why not `actor`?

Swift 6 `actor` is the long-term right answer, but:
- It would force every public method (and accessor) to be `async` at
  every call site, which is a much larger refactor — render-loop hot
  paths are not async-friendly, and the engine's `nonisolated(unsafe)`
  pattern is consistent throughout.
- `LightManager` already established the lock pattern as the
  project's convention.

Actor migration is a separate, larger architectural change. Out of
scope for the simplification series.

---

## Acceptance criteria

- [ ] `SceneManager.swift` no longer exposes any directly-mutable
      `public static var` for the seven collections; all access goes
      through computed properties or methods that take `stateLock`.
- [ ] All callers in `DrawManager`, scenes, and renderers continue to
      compile without changes (or with only the `let snap = ...`
      hoist where atomic between two reads is required).
- [ ] Full test suite passes.
- [ ] Manual scene-swap stress test passes with no crashes/glitches.
- [ ] (Optional) Thread Sanitizer reports zero data races on
      SceneManager fields during a 60-second session that includes
      several scene swaps.

---

## Open questions

1. **Should `Paused` get the same treatment?** Argument for: consistency.
   Argument against: it's a single Bool, and the existing
   `nonisolated(unsafe)` is functionally fine on Apple platforms.
   *Recommendation:* leave alone, document in the commit.

2. **What's the right place to put the lock helper?** `withLock(_:_:)`
   in `Utils/TFSLock.swift` (used by `LightManager`) vs. the built-in
   `OSAllocatedUnfairLock.withLock { ... }` method (Swift 5.9+). The
   built-in is preferable — drop the custom wrapper if no other callers
   need it. *Recommendation:* migrate `LightManager` to the built-in
   method too in a tiny follow-up PR after this lands, retire the
   custom wrapper.

3. **Should this land before or after Q6 (print cleanup), Q8
   (commented-code deletion), etc.?** This is independent of those.
   *Recommendation:* land independently whenever it's ready.
