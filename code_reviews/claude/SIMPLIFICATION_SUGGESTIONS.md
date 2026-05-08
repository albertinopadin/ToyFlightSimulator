# ToyFlightSimulator — Simplification Suggestions

**Generated:** 2026-05-07
**Scope:** Whole codebase review (~168 Swift files + 22 Metal shaders)
**Status:** Suggestions only — nothing applied yet. Review and approve items before implementation.

This document is the consolidated output of three parallel review passes:

1. **Reuse** — duplicated logic, hand-rolled code where utilities exist
2. **Quality** — hacky patterns, force unwraps, leaky abstractions, dead code
3. **Efficiency** — per-frame allocations, hot-path waste, lock contention

Findings are grouped by category and ranked by impact. Each finding includes verified file paths/line numbers, a before/after sample, and a brief note on why it's worth doing (or why you might skip it).

---

## TL;DR — What I'd Do First

If you only want to do a few high-leverage cleanups, in this order:

1. **E1** — Cache `meshDatas` for transparent objects (per-frame `.map` allocation in hot path)
2. **E2/E3** — Cache light/icosahedron uniform arrays (per-frame `.map` allocations during render encoding)
3. **E5** — One-line fix: `lastFramePositions.removeAll(keepingCapacity: true)` in physics broad phase
4. **R4 + R11** — Move `addGround()` and the sky-setup switch into `GameScene` (7 scenes copy `addGround`, 4 copy the sky switch)
5. **Q13** — Delete the 2 duplicate `sourceRGB/AlphaBlendFactor = .one` lines in `SinglePassDeferredPipeline.swift` (clearly a copy-paste bug)
6. **R1/R2** — Collapse the three perspective + two orthographic projection implementations into `Transform`

Everything else is incremental; I'd batch the architectural items (gear-state dedup, animator base class extraction, force-unwrap removal) into separate PRs to keep diffs reviewable.

---

# Section 1 — Efficiency (Per-Frame Hot Paths)

These are the highest-impact items because they fire every frame at 60+ Hz.

## E1 — Per-frame `MeshData` allocation for transparent objects [CRITICAL]

**File:** `ToyFlightSimulator Shared/Managers/SceneManager.swift:227-231` (inside `writeFrameSnapshot`)

`writeFrameSnapshot` runs every update tick. For each transparent model it allocates a fresh `[MeshData]` via `.map`, even though the mesh layout never changes after registration. Opaque objects already cache `modelData.meshDatas` — transparent ones should too.

**Before:**
```swift
transparent[model] = RingBufferRegion(
    offset: offset,
    count: gameObjects.count,
    meshDatas: model.meshes.map { mesh in
        MeshData(mesh: mesh,
                 opaqueSubmeshes: [],
                 transparentSubmeshes: mesh.submeshes)
    }
)
```

**After:** Cache `meshDatas` in `TransparentObjectData` at registration (the place where transparent objects are first added to `transparentObjectDatas`), then reuse:

```swift
// In TransparentObjectData (one-time at registration):
self.meshDatas = model.meshes.map { mesh in
    MeshData(mesh: mesh, opaqueSubmeshes: [], transparentSubmeshes: mesh.submeshes)
}

// In writeFrameSnapshot:
transparent[model] = RingBufferRegion(
    offset: offset,
    count: gameObjects.count,
    meshDatas: objData.meshDatas       // reused reference, no allocation
)
```

**Why:** Eliminates N + 1 allocations per frame per transparent model (1 outer array + N MeshData). At 60 fps with several transparent models, that's hundreds of allocations/sec for no reason.

---

## E2 — `LightManager` allocates light arrays every frame [HIGH]

**File:** `ToyFlightSimulator Shared/Managers/LightManager.swift:21-41`

Every render frame, `GetDirectionalLightData` and `GetPointLightData`:
1. Acquire a lock,
2. Filter the master light array (`.filter` allocates),
3. Then `.map { $0.lightData }` allocates again.

Three allocations per frame per light type, all under a lock.

**Before:**
```swift
public static func GetLightObjects(lightType: LightType) -> [LightObject] {
    withLock(lightLock) {
        return Self._lightObjects.filter { $0.lightType == lightType }
    }
}

public static func GetDirectionalLightData(viewMatrix: float4x4) -> [LightData] {
    let lightObjs = Self.GetLightObjects(lightType: Directional)
    lightObjs.forEach { $0.lightData.lightEyeDirection = normalize(viewMatrix * float4($0.getPosition(), 1)).xyz }
    return lightObjs.map { $0.lightData }
}
```

**After:** Maintain pre-bucketed arrays updated only when lights are added/removed, plus a reusable scratch buffer for `LightData`:

