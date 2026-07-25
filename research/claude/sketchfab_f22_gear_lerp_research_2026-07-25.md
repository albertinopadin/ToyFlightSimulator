# Animating the Sketchfab F-22's landing gear with LERP

**Date:** 2026-07-25
**Asset:** `ToyFlightSimulator Shared/Core/Resources/Models/Sketchfab/F-22_Raptor.usdz` (`ModelType.Sketchfab_F22`, class `F22`)
**Question:** the asset ships alternate `landingOn` / `landingOff` meshes and has no skeleton — can linear interpolation animate the gear?

## 1. Short answer

**Interpolating between the two shipped meshes: no.** They are not two poses of one mesh — they are
two *different* meshes (324 vs 11,975 vertices, 3 vs 258 connected components, 376 vs 12,356
triangles). Per-vertex LERP requires a 1:1 vertex correspondence that does not exist here and cannot
be synthesized meaningfully, and the asset carries no blend shapes or skeleton to supply one (§2, §3).

**LERP as the driver of a gear animation: yes, and the engine already has every hook it needs.**
The right target for interpolation is not vertex positions but **rigid transforms of gear parts**,
because that is what real gear motion is. Three tiers, all LERP-driven (§4):

| Tier | What LERPs | Effort | Fidelity |
|---|---|---|---|
| **A. Whole-assembly** | one transform for the entire gear-down mesh, via `Mesh.transform.currentTransform` | ~40 lines, no shader/PSO/vertex work | gear slides/swings up as one rigid lump |
| **B. Per-part rig** (recommended) | 5–7 part transforms through the **existing skinning path** | ~250 lines, still no shader or PSO changes | struts, wheels and doors each swing on their own hinge |
| **C. Cross-dissolve** | material alpha between the two meshes | small | looks wrong; fights the deferred renderer. Not recommended |

In both A and B, the two shipped meshes keep a job: they are the **endpoint states**, swapped at
`progress == 0` and `progress == 1`. LERP supplies the motion in between. That hybrid — *interpolate
the transforms, swap the geometry at the ends* — is the recommendation.

A prerequisite finding, independent of any animation: **both gear meshes are drawn right now,
simultaneously.** `SceneManager.CreateModelData` puts every mesh and submesh of a model into the
draw list unless `GameObject.shouldRenderSubmesh` says otherwise, and `F22` does not override it
(`SceneManager.swift:402-422`, `GameObject.swift:103-109`). So the closed-bay panels render *while*
the deployed gear hangs through them. Fixing that is step 0 of any of the options below, and it is
worth confirming on screen before building anything.

## 2. What is actually in the asset (measured)

Measured with ModelIO (script in Appendix A). Mesh-local values, native units.

### 2.1 Mesh inventory

`F-22_Raptor.usdz` — 8 meshes, **0 skeletons, 0 joint animations, asset time range 0.0–0.0**:

| USD node | `Mesh.name` | Vertices | Triangles | Material | Role |
|---|---|---|---|---|---|
| `f22a_airframe_0` | `Object_0` | 33,859 | 26,604 | `f22a_airframe` | fuselage/wings |
| `f22a_canopy_1` | `Object_1` | 84 | 136 | `Glass` | canopy |
| `f22a_cockpit_2` | `Object_2` | 1,908 | 1,468 | `f22a_cockpit` | cockpit interior |
| `f22a_hud_3` | `Object_3` | 20 | 16 | `HudGlass` | HUD glass |
| `f22a_instrGlass_4` | `Object_4` | 84 | 96 | `Glass` | instrument glass |
| **`f22a_landingOff_5`** | **`Object_5`** | **324** | **376** | `f22a_airframe` | **gear-up: closed bay panels** |
| `f22a_landingOnLight_7` | `Object_7` | 60 | 20 | `f22a_landingLights` | gear light lens |
| **`f22a_landingOn_6`** | **`Object_6`** | **11,975** | **12,356** | `f22a_airframe` | **gear-down: struts + wheels + open doors** |

Note the two gear variants share the `f22a_airframe` material, so material name cannot disambiguate
them — resolve by mesh name, and guard with the vertex count (§4.1). Also note `model.meshes` order
is the `childObjects(of:)` order, in which `Object_6` is **last (index 7)** and `Object_5` is index 5.

### 2.2 Bounds — and the retraction distance

| Mesh | local min | local max | extent |
|---|---|---|---|
| `Object_5` (gear up) | [ 11.463, −24.620, −0.223] | [ 90.336, 24.620, **8.920**] | [78.873, 49.240, 9.143] |
| `Object_6` (gear down) | [ 11.621, −27.355, −1.869] | [ 90.342, 27.355, **20.515**] | [78.721, 54.710, 22.384] |

Mesh-local axes for this asset: **X = length** (nose at +X — the canopy sits at X 79.7…110.1),
**Y = span** (symmetric ±), **Z = height, positive downward**. The registered basis
`Transform.transformYMinusZXToXYZ` maps native → engine as

```
X_engine = +Y_native · s      (span)
Y_engine = −Z_native · s      (up)
Z_engine = +X_native · s      (forward/length)          s = 18.92 / 189.952 = 0.0996041
```

So the deployed wheels reach `Z_native = 20.515` → **1.15 m** below the closed belly line
(`Z_native = 8.920`). That is the gear's vertical travel, and it is the single most useful number
for authoring the stowed pose.

### 2.3 Connected components — why a per-part rig is feasible

Union-find over triangle adjacency, positions welded at 1e-3 to collapse UV-seam duplicates:

**`Object_5` (gear up) — 3 components.** Two symmetric main-bay panels at native
`(18.66, ±16.84, 3.77)` and one nose-bay panel at `(81.90, 0, 7.54)`. That is all it is: three
closed doors.

**`Object_6` (gear down) — 258 components**, but they cluster cleanly into gear legs. Largest:

