# F-35 Animation Fix Plan

## Problem Statement
The F-35 model animates with incorrect scale (too big) and orientation (pointing at player instead of forward).

## Root Cause Analysis

### Critical Bug #1: Animated Vertex Shader Error (FIXED)

**Location**: `TiledDeferredGBuffer.metal:43-86`

The `tiled_deferred_gbuffer_animated_vertex` shader was applying joint matrices **in clip space** instead of model space:

```metal
// WRONG (original):
float4 worldPosition = modelInstance.modelMatrix * float4(in.position, 1);
float4 position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * worldPosition;
// ...
position = weights.x * (jointMatrices[joints.x] * position) + ...  // APPLIED TO CLIP SPACE!
```

**Fix**: Apply joint matrices in model space BEFORE world/view/projection transforms (matching `shadow_animated_vertex`):

```metal
// CORRECT:
float4 position = float4(in.position, 1.0);  // Start with local position
if (jointMatrices != nullptr) {
    position = weights.x * (jointMatrices[joints.x] * position) + ...  // APPLY IN MODEL SPACE
}
float4 worldPosition = modelInstance.modelMatrix * position;  // THEN transform
```

### Issue #2: Incomplete Basis Transform Propagation

The `basisTransform` is only partially applied through the animation pipeline:

| Component | basisTransform Applied? |
|-----------|------------------------|
| Mesh vertex positions | Yes (`Mesh.transformMeshBasis`) |
| TransformComponent keyframes | Yes (line 68) |
| **Skeleton.bindTransforms** | **No** |
| **Skeleton.restTransforms** | **No** |
| **AnimationClip joint data** | **No** |

The skeletal animation operates in the original USDZ coordinate system, creating a mismatch.

### Issue #3: TransformComponent Scale/Translation Problem (FIXED)

**Root Cause**: `MDLTransform.globalTransform()` returns an **absolute** transform containing:
- Translation in WORLD coordinates (after USDZ scale applied)
- Rotation
- Scale as authored in the USDZ file

When `DrawManager` multiplies `modelMatrix *= currentLocalTransform`:
- The USDZ scale compounds with GameObject's scale (double-scaling)
- The translation is in world coords, not model-local coords (animations appear too large)

**Why Translation & Rotation Worked But Scale Didn't**:
- **Translation**: Additive in world space, combines correctly
- **Rotation**: Multiplicative composition works with conjugation
- **Scale**: Both USDZ scale and GameObject scale multiply together instead of GameObject scale replacing USDZ scale

**Why Skeletal Animation Doesn't Have This Problem**:
- Joint matrices are **relative** transforms from bind pose (`worldPose *= bindTransforms.inverse`)
- Applied in model space before world transform
- GameObject's scale is the sole source of scale

**TransformComponent Problem**:
- `keyTransforms` are **absolute** world-space transforms
- Scale and translation baked into the transform conflict with GameObject's TRS

## Implementation Plan

### Phase 1: Fix Vertex Shader (COMPLETED)
Manually fixed by user.

### Phase 2: Propagate basisTransform to Skeleton/Animation

#### Step 1: Modify Skeleton to Accept basisTransform
- Add `basisTransform` parameter to `Skeleton.init(mdlSkeleton:basisTransform:)`
- Transform `bindTransforms` by the basis matrix
- Transform `restTransforms` by the basis matrix

#### Step 2: Modify AnimationClip to Accept basisTransform
- Add `basisTransform` parameter to `AnimationClip.init(animation:basisTransform:)`
- Transform joint translations by the basis matrix
- Transform joint rotations by the basis quaternion (extract from matrix)

#### Step 3: Update UsdModel to Pass basisTransform
- Pass `basisTransform` when creating Skeleton
- Pass `basisTransform` when creating AnimationClips

### Phase 3: Multi-Skeleton Support (COMPLETED)

**Problem Identified**: Complex models like F-35 may have multiple skeletons (landing gear, canopy, control surfaces, etc.), but the original code only used the FIRST skeleton for ALL meshes.

**Root Cause**: `MDLAnimationBindComponent.skeleton` property was being ignored - this property tells us which skeleton a specific mesh is bound to.

#### Implementation:

1. **Changed data structures in UsdModel**:
   - `skeleton: Skeleton?` → `skeletons: [String: Skeleton]` (dictionary keyed by path)
   - Added `meshSkeletonMap: [Int: String]` to track mesh-to-skeleton associations
   - Added `skeletonAnimationMap: [String: String]` to associate animations with skeletons

