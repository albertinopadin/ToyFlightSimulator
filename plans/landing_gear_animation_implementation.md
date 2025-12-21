# Landing Gear Animation Implementation Plan

## Overview

This document outlines the implementation plan for adding animated landing gear to the F18 aircraft in ToyFlightSimulator. The animation system uses the existing `SubMeshGameObject` pattern for procedural transform-based animation.

## Current State Analysis

### Existing Infrastructure

| Component | Status | Details |
|-----------|--------|---------|
| Input Binding | ✅ Ready | `ToggleGear` command mapped to 'G' key in `InputManager.swift` |
| State Machine | ✅ Partial | Logic exists in `F18.swift:444-476`, transforms marked `// TODO` |
| F18 Model Parts | ✅ Ready | 94 named mesh groups including all landing gear components |
| Animation Pattern | ✅ Established | Flaps animation at `F18.swift:407-441` provides the template |

### F18 Landing Gear Parts Available

The FA-18F.obj model contains the following named groups for landing gear:

**Nose Gear:**
- `TopStrut_Paint` - Upper strut assembly
- `MainStrut_Paint` - Primary strut
- `UpperStrut_Paint`, `MidStrut_Paint`, `LowerStrut_Paint` - Strut segments
- `NoseWheels_Paint` - Nose wheel assembly
- `NoseDoors1A_Paint`, `NoseDoors1B_Paint` - Forward doors
- `NoseDoors2_Paint`, `NoseDoors3_Paint` - Aft doors
- `CatobarHook_Paint` - Catapult attachment
- `BackStrut_Paint`, `BackStrut1_Paint`, `BackStrut2_Paint` - Rear strut components

**Main Gear Left:**
- `TopStrutL_Paint` - Upper strut
- `MainStrutL_Paint` - Primary strut
- `MidStrutL_Paint` - Middle strut segment
- `LowerStrutL_Paint` - Lower strut
- `WheelMainL_Paint` - Main wheel
- `GearDoors1L_Paint`, `GearDoors2L_Paint`, `GearDoors3L_Paint` - Gear doors

**Main Gear Right:**
- `TopStrutR_Paint` - Upper strut
- `MainStrutR_Paint` - Primary strut
- `MidStrutR_Paint` - Middle strut segment (note: typo in model as `MidStrutLR_Paint`)
- `LowerStrutR_Paint` - Lower strut
- `WheelMainR_Paint` - Main wheel
- `GearDoors1R_Paint`, `GearDoors2R_Paint`, `GearDoors3R_Paint` - Gear doors

## Animation Approach

### Option 1: Procedural Transform Animation (Selected)

Uses the existing `SubMeshGameObject` pattern where individual mesh parts are extracted, positioned as child nodes, and animated via transform manipulations.

**Pros:**
- Matches existing codebase patterns (flaps, ailerons, rudders)
- No new model assets required
- Full programmatic control over timing and interpolation
- Hierarchical parent-child relationships (strut → wheels)

**Cons:**
- Requires manual tuning of pivot points and rotation axes
- More code to write for complex assemblies

### Option 2: USD Skeletal Animation (Not Used)

Would require re-exporting models with skeletal rigs from Blender/Maya.

**Why not selected:**
- Current models lack skeleton/bone data
- Would require significant asset pipeline changes
- Overkill for mechanical animations like landing gear

## Implementation Architecture

### Class Hierarchy

```
LandingGearAnimator (animation state machine)
    ├── Manages: GearState (deployed, retracted, deploying, retracting)
    ├── Tracks: progress (0.0 = deployed, 1.0 = retracted)
    └── Provides: currentAngleRadians, update(), toggle()

NoseGearAssembly (nose gear parts)
    ├── mainStrut: SubMeshGameObject (rotates backward to retract)
    │   └── wheels: SubMeshGameObject (child, moves with strut)
    ├── doorLeft: SubMeshGameObject (rotates outward)
    └── doorRight: SubMeshGameObject (rotates outward)

MainGearAssembly (left or right main gear)
    ├── strut: SubMeshGameObject (rotates forward/inward to retract)
    │   └── wheel: SubMeshGameObject (child, moves with strut)
    └── doors: [SubMeshGameObject] (rotate to open/close)
```