| Vertices | Extent | Centroid (native) | Reading |
|---|---|---|---|
| 360 | [ 5.57, 1.80, 5.57] | (78.95, 0.00, 16.77) | nose wheel (round in X/Z, 1.80 thick in Y) |
| 236 ×2 | [ 8.75, 3.19, 8.75] | (18.28, ±15.86, 16.14) | main wheels |
| 156 ×2 | [ 3.64, 3.03, 8.66] | (21.12, ±12.64, 11.25) | main struts |
| 96 ×2 | [ 1.60, 2.51, 6.61] | (18.28, ±12.81, 9.99) | main strut uppers / drag links |
| 88 ×2 | [12.93, 2.81, 10.64] | (18.28, ±25.81, 6.54) | main doors, hanging open (outboard at ±25.8) |
| 86 ×2 | [ 1.27, 1.58, 1.61] | (79.15, ±0.90, 8.65/9.15) | nose light housings |
| 244 more | — | — | 5,456 vertices of hydraulics, bolts, brake detail |

Component centroids span native X 13.98…87.28 and Y ±25.96. **The gear separates by position**:
nose leg near X ≈ 79–87 with |Y| < 3, mains near X ≈ 17–22 with |Y| = 12…17, doors outboard at
|Y| ≈ 26. In engine meters (using the mapping above):

| Part | Engine centroid (m) — X span, Y up, Z fwd |
|---|---|
| nose leg + wheel | (0.000, −1.671, 7.864) |
| main wheel L / R | (±1.580, −1.607, 1.820) |
| main strut L / R | (±1.259, −1.121, 2.103) |
| main door L / R | (±2.571, −0.651, 1.820) |
| *(closed)* main panel L / R | (±1.677, −0.375, 1.859) |
| *(closed)* nose panel | (0.000, −0.751, 8.156) |

Two consequences: (1) a classifier on engine-space position can assign every one of the 11,975
vertices to a gear part with no authoring tool, and (2) the closed-panel positions tell you exactly
where each bay is, which is what you need to aim the stowed pose.

## 3. Why per-vertex LERP between the two meshes is impossible

Morph-target (blend-shape) interpolation is defined only between meshes that share vertex count,
vertex *order*, and topology: each target is a copy of the base mesh with vertices moved, stored as
one 3D offset per vertex, and "if three vertices form a triangle in the base model, they will form a
triangle in all the morph targets" ([Knowledge.Deck.no][kd], [MoCap Online][mco]). GPU
implementations bind the targets as parallel per-vertex position attributes and weight them in the
vertex shader, which is only meaningful under that same guarantee — "each target mesh must have the
same number of vertices" and "vertices must be in the same order in each target mesh"
([Gerdelan][ag]). USD's own blend-shape schema follows the same model: `UsdSkelBlendShape` stores
`offsets`/`normalOffsets` against the base pose, with optional `pointIndices` *into the original
mesh* ([OpenUSD][usd]).

`Object_5` and `Object_6` fail this on every axis: 324 vs 11,975 vertices, 376 vs 12,356 triangles,
3 vs 258 components, and semantically different geometry (flat contoured belly patches vs. struts,
tires, brake detail and door slabs). There is no correspondence to interpolate, and no defensible way
to invent one — the meshes do not describe the same surface.

Nor can the asset supply a correspondence some other way:

- **No blend shapes in the file.** Zero skeletons, zero joint animations, and an empty time range
  (`startTime == endTime == 0.0`), consistent with a glTF→USDZ Sketchfab export where the artist
  modelled two static gear states.
- **Even if they were authored, the import path would not see them.** ModelIO exposes skinning
  (`MDLAnimationBindComponent`, `MDLSkeleton`, `MDLPackedJointAnimation` — all used by
  `UsdModel.swift`) but no blend-shape/morph API, and Apple's own runtime stack has documented gaps
  here (blend shapes stored in USDZ but not reachable at runtime; RealityKit needing a custom
  geometry modifier to apply vertex offsets — [Apple forums][af]). The engine's vertex descriptor
  (`Mesh.createMdlVertexDescriptor`) has no morph-target attributes either.
- **`Object_6`'s "gear up" pose does not exist anywhere.** The only authored gear-up geometry is the
  *doors*, not a retracted strut. Any stowed pose for the strut must be *computed*, which is exactly
  what §4 does.

One genuine per-vertex LERP does exist as a variant: morph a mesh against **itself** — the same
`Object_6`, with a procedurally computed retracted pose as the second endpoint. Vertex counts match
trivially. But computing that endpoint means knowing each part's hinge and rotation, and once you
know those you can send them to the GPU as 5–7 matrices instead of 11,975 interpolated positions.
That is option B, and it is strictly cheaper and sharper than morphing (rigid parts stay rigid
instead of shearing through the interpolation). Vertex morphing is the wrong tool for hard-body
motion; Wikipedia's own caveats about vertex animation — memory cost and mid-interpolation
distortion — are exactly the failure modes here ([Wikipedia][wiki]).

## 4. What LERP *can* drive — three designs

### 4.0 Engine hooks that already exist

Everything below rests on five facts about this codebase:

1. **Per-mesh rigid transform, read every frame.** `DrawManager.DrawFromRingBuffer` does
   `let localTransform = mesh.transform?.currentTransform ?? .identity` and, when non-identity,
   post-multiplies it into every instance's `modelMatrix`
   (`DrawManager.swift:481-508`, `writeTransformedUniforms` at `:524`). All 8 F-22 meshes *have* a
   `TransformComponent` (`Mesh.swift:109-114` creates one whenever `mdlMesh.transform != nil`), and
   because this asset's time range is empty, `currentTransform` is identity and **nothing writes it**
   — the hook is live and unused. Writing it is a supported, zero-cost animation channel.