2. **`loadSkeletons()`**: Creates Skeleton objects for ALL MDLSkeletons in the asset

3. **`loadSkins()`**: Now uses `animationBindComponent.skeleton` to find the correct skeleton for each mesh
   - Falls back to joint path matching if skeleton property is nil
   - Falls back to single skeleton if only one exists

4. **`loadAnimations()`**: Associates each animation clip with its matching skeleton by comparing joint paths

5. **`update()`**: Updates ALL skeletons with their respective animations, then updates each mesh's skin with its OWN skeleton

### Phase 4: Determine Correct Basis for F-35 (COMPLETED)
- F-35 uses `Transform.rotationMatrix(radians: Float(180).toRadians, axis: Y_AXIS)` (180° Y rotation)
- This corrects the orientation so the jet faces forward instead of at the player

### Phase 5: Fix TransformComponent Scale & Translation (COMPLETED)

**Problem**: Non-skeletal mesh animations (landing gear, canopy) had wrong scale and oversized movements.

#### Step 1: Add Matrix Decomposition Utility
Added to `Transform.swift`:
- `decomposeTRS(_ matrix:)` - Extracts translation, rotation, and scale from a 4x4 TRS matrix
- `matrixFromTR(translation:rotation:)` - Reconstructs matrix from T and R only (no scale)

#### Step 2: Strip Scale from TransformComponent Keyframes
Modified `TransformComponent.init()` to:
1. Decompose each `globalTransform` into T, R, S components
2. **Strip scale** - Scale is now solely controlled by `GameObject.setScale()`
3. **Normalize translation** - Divide world-space translation by USDZ scale to get model-local translation
4. Reconstruct transform with only normalized T and R
5. Apply basisTransform conjugation for coordinate system conversion

```swift
let (worldTranslation, rotation, scale) = Transform.decomposeTRS(globalTransform)

// Normalize: world coords → model-local coords
let normalizedTranslation = float3(
    worldTranslation.x / scale.x,
    worldTranslation.y / scale.y,
    worldTranslation.z / scale.z
)

let transformWithoutScale = Transform.matrixFromTR(translation: normalizedTranslation, rotation: rotation)
```

**Result**: Animation translations are now in model-local coordinates, so `GameObject.setScale()` scales everything proportionally together.

## Files Modified

1. `TiledDeferredGBuffer.metal` - Fixed vertex shader order (Phase 1)
2. `Skeleton.swift` - Added basisTransform support with conjugation in updatePose() (Phase 2)
3. `UsdModel.swift` - Complete refactor for multi-skeleton support (Phase 2 & 3):
   - Store all skeletons in dictionary
   - Track mesh-to-skeleton mappings
   - Associate animations with correct skeletons
   - Update each mesh with its own skeleton
4. `Transform.swift` - Added matrix decomposition utilities (Phase 5):
   - `decomposeTRS()` - Extracts T, R, S from 4x4 matrix
   - `matrixFromTR()` - Reconstructs matrix without scale
5. `TransformComponent.swift` - Fixed scale/translation handling (Phase 5):
   - Strip USDZ scale from keyframes
   - Normalize translations from world coords to model-local coords
   - Apply basisTransform conjugation for coordinate conversion

## Testing

After implementation:
1. Build the project
2. Load a scene with the F-35
3. Check console output for skeleton/mesh/animation associations
4. Verify:
   - All animated parts (landing gear, canopy, etc.) animate correctly
   - Each mesh uses its correct skeleton
   - Model is correctly scaled and oriented
   - `GameObject.setScale()` controls the model size
   - Animation movements are proportional to the scaled model

## Summary

The F-35 animation issues were caused by multiple factors:
1. **Shader bug**: Joint matrices applied in clip space instead of model space
2. **Coordinate system mismatch**: basisTransform needed conjugation in Skeleton and TransformComponent
3. **Multi-skeleton support**: Complex models need per-mesh skeleton associations
4. **Scale/translation conflict**: USDZ absolute transforms conflicted with GameObject's TRS system

The fix ensures that:
- Skeletal animations use relative transforms (joint matrices relative to bind pose)
- Non-skeletal animations use normalized transforms (scale stripped, translation in model-local coords)
- `GameObject.setScale()` is the sole source of scale for the entire model