### Animation Sequence

1. **Gear Retraction (G key when deployed):**
   - Doors open (0-30% of animation)
   - Struts rotate upward (10-90% of animation)
   - Doors close (70-100% of animation)

2. **Gear Extension (G key when retracted):**
   - Doors open (0-30% of animation)
   - Struts rotate downward (10-90% of animation)
   - Doors close (70-100% of animation)

### Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `SingleSubmeshMeshLibrary.swift` | Modify | Add landing gear mesh types |
| `ModelLibrary.swift` | Modify | Add landing gear model types |
| `LandingGearAnimator.swift` | Create | Animation state machine |
| `NoseGearAssembly.swift` | Create | Nose gear component hierarchy |
| `MainGearAssembly.swift` | Create | Main gear component hierarchy |
| `F18.swift` | Modify | Integrate landing gear assemblies |

## Detailed Implementation

### Step 1: Add Mesh Types

Add to `SingleSMMeshType` enum in `SingleSubmeshMeshLibrary.swift`:

```swift
// Landing Gear - Nose
case F18_NoseGear_Strut
case F18_NoseGear_Wheels
case F18_NoseGear_DoorLeft
case F18_NoseGear_DoorRight

// Landing Gear - Main Left
case F18_MainGearL_Strut
case F18_MainGearL_Wheel
case F18_MainGearL_Door

// Landing Gear - Main Right
case F18_MainGearR_Strut
case F18_MainGearR_Wheel
case F18_MainGearR_Door
```

### Step 2: Create LandingGearAnimator

State machine to manage gear animation timing:

```swift
class LandingGearAnimator {
    enum GearState {
        case deployed, retracted, deploying, retracting
    }

    var state: GearState = .deployed
    var progress: Float = 0.0  // 0 = deployed, 1 = retracted
    let animationSpeed: Float = 1.5  // degrees per frame
    let maxRotation: Float = 90.0

    func toggle() { /* switch states */ }
    func update() -> Bool { /* animate progress */ }
    var currentAngleRadians: Float { /* computed */ }
}
```

### Step 3: Create Gear Assemblies

Hierarchical component management:

```swift
class NoseGearAssembly {
    let strut: SubMeshGameObject
    let wheels: SubMeshGameObject  // child of strut
    let doorLeft: SubMeshGameObject
    let doorRight: SubMeshGameObject

    func attachTo(aircraft: Node)
    func animate(progress: Float)
}

class MainGearAssembly {
    let strut: SubMeshGameObject
    let wheel: SubMeshGameObject  // child of strut
    let door: SubMeshGameObject

    func attachTo(aircraft: Node)
    func animate(progress: Float)
}
```

### Step 4: Integrate into F18

Update `F18.swift`:

```swift
class F18: Aircraft {
    let noseGear = NoseGearAssembly()
    let leftMainGear = MainGearAssembly(side: .left)
    let rightMainGear = MainGearAssembly(side: .right)
    let gearAnimator = LandingGearAnimator()

    func setupLandingGear() {
        noseGear.attachTo(aircraft: self)
        leftMainGear.attachTo(aircraft: self)
        rightMainGear.attachTo(aircraft: self)
        // Hide static gear submeshes
    }

    override func doUpdate() {
        // Handle G key
        InputManager.HasDiscreteCommandDebounced(command: .ToggleGear) {
            gearAnimator.toggle()
        }

        // Animate if in motion
        if gearAnimator.update() {
            noseGear.animate(progress: gearAnimator.progress)
            leftMainGear.animate(progress: gearAnimator.progress)
            rightMainGear.animate(progress: gearAnimator.progress)
        }
    }
}
```

## Rotation Axes and Pivot Points

### Nose Gear
- **Strut Rotation Axis:** `float3(1, 0, 0)` (rotates backward around X axis)
- **Strut Pivot:** Top of strut assembly
- **Door Rotation Axis:** `float3(0, 0, ±1)` (rotate outward around Z axis)

### Main Gear
- **Strut Rotation Axis:** `float3(0, 0, 1)` (rotates forward/inward around Z axis)
- **Strut Pivot:** Top attachment point in wing
- **Door Rotation Axis:** `float3(1, 0, 0)` (rotate around X axis)

