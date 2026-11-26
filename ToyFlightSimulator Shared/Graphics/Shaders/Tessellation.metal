//
//  Tessellation.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/11/25.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"
#import "Lighting.metal"

float getCameraDistance(float3 pointA, float3 pointB, float3 cameraPosition, float4x4 modelMatrix) {
    float3 positionA = (modelMatrix * float4(pointA, 1)).xyz;
    float3 positionB = (modelMatrix * float4(pointB, 1)).xyz;
    float3 midPoint = (positionA + positionB) * 0.5;
    
    float cameraDistance = distance(cameraPosition, midPoint);
    return cameraDistance;
}

// Reads the height texture at a position between samples: the four texels around the position,
// blended by how far the position is across the cell they form (bilinear interpolation,
// written out by hand).
//
// sampleCoordinate is measured in samples: (2.0, 7.0) is exactly the texel in column 2, row 7,
// and (2.5, 7.0) is halfway to column 3. A coordinate outside the texture gives the value at
// the nearest edge.
//
// Uses exact texel reads (read, not sample), so it works for a 32-bit float texture on every
// GPU. Not every GPU can filter that format with a sampler.
//
// The texture must be at least 2 texels wide and 2 tall. With 1, "lastColumn - 1" below wraps
// around to 4,294,967,295, because a uint has no -1.
float readHeightBetweenSamples(texture2d<float> heightMap, float2 sampleCoordinate) {
    uint lastColumn = heightMap.get_width() - 1;
    uint lastRow = heightMap.get_height() - 1;
    // The same two numbers as floats: clamp does not accept a uint2 bound next to a float2.
    float2 lastSampleCoordinate = float2(lastColumn, lastRow);
    // Keep the position on the grid. This is done while the value is still a float: a
    // coordinate below 0 must become 0 before it is converted to a uint, which cannot hold a
    // negative number.
    float2 clampedCoordinate = clamp(sampleCoordinate, float2(0, 0), lastSampleCoordinate);
    // The lower-index corner of the cell the position is in. Never the last column or row, so
    // that "+ 1" below stays inside the texture.
    uint lowerColumn = min(uint(floor(clampedCoordinate.x)), lastColumn - 1);
    uint lowerRow = min(uint(floor(clampedCoordinate.y)), lastRow - 1);
    // How far the position is across the cell, 0 … 1. On the far edge of the texture the
    // corner is the second-to-last sample and the fraction is 1, so the last texel is returned.
    float fractionAlongColumns = clampedCoordinate.x - float(lowerColumn);
    float fractionAlongRows = clampedCoordinate.y - float(lowerRow);
    // read takes one uint2 (column, row). Given two separate numbers, read(column, row) still
    // compiles, but takes the second number as the mip level. read returns a float4; .r is
    // the texel's value.
    float valueAtLowColumnLowRow    = heightMap.read(uint2(lowerColumn,     lowerRow    )).r;
    float valueAtHighColumnLowRow   = heightMap.read(uint2(lowerColumn + 1, lowerRow    )).r;
    float valueAtLowColumnHighRow   = heightMap.read(uint2(lowerColumn,     lowerRow + 1)).r;
    float valueAtHighColumnHighRow  = heightMap.read(uint2(lowerColumn + 1, lowerRow + 1)).r;
    // Blend along the columns in each of the two rows, then along the rows between the two
    // results. mix(a, b, t) is a + (b - a) * t.
    float alongLowRow  = mix(valueAtLowColumnLowRow,  valueAtHighColumnLowRow,  fractionAlongColumns);
    float alongHighRow = mix(valueAtLowColumnHighRow, valueAtHighColumnHighRow, fractionAlongColumns);
    return mix(alongLowRow, alongHighRow, fractionAlongRows);
}

// The terrain's height in local units at a position on the sample grid:
// heightOffset + texel * heightScale. The two numbers come from the Terrain struct, so the same
// code serves a texture that stores 0 … 1 (the image) and one that stores meters (the
// procedural bake).
float decodedLocalHeight(texture2d<float> heightMap, float2 sampleCoordinate, Terrain terrain) {
    float texelValue = readHeightBetweenSamples(heightMap, sampleCoordinate);
    return terrain.heightOffset + texelValue * terrain.heightScale;
}

