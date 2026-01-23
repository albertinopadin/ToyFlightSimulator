# Tessellated Terrain Bug Analysis and Fix Plan

## Issue Summary

The tessellated terrain displays a jagged/sawtooth pattern along edges in the `animation` branch, while it renders correctly (smooth) in the `main` branch.

## Root Cause: Stride Mismatch Between Swift ControlPoint and Metal Vertex Descriptor

There's a **fundamental pre-existing bug** where the Swift `ControlPoint` struct has a different memory stride than what the `TessellationVertexDescriptor` and shaders expect:

| Component | Expected Stride | Actual ControlPoint Stride |
|-----------|-----------------|---------------------------|
| Vertex Descriptor | **32 bytes** | ~80-96 bytes |
| Compute Shader (`float3*`) | **12 bytes** | ~80-96 bytes |

### Swift `ControlPoint` Layout (with SIMD alignment)

```
Offset  Field              Size    Notes
------  -----------------  ------  ---------------------------
0       position: float3   12      padded to 16 for alignment
16      color: float4      16
32      textureCoord: f2   8       padded to 16
48      normal: float3     12      padded to 16
64      tangent: float3    12      padded to 16
80      bitangent: float3  12
------
Total stride: ~80-96 bytes
```

### TessellationVertexDescriptor Expects

From `BasicVertexDescriptors.swift:55-60`:

```swift
init() {
    vertexDescriptor = MTLVertexDescriptor()
    addAttributeWithOffset(format: .float3, bufferIndex: 0)  // position @ offset 0
    addAttributeWithOffset(format: .float4, bufferIndex: 0)  // color @ offset 12
    vertexDescriptor.layouts[0].stride = float4.stride * 2   // stride: 32 bytes
    vertexDescriptor.layouts[0].stepFunction = .perPatchControlPoint
}
```

## Why This Causes The Sawtooth Pattern

When the GPU reads control points with 32-byte stride but actual data has ~96-byte stride:

| Control Point | Reads Bytes | Actually Contains |
|---------------|-------------|-------------------|
| CP[0] | 0-11 | CP[0].position ✓ |
| CP[1] | 32-43 | CP[0].textureCoord/normal ✗ |
| CP[2] | 64-75 | CP[0].tangent ✗ |
| CP[3] | 96-107 | CP[1].position (by coincidence) |

The compute shader (`Tessellation.metal:29`) reads `constant float3 *controlPoints` with implicit 12-byte stride:

```metal
constant float3 *controlPoints  [[ buffer(5) ]]
```

This reads wrong positions for CP[1], CP[2], CP[3], causing:
1. Wrong tessellation factors (incorrect camera distances)
2. Wrong patch corner positions for interpolation
3. Regular sawtooth pattern along terrain edges

## Why Main Branch Appears to Work

The bug exists in both branches, but main may appear to work due to:
1. Different memory alignment/padding behavior
2. Accidental data patterns where wrong values looked acceptable
3. Metal driver tolerance for mismatched data

Animation branch changes that may have affected behavior:
- Added `joints: simd_ushort4` and `jointWeights: float4` to `Vertex` struct
- Added joints/jointWeights to `TFSVertexAttributes.allCases`
- Refactored DrawManager with mesh parameter
- Added RenderState tracking

## Affected Files

- `ToyFlightSimulator Shared/Core/Types/MetalTypes.swift` - ControlPoint struct
- `ToyFlightSimulator Shared/GameObjects/Tesselation/TerrainObject.swift` - Buffer creation
- `ToyFlightSimulator Shared/Graphics/Libraries/VertexDescriptors/BasicVertexDescriptors.swift` - TessellationVertexDescriptor
- `ToyFlightSimulator Shared/Graphics/Shaders/Tessellation.metal` - Compute shader
- `ToyFlightSimulator Shared/Graphics/Shaders/TFSCommon.h` - Metal ControlPoint struct

---

## Fix Plan

### Option A: Create Dedicated Tessellation Control Point Struct (Recommended)

#### Step 1: Add New Struct to MetalTypes.swift

```swift
/// Control point struct specifically for tessellation.
/// Matches TessellationVertexDescriptor layout exactly (32-byte stride).
struct TessellationControlPoint: sizeable {
    var position: float4 = [0, 0, 0, 1]  // 16 bytes (use float4 for alignment)
    var color: float4 = [0, 0, 0, 1]     // 16 bytes
}
// Total stride: 32 bytes
```

#### Step 2: Update TerrainObject.createControlPoints()

Change return type and buffer creation:

