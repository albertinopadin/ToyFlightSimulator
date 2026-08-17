//
//  SinglePassDeferredTransparency.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/15/24.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"
#import "ShaderHelpers.h"

vertex VertexOut
single_pass_deferred_transparency_vertex(   VertexIn       in              [[ stage_in ]],
                                   constant SceneConstants &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
                                   constant ModelConstants *modelConstants [[ buffer(TFSBufferModelConstants) ]],
                                   uint                    instanceId      [[ instance_id ]]) {
    ModelConstants modelInstance = modelConstants[instanceId];
    float4 worldPosition = modelInstance.modelMatrix * float4(in.position, 1);
    float4 position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * worldPosition;

    VertexOut out {
        .position = position,
        .normal = in.normal,
        .uv = in.textureCoordinate,
        .worldPosition = worldPosition.xyz,
        .worldNormal = modelInstance.normalMatrix * in.normal,
        .worldTangent = modelInstance.normalMatrix * in.tangent,
        .worldBitangent = modelInstance.normalMatrix * in.bitangent,
        .instanceId = instanceId,
        .objectColor = modelInstance.objectColor,
        .useObjectColor = modelInstance.useObjectColor
    };
    return out;
}

vertex VertexOut
single_pass_deferred_transparency_animated_vertex(
                                         VertexIn       in              [[ stage_in ]],
                                constant SceneConstants &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
                                constant ModelConstants *modelConstants [[ buffer(TFSBufferModelConstants) ]],
                                constant float4x4       *jointMatrices  [[ buffer(TFSBufferIndexJointBuffer) ]],
                                uint                    instanceId      [[ instance_id ]]) {
    ModelConstants modelInstance = modelConstants[instanceId];
    float4 modelPosition = float4(in.position, 1);
    float4 normal = float4(in.normal, 0);

    float4x4 skinMatrix = BlendJointMatrix(jointMatrices, in.joints, in.jointWeights);
    modelPosition = skinMatrix * modelPosition;
    normal = skinMatrix * normal;
    float3 skinnedTangent = (skinMatrix * float4(in.tangent, 0)).xyz;
    float3 skinnedBitangent = (skinMatrix * float4(in.bitangent, 0)).xyz;

    float4 worldPosition = modelInstance.modelMatrix * modelPosition;

    VertexOut out {
        .position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * worldPosition,
        .normal = normal.xyz,
        .uv = in.textureCoordinate,
        .worldPosition = worldPosition.xyz,
        .worldNormal = modelInstance.normalMatrix * normal.xyz,
        .worldTangent = modelInstance.normalMatrix * skinnedTangent,
        .worldBitangent = modelInstance.normalMatrix * skinnedBitangent,
        .instanceId = instanceId,
        .objectColor = modelInstance.objectColor,
        .useObjectColor = modelInstance.useObjectColor
    };
    return out;
}

fragment float4
single_pass_deferred_transparency_fragment(
                 VertexOut                    in                  [[ stage_in ]],
        constant MaterialProperties           &material           [[ buffer(TFSBufferIndexMaterial) ]],
        constant MaterialTextureTransforms    &uvXforms           [[ buffer(TFSBufferIndexMaterialTextureTransforms) ]],
        sampler                               sampler2d           [[ sampler(0) ]],
        texture2d<half>                       baseColorTexture    [[ texture(TFSTextureIndexBaseColor) ]]) {
    float2 baseUV = in.uv;
    if (uvXforms.hasTextureTransforms) {
        baseUV = ApplyUVTransform(in.uv, uvXforms.baseColorUVTransform);
    }
    
    float4 color = ResolveBaseColor(in.useObjectColor,
                                    in.objectColor,
                                    material.color,
                                    baseColorTexture,
                                    sampler2d,
                                    baseUV);
    
    color.a = ResolveOpacity(color.a, material.opacity);
    
    return color;
}
