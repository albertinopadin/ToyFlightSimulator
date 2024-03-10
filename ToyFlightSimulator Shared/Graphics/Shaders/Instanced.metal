//
//  Instanced.metal
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/25/22.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"

vertex RasterizerData instanced_vertex(const VertexIn vIn [[ stage_in ]],
                                       constant SceneConstants &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
                                       constant ModelConstants *modelConstants [[ buffer(TFSBufferModelConstants) ]],
                                       uint instanceId [[ instance_id ]]) {
    ModelConstants modelConstant = modelConstants[instanceId];
    float4 worldPosition = modelConstant.modelMatrix * float4(vIn.position, 1);
    
    RasterizerData rd = {
        // Order of matrix multiplication is important here:
        .position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * worldPosition,
        .color = vIn.color,
        .textureCoordinate = vIn.textureCoordinate,
        .totalGameTime = sceneConstants.totalGameTime,
        .worldPosition = worldPosition.xyz,
        .toCameraVector = sceneConstants.cameraPosition - worldPosition.xyz,
        .surfaceNormal = normalize(modelConstant.modelMatrix * float4(vIn.normal, 1.0)).xyz,
        .surfaceTangent = normalize(modelConstant.modelMatrix * float4(vIn.tangent, 1.0)).xyz,
        .surfaceBitangent = normalize(modelConstant.modelMatrix * float4(vIn.bitangent, 1.0)).xyz
    };
    
    return rd;
}