```swift
private static var _directionalLights: [LightObject] = []
private static var _pointLights: [LightObject] = []
private static var _directionalDataScratch: [LightData] = []
private static var _pointDataScratch: [LightData] = []

public static func AddLightObject(_ lightObject: LightObject) {
    withLock(lightLock) {
        Self._lightObjects.append(lightObject)
        switch lightObject.lightType {
        case Directional: Self._directionalLights.append(lightObject)
        case Point:       Self._pointLights.append(lightObject)
        default: break
        }
    }
}

public static func GetDirectionalLightData(viewMatrix: float4x4) -> [LightData] {
    withLock(lightLock) {
        Self._directionalDataScratch.removeAll(keepingCapacity: true)
        for light in Self._directionalLights {
            light.lightData.lightEyeDirection =
                normalize(viewMatrix * float4(light.getPosition(), 1)).xyz
            Self._directionalDataScratch.append(light.lightData)
        }
        return Self._directionalDataScratch
    }
}
```

**Caveat:** Returning a reference to the scratch buffer is fine because callers immediately copy into the encoder via `setFragmentBytes`. If you ever cache the returned array, this changes — but a quick grep shows no callers currently do.

---

## E3 — `DrawPointLights` / `DrawIcosahedrons` per-frame `.map` and `.flatMap` [HIGH]

**File:** `ToyFlightSimulator Shared/Managers/DrawManager.swift:257-287`

Same pattern — array allocations every render frame for data that's static for many frames.

**Before:**
```swift
static func DrawPointLights(with renderEncoder: MTLRenderCommandEncoder) {
    let pointLights = LightManager.GetLightObjects(lightType: Point)
    let uniforms = pointLights.map { $0.modelConstants }
    let pointLightModel = Assets.Models[.Icosahedron]
    let submeshes = pointLightModel.meshes.flatMap { $0.submeshes }

    if !pointLights.isEmpty {
        Draw(renderEncoder, model: pointLightModel, uniforms: uniforms,
             mesh: pointLightModel.meshes.first!, submeshes: submeshes,
             applyMaterials: true)
    }
}
```