2. **Skinning is wired end-to-end and keys off one optional.** `DrawManager.SetupAnimation` binds
   `mesh.skin?.jointMatrixPaletteBuffer` and switches to `psoType.animatedVariant`
   (`DrawManager.swift:237-258`). The animated vertex functions already do 4-weight palette skinning
   (`GBuffer.metal:67-90`, `Base.metal:55-66`), and animated variants exist for GBuffer,
   transparency **and shadow** passes (`RenderPipelineStateLibrary.swift:78-97`) — so a skinned gear
   casts a correctly posed shadow. **No shader or PSO work is required.**
3. **The 0→1 driver already exists.** `BinaryAnimationChannel` is exactly a gear switch: `activate()`
   / `deactivate()` / `toggle()`, `progress` advanced by `deltaTime / transitionDuration`, states
   `inactive → activating → active → deactivating`.
4. **Vertex buffers are CPU-writable.** `Mesh.transformMeshBasis` already rewrites every vertex in
   place through `vertexBuffer.contents().bindMemory(to: Vertex.self, ...)` (`Mesh.swift:159-177`),
   including the `didModifyRange` handling for managed buffers on Intel Macs (`:224-232`).
5. **Draw lists are re-snapshotted every frame by the update thread.**
   `SceneManager.writeFrameSnapshot` copies `modelData.meshDatas` into that frame's
   `RingBufferRegion` (`SceneManager.swift:250-265`), so a mesh added to / removed from the draw list
   on the update thread takes effect on the next frame without racing the render thread.

Threading is already in your favour: the render thread signals the update thread at frame start and
**waits** for it before encoding (`updateSemaphore` / `updateDoneSemaphore`), so update-thread writes
to `currentTransform` and to a palette buffer are complete before that frame is encoded. See §6 for
the remaining in-flight-frame caveat.

### 4.1 Option A — whole-assembly rigid LERP (smallest change that looks like motion)

One transform for `Object_6`, LERPed from deployed (identity) to stowed (translated up by the 1.15 m
of §2.2), with the endpoint swap. No vertex edits, no skin, no shader work.

```swift
// GameObjects/F22.swift

import MetalKit

/// The Sketchfab F-22 has no skeleton and no animation clips: gear state is two
/// alternate meshes (see research/claude/sketchfab_f22_gear_lerp_research_2026-07-25.md §2).
/// Mesh names are the USD node names ModelIO hands us; the vertex counts guard against a
/// re-export silently renumbering them.
private struct F22GearMeshes {
    let deployed: Mesh      // Object_6 — f22a_landingOn_6,  11,975 verts
    let stowedDoors: Mesh   // Object_5 — f22a_landingOff_5,     324 verts
    let gearLight: Mesh     // Object_7 — f22a_landingOnLight_7,  60 verts

    init?(model: Model) {
        func mesh(named name: String, expectedVertexCount: Int) -> Mesh? {
            guard let mesh = model.meshes.first(where: { $0.name == name }) else {
                print("[F22GearMeshes] mesh '\(name)' not found in \(model.name) — gear animation disabled")
                return nil
            }
            if let count = mesh.mdlMesh?.vertexCount, count != expectedVertexCount {
                print("[F22GearMeshes] '\(name)' has \(count) verts, expected \(expectedVertexCount) — "
                      + "asset changed; re-check the gear rig constants")
            }
            return mesh
        }
        guard let deployed = mesh(named: "Object_6", expectedVertexCount: 11_975),
              let stowedDoors = mesh(named: "Object_5", expectedVertexCount: 324),
              let gearLight = mesh(named: "Object_7", expectedVertexCount: 60) else { return nil }
        self.deployed = deployed
        self.stowedDoors = stowedDoors
        self.gearLight = gearLight
    }
}

/// Rigid gear animation for a model that only ships gear-up / gear-down meshes.
///
/// `Mesh.transform.currentTransform` is post-multiplied into the model matrix by
/// `DrawManager.DrawFromRingBuffer`, in ENGINE model space (vertices are already baked
/// through `s·B`), so these transforms are authored directly in engine axes:
/// +X span, +Y up, +Z forward. No basis conjugation — that is only for deltas read out
/// of the USD file (`Transform.basisConjugationMatrices`).
final class F22SwapGearAnimator {
    /// Vertical travel from deployed wheels to the closed belly line: native Z 20.515 → 8.920,
    /// times the meterization scale s = 0.0996041. See §2.2.
    static let retractHeight: Float = 1.155   // meters

    /// Collapses a mesh to a point so its triangles are degenerate and rasterize nothing —
    /// a hide that needs no draw-list surgery. Vertex shading still runs (12k verts: noise).
    private static let hidden = Transform.scaleMatrix(.zero)

    private let meshes: F22GearMeshes
    private let channel: BinaryAnimationChannel

    var isGearDown: Bool { channel.progress > 0.5 }

    init?(model: Model, transitionDuration: Float = 2.5) {
        guard let meshes = F22GearMeshes(model: model) else { return nil }
        self.meshes = meshes
        self.channel = BinaryAnimationChannel(id: "f22SwapGear",
                                              mask: AnimationMask(jointPaths: []),
                                              transitionDuration: transitionDuration,
                                              initialState: .active)   // start gear down
        apply(progress: 1.0)
    }

    func toggleGear() { channel.toggle() }

    /// Called from `F22.doUpdate()` on the UPDATE thread.
    func update(deltaTime: Float) {
        guard channel.isAnimating else { return }
        channel.update(deltaTime: deltaTime)
        apply(progress: channel.progress)
        channel.clearDirty()
    }

    /// progress 1 = fully deployed, 0 = fully stowed.
    private func apply(progress t: Float) {
        // LERP the deployed mesh up into the belly. Pure translation needs no slerp;
        // Option B replaces this with per-part rotation (see §5 for why that matters).
        let lift = Self.retractHeight * (1 - t)
        meshes.deployed.transform?.currentTransform = t > 0
            ? Transform.translationMatrix([0, lift, 0])
            : Self.hidden                        // fully up: stop drawing the gear entirely
        // Closed-bay panels are the gear-UP geometry: visible only at t == 0.
        meshes.stowedDoors.transform?.currentTransform = t > 0 ? Self.hidden : .identity
        // Gear light only exists with the gear extended.
        meshes.gearLight.transform?.currentTransform = t > 0 ? .identity : Self.hidden
    }
}
```

