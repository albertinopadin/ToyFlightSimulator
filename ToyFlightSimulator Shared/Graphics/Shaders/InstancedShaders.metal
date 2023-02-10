//
//  InstancedShaders.metal
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/25/22.
//

#include <metal_stdlib>
#include "Shared.metal"
#include "TFSShaderTypes.h"

using namespace metal;

vertex RasterizerData instanced_vertex(const VertexIn vIn [[ stage_in ]],
                                       constant SceneConstants &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
                                       constant ModelConstants *modelConstants [[ buffer(TFSBufferModelConstants) ]],
                                       uint instanceId [[ instance_id ]]) {
    RasterizerData rd;
    ModelConstants modelConstant = modelConstants[instanceId];
    // Order of matrix multiplication is important here:
//    rd.position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * modelConstant.modelMatrix *
//                  float4(vIn.position, 1);
    
    float4 worldPosition = modelConstant.modelMatrix * float4(vIn.position, 1);
    // Order of matrix multiplication is important here:
    rd.position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * worldPosition;
    rd.color = vIn.color;
    rd.textureCoordinate = vIn.textureCoordinate;
    rd.totalGameTime = sceneConstants.totalGameTime;
    rd.worldPosition = worldPosition.xyz;
    rd.toCameraVector = sceneConstants.cameraPosition - worldPosition.xyz;

    rd.surfaceNormal = normalize(modelConstant.modelMatrix * float4(vIn.normal, 0.0)).xyz;
    rd.surfaceTangent = normalize(modelConstant.modelMatrix * float4(vIn.tangent, 0.0)).xyz;
    rd.surfaceBitangent = normalize(modelConstant.modelMatrix * float4(vIn.bitangent, 0.0)).xyz;
    return rd;
}