> **Note:** Pivot points and axes will require experimental tuning based on actual mesh geometry.

## Alternative: Skeletal Animation (Future)

If skeletal animation is desired in the future, the following would be required:

### Model Requirements
1. Re-export models from Blender/Maya with:
   - Armature/skeleton hierarchy
   - Bone weights per vertex
   - Animation clips (keyframe data)
2. Export as USDZ with animation data

### Code Requirements
1. Parse `MDLAsset.animations` for animation data
2. Load bone/joint hierarchy from `MDLSkeleton`
3. Create bone matrix buffer for GPU
4. Modify vertex shader:

```metal
vertex VertexOut vertex_skeletal(
    VertexIn in [[stage_in]],
    constant float4x4 *boneMatrices [[buffer(BufferIndexBones)]]
) {
    float4x4 skinMatrix =
        boneMatrices[in.boneIndices.x] * in.boneWeights.x +
        boneMatrices[in.boneIndices.y] * in.boneWeights.y +
        boneMatrices[in.boneIndices.z] * in.boneWeights.z +
        boneMatrices[in.boneIndices.w] * in.boneWeights.w;

    float4 skinnedPosition = skinMatrix * float4(in.position, 1.0);
    // ...
}
```

## Testing Plan

1. **Unit Test:** Verify `LandingGearAnimator` state transitions
2. **Visual Test:** Confirm gear retracts/extends smoothly
3. **Hierarchy Test:** Verify wheels move with struts
4. **Door Sequence:** Confirm doors open before strut moves, close after
5. **Input Test:** Verify G key toggles properly, handles rapid presses

## References