**After:** Cache `submeshes` once (it's invariant once the model is loaded); fill a reusable `uniforms` buffer in place:

```swift
private static var _pointLightUniformsScratch: [ModelConstants] = []
private static var _pointLightSubmeshes: [Submesh]?

static func DrawPointLights(with renderEncoder: MTLRenderCommandEncoder) {
    let pointLights = LightManager.GetLightObjects(lightType: Point)
    guard !pointLights.isEmpty else { return }

    let pointLightModel = Assets.Models[.Icosahedron]
    if _pointLightSubmeshes == nil {
        _pointLightSubmeshes = pointLightModel.meshes.flatMap { $0.submeshes }
    }
    _pointLightUniformsScratch.removeAll(keepingCapacity: true)
    for l in pointLights { _pointLightUniformsScratch.append(l.modelConstants) }

    Draw(renderEncoder, model: pointLightModel,
         uniforms: _pointLightUniformsScratch,
         mesh: pointLightModel.meshes.first!,    // see Q1: replace with safe accessor
         submeshes: _pointLightSubmeshes!,
         applyMaterials: true)
}
```

Apply the same pattern to `DrawIcosahedrons` (lines 273-287).

---

## E4 — Broad-phase per-frame `Set` and `filter` allocations [HIGH]

**File:** `ToyFlightSimulator Shared/Physics/BroadPhase/BroadPhaseCollisionDetector.swift:36-68, 186-225`

Every physics tick, `update(entities:)` filters static/dynamic entities, then `performInsertionSort` builds two `Set<UUID>` instances to detect adds/removes.

**Before (lines 40-41):**
```swift
staticEntities = entities.filter { $0.isStatic }
let dynamicEntities = entities.filter { $0.isDynamic }
```

**Before (lines 191-198):**
```swift
let currentIds = Set(dynamicEntities.map { $0.id })
let sortedIds = Set(sorted.map { $0.id })

sorted.removeAll { !currentIds.contains($0.id) }
let newEntities = dynamicEntities.filter { !sortedIds.contains($0.id) }
```

**After:** Track static/dynamic membership in `setEntities` (when entities are added/removed, not every frame). For the insertion-sort path, replace ad-hoc Sets with reused `Set` instances stored on the detector:

```swift
private var _staticEntitiesCache: [PhysicsEntity] = []
private var _dynamicEntitiesCache: [PhysicsEntity] = []
private var _currentIdsScratch: Set<UUID> = []
private var _sortedIdsScratch: Set<UUID> = []

func setEntities(_ entities: [PhysicsEntity]) {
    _staticEntitiesCache = entities.filter { $0.isStatic }
    _dynamicEntitiesCache = entities.filter { $0.isDynamic }
}

func update(entities: [PhysicsEntity]) {
    // No filtering here — use cached lists
    let dynamicEntities = _dynamicEntitiesCache
    staticEntities = _staticEntitiesCache
    ...
}

private func performInsertionSort(_ dynamicEntities: [PhysicsEntity]) {
    _currentIdsScratch.removeAll(keepingCapacity: true)
    _sortedIdsScratch.removeAll(keepingCapacity: true)
    for e in dynamicEntities { _currentIdsScratch.insert(e.id) }
    for e in sortedDynamicEntities { _sortedIdsScratch.insert(e.id) }
    ...
}
```

**Caveat to verify:** Make sure entity static/dynamic state really doesn't change at runtime in this codebase — `CollidablePlane.isStatic = true` in scene setup looks fixed, but if any entity flips at runtime, this needs an invalidation hook.

---

## E5 — `lastFramePositions.removeAll()` deallocates the dictionary every frame [MEDIUM-HIGH]

**File:** `ToyFlightSimulator Shared/Physics/BroadPhase/BroadPhaseCollisionDetector.swift:228-234`

One-line fix.

**Before:**
```swift
private func updateLastFramePositions(_ dynamicEntities: [PhysicsEntity]) {
    lastFramePositions.removeAll()
    for entity in dynamicEntities {
        lastFramePositions[entity.id] = entity.getPosition()
    }
}
```

**After:**
```swift
private func updateLastFramePositions(_ dynamicEntities: [PhysicsEntity]) {
    lastFramePositions.removeAll(keepingCapacity: true)
    for entity in dynamicEntities {
        lastFramePositions[entity.id] = entity.getPosition()
    }
}
```

**Why:** `removeAll()` (no parameter) drops the hash table backing storage. Reusing capacity avoids reallocation each tick.

---

## E6 — `SceneManager.SubmeshCount` recomputes via `.map` on every read [MEDIUM]

**File:** `ToyFlightSimulator Shared/Managers/SceneManager.swift:406-410`

If this is called from a per-frame stats overlay (`FlightboxScene.swift:230` does call it once at scene build, but it's also exposed for runtime inspection), each call allocates and reduces.

**Before:**
```swift
public static var SubmeshCount: Int {
    return modelDatas.map {
        $0.value.meshDatas.reduce(0) { $0 + $1.opaqueSubmeshes.count + $1.transparentSubmeshes.count }
    }.reduce(0, +)
}
```

**After:** Maintain a cached counter updated in `CreateModelData` / removal paths, or compute lazily without the intermediate array:

```swift
public static var SubmeshCount: Int {
    var total = 0
    for (_, data) in modelDatas {
        for md in data.meshDatas {
            total += md.opaqueSubmeshes.count + md.transparentSubmeshes.count
        }
    }
    return total
}
```

The intermediate-free version eliminates the outer array allocation; if it's called per-frame anywhere, also cache the count.

---

## E7 — `for case let ... as ProceduralAnimationChannel` performs a runtime cast per iteration [MEDIUM]

**File:** `ToyFlightSimulator Shared/Animation/Animators/AircraftAnimator.swift:210-266` (rollAilerons, rollFlaperons, deflectHorizontalStabilizers, yawRudders)

Every input frame for an aircraft using procedural channels iterates with `for case let`, which is a runtime type check per element.

**Before:**
```swift
func rollAilerons(value: Float) {
    guard let layer = aileronLayer else { return }
    for case let channel as ProceduralAnimationChannel in layer.channels {
        channel.setValue(value)
    }
}
```

**After:** Store a typed array of `ProceduralAnimationChannel` directly on each layer (or on the animator) at registration time:

```swift
private var aileronProceduralChannels: [ProceduralAnimationChannel] = []

// At registration:
aileronProceduralChannels = layer.channels.compactMap { $0 as? ProceduralAnimationChannel }

func rollAilerons(value: Float) {
    for ch in aileronProceduralChannels { ch.setValue(value) }
}
```

**Why:** Removes the type cast from the hot path. For aircraft like F22 that call this every frame for pitch/roll/yaw, this is small but real.

---

# Section 2 — Code Reuse

## R1 — Three perspective-projection implementations [HIGH IMPACT]

**Files:**
- `Math/Math.swift:114-134` — `matrix_float4x4.perspective(degreesFov:aspectRatio:near:far:)`
- `Math/MathUtils.swift:126-139` — `float4x4.init(perspectiveProjectionFoVY:aspectRatio:near:far:)`
- `Math/Transform.swift:73-88` — `Transform.perspectiveProjection(_:_:_:_:)` ← already documented as canonical

`Math.swift:115` literally says "See also: Transform.perspectiveProjection (canonical version, takes radians)" but the function still re-implements the math.

**Before — Math.swift:**
```swift
static func perspective(degreesFov: Float, aspectRatio: Float, near: Float, far: Float) -> matrix_float4x4 {
    let fov = degreesFov.toRadians
    let t: Float = tan(fov / 2)
    let x: Float = 1 / (aspectRatio * t)
    let y: Float = 1 / t
    let z: Float = far / (far - near)
    let w: Float = -(near * far) / (far - near)
    var result = matrix_identity_float4x4
    result.columns = (float4(x,0,0,0), float4(0,y,0,0), float4(0,0,z,1), float4(0,0,w,0))
    return result
}
```

**After — Math.swift:**
```swift
@available(*, deprecated, message: "Use Transform.perspectiveProjection (radians).")
static func perspective(degreesFov: Float, aspectRatio: Float, near: Float, far: Float) -> matrix_float4x4 {
    Transform.perspectiveProjection(degreesFov.toRadians, aspectRatio, near, far)
}
```

Then update the few callers (Camera/AttachedCamera/DebugCamera) to call `Transform.perspectiveProjection` directly with radians, and delete the deprecated wrappers when callers are migrated.

**Caveat:** Verify that all three implementations produce numerically identical matrices for the same inputs before consolidating. From inspection they're algebraically equivalent (`w = -near*far/(far-near)` vs `-nearZ*zs` where `zs = far/(far-near)`), but a one-shot Swift Testing assertion is cheap insurance.

---

## R2 — Two orthographic-projection implementations [HIGH IMPACT]

**Files:**
- `Math/MathUtils.swift:109-122` — `float4x4.init(orthographicProjectionWithLeft:top:right:bottom:near:far:)`
- `Math/Transform.swift:59-71` — `Transform.orthographicProjection(_:_:_:_:_:_:)`

Same pattern as R1. Different parameter orders + different sign conventions on Z. Keep `Transform.orthographicProjection` as canonical.

---

## R3 — `addGround()` copy-pasted across 7 scenes [HIGH IMPACT, EASY]

Verified `grep` results — `addGround()` is defined in **all of these** with near-identical bodies:

- `Scenes/PhysicsStressTestScene.swift:88`
- `Scenes/FlightboxScene.swift:22`
- `Scenes/BallPhysicsScene.swift:82`
- `Scenes/FreeCamFlightboxScene.swift:21`
- `Scenes/FlightboxWithPhysics.swift:17`
- `Scenes/FlightboxWithTerrain.swift:16`

**Before — repeated in every scene:**
```swift
private func addGround() {
    let groundColor = float4(0.3, 0.7, 0.1, 1.0)
    let ground = CollidablePlane()
    ground.collisionNormal = [0, 1, 0]
    ground.collisionShape = .Plane
    ground.restitution = 1.0
    ground.isStatic = true
    ground.setColor(groundColor)
    ground.rotateZ(Float(270).toRadians)
    ground.setScale(1000)
    addChild(ground)
    entities.append(ground)
}
```

**After — once in `GameScene` base:**
```swift
// GameScene.swift
@discardableResult
public func addGround(color: float4 = float4(0.3, 0.7, 0.1, 1.0),
                     scale: Float = 1000) -> CollidablePlane {
    let ground = CollidablePlane()
    ground.collisionNormal = [0, 1, 0]
    ground.collisionShape = .Plane
    ground.restitution = 1.0
    ground.isStatic = true
    ground.setColor(color)
    ground.rotateZ(Float(270).toRadians)
    ground.setScale(scale)
    addChild(ground)
    return ground
}
```

**Caveat:** Each subclass also appends to its own local `entities: [PhysicsEntity]` array. That `entities` list is itself duplicated across scenes (it's redundant — the scene already tracks children). You could either return the ground for the caller to append, or — cleaner — let `GameScene` own a `physicsEntities` array if more than one scene needs it.

---

## R4 — Sky-setup switch copy-pasted across 4 scenes [MEDIUM IMPACT, EASY]

**Files (verified by grep):**
- `Scenes/FlightboxScene.swift:70-79`
- `Scenes/FlightboxWithPhysics.swift:44`
- `Scenes/FlightboxWithTerrain.swift:47`
- `Scenes/FreeCamFlightboxScene.swift:43`

**Before:**
```swift
switch _rendererType {
    case .OrderIndependentTransparency:
        let sky = SkySphere(textureType: .Clouds_Skysphere)
        addChild(sky)
    case .SinglePassDeferredLighting:
        let sky = SkyBox(textureType: .SkyMap)
        addChild(sky)
    default:
        print("No sky")
}
```

**After — `GameScene`:**
```swift
public func setupDefaultSky() {
    switch _rendererType {
    case .OrderIndependentTransparency:
        addChild(SkySphere(textureType: .Clouds_Skysphere))
    case .SinglePassDeferredLighting:
        addChild(SkyBox(textureType: .SkyMap))
    default:
        break    // silent — scenes that need a different sky override
    }
}
```

Note: `FreeCamFlightboxScene.swift:43-49` uses an `if/else` instead of `switch` and adds a SkyBox for any non-OIT renderer. Decide which behavior is correct before consolidating.

---

## R5 — Aircraft animator setup boilerplate (F35 vs F22_CGTrader) [MEDIUM]

**Files:**
- `GameObjects/F35.swift:26-50`
- `GameObjects/F22_CGTrader.swift:24-57`

**Before (F35.swift:26-36):**
```swift
private func setupAnimator() {
    guard let usdModel = model as? UsdModel else {
        print("[F35] Warning: Model is not a UsdModel, animations will not be controlled")
        return
    }
    animator = F35Animator(model: usdModel)
    print("[F35] F35Animator initialized with duration: \(animator?.gearAnimationDuration ?? 0)")
}
```

F22_CGTrader has the same body modulo a class tag.

**After — generic helper in `Aircraft`:**
```swift
// Aircraft.swift
func setupAnimator<A: AircraftAnimator>(_ make: (UsdModel) -> A) {
    guard let usdModel = model as? UsdModel else {
        print("[\(getName())] Warning: Model is not a UsdModel; animations disabled")
        return
    }
    animator = make(usdModel)
}

// F35.swift
init(scale: Float = 1.0, shouldUpdateOnPlayerInput: Bool = true) {
    super.init(name: Self.NAME, modelType: .Sketchfab_F35,
               scale: scale, shouldUpdateOnPlayerInput: shouldUpdateOnPlayerInput)
    setupAnimator(F35Animator.init)
}
```

The per-frame `animator?.update(deltaTime:)` and gear-toggle pattern in both `doUpdate()` overrides could likewise move into `Aircraft.doUpdate()`, with subclasses overriding only the control-surface inputs that differ.

---

## R6 — Three near-identical `setGBufferTextures` / `setDepthAndStencilTextures` methods [MEDIUM]

**Files:**
- `Display/TiledDeferredRenderer.swift:70-82`
- `Display/TiledMultisampleRenderer.swift:86-98`
- `Display/TiledMSAATessellatedRenderer.swift:91-104`

The three deferred renderers each define identical methods to wire GBuffer and depth attachments. Pull them up into a default protocol implementation:

**Before — duplicated in three files:**
```swift
func setGBufferTextures(_ rpd: MTLRenderPassDescriptor) {
    rpd.colorAttachments[TFSRenderTargetAlbedo.index].texture  = gBufferTextures.albedoTexture
    rpd.colorAttachments[TFSRenderTargetNormal.index].texture  = gBufferTextures.normalTexture
    rpd.colorAttachments[TFSRenderTargetPosition.index].texture = gBufferTextures.positionTexture
    setDepthAndStencilTextures(rpd)
}

func setDepthAndStencilTextures(_ rpd: MTLRenderPassDescriptor) {
    rpd.depthAttachment.texture       = gBufferTextures.depthTexture
    rpd.depthAttachment.storeAction   = .dontCare
    rpd.stencilAttachment.texture     = gBufferTextures.depthTexture
    rpd.stencilAttachment.storeAction = .dontCare
}
```

**After — protocol default in `Display/Protocols/`:**
```swift
protocol TiledGBufferRendering: AnyObject {
    var gBufferTextures: TiledDeferredGBufferTextures { get }
}

extension TiledGBufferRendering {
    func setGBufferTextures(_ rpd: MTLRenderPassDescriptor) {
        rpd.colorAttachments[TFSRenderTargetAlbedo.index].texture  = gBufferTextures.albedoTexture
        rpd.colorAttachments[TFSRenderTargetNormal.index].texture  = gBufferTextures.normalTexture
        rpd.colorAttachments[TFSRenderTargetPosition.index].texture = gBufferTextures.positionTexture
        setDepthAndStencilTextures(rpd)
    }
    func setDepthAndStencilTextures(_ rpd: MTLRenderPassDescriptor) {
        rpd.depthAttachment.texture       = gBufferTextures.depthTexture
        rpd.depthAttachment.storeAction   = .dontCare
        rpd.stencilAttachment.texture     = gBufferTextures.depthTexture
        rpd.stencilAttachment.storeAction = .dontCare
    }
}
```

---

## R7 — Additive blending boilerplate duplicated in 3 pipeline structs [LOW-MEDIUM]

**Files:**
- `Graphics/Libraries/Pipelines/Render/SinglePassDeferredPipeline.swift:77-87` — `TransparencyPipelineState.enableBlending`
- `Graphics/Libraries/Pipelines/Render/TiledDeferredPipeline.swift:78-88, 105-115` — two copies

Same body. Push into the `RenderPipelineState` protocol extension:

```swift
extension RenderPipelineState {
    static func enableAdditiveBlending(_ ca: MTLRenderPipelineColorAttachmentDescriptor) {
        ca.isBlendingEnabled = true
        ca.rgbBlendOperation = .add
        ca.alphaBlendOperation = .add
        ca.sourceRGBBlendFactor = .one
        ca.sourceAlphaBlendFactor = .one
        ca.destinationRGBBlendFactor = .one
        ca.destinationAlphaBlendFactor = .zero
    }
}
```

Note: while doing this, drop the duplicate `sourceRGBBlendFactor = .one` / `sourceAlphaBlendFactor = .one` lines (see Q13).

---

## R8 — `TextureLoader` options dictionary built inline in some paths [LOW]

**File:** `AssetPipeline/Libraries/Textures/TextureLoader.swift`

Lines 35 and 59 build an options dictionary inline; lines 84, 102, 117 use the existing helper `MakeTextureLoaderOptions` (defined at line 128). Just route the first two through the helper for consistency.

---

# Section 3 — Code Quality

## Q1 — `model.meshes.first!` and `LightManager...first!` force-unwrap chains [HIGH]

**File:** `ToyFlightSimulator Shared/Managers/DrawManager.swift:267, 278, 283, 299, 300`
**File:** `ToyFlightSimulator Shared/Scenes/GameScene.swift:142`

`pointLightModel.meshes.first!` and `SceneManager.icosahedrons.first!.model.meshes.first!` are reachable from `draw()` — a missing model crashes the renderer.

**Before:**
```swift
let mesh = pointLightModel.meshes.first!
...
mesh: SceneManager.icosahedrons.first!.model.meshes.first!,
```

**After:** Add a safe accessor on `Model`:
```swift
extension Model {
    var primaryMesh: Mesh? { meshes.first }
}

guard let mesh = pointLightModel.primaryMesh else {
    assertionFailure("Icosahedron model missing meshes"); return
}
```

`assertionFailure` keeps the bug visible in debug builds without crashing a shipping binary.

---

## Q2 — Aircraft gear state duplicated across `Aircraft._legacyGearDown` and `AircraftAnimator` [HIGH]

**Files:**
- `GameObjects/Aircraft.swift:20-30`
- `Animation/Animators/AircraftAnimator.swift:269-272`

**Before:**
```swift
// Aircraft.swift
var isGearDown: Bool {
    if let animator = animator {
        return animator.isGearDown
    }
    return _legacyGearDown
}
private var _legacyGearDown: Bool = true
```

**Why this is fragile:** `_legacyGearDown` is private and never written by anything visible in `Aircraft.swift`. It's effectively a constant `true` for legacy aircraft, so it's not really tracking state — it's a fallback default dressed up as state.

**After:**
```swift
var isGearDown: Bool {
    animator?.isGearDown ?? true   // legacy aircraft: always considered down
}
```

Delete `_legacyGearDown`. If a non-animator aircraft ever needs to actually toggle gear, the right answer is to give it an animator (or a stub gear-state object), not to keep a parallel boolean.

---

## Q3 — `nonisolated(unsafe)` static mutable state in `SceneManager` [HIGH — review carefully]

**File:** `ToyFlightSimulator Shared/Managers/SceneManager.swift:87-99`

The file itself contains a TODO ("wrap this in a thread safe container (?)") for these mutables:
```swift
nonisolated(unsafe) public static var modelDatas: [Model: ModelData] = [:]
nonisolated(unsafe) public static var transparentObjectDatas: [Model: TransparentObjectData] = [:]
nonisolated(unsafe) public static var particleObjects: [ParticleEmitterObject] = []
nonisolated(unsafe) public static var tessellatables: [Tessellatable] = []
nonisolated(unsafe) public static var skyData = ModelData()
nonisolated(unsafe) public static var lines: [Line] = []
nonisolated(unsafe) public static var icosahedrons: [Icosahedron] = []
```

Update thread mutates these (during `addChild`); render thread reads them. The render-thread reads happen after `writeFrameSnapshot` finishes for that frame, so the **snapshot** path is safe — but ad-hoc reads (e.g., `SceneManager.icosahedrons` in `DrawIcosahedrons`) are not.

**Recommendation:** Put adds/removes through the same lock pattern `LightManager` uses (`OSAllocatedUnfairLock`), and have render-thread reads either pull from the per-frame snapshot or take the lock briefly. This is a bigger change — flagging for awareness; don't lump it into a "simplify" PR.

---

## Q4 — Implicitly unwrapped `var model: Model!` on `GameObject` [MEDIUM]

**File:** `ToyFlightSimulator Shared/GameObjects/GameObject.swift:33, ~47-55`

```swift
public var model: Model!
init(name: String, modelType: ModelType) {
    super.init(name: name)
    model = Assets.Models[modelType]
    model.parent = self
    print("GameObject init; named \(self.getName())")
}
```

**Issues:**
1. `Assets.Models[modelType]` returning nil → crash on next line.
2. The TODO already in the file admits `model.parent = self` is wrong (it's overwritten when another GameObject loads the same model).

**After:** Make `model` a non-optional `let`, fail loudly during scene build (where it's recoverable), and drop the parent assignment that was acknowledged as wrong:
```swift
public let model: Model

init(name: String, modelType: ModelType) {
    guard let model = Assets.Models[modelType] else {
        fatalError("Model \(modelType) is not registered. Add it to ModelLibrary.")
    }
    self.model = model
    super.init(name: name)
}
```

`fatalError` is fine here because this is a developer error (forgot to register a model), not a runtime condition.

---

## Q5 — Material texture binding has 3 identical if/else branches [MEDIUM]

**File:** `ToyFlightSimulator Shared/Managers/DrawManager.swift:469-494` (`applyMaterialTextures`)

**Before:**
```swift
if let baseColorTexture = material.baseColorTexture {
    renderEncoder.setFragmentTexture(baseColorTexture, index: TFSTextureIndexBaseColor.index)
} else {
    renderEncoder.setFragmentTexture(nil, index: TFSTextureIndexBaseColor.index)
}
if let normalMapTexture = material.normalMapTexture { ... } else { ... }
if let specularTexture = material.specularTexture { ... } else { ... }
```

**After:**
```swift
let bindings: [(MTLTexture?, Int)] = [
    (material.baseColorTexture, TFSTextureIndexBaseColor.index),
    (material.normalMapTexture, TFSTextureIndexNormal.index),
    (material.specularTexture,  TFSTextureIndexSpecular.index),
]
for (tex, idx) in bindings {
    renderEncoder.setFragmentTexture(tex, index: idx)
}
```

Each `if let ... else { setFragmentTexture(nil, ...) }` is just `setFragmentTexture(optional, ...)` — Metal accepts a nil texture.

---

## Q6 — `print(...)` calls in per-init / per-input paths [MEDIUM]

Verified hotspots:
- `Aircraft.swift:40` — every aircraft init
- `GameObject.swift:54` — every GameObject init
- `F35.swift:35`, `F22_CGTrader.swift:33` — animator setup
- `AircraftAnimator.swift:108-111, 200, 204, 212, 225, 244, 259` — every gear toggle and every input frame for control surfaces
- `GameScene.swift:105, 109` — every click/focus event

**Before:**
```swift
print("[Aircraft init] name: \(name), scale: \(scale)")
```

**After:**
```swift
#if DEBUG
print("[Aircraft init] name: \(name), scale: \(scale)")
#endif
```

Or migrate to `os.Logger`:
```swift
import os
private let logger = Logger(subsystem: "TFS", category: "Aircraft")
logger.debug("Aircraft init name=\(name) scale=\(scale)")
```

**Especially urgent:** the `print` calls in `rollAilerons`/`rollFlaperons`/etc. fire every input frame when the corresponding layer is missing — that's a flood.

---

## Q7 — Stringly-typed animation layer IDs [MEDIUM]

**Files:**
- `Animation/Animators/AircraftAnimator.swift:48-52`
- `Animation/Configs/F22AnimationConfig.swift:11` (the file even has a TODO about this)

**Before:**
```swift
static let landingGearLayerID = "landingGear"
static let flaperonLayerID    = "flaperon"
// ...also redeclared in F22AnimationConfig.swift
```

**After:**
```swift
enum AnimationLayerID: String {
    case landingGear, flaperon, aileron, horizontalStabilizer, rudder
}
```

---

## Q8 — Dead/commented code in `FlightboxScene.swift` and `F18.swift` [LOW, EASY]

**FlightboxScene.swift** has commented blocks at lines 19, 40-46, 56-68, 119-126, 128-144, 146, 174-186, 190-196, 203-206, 218-221 — roughly 60 lines of commented code mixed in with live logic.

**F18.swift:10-18** has a commented `class Store` definition followed immediately by the live `final class Store` — the comment block is just an old version.

**Recommendation:** Delete. Git history has it if you ever need it back.

---

## Q9 — Two identically-implemented `shouldRenderSubmesh` overloads [LOW]

**File:** `GameObjects/GameObject.swift:78-84`

```swift
public func shouldRenderSubmesh(_ submesh: Submesh) -> Bool { return true }
public func shouldRenderSubmesh(_ submeshName: String) -> Bool { return true }
```

Both unconditionally return `true`. Find callers; if neither is overridden anywhere meaningful, delete them. If subclasses override only one, drop the unused overload.

---

## Q10 — `DrawFromRingBuffer` and `Draw` in `DrawManager` are 90% identical [MEDIUM]

**File:** `ToyFlightSimulator Shared/Managers/DrawManager.swift:368-422` and `:426-467`

The two functions differ only in how they bind uniforms (`region.offset` from a ring buffer vs `setVertexBytes` for inline uniforms). Extract a `UniformsSource` enum or use a small closure:

```swift
enum UniformsSource {
    case ringBuffer(offset: Int)
    case inline([ModelConstants])
}

private static func draw(
    _ renderEncoder: MTLRenderCommandEncoder,
    model: Model, mesh: Mesh, submeshes: [Submesh],
    uniforms: UniformsSource, applyMaterials: Bool
) { ... }
```

This is a moderate refactor — worth doing once, but make sure to land it in its own PR with the existing tests passing.

---

## Q11 — Inconsistent matrix construction APIs across `Math.swift` and `MathUtils.swift` [MEDIUM]

**Files:**
- `Math/Math.swift` — mutating functions on `matrix_float4x4` (translate, scale, rotate)
- `Math/MathUtils.swift` — initializers on `float4x4` (`init(scale:)`, `init(rotateAbout:byAngle:)`, `init(translate:)`)

Two different idioms for the same operation. Standardize on the immutable initializer style in `Transform`/`MathUtils` and either delete or make the mutating versions trivial wrappers:

```swift
extension matrix_float4x4 {
    @available(*, deprecated, message: "Use Transform.translation/rotation/scale or simd_float4x4 initializers")
    mutating func translate(direction: float3) {
        self = self * float4x4(translate: direction)
    }
}
```

---

## Q12 — `CameraManager.CurrentCamera: Camera!` is force-unwrapped global [MEDIUM]

**File:** `ToyFlightSimulator Shared/Managers/CameraManager.swift:9-10`

```swift
nonisolated(unsafe) public static var CurrentCamera: Camera!
```

Anyone reading before a camera is set crashes. Make it `Camera?` and have `SetCamera` / accessors handle the nil case (or fail loudly with `assertionFailure` once during scene build).

---

## Q13 — Duplicate blend-factor lines (clearly a copy-paste bug) [LOW, INSTANT]

**File:** `Graphics/Libraries/Pipelines/Render/SinglePassDeferredPipeline.swift:77-87`

```swift
colorAttachment.sourceRGBBlendFactor = .one
colorAttachment.sourceAlphaBlendFactor = .one
colorAttachment.destinationRGBBlendFactor = .one
colorAttachment.destinationAlphaBlendFactor = .zero
colorAttachment.sourceRGBBlendFactor = .one        // ← duplicate
colorAttachment.sourceAlphaBlendFactor = .one      // ← duplicate
```

Just delete the last two lines. Behavior unchanged. Consider taking R7 at the same time.

---

## Q14 — TODO debt to surface [LOW — informational]

Notable in-source TODOs that signal future work (don't fix in a "simplify" pass, but worth tracking):

| File:line | TODO |
|---|---|
| `Managers/SceneManager.swift:91` | "wrap this in a thread safe container" (see Q3) |
| `Managers/DrawManager.swift:120` | "Consider removing this as it's the same code as in RenderPassEncoding" |
| `Managers/ComputeManager.swift:12` | "this sucks, refactor!" |
| `Animation/Configs/F22AnimationConfig.swift:11` | "Provide this to aircraft animator so you don't redeclare" (see Q7) |
| `GameObjects/Aircraft.swift:41` | "This doesn't look right..." (`hasFocus = true` in init) |
| `GameObjects/GameObject.swift` (around init) | "this parent gets overwritten every time a new object with the same model is created" (see Q4) |

---

# Suggested Sequencing (if approved)

PR-sized, reviewable chunks:

1. **PR 1 — Hot-path allocations:** E1, E2, E3, E5, E6 (all in `SceneManager`/`LightManager`/`DrawManager`/broad-phase). Self-contained, measurable.
2. **PR 2 — Scene scaffolding dedup:** R3 (`addGround`), R4 (sky). Touches only `Scenes/` + `GameScene.swift`.
3. **PR 3 — Math consolidation:** R1, R2, Q11. Add unit tests asserting matrix equality before deleting old code.
4. **PR 4 — Renderer protocol extraction:** R6, R7 (with Q13 included as the trivial cleanup).
5. **PR 5 — Aircraft cleanup:** R5 (animator generic), Q2 (drop legacy gear flag), Q7 (layer ID enum).
6. **PR 6 — Safety pass:** Q1, Q4, Q12 — remove force unwraps in critical paths.
7. **PR 7 — Material/Draw refactor:** Q5, Q10. Largest scope; do last.
8. **Standalone:** Q3 (thread-safety on `SceneManager`) — its own design discussion, not a "simplify" task.
9. **Cleanup hygiene (any time):** Q6 (`print` removal), Q8 (commented-code deletion), Q9 (unused overload), R8 (TextureLoader options).

---

# What I Need From You

For each finding, please mark approved / skip / questions, then I'll proceed in the order above.

If you want a different grouping (e.g., "do everything in `SceneManager.swift` together"), tell me and I'll reorder.