Wire-up in `F22` (which today has no animator at all — `F22Animator` belongs to `F22_CGTrader`,
despite the filename). Note the toggle goes through an **override of `handleGearToggle()`**, not a
second debounce call: `Aircraft.doUpdate` already calls it (`Aircraft.swift:149`), and the debounce is
edge-consuming, so a second caller in the same frame never fires (§6.7):

```swift
// F22.swift
private var gearAnimator: F22SwapGearAnimator?
override var isGearDown: Bool { gearAnimator?.isGearDown ?? true }

init(...) {
    super.init(...)
    gearAnimator = F22SwapGearAnimator(model: model)
}

/// Aircraft.handleGearToggle drives `animator?.toggleGear()`, and this aircraft has no
/// AircraftAnimator — so take over the (single, edge-consuming) debounced ToggleGear edge.
override func handleGearToggle() {
    InputManager.HasDiscreteCommandDebounced(command: .ToggleGear) { [weak self] in
        self?.gearAnimator?.toggleGear()
    }
}

override func doUpdate() {
    super.doUpdate()                                          // runs handleGearToggle() when focused
    gearAnimator?.update(deltaTime: Float(GameTime.DeltaTime))
    // ... existing afterburner logic
}
```

**What you get:** the gear sinks/rises as one piece over 2.5 s, the bay doors appear closed only when
it is up, and the always-drawn-overlap bug (§1) is fixed as a side effect. **What you don't get:**
struts don't fold, wheels don't rotate into the bay, doors don't swing.

### 4.2 Option B — per-part rigid LERP through the existing skinning path (recommended)

Give the gear a synthetic 5–7 "joint" rig, bind each vertex rigidly (weight 1.0 to one joint), and
LERP/slerp each part's transform into the palette buffer every frame. The vertex shader, PSOs and
shadow path are already there (§4.0 fact 2).

**Step 1 — classify vertices into parts.** Pure function on engine-space position (post-basis, i.e.
what is in the vertex buffer), thresholds from §2.3. Metal-free and unit-testable, per the project's
test-design rule:

```swift
// Animation/Rigs/F22GearRig.swift

/// Parts of the Sketchfab F-22's gear-down mesh, derived by spatial clustering of its 258
/// connected components (§2.3). Raw values are palette indices — keep them contiguous from 0.
enum F22GearPart: UInt16, CaseIterable {
    case noseLeg = 0, noseDoor, leftLeg, leftDoor, rightLeg, rightDoor
}

struct F22GearRig {
    /// Boundaries in ENGINE meters (X span, Y up, Z forward), from the measured centroids:
    /// nose cluster sits at Z ≈ 7.9, mains at Z ≈ 1.8–2.1; doors are outboard (|X| ≈ 2.57)
    /// of the legs (|X| ≈ 1.26–1.58).
    static let noseZThreshold: Float = 5.0
    static let doorSpanThreshold: Float = 2.2

    /// Pure: no Metal, no Model. Unit-test with the §2.3 centroid table.
    static func part(for position: float3) -> F22GearPart {
        if position.z > noseZThreshold {
            return abs(position.x) > 0.5 ? .noseDoor : .noseLeg
        }
        if position.x >= 0 {
            return position.x > doorSpanThreshold ? .leftDoor : .leftLeg
        }
        return -position.x > doorSpanThreshold ? .rightDoor : .rightLeg
    }
}
```

> The nose-door split is a guess pending a look at the asset: §2.3 shows nose-area components at
> |Y_native| ≈ 0.9 that are *light housings*, and the nose bay door may be modelled as part of the
> leg cluster. Dump the per-part vertex counts (Appendix A prints components; extend it to print
> `part(for:)` histograms) before trusting six parts — four (nose leg, both main legs, both main
> doors as one group) may be all the asset supports.

**Step 2 — bind the vertices, once.** One pass over 11,975 vertices at load. Note that vertices whose
`jointWeights` are all zero collapse to the origin in the animated shader, so **every** vertex of a
skinned mesh must be bound:

```swift
extension F22GearRig {
    /// Writes rigid joint bindings into the mesh's vertex buffer: one joint, weight 1.
    /// Mirrors the in-place write idiom of `Mesh.transformMeshBasis` (Mesh.swift:159).
    /// Must run BEFORE the mesh is first drawn, and exactly once per Mesh — the Model is
    /// cached process-wide by ModelLibrary (§6).
    static func bindRigidly(mesh: Mesh) {
        guard let buffer = mesh.vertexBuffer else { return }
        let count = buffer.length / Vertex.stride
        var pointer = buffer.contents().bindMemory(to: Vertex.self, capacity: count)
        for _ in 0..<count {
            pointer.pointee.joints = simd_ushort4(part(for: pointer.pointee.position).rawValue, 0, 0, 0)
            pointer.pointee.jointWeights = float4(1, 0, 0, 0)
            pointer = pointer.advanced(by: 1)
        }
        #if os(macOS)
        if buffer.storageMode == .managed { buffer.didModifyRange(0..<buffer.length) }
        #endif
    }
}
```

**Step 3 — a synthetic `Skin`.** `Skin`'s only initializer needs an `MDLAnimationBindComponent`;
add one that just allocates the palette:

