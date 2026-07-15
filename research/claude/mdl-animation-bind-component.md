# MDLAnimationBindComponent Investigation

## Overview

This document explains why some `MDLMesh` objects in ModelIO do not have `MDLAnimationBindComponent` attached, even though the meshes are actually animatable.

## Key Insight

**`MDLAnimationBindComponent` is specifically for skeletal/skinned mesh animation** - where individual vertex positions are influenced by bone weights. However, meshes can be animated through several other mechanisms that don't require this component.

## Animation Types in ModelIO

### 1. Skeletal/Skinned Animation

- **Requires**: `MDLAnimationBindComponent`
- **How it works**: Vertices are bound to bones/joints with weights. When bones move, vertices are deformed accordingly.
- **Use case**: Character animation, organic deformation

### 2. Transform Animation (Rigid Body)

- **Does NOT require**: `MDLAnimationBindComponent`
- **How it works**: The mesh's position/rotation/scale is animated as a whole unit. No vertex deformation occurs.
- **Use case**: Aircraft control surfaces, landing gear, mechanical parts
- **Detection**: Check `mesh.transform?.keyTimes`

### 3. Morph Targets / Blend Shapes

- **Does NOT require**: `MDLAnimationBindComponent`
- **Uses**: `MDLMorphDeformTransform` instead
- **How it works**: Interpolates between pre-defined mesh states
- **Use case**: Facial expressions, shape morphing

### 4. Hierarchical Animation

- **Does NOT require**: `MDLAnimationBindComponent` on child meshes
- **How it works**: Child meshes inherit animated transforms from parent nodes
- **Use case**: Articulated mechanisms, robotic arms, aircraft parts

## File Format Variations

Different 3D file formats store animation data differently, affecting whether ModelIO creates an `MDLAnimationBindComponent`:

| Format                | Skeleton Support     | MDLAnimationBindComponent Presence               |
| --------------------- | -------------------- | ------------------------------------------------ |
| USDZ/USD              | Full support         | Usually present for skinned meshes               |
| FBX                   | Partial/inconsistent | May be missing due to parsing limitations        |
| OBJ                   | None                 | Never present (format doesn't support animation) |
| glTF (via conversion) | Varies               | Often lost in format conversion                  |

## Separate vs. Embedded Skeletons

In some file formats, the skeleton exists as a **separate scene graph hierarchy** rather than being embedded as a component on the mesh itself:

- The mesh _can_ be animated by referencing that skeleton
- ModelIO doesn't automatically create the binding component in this case
- The binding information may be stored elsewhere in the asset's structure

## Relevance to Aircraft Animation

Aircraft typically use **rigid body animation** rather than skeletal animation:

### Common Rigid Body Animated Parts

- Control surfaces (ailerons, elevators, rudders, flaps)
- Landing gear (doors, struts, wheels)
- Canopy/cockpit elements
- Thrust vectoring nozzles
- Weapon bay doors
- Refueling probes

These are usually **separate mesh objects** whose transforms are animated independently. They don't need `MDLAnimationBindComponent` because:

1. No vertex deformation is occurring
2. Each part moves as a rigid unit
3. Animation is achieved by rotating/translating the entire mesh object

## Detecting Animation Capability

To properly detect all animation types on an MDLMesh:

```swift
import ModelIO

extension MDLMesh {
    /// Check if this mesh has skeletal animation binding
    var hasSkeletalAnimation: Bool {
        return component(ofType: MDLAnimationBindComponent.self) != nil
    }

    /// Check if this mesh has direct transform animation
    var hasTransformAnimation: Bool {
        guard let transform = self.transform,
              let keyTimes = transform.keyTimes else {
            return false
        }
        return !keyTimes.isEmpty
    }
}

/// Check if an object has any animated ancestors in the hierarchy
func hasAnimatedAncestor(_ object: MDLObject) -> Bool {
    var current = object.parent
    while let parent = current {
        if let transform = parent.transform,
           let keyTimes = transform.keyTimes,
           !keyTimes.isEmpty {
            return true
        }
        current = parent.parent
    }
    return false
}

/// Comprehensive animation detection
func detectAnimationType(for mesh: MDLMesh) -> [String] {
    var types: [String] = []

    // Skeletal animation
    // TINO's NOTE: the following component(ofType:) method doesn't actually exist:
    if mesh.component(ofType: MDLAnimationBindComponent.self) != nil {
        types.append("skeletal")
    }

    // Direct transform animation
    if let transform = mesh.transform,
       let keyTimes = transform.keyTimes,
       !keyTimes.isEmpty {
        types.append("transform")
    }

    // Hierarchical animation (animated parent)
    if hasAnimatedAncestor(mesh) {
        types.append("hierarchical")
    }

    return types
}
```

## Inspecting MDLAnimationBindComponent

When present, `MDLAnimationBindComponent` provides:

```swift
if let bindComponent = mesh.component(ofType: MDLAnimationBindComponent.self) {
    // The skeleton controlling this mesh
    let skeleton = bindComponent.skeleton

    // Joint bind transforms (rest pose)
    let jointBindTransforms = bindComponent.jointBindTransforms

    // Joint paths in the skeleton hierarchy
    let jointPaths = bindComponent.jointPaths
}
```

## Implications for Animation System Design

When building an animation system that needs to handle ModelIO assets:

1. **Don't assume `MDLAnimationBindComponent` presence** means "animatable"
2. **Don't assume absence** means "not animatable"
3. **Check multiple animation sources**:
   - Skeletal binding component
   - Transform keyframes on the object itself
   - Transform keyframes on parent objects
   - Morph deform transforms
4. **For rigid body animation** (like aircraft parts), look for transform animations rather than skeletal bindings

## References

- [MDLAnimationBindComponent - Apple Developer Documentation](https://developer.apple.com/documentation/modelio/mdlanimationbindcomponent)
- [MDLTransformComponent - Apple Developer Documentation](https://developer.apple.com/documentation/modelio/mdltransformcomponent)
- [Working with USD in ModelIO - WWDC Sessions](https://developer.apple.com/videos/play/wwdc2019/610/)