```swift
static func createControlPoints(patches: (horizontal: Int, vertical: Int),
                                size: (width: Float, height: Float)) -> [TessellationControlPoint] {
    var points: [float3] = []
    // ... existing point generation code ...

    return points.map { TessellationControlPoint(position: float4($0, 1)) }
}

func makeControlPointsBuffer(size: (width: Float, height: Float) = (2, 2)) -> MTLBuffer? {
    let controlPoints = Self.createControlPoints(patches: self.patches, size: size)
    return Engine.Device.makeBuffer(bytes: controlPoints,
                                    length: TessellationControlPoint.stride(controlPoints.count))
}
```

#### Step 3: Update TessellationVertexDescriptor

Ensure position uses float4 format:

```swift
init() {
    vertexDescriptor = MTLVertexDescriptor()
    addAttributeWithOffset(format: .float4, bufferIndex: TFSBufferIndexMeshVertex.index)  // position
    addAttributeWithOffset(format: .float4, bufferIndex: TFSBufferIndexMeshVertex.index)  // color
    vertexDescriptor.layouts[0].stride = TessellationControlPoint.stride  // 32 bytes
    vertexDescriptor.layouts[0].stepFunction = .perPatchControlPoint
}
```

#### Step 4: Update Metal ControlPoint Struct (TFSCommon.h)

Add a tessellation-specific struct or update existing:

```c
struct TessellationControlPoint {
    vector_float4 position  [[ attribute(TFSVertexAttributePosition) ]];
    vector_float4 color     [[ attribute(TFSVertexAttributeColor) ]];
};
```

#### Step 5: Update Tessellation Shader

Update `tessellation_vertex` to use float4 position:

```metal
[[ patch(quad, 4) ]]
vertex TessellationVertexOut
tessellation_vertex(patch_control_point<TessellationControlPoint> controlPoints [[ stage_in ]],
                    // ... other parameters
{
    float2 top = mix(controlPoints[0].position.xz,
                     controlPoints[1].position.xz,
                     u);
    // ... rest of shader (unchanged since we use .xz)
}
```

#### Step 6: Update Compute Shader

Fix control point reading in `compute_tessellation`:

```metal
// Option A: Use float4 stride (32 bytes per control point)
constant float4 *controlPointPositions  [[ buffer(5) ]]

// Access: controlPointPositions[i * 2] gives position of control point i
// (color is at controlPointPositions[i * 2 + 1])

// Option B: Create matching struct
struct TessellationControlPointData {
    float4 position;
    float4 color;
};
constant TessellationControlPointData *controlPoints  [[ buffer(5) ]]
```

---

### Option B: Fix Vertex Descriptor to Match Existing ControlPoint

This option keeps the existing ControlPoint struct but updates the vertex descriptor.

#### Step 1: Calculate Actual ControlPoint Stride

Add debug logging to verify:

```swift
print("ControlPoint.stride: \(ControlPoint.stride)")
print("ControlPoint.size: \(ControlPoint.size)")
```

#### Step 2: Update TessellationVertexDescriptor

```swift
init() {
    vertexDescriptor = MTLVertexDescriptor()
    // Set offsets to match actual ControlPoint memory layout
    addAttribute(attributeIdx: TFSVertexAttributePosition.index,
                 format: .float3,
                 bufferIndex: 0,
                 m_offset: 0)
    addAttribute(attributeIdx: TFSVertexAttributeColor.index,
                 format: .float4,
                 bufferIndex: 0,
                 m_offset: 16)  // After float3 + padding
    vertexDescriptor.layouts[0].stride = ControlPoint.stride
    vertexDescriptor.layouts[0].stepFunction = .perPatchControlPoint
}
```

#### Step 3: Update Compute Shader

Create matching struct in Metal to read ControlPoint data correctly.

---

## Verification Steps

After implementing the fix:

1. **Build and run** with TiledMSAATessellatedRenderer
2. **Visual verification**: Terrain edges should be smooth (no sawtooth pattern)
3. **Multi-angle testing**: Verify from multiple camera angles and distances
4. **Height map verification**: Terrain height should match heightmap data
5. **Performance check**: Ensure no performance regression from stride changes
6. **Compare with main**: Side-by-side comparison with main branch rendering

## Recommendation

**Option A is recommended** because:
- Creates a minimal struct specifically designed for tessellation
- Matches both vertex descriptor and shader expectations exactly
- Avoids complexity of trying to make general ControlPoint work with tessellation
- Clearer separation of concerns between animation vertices and tessellation control points
- 32-byte stride is clean and cache-friendly

## Notes

- The existing `ControlPoint` struct in `MetalTypes.swift` should remain unchanged for other uses
- The Metal `ControlPoint` struct in `TFSCommon.h` may need to be renamed or a new struct added
- Consider adding static assertions or runtime checks to verify struct sizes match expectations