```swift
// Animation/Skin.swift
extension Skin {
    /// Palette-only skin for a procedurally rigged mesh (no USD skeleton). `SetupAnimation`
    /// binds `jointMatrixPaletteBuffer` and selects the animated PSO purely from `mesh.skin`
    /// being non-nil (DrawManager.swift:241), so this is all a synthetic rig needs.
    init?(syntheticJointCount count: Int, label: String) {
        guard count > 0,
              let buffer = Engine.Device.makeBuffer(length: count * MemoryLayout<float4x4>.stride,
                                                    options: .storageModeShared) else { return nil }
        buffer.label = label
        self.init(jointPaths: (0..<count).map { "\(label)/joint\($0)" },
                  skinToSkeletonMap: Array(0..<count),
                  jointMatrixPaletteBuffer: buffer)
    }
}
```
(`Skin` is a struct with three stored properties; either add the memberwise `init` explicitly or
assign the properties directly in the new initializer.)

**Step 4 — author deployed and stowed poses per part, then interpolate.** The deployed pose is
identity (the mesh *is* the deployed pose). The stowed pose is a rotation about a hinge:

```swift
/// One part's retraction: rotate `angle` about `axis` through `pivot`, all in ENGINE
/// model space (X span, Y up, Z forward), meters and radians.
struct GearPartMotion {
    var pivot: float3
    var axis: float3
    var angle: Float

    /// Rotation about an axis through a point: T(p) · R · T(-p).
    var stowed: float4x4 {
        Transform.translationMatrix(pivot)
            * Transform.rotationMatrix(radians: angle, axis: axis)
            * Transform.translationMatrix(-pivot)
    }
}

extension F22GearRig {
    /// Hinges anchored on measured geometry (§2.3), angles tuned by eye.
    /// Main legs: pivot at the top-inboard corner of the strut — native (21.12, ±11.1, 6.9)
    /// → engine (±1.106, −0.687, 2.103) — swinging inboard/up about the fore-aft (Z) axis
    /// so the wheel ends up over the bay, whose position the closed panels give as
    /// engine (±1.677, −0.375, 1.859).
    /// Nose leg: pivot at the top of the strut, rotating aft about the span (X) axis.
    static func motion(for part: F22GearPart) -> GearPartMotion {
        switch part {
        case .leftLeg:
            return GearPartMotion(pivot: [ 1.106, -0.687, 2.103], axis: [0, 0, 1], angle: -Float(85).toRadians)
        case .rightLeg:
            return GearPartMotion(pivot: [-1.106, -0.687, 2.103], axis: [0, 0, 1], angle:  Float(85).toRadians)
        case .leftDoor:
            return GearPartMotion(pivot: [ 1.95, -0.45, 1.820], axis: [0, 0, 1], angle: -Float(90).toRadians)
        case .rightDoor:
            return GearPartMotion(pivot: [-1.95, -0.45, 1.820], axis: [0, 0, 1], angle:  Float(90).toRadians)
        case .noseLeg:
            return GearPartMotion(pivot: [0, -0.80, 8.10], axis: [1, 0, 0], angle: Float(90).toRadians)
        case .noseDoor:
            return GearPartMotion(pivot: [0, -0.75, 8.30], axis: [1, 0, 0], angle: Float(95).toRadians)
        }
    }
}
```

**Step 5 — the per-frame driver.** This is where the LERP lives, and where doing it *correctly*
matters (§5):

```swift
// Animation/Animators/F22SketchfabGearAnimator.swift

/// Gear animation for a model with no skeleton: a synthetic rigid rig on the gear-down mesh,
/// driven by a BinaryAnimationChannel and interpolated per part.
final class F22SketchfabGearAnimator {
    private let deployedMesh: Mesh
    private let stowedDoorsMesh: Mesh
    private let gearLightMesh: Mesh
    private let channel: BinaryAnimationChannel
    /// Pre-decomposed endpoints so the per-frame path does no matrix decomposition.
    private let stowedRotations: [simd_quatf]
    private let stowedTranslations: [float3]

    var isGearDown: Bool { channel.progress > 0.5 }

    init?(model: Model, transitionDuration: Float = 2.5) {
        guard let meshes = F22GearMeshes(model: model) else { return nil }
        deployedMesh = meshes.deployed
        stowedDoorsMesh = meshes.stowedDoors
        gearLightMesh = meshes.gearLight

        F22GearRig.bindRigidly(mesh: deployedMesh)
        guard let skin = Skin(syntheticJointCount: F22GearPart.allCases.count,
                              label: "F22 Gear Palette") else { return nil }
        deployedMesh.skin = skin

        var rotations: [simd_quatf] = []
        var translations: [float3] = []
        for part in F22GearPart.allCases {
            let stowed = F22GearRig.motion(for: part).stowed
            let (translation, rotation, _) = Transform.decomposeTRS(stowed)
            rotations.append(simd_quatf(rotation))
            translations.append(translation)
        }
        stowedRotations = rotations
        stowedTranslations = translations

        channel = BinaryAnimationChannel(id: "f22SketchfabGear",
                                         mask: AnimationMask(jointPaths: []),
                                         transitionDuration: transitionDuration,
                                         initialState: .active)
        writePalette(progress: 1.0)
        applyVisibility(progress: 1.0)
    }

    func toggleGear() { channel.toggle() }

    /// UPDATE thread (F22.doUpdate → here). Completed before the render thread encodes
    /// this frame, thanks to the updateSemaphore/updateDoneSemaphore handshake.
    func update(deltaTime: Float) {
        guard channel.isAnimating else { return }
        channel.update(deltaTime: deltaTime)
        writePalette(progress: channel.progress)
        applyVisibility(progress: channel.progress)
        channel.clearDirty()
    }

    /// t = 1 fully deployed (identity), t = 0 fully stowed.
    private func writePalette(progress t: Float) {
        guard let skin = deployedMesh.skin else { return }
        let blend = 1 - t   // 0 at deployed, 1 at stowed
        var palette = skin.jointMatrixPaletteBuffer.contents()
            .bindMemory(to: float4x4.self, capacity: F22GearPart.allCases.count)
        for index in F22GearPart.allCases.indices {
            // SLERP the rotation, LERP the translation — never interpolate matrix
            // components directly (§5). `simd_quatf.identity` is the project's spelling
            // for "no rotation" (Transform.swift:248 — the default init is the invalid
            // zero quaternion).
            let rotation = simd_slerp(.identity, stowedRotations[index], blend)
            let translation = stowedTranslations[index] * blend
            palette.pointee = Transform.matrixFromTR(translation: translation,
                                                     rotation: float4x4(rotation))
            palette = palette.advanced(by: 1)
        }
    }

    private func applyVisibility(progress t: Float) {
        let hidden = Transform.scaleMatrix(.zero)
        deployedMesh.transform?.currentTransform = t > 0 ? .identity : hidden
        stowedDoorsMesh.transform?.currentTransform = t > 0 ? hidden : .identity
        gearLightMesh.transform?.currentTransform = t > 0 ? .identity : hidden
    }
}
```