- [MDLAsset | Apple Developer Documentation](https://developer.apple.com/documentation/modelio/mdlasset)
- [Metal by Tutorials, Chapter 8: Character Animation | Kodeco](https://www.kodeco.com/books/metal-by-tutorials/v2.0/chapters/8-character-animation)
- [LearnOpenGL - Skeletal Animation](https://learnopengl.com/Guest-Articles/2020/Skeletal-Animation)
- Existing flaps animation in `F18.swift:407-441`
- Existing control surface setup in `F18.swift:306-370`

---

# Implementation Addendum

*Date: December 2024*

## Implementation Summary

The landing gear animation system has been implemented following the plan outlined above. This addendum documents the actual implementation details, files created/modified, issues encountered, and remaining work.

## Files Created

### 1. `ToyFlightSimulator Shared/GameObjects/LandingGearAnimator.swift`

Animation state machine managing gear deployment states and timing.

**Key Features:**
- **States:** `deployed`, `retracted`, `deploying`, `retracting`
- **Progress Tracking:** 0.0 (deployed) to 1.0 (retracted)
- **Animation Speed:** Configurable, default 0.015 progress per frame (~1.5 seconds for full animation at 60fps)
- **Sequenced Animation:**
  - `doorOpenProgress`: Doors open 0-30%, stay open 30-70%, close 70-100%
  - `strutProgress`: Struts move during 10-90% of animation
- **Debug Logging:** Prints state transitions to console

### 2. `ToyFlightSimulator Shared/GameObjects/NoseGearAssembly.swift`

Nose gear component hierarchy with parent-child relationships.

**Components:**
- `strut: SubMeshGameObject` - Uses `MainStrut_Paint` mesh, rotates backward around X axis
- `wheels: SubMeshGameObject` - Uses `NoseWheels_Paint` mesh, child of strut
- `doorLeft: SubMeshGameObject` - Uses `NoseDoors1A_Paint` mesh, rotates outward
- `doorRight: SubMeshGameObject` - Uses `NoseDoors1B_Paint` mesh, rotates outward

**Configuration:**
- Strut pivot: `float3(0, 0, 0.8)`
- Door pivot: `float3(0, 0, 0.2)`
- Strut rotation axis: `float3(1, 0, 0)` (X axis, backward rotation)
- Door rotation axes: `float3(0, 0, ±1)` (Z axis, outward rotation)

### 3. `ToyFlightSimulator Shared/GameObjects/MainGearAssembly.swift`

Main (wing) gear component hierarchy with left/right side variants.

**Components:**
- `strut: SubMeshGameObject` - Uses side-specific mesh, rotates inward/forward
- `wheel: SubMeshGameObject` - Uses side-specific mesh, child of strut
- `door: SubMeshGameObject` - Uses side-specific mesh, rotates outward

**Side-Specific Configuration:**
| Property | Left Side | Right Side |
|----------|-----------|------------|
| Strut Mesh | `MainStrutL_Paint` | `MainStrutR_Paint` |
| Wheel Mesh | `WheelMainL_Paint` | `WheelMainR_Paint` |
| Door Mesh | `GearDoors1L_Paint` | `GearDoors1R_Paint` |
| Strut Rotation Axis | `float3(0.2, 0, 1)` | `float3(-0.2, 0, 1)` |
| Door Rotation Axis | `float3(0, 0, 1)` | `float3(0, 0, -1)` |

**Configuration:**
- Strut pivot: `float3(0, 0, 0.5)`
- Door pivot: `float3(0, 0, 0.3)`

## Files Modified

### 1. `ToyFlightSimulator Shared/Assets/Libraries/SingleSubmeshMeshLibrary.swift`

**Changes:**
- Added 10 new enum cases to `SingleSMMeshType`:
  ```swift
  // Landing Gear - Nose
  case F18_NoseGear_Strut
  case F18_NoseGear_Wheels
  case F18_NoseGear_DoorLeft
  case F18_NoseGear_DoorRight

  // Landing Gear - Main Left
  case F18_MainGearL_Strut
  case F18_MainGearL_Wheel
  case F18_MainGearL_Door

  // Landing Gear - Main Right
  case F18_MainGearR_Strut
  case F18_MainGearR_Wheel
  case F18_MainGearR_Door
  ```

- Added mesh creation and registration in `makeLibrary()` using `SingleSubmeshMesh.createSingleSMMeshFromModel()` with corresponding submesh names from the F18 OBJ model.

### 2. `ToyFlightSimulator Shared/Assets/Libraries/Models/ModelLibrary.swift`

**Changes:**
- Added 10 new enum cases to `ModelType` matching the mesh types
- Added model registration in `makeLibrary()`:
  ```swift
  _library.updateValue(Model(name: "F18_NoseGear_Strut", mesh: noseGearStrutMesh),
                       forKey: .F18_NoseGear_Strut)
  // ... etc for all 10 landing gear models
  ```

### 3. `ToyFlightSimulator Shared/GameObjects/F18.swift`

**Changes:**
- Added landing gear assembly properties:
  ```swift
  let noseGear = NoseGearAssembly()
  let leftMainGear = MainGearAssembly(side: .left)
  let rightMainGear = MainGearAssembly(side: .right)
  let gearAnimator = LandingGearAnimator()
  ```

- Added `setupLandingGear()` call in initializer

- Implemented `setupLandingGear()` method:
  - Attaches gear assemblies to aircraft node hierarchy
  - Hides static landing gear submeshes via `submeshesToDisplay` dictionary

- Replaced TODO landing gear code in `doUpdate()` with working implementation:
  ```swift
  // Landing Gear Animation
  InputManager.HasDiscreteCommandDebounced(command: .ToggleGear) {
      gearAnimator.toggle()
  }

  if gearAnimator.update() {
      noseGear.animate(with: gearAnimator)
      leftMainGear.animate(with: gearAnimator)
      rightMainGear.animate(with: gearAnimator)
  }
  ```

## Issues Encountered and Resolved

### 1. Duplicate `toRadians` Float Extension

**Issue:** Initially added a `toRadians` computed property extension to `LandingGearAnimator.swift`, but this extension already exists in `Math.swift`.

**Resolution:** Removed the duplicate extension from `LandingGearAnimator.swift`. The existing extension in `Math.swift` is used instead:
```swift
extension Float {
    var toRadians: Float { return (self / 180.0) * Float.pi }
    var toDegrees: Float { return self * (180.0 / Float.pi) }
}
```

### 2. Build Failed - Missing Metal Toolchain

**Issue:** Build command failed with error:
```
error: cannot execute tool 'metal' due to missing Metal Toolchain;
use: xcodebuild -downloadComponent MetalToolchain
```

**Resolution:** This is an environment configuration issue, not a code problem. Run the following command to fix:
```bash
xcodebuild -downloadComponent MetalToolchain
```

## Required User Actions

### 1. Add New Files to Xcode Project

The following new Swift files need to be manually added to the Xcode project:

1. Open `ToyFlightSimulator.xcodeproj` in Xcode
2. Right-click on `ToyFlightSimulator Shared/GameObjects/` group
3. Select "Add Files to ToyFlightSimulator..."
4. Add these files:
   - `LandingGearAnimator.swift`
   - `NoseGearAssembly.swift`
   - `MainGearAssembly.swift`
5. Ensure both macOS and iOS targets are checked

### 2. Install Metal Toolchain (if not already installed)

```bash
xcodebuild -downloadComponent MetalToolchain
```

### 3. Build and Test

```bash
# Build Debug configuration
xcodebuild build -project ToyFlightSimulator.xcodeproj \
  -scheme "ToyFlightSimulator macOS" \
  -sdk macosx \
  -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## Tuning Guide

The pivot points and rotation axes may require adjustment based on visual testing. Here's how to tune them:

### Pivot Points

Pivot points define the center of rotation for each component. They are specified relative to the mesh's local coordinate system.

**In `NoseGearAssembly.swift`:**
```swift
let strutPivot = float3(0, 0, 0.8)   // Adjust Z to move pivot up/down strut
let doorPivot = float3(0, 0, 0.2)    // Adjust Z to move pivot along door
```

**In `MainGearAssembly.swift`:**
```swift
let strutPivot = float3(0, 0, 0.5)   // Adjust to match strut attachment point
let doorPivot = float3(0, 0, 0.3)    // Adjust to match door hinge location
```

### Rotation Axes

Rotation axes define the direction of rotation. Use normalized vectors.

| Component | Current Axis | Description |
|-----------|--------------|-------------|
| Nose strut | `(1, 0, 0)` | Rotates backward around X |
| Nose doors | `(0, 0, ±1)` | Rotate outward around Z |
| Main strut L | `(0.2, 0, 1)` | Rotates inward-forward |
| Main strut R | `(-0.2, 0, 1)` | Rotates inward-forward (mirrored) |
| Main doors | `(0, 0, ±1)` | Rotate outward around Z |

### Animation Timing

In `LandingGearAnimator.swift`:
```swift
var animationSpeed: Float = 0.015   // Progress per frame (higher = faster)
let maxStrutRotation: Float = 90.0  // Degrees of strut rotation
let maxDoorRotation: Float = 90.0   // Degrees of door rotation
```

### Door/Strut Sequencing

The animation is sequenced so doors open before struts move and close after:
- **Doors open:** 0% → 30% of progress
- **Struts move:** 10% → 90% of progress
- **Doors close:** 70% → 100% of progress

To adjust this timing, modify `doorOpenProgress` and `strutProgress` computed properties in `LandingGearAnimator.swift`.

## Future Improvements

1. **Additional Doors:** The F18 has multiple door segments per gear. Currently only one door per side is animated. Additional doors could be added for realism.

2. **Sound Effects:** Add audio cues for gear actuation (hydraulic sounds, gear door clunks, gear lock sounds).

3. **Gear Warning System:** Visual/audio warning when gear is up below a certain altitude or airspeed.

4. **Wheel Spin Animation:** Animate wheel rotation based on ground speed when deployed.

5. **Gear Weight-on-Wheels Logic:** Prevent gear retraction when weight is on wheels (aircraft is on ground).

6. **Per-Gear Failure:** Simulate individual gear failures for more realistic emergency scenarios.

## Verification Checklist

- [ ] New files added to Xcode project
- [ ] Metal Toolchain installed
- [ ] Project builds successfully
- [ ] G key toggles gear animation
- [ ] Nose gear retracts backward
- [ ] Main gear retracts inward/forward
- [ ] Wheels move with struts (child hierarchy working)
- [ ] Doors open before struts move
- [ ] Doors close after struts finish
- [ ] Animation can be interrupted mid-cycle
- [ ] Animation reverses smoothly when toggled mid-cycle