// ORIGINAL:
//static float4 SampleTerrainLayer(float height,
//                                 float2 uv,
//                                 float tiling,
//                                 texture2d<float> grass,
//                                 texture2d<float> cliff,
//                                 texture2d<float> snow,
//                                 sampler s) {
//    if (height < -0.5) { return grass.sample(s, uv * tiling); }
//    if (height <  0.3) { return cliff.sample(s, uv * tiling); }
//    return snow.sample(s, uv * tiling);
//}

// Picks the ground texture by height: grass below grassBelowHeight, snow at and above
// snowAboveHeight, rock (the cliff texture) between. The thresholds come from the Terrain
// struct and are in the same local units as the height the vertex function wrote.
//
// textureCoordinate runs 0 … 1 across the terrain. It is multiplied by
// colorTextureRepeatCount, so the sampler must use repeat addressing.
static float4 SampleTerrainLayer(float localHeight,
                                 float2 textureCoordinate,
                                 Terrain terrain,
                                 texture2d<float> grass,
                                 texture2d<float> cliff,
                                 texture2d<float> snow,
                                 sampler repeatingSampler) {
    float2 repeatedCoordinate = textureCoordinate * terrain.colorTextureRepeatCount;
    if (localHeight < terrain.grassBelowHeight) { return grass.sample(repeatingSampler, repeatedCoordinate); }
    if (localHeight < terrain.snowAboveHeight)  { return cliff.sample(repeatingSampler, repeatedCoordinate); }
    return snow.sample(repeatingSampler, repeatedCoordinate);
}

// This kernel computes tessellation for quads (for things like terrain)
kernel void compute_tessellation(
  constant float                          *edgeFactors    [[ buffer(0) ]],
  constant float                          *insideFactors  [[ buffer(1) ]],
  device MTLQuadTessellationFactorsHalf   *factors        [[ buffer(2) ]],
  uint                                    pid             [[ thread_position_in_grid ]],
  constant float4                         &cameraPosition [[ buffer(3) ]],
  constant float4x4                       &modelMatrix    [[ buffer(4) ]],
  constant TerrainControlPoint            *controlPoints  [[ buffer(5) ]],
  constant Terrain                        &terrain        [[ buffer(TFSBufferIndexTerrain) ]]) {
    uint index = pid * 4;  // 4 is the number of control points per patch; may want to dynamically supply this
    float totalTessellation = 0;
    
    for (int i = 0; i < 4; i++) {
        int pointAIndex = i;
        int pointBIndex = i + 1;
        if (pointAIndex == 3) {
            pointBIndex = 0;
        }
        int edgeIndex = pointBIndex;
        
        float cameraDistance = getCameraDistance(controlPoints[pointAIndex + index].position,
                                                 controlPoints[pointBIndex + index].position,
                                                 cameraPosition.xyz,
                                                 modelMatrix);
        
        float tessellation = max(4.0, terrain.maxTessellation / cameraDistance);
        factors[pid].edgeTessellationFactor[edgeIndex] = tessellation;
        totalTessellation += tessellation;
    }
    
    factors[pid].insideTessellationFactor[0] = totalTessellation * 0.25;
    factors[pid].insideTessellationFactor[1] = totalTessellation * 0.25;
}


[[ patch(quad, 4) ]]
vertex TessellationVertexOut
tessellation_vertex(patch_control_point<TerrainControlPoint> controlPoints      [[ stage_in ]],
                    constant SceneConstants                  &sceneConstants    [[ buffer(TFSBufferIndexSceneConstants) ]],
                    constant ModelConstants                  &modelConstants    [[ buffer(TFSBufferModelConstants) ]],
                    texture2d<float>                         heightMap          [[ texture(TFSTextureIndexHeightMap) ]],
                    constant Terrain                         &terrain           [[ buffer(TFSBufferIndexTerrain) ]],
                    float2                                   patchCoord         [[ position_in_patch ]],
                    uint                                     patchId            [[ patch_id ]]) {
    float u = patchCoord.x;
    float v = patchCoord.y;
    
    float2 top = mix(controlPoints[0].position.xz,
                     controlPoints[1].position.xz,
                     u);
    
    float2 bottom = mix(controlPoints[3].position.xz,
                        controlPoints[2].position.xz,
                        u);
    
    float2 interpolated = mix(top, bottom, v);
    float4 position = float4(interpolated.x, 0.0, interpolated.y, 1.0);
    
    // Where the vertex is across the terrain, 0 … 1 on each axis. Local x and z run from
    // -size / 2 to +size / 2.
    float2 positionAcrossTerrain = (position.xz + terrain.size / 2.0) / terrain.size;
    // The same place measured in samples. N samples span N - 1 cells, so the far edge of the
    // terrain is sample N - 1, not N.
    float2 lastSampleCoordinate = float2(heightMap.get_width() - 1, heightMap.get_height() - 1);
    float2 sampleCoordinate = positionAcrossTerrain * lastSampleCoordinate;
    float localHeight = decodedLocalHeight(heightMap, sampleCoordinate, terrain);
    position.y = localHeight;
    
    /*
     -- ORIGINAL HEIGHT SAMPLING CODE --
     float2 xy = (position.xz + terrain.size / 2.0) / terrain.size;
    constexpr sampler sample;
    float4 color = heightMap.sample(sample, xy);
    float height = (color.r * 2 - 1) * terrain.height;
    position.y = height;
     */
    
    float4 worldPosition = modelConstants.modelMatrix * position;
    position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * worldPosition;
    
    TessellationVertexOut out {
        .position = position,
        .color = float4(localHeight),
        .height = localHeight,
        .uv = positionAcrossTerrain,
        .worldPosition = worldPosition.xyz
    };
    
    return out;
}