Add an easing curve if the linear ramp reads mechanically — the project already has
`SymmetricSigmoidCurve` and `ValueCurve` (`Utils/`); feed `blend` through one before slerping.

### 4.3 Option C — cross-dissolve (alpha LERP). Not recommended

LERP a material alpha: `landingOff` 1→0 while `landingOn` 0→1. It is the only option that uses the
two meshes as literal interpolation endpoints, and it is the worst:

- Gear that *fades* into existence rather than swinging reads as a rendering glitch, not machinery.
- Both meshes use the opaque `f22a_airframe` material and go through the GBuffer path. Alpha requires
  moving them to the transparency pass, which changes `GameObjectType` batching
  (`.renderables(transparent:)`), and `SceneManager` captures the transparent/opaque split **at
  registration** (`CreateModelData`, `SceneManager.swift:402`) — a mid-flight change means
  re-registering the object.
- `MaterialProperties` is per-submesh, and both gear meshes share the airframe material, so a
  naive alpha write would fade the fuselage too. You'd need per-instance alpha
  (`ModelConstants.objectColor` + `useObjectColor`) and a fragment path that honours it.

Mentioned for completeness; the effort is comparable to option B for a worse result.

### 4.4 Option D — author the rig in Blender, outside the engine

Import the USDZ into Blender, add an armature with gear bones (or shape keys), re-export as USDZ, and
the existing `UsdModel` + `F22Animator` + `BinaryAnimationChannel` path animates it with **no engine
changes at all** — that is precisely how the CGTrader F-22 and the F-35 already work
(`F22AnimationConfig.createLandingGearLayer` filters clip channels to bones named
`LeftWheelBone`, `RightMainBayBone`, …). If you are willing to touch the asset, this is the highest
fidelity per unit of *engine* code, and it moves the hinge tuning into a tool built for it. The
trade-off is an asset fork to re-do whenever the source model is updated, plus the meterization
recalibration that follows any re-export (draw-space native length changes → new `s`).

## 5. Getting the interpolation right

**Never LERP matrix components.** Linearly interpolating the entries of two rotation matrices "does
not create anything that resembles an inbetween transformation" — the columns stop being unit-length
and orthogonal, so the geometry shears and shrinks mid-transition ([Positioning tutorial][nb],
[GameDev.net][gd]). Decompose, then interpolate each part with the right operator: LERP the
translation, **SLERP** (or normalized-LERP) the rotation, LERP the scale. Apple ships this:
`simd_slerp(q0, q1, t)` interpolates along the shortest arc between two `simd_quatf`
([Apple][slerp]); `simd_slerp_longest` takes the other arc when you deliberately want the long way
round.

In this codebase:

- `Transform.decomposeTRS` gives `(translation, rotation, scale)`; `float4x4(simd_quatf)` and
  `simd_quatf(float4x4)` convert both ways; `Transform.matrixFromTR` rebuilds the matrix.
- Decompose the **endpoints once** (in `init`), not per frame — §4.2 stores `stowedRotations` /
  `stowedTranslations` for exactly that reason.
- A single-axis hinge is the one case where you can skip quaternions entirely and just LERP the
  *angle*, rebuilding `Transform.rotationMatrix(radians: angle * blend, axis:)` each frame. For the
  gear that is arguably simpler and unambiguous — one scalar per part. Use slerp when a part needs a
  compound rotation (e.g. an F-22 main gear that both folds inboard and rotates the wheel flat).
- Do not conjugate hand-authored transforms. `Transform.basisConjugationMatrices` (`Bᵀ · M · (Bᵀ)⁻¹`)
  exists to map deltas read out of the USD file (native space) into engine space, and it carries the
  meterization scale. Poses authored directly in engine meters, as above, need none of it.

## 6. Caveats that will bite

1. **`Model` and its `Mesh`es are process-wide singletons.** `ModelLibrary` is a `LazyLibrary` that
   caches one `Model` per `ModelType` for the process lifetime, so `mesh.transform`,
   `mesh.skin`, and the vertex buffer are **shared by every `F22` instance**. Two Sketchfab F-22s in
   a scene cannot have different gear states, and `bindRigidly` must run exactly once (guard it with
   a flag on the rig, or key it off `mesh.skin == nil`). Per-instance gear needs per-instance meshes,
   which is a much larger change (`instanceCount`/batching assumes shared geometry).
2. **A layer-system animator would stomp `currentTransform`.** If a future `F22SketchfabAnimator`
   goes through `AnimationLayerSystem`, both `applyChannel` and `applyChannelFallback` call
   `mesh.transform?.setCurrentTransform(at:)` (`AnimationLayerSystem.swift:299,344`), whose first
   line is `guard duration > 0 else { currentTransform = .identity; return }`. This asset's duration
   **is** 0, so every such call resets the gear pose to identity. Keep the swap/rig animator off the
   layer-system path, or teach `TransformComponent` to leave `currentTransform` alone when it has no
   keyframes.
