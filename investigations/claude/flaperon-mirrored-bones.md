# Why Flaperon Channels Don't Need Opposite Inversion

## Question
Why do the left and right flaperon `ProceduralAnimationChannel`s both use `inverted: false` and still produce opposite visual deflections for roll?

## Answer
The rig was built with mirrored bone orientations (standard Blender symmetric rig setup), so the same rotation applied to both produces naturally opposite visual deflections. No inversion flag is needed.

## Evidence

Dumped from `cgtrader_F22.usdz` via `inspect_flaperon_transforms.swift`:

### LeftFlaperon Rest Transform
```
Rotation matrix (3x3):
  [+0.2907, +0.9568,  0.0000]
  [-0.9568, +0.2907,  0.0000]
  [ 0.0000,  0.0000, +1.0000]

Quaternion axis: (0, 0, +1.0), angle: +73.1°
Translation: (2.07, 1.71, 0.10)
```

### RightFlaperon Rest Transform
```
Rotation matrix (3x3):
  [+0.2907, -0.9568,  0.0000]
  [+0.9568, +0.2907,  0.0000]
  [ 0.0000,  0.0000, +1.0000]

Quaternion axis: (0, 0, -1.0), angle: +73.1°
Translation: (-2.07, 1.71, 0.10)
```

### Key Observation
The rest transforms are **mirror images** around the YZ plane:
- LeftFlaperon: rotated **+73° around +Z**
- RightFlaperon: rotated **+73° around -Z** (equivalently, -73° around +Z)
- Translations are mirrored on X axis: `+2.07` vs `-2.07`

## Mechanism

In `Skeleton.applyProceduralOverrides()`, the final local pose is:
```swift
localPoses[index] = restTransforms[index] * rotationOverride
```

When both channels receive the same value (e.g., `value = 1.0`) and compute the same rotation override (e.g., `+25° around Y`):

- **LeftFlaperon**: `restTransform(+73° around Z) * rotation(+25° around Y)`
- **RightFlaperon**: `restTransform(-73° around Z) * rotation(+25° around Y)`

The rotation override is applied **in bone-local space** (right-multiplied). Since the bones' local coordinate frames are mirrored (due to the opposite Z-rotation in the rest pose), their local Y-axes point in **opposite world-space directions**. A positive Y-rotation on the left bone deflects one way; the same positive Y-rotation on the right bone deflects the opposite way.

## Same Pattern Across All Control Surfaces

This mirroring is consistent across the F-22 rig:

| Surface | Left Z-axis | Right Z-axis | Left X translation | Right X translation |
|---------|-------------|--------------|-------------------|---------------------|
| Aileron | +1.0 | -1.0 | +2.73 | -2.73 |
| Flaperon | +1.0 | -1.0 | +2.07 | -2.07 |
| Rudder | Complex 3-axis | Mirrored 3-axis | +1.40 | -1.40 |
| HorzStablizer | Identity | Identity | +0.70 | -0.70 |

Note: Horizontal stabilizers have identity rotation (no Z-rotation), meaning their local axes are aligned with world axes. Both left and right would deflect the same direction for the same input — which is correct, since elevator surfaces deflect together for pitch control (not oppositely like ailerons/flaperons for roll).