fragment float4
tessellation_fragment(TessellationVertexOut in              [[ stage_in ]],
                      constant Terrain      &terrain        [[ buffer(TFSBufferIndexTerrain) ]],
                      texture2d<float>      grassTexture    [[ texture(TFSTextureIndexGrass) ]],
                      texture2d<float>      cliffTexture    [[ texture(TFSTextureIndexCliff) ]],
                      texture2d<float>      snowTexture     [[ texture(TFSTextureIndexSnow) ]]) {
    // Repeat addressing: a default sampler clamps to the edge, which would smear the last
    // texel over every repeat after the first.
    constexpr sampler repeatingSampler(filter::linear, mip_filter::linear, address::repeat);
    float4 color = SampleTerrainLayer(in.height, in.uv, terrain, grassTexture, cliffTexture, snowTexture, repeatingSampler);
    return color;
}

fragment GBufferOut
tessellation_gbuffer_fragment(
                      TessellationVertexOut in              [[ stage_in ]],
                      constant Terrain      &terrain        [[ buffer(TFSBufferIndexTerrain) ]],
                      texture2d<float>      grassTexture    [[ texture(TFSTextureIndexGrass) ]],
                      texture2d<float>      cliffTexture    [[ texture(TFSTextureIndexCliff) ]],
                      texture2d<float>      snowTexture     [[ texture(TFSTextureIndexSnow) ]],
                      texture2d<half>       normalTexture   [[ texture(TFSTextureIndexNormal) ]],
                      depth2d_array<float>  shadowArray     [[ texture(TFSTextureIndexShadow) ]]) {
    // Repeat addressing, as in tessellation_fragment.
    constexpr sampler repeatingSampler(filter::linear, mip_filter::linear, address::repeat);
    float4 color = SampleTerrainLayer(in.height, in.uv, terrain, grassTexture, cliffTexture, snowTexture, repeatingSampler);
    
    // TODO:
//    color.a = Lighting::CalculateShadowMSAA(in.shadowPosition, shadowTexture);
    
    // No material is bound for the terrain, so the spare G-buffer channels get constants: a
    // strength of 0 (matte; a 1.0 here washed the whole terrain with a 60°-wide highlight) and
    // the default exponent. The flat up normal is a placeholder until the terrain derives one.
    float4 normalSpecular = float4(0.0, 1.0, 0.0, Lighting::DEFAULT_SPECULAR_STRENGTH);  // TODO
    
    if (!is_null_texture(normalTexture)) {
        normalSpecular = float4(normalTexture.sample(repeatingSampler, in.uv));
        normalSpecular.a = Lighting::DEFAULT_SPECULAR_STRENGTH;
    }
    
    GBufferOut out {
        // The terrain gives off no light: 0 replaces the clear color in the lighting target,
        // so the sun pass reads no emission here (see GBufferOut).
        .lighting = float4(0, 0, 0, 1),
        .albedo = color,
        .normalSpecular = normalSpecular,
        // World-space meters — the point-light pass reads this target as the fragment's
        // world position. ([[position]] at the fragment stage is the window coordinate.)
        .positionShininess = float4(in.worldPosition, Lighting::DEFAULT_SHININESS)
    };
    return out;
}