3. **The palette buffer is single-buffered.** `Skin` allocates one `MTLBuffer` and the update thread
   writes it while up to 3 frames are in flight, so frame *N*'s write can land while the GPU still
   reads frame *N−1*. This is pre-existing behaviour shared with the F-35 and CGTrader F-22 skins,
   and at gear speeds the worst case is a one-frame-stale pose. If it shows, triple-buffer the
   palette the way `DrawManager` triple-buffers ModelConstants.
4. **`Transform.scaleMatrix(.zero)` as a hide is a trick, not a feature.** Triangles collapse and
   rasterize nothing, but the vertex shader still runs and the draw call is still submitted. It is
   the right trade at 12k vertices; if you want it properly gone, mutate
   `modelDatas[model]!.meshDatas[i].opaqueSubmeshes` on the update thread before
   `writeFrameSnapshot` (§4.0 fact 5) — the same surgery `hideSubmeshInParentModel` does at
   registration. Also check that a zero-scale model matrix does not upset `ShadowCascadeFitting` or
   any AABB consumer.
5. **Everything is post-meterization.** All engine-space constants above assume
   `s = 18.92 / 189.952 = 0.0996041` (draw-space calibration, `Model.DrawSpaceNativeExtent`). If the
   asset is re-exported or `realWorldLength` changes, `s` changes and every hinge/pivot moves. Derive
   them from native units × `s` in code, or re-run Appendix A, rather than pasting meters.
6. **`isGearDown` feeds nothing yet, but will.** `Aircraft.isGearDown` currently returns
   `animator?.isGearDown ?? true`; a swap/rig animator is not an `AircraftAnimator`, so `F22` must
   override `isGearDown` itself (§4.1) or the property will lie once gear-dependent drag/collision
   logic exists.
7. **The gear-toggle debounce is edge-consuming — only one handler can win.**
   `InputManager.HandleKeyPressedDebounced` flips `keysPressed[keyCode] = true` and runs the block on
   the first call after a key-down; every later call that frame sees `true` and does nothing
   (`InputManager.swift:193-209`). `Aircraft.doUpdate` already calls `handleGearToggle()` when
   focused (`Aircraft.swift:149`), whose block is `animator?.toggleGear()` — a no-op here, but it
   **still consumes the edge**. So drive the gear from an `override func handleGearToggle()` (§4.1),
   not from an extra `HasDiscreteCommandDebounced` call in `F22.doUpdate`, which would silently never
   fire.

## 7. Recommendation

1. **Fix the overlap first** (§1) — it is a bug independent of animation, and option A's
   `applyVisibility` is the whole fix.
2. **Land option A** as the shipping behaviour: ~40 lines, no shader/PSO/vertex-buffer changes, and it
   gets the F-22 a gear toggle that reads correctly at a distance.
3. **Then option B** if the gear is ever seen close up. The measured component data (§2.3) already
   gives the classifier thresholds and hinge anchors; the only real work is eyeballing six angles.
4. **Consider option D** if you are willing to fork the asset — it is the only path to
   *authored*-quality gear kinematics, and it needs no engine code at all.

Do **not** pursue per-vertex morphing between the two shipped meshes (§3), and do not pursue the
cross-dissolve (§4.3).

Suggested tests, all Metal-free per the project's test-design rule (pure statics, no `Model`
construction): `F22GearRig.part(for:)` against the §2.3 centroid table (each measured centroid must
land in its expected part, and the mirror pairs must be symmetric); `GearPartMotion.stowed` moving a
representative wheel centroid to within a tolerance of the corresponding closed-panel position; and
an interpolation test asserting that the slerp path keeps the rotation matrix orthonormal at
t = 0.25/0.5/0.75, which is the regression that catches somebody "simplifying" it back to a matrix
LERP.

## Appendix A — measurement scripts

Both were run from the repo root with `swift <file>` and live in this session's scratchpad; the
inventory numbers in §2.1–2.2 come from the first, the component table in §2.3 from the second.

**Mesh inventory / rigging probe** — hierarchy walk plus, per `MDLMesh`: `vertexCount`,
submesh `indexCount`/material, `boundingBox`, vertex-attribute layout, and
`componentConforming(to: MDLComponent.self) as? MDLAnimationBindComponent` (the same probe
`UsdModel.swift:107` uses). Also counts `childObjects(of: MDLSkeleton.self)` and
`MDLPackedJointAnimation.self` — both 0 here — and prints `asset.startTime/endTime`.

**Connected-component analysis** — the core of the feasibility finding:

```swift
// Weld positions first: exporters split vertices at UV seams, which would otherwise
// read as separate islands.
func weldMap(_ positions: [SIMD3<Float>], epsilon: Float) -> [Int] {
    var lookup: [SIMD3<Int32>: Int] = [:]
    var canonical = Array(repeating: 0, count: positions.count)
    let inverse = 1.0 / epsilon
    for (i, p) in positions.enumerated() {
        let key = SIMD3<Int32>(Int32((p.x * inverse).rounded()),
                               Int32((p.y * inverse).rounded()),
                               Int32((p.z * inverse).rounded()))
        if let existing = lookup[key] { canonical[i] = existing } else { lookup[key] = i; canonical[i] = i }
    }
    return canonical
}

// Union-find over triangle adjacency, then group by root and report vertex count,
// extent and centroid per island (sorted largest first).
for t in stride(from: 0, to: indices.count - 2, by: 3) {
    let a = welded[indices[t]], b = welded[indices[t + 1]], c = welded[indices[t + 2]]
    uf.union(a, b); uf.union(a, c)
}
```

