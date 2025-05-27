//
//  Tessellation.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/11/25.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"

float getCameraDistance(float3 pointA, float3 pointB, float3 cameraPosition, float4x4 modelMatrix) {
    float3 positionA = (modelMatrix * float4(pointA, 1)).xyz;
    float3 positionB = (modelMatrix * float4(pointB, 1)).xyz;
    float3 midPoint = (positionA + positionB) * 0.5;
    
    float cameraDistance = distance(cameraPosition, midPoint);
    return cameraDistance;
}

// This kernel computes tessellation for quads (for things like terrain)
kernel void compute_tessellation(constant float                          *edgeFactors    [[ buffer(0) ]],
                                 constant float                          *insideFactors  [[ buffer(1) ]],
                                 device MTLQuadTessellationFactorsHalf   *factors        [[ buffer(2) ]],
                                 uint                                    pid             [[ thread_position_in_grid ]],
                                 constant float4                         &cameraPosition [[ buffer(3) ]],
                                 constant float4x4                       &modelMatrix    [[ buffer(4) ]],
                                 constant float3                         *controlPoints  [[ buffer(5) ]],
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
        
        float cameraDistance = getCameraDistance(controlPoints[pointAIndex + index],
                                                 controlPoints[pointBIndex + index],
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
tessellation_vertex(patch_control_point<ControlPoint> controlPoints      [[ stage_in ]],
                    constant SceneConstants           &sceneConstants    [[ buffer(TFSBufferIndexSceneConstants) ]],
                    constant ModelConstants           &modelConstants    [[ buffer(TFSBufferModelConstants) ]],
                    texture2d<float>                  heightMap          [[ texture(0) ]],
                    constant Terrain                  &terrain           [[ buffer(TFSBufferIndexTerrain) ]],
                    float2                            patchCoord         [[ position_in_patch ]],
                    uint                              patchId            [[ patch_id ]]) {
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
    
    float2 xy = (position.xz + terrain.size / 2.0) / terrain.size;
    
    constexpr sampler sample;
    float4 color = heightMap.sample(sample, xy);
    float height = (color.r * 2 - 1) * terrain.height;
    position.y = height;
    
    float4x4 mvp = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * modelConstants.modelMatrix ;
    position = mvp * position;
    
    TessellationVertexOut out {
        .position = position,
        .color = float4(color.r)
    };
    
    return out;
}

fragment float4
tessellation_fragment(TessellationVertexOut in [[ stage_in ]]) {
    return in.color;
}
