//
//  TiledDeferredGBuffer.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/2/24.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"
#import "Lighting.metal"

//constant bool hasSkeleton [[ function_constant(0) ]];

vertex VertexOut
tiled_deferred_gbuffer_vertex(
           VertexIn       in              [[ stage_in ]],
  constant SceneConstants &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
  constant ModelConstants *modelConstants [[ buffer(TFSBufferModelConstants) ]],
  constant LightData      &lightData      [[ buffer(TFSBufferDirectionalLightData) ]],
           uint           instanceId      [[ instance_id ]]) {
    ModelConstants modelInstance = modelConstants[instanceId];
    float4 worldPosition = modelInstance.modelMatrix * float4(in.position, 1);
    float4 position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * worldPosition;
    
    VertexOut out {
        .position = position,
        .normal = in.normal,
        .uv = in.textureCoordinate,
        .worldPosition = worldPosition.xyz / worldPosition.w,
        .worldNormal = modelInstance.normalMatrix * in.normal,
        .worldTangent = modelInstance.normalMatrix * in.tangent,
        .worldBitangent = modelInstance.normalMatrix * in.bitangent,
        .shadowPosition = lightData.shadowViewProjectionMatrix * worldPosition,
        .instanceId = instanceId,
        .objectColor = modelInstance.objectColor,
        .useObjectColor = modelInstance.useObjectColor
    };
    return out;
}

vertex VertexOut 
tiled_deferred_gbuffer_animated_vertex(
           VertexIn       in              [[ stage_in ]],
  constant SceneConstants &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
  constant ModelConstants *modelConstants [[ buffer(TFSBufferModelConstants) ]],
  constant LightData      &lightData      [[ buffer(TFSBufferDirectionalLightData) ]],
  constant float4x4       *jointMatrices  [[ buffer(TFSBufferIndexJointBuffer) ]],
           uint           instanceId      [[ instance_id ]]) {
    ModelConstants modelInstance = modelConstants[instanceId];
    float4 worldPosition = modelInstance.modelMatrix * float4(in.position, 1);
    float4 position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * worldPosition;
    float4 normal = float4(in.normal, 0);
    
    // Hope this works, ugh...
    if (jointMatrices != nullptr) {
        float4 weights = in.jointWeights;
        ushort4 joints = in.joints;
        
        position = weights.x * (jointMatrices[joints.x] * position) +
                weights.y * (jointMatrices[joints.y] * position) +
                weights.z * (jointMatrices[joints.z] * position) +
                weights.w * (jointMatrices[joints.w] * position);
        
        normal = weights.x * (jointMatrices[joints.x] * normal) +
                weights.y * (jointMatrices[joints.y] * normal) +
                weights.z * (jointMatrices[joints.z] * normal) +
                weights.w * (jointMatrices[joints.w] * normal);
    }
    
    VertexOut out {
        .position = position,
        .normal = normal.xyz,
        .uv = in.textureCoordinate,
        .worldPosition = worldPosition.xyz / worldPosition.w,
        .worldNormal = modelInstance.normalMatrix * in.normal,
        .worldTangent = modelInstance.normalMatrix * in.tangent,
        .worldBitangent = modelInstance.normalMatrix * in.bitangent,
        .shadowPosition = lightData.shadowViewProjectionMatrix * worldPosition,
        .instanceId = instanceId,
        .objectColor = modelInstance.objectColor,
        .useObjectColor = modelInstance.useObjectColor
    };
    return out;
}

fragment GBufferOut 
tiled_deferred_gbuffer_fragment(VertexOut                   in                  [[ stage_in ]],
                                constant MaterialProperties &material           [[ buffer(TFSBufferIndexMaterial) ]],
                                sampler                     sampler2d           [[ sampler(0) ]],
                                texture2d<half>             baseColorTexture    [[ texture(TFSTextureIndexBaseColor) ]],
                                texture2d<half>             normalTexture       [[ texture(TFSTextureIndexNormal) ]],
                                depth2d<float>              shadowTexture       [[ texture(TFSTextureIndexShadow) ]]) {
    float4 color;
    
    if (in.useObjectColor) {
        color = in.objectColor;
    } else if (!is_null_texture(baseColorTexture)) {
        color = float4(baseColorTexture.sample(sampler2d, in.uv));
    }
    
    color.a = Lighting::CalculateShadow(in.shadowPosition, shadowTexture);
    
    float4 normal = float4(normalize(in.worldNormal), 1.0);
    
    if (!in.useObjectColor && !is_null_texture(normalTexture)) {
        normal = float4(normalTexture.sample(sampler2d, in.uv));
    }
    
    GBufferOut out {
        .albedo = color,
        .normal = normal,
        .position = float4(in.worldPosition, 1.0)
    };
    return out;
}