Positions are read through the source `MDLVertexDescriptor` (this asset stores one buffer per
attribute: position float3 in buffer 0, normal in 1, texcoord in 2), indices through
`MDLSubmesh.indexBuffer.map()` switched on `indexType`. Worth promoting to `scripts/` alongside
`measure_models.swift` if per-part rigging is pursued — extend it to print a
`F22GearRig.part(for:)` histogram so the classifier thresholds are validated against the asset
rather than assumed.

## References

Fetched and read:

- [Morph target animation — Wikipedia][wiki] — how vertex/morph animation stores and interpolates per-vertex positions; memory cost and mid-interpolation distortion caveats. <https://en.wikipedia.org/wiki/Morph_target_animation>
- [UsdSkelBlendShape — OpenUSD API][usd] — blend shapes as `offsets`/`normalOffsets` against the base pose, with optional `pointIndices` into the original mesh. <https://openusd.org/dev/api/class_usd_skel_blend_shape.html>
- [Interpolation — "Learning Modern 3D Graphics Programming" (Positioning, Tut08)][nb] — why linearly interpolating matrix components fails, and why normalized-LERP/SLERP of quaternions works. <https://nicolbolas.github.io/oldtut/Positioning/Tut08%20Interpolation.html>
- [Animating Blend Shapes — Anton Gerdelan][ag] — GPU blend shapes as parallel per-vertex position attributes; the "same vertex count, same order" requirement. <https://antongerdelan.net/opengl/blend_shapes.html>
- [`simd_slerp(_:_:_:)` — Apple Developer Documentation][slerp] — shortest-arc spherical linear interpolation of `simd_quatf`. <https://developer.apple.com/documentation/simd/2867359-simd_slerp>
- <https://developer.apple.com/documentation/accelerate/simd_slerp(_:_:_:)> — attempted first for the same function; returns HTTP 404. The `/simd/2867359-simd_slerp` path above is the live one.

Surfaced in web searches and used for the statements cited, not opened directly:

- [Morph Targets and Blend Shapes — Knowledge.Deck.no][kd] — "same topology and vertex count as the base mesh"; a morph target is a copy with vertex order preserved, stored as per-vertex offsets. <https://knowledge.deck.no/art-and-literature/digital-art/digital-sculpting/morph-targets-and-blend-shapes>
- [Blend Shapes & Morph Targets — MoCap Online][mco] — vertex count/order must be consistent for correct interpolation; skeleton handles structural motion, blend shapes surface deformation. <https://mocaponline.com/blogs/mocap-news/blend-shapes-morph-targets-guide>
- [Blend shape manipulation of a usdz file in visionOS — Apple Developer Forums][af] — RealityKit's lack of blend-shape support and the geometry-modifier/`MeshResource` workarounds. <https://developer.apple.com/forums/thread/746232>
- [USD Python tools and Blend Shapes not working — Apple Developer Forums](https://developer.apple.com/forums/thread/659567) — blend shapes present in USDZ but not reachable through Apple's runtime.
- [Matrix Interpolation — GameDev.net][gd] — decompose into rotation + translation/scale and interpolate each with the appropriate operator. <https://www.gamedev.net/forums/topic/474790-matrix-interpolation/4114314/>
- [`simd_slerp_longest(_:_:_:)` — Apple Developer Documentation](https://developer.apple.com/documentation/simd/2867366-simd_slerp_longest) — longest-arc variant.
- [UsdSkel schemas overview — OpenUSD](https://openusd.org/dev/api/_usd_skel__schemas.html) — `skel:blendShapes` / `skel:blendShapeTargets` binding.
- [Morphing Animation — Qt Quick 3D](https://doc.qt.io/qt-6/quick3d-morphing.html), [Morph Targets — DigitalRune](https://digitalrune.github.io/DigitalRune-Documentation/html/b44b915a-f5f6-416a-9ffb-98de885812d7.htm), [Morphing — RAMSES Composer](https://ramses-composer.readthedocs.io/en/latest/advanced/morphing/README.html) — weighted per-vertex delta accumulation in a vertex shader, the standard formulation.
- [Spherical linear interpolation — Wikipedia](https://en.wikipedia.org/wiki/Spherical_linear_interpolation), [Interpolating quaternion rotations with SLERP — John D. Cook](https://www.johndcook.com/blog/2023/03/15/slerp/) — constant-angular-velocity property of slerp.

Engine sources (this repo, at commit `2363cf6`): `AssetPipeline/Mesh.swift`,
`AssetPipeline/Model.swift`, `AssetPipeline/UsdModel.swift`, `Animation/Skin.swift`,
`Animation/TransformComponent.swift`, `Animation/Layers/BinaryAnimationChannel.swift`,
`Animation/Layers/AnimationLayerSystem.swift`, `Animation/Configs/F22AnimationConfig.swift`,
`Managers/DrawManager.swift`, `Managers/SceneManager.swift`, `GameObjects/F22.swift`,
`GameObjects/Aircraft.swift`, `Graphics/Shaders/GBuffer.metal`, `Graphics/Shaders/Base.metal`,
`Graphics/Libraries/Pipelines/Render/RenderPipelineStateLibrary.swift`, `Math/Transform.swift`.

[wiki]: https://en.wikipedia.org/wiki/Morph_target_animation
[usd]: https://openusd.org/dev/api/class_usd_skel_blend_shape.html
[nb]: https://nicolbolas.github.io/oldtut/Positioning/Tut08%20Interpolation.html
[ag]: https://antongerdelan.net/opengl/blend_shapes.html
[slerp]: https://developer.apple.com/documentation/simd/2867359-simd_slerp
[kd]: https://knowledge.deck.no/art-and-literature/digital-art/digital-sculpting/morph-targets-and-blend-shapes
[mco]: https://mocaponline.com/blogs/mocap-news/blend-shapes-morph-targets-guide
[af]: https://developer.apple.com/forums/thread/746232
[gd]: https://www.gamedev.net/forums/topic/474790-matrix-interpolation/4114314/
