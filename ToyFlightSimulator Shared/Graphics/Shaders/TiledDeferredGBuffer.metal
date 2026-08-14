//
//  TiledDeferredGBuffer.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/2/24.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"
#import "ShaderHelpers.h"
#import "Lighting.metal"

//constant bool hasSkeleton [[ function_constant(0) ]];

vertex VertexOut
tiled_deferred_gbuffer_vertex(
           VertexIn       in              [[ stage_in ]],
  constant SceneConstants &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
  constant ModelConstants *modelConstants [[ buffer(TFSBufferModelConstants) ]],
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
                  constant float4x4       *jointMatrices  [[ buffer(TFSBufferIndexJointBuffer) ]],
                           uint           instanceId      [[ instance_id ]]) {
    ModelConstants modelInstance = modelConstants[instanceId];
    float4 position = float4(in.position, 1);
    float4 normal = float4(in.normal, 0);
    
    float4x4 skinMatrix = BlendJointMatrix(jointMatrices, in.joints, in.jointWeights);
    position = skinMatrix * position;
    normal = skinMatrix * normal;
    float3 skinnedTangent = (skinMatrix * float4(in.tangent, 0)).xyz;
    float3 skinnedBitangent = (skinMatrix * float4(in.bitangent, 0)).xyz;
    
    float4 worldPosition = modelInstance.modelMatrix * position;

    VertexOut out {
        .position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * worldPosition,
        .normal = normal.xyz,
        .uv = in.textureCoordinate,
        .worldPosition = worldPosition.xyz / worldPosition.w,
        .worldNormal = modelInstance.normalMatrix * normal.xyz,
        .worldTangent = modelInstance.normalMatrix * skinnedTangent,
        .worldBitangent = modelInstance.normalMatrix * skinnedBitangent,
        .instanceId = instanceId,
        .objectColor = modelInstance.objectColor,
        .useObjectColor = modelInstance.useObjectColor
    };
    return out;
}

fragment GBufferOut
tiled_deferred_gbuffer_fragment(
            VertexOut                          in                  [[ stage_in ]],
            constant SceneConstants            &sceneConstants     [[ buffer(TFSBufferIndexSceneConstants) ]],
            constant MaterialProperties        &material           [[ buffer(TFSBufferIndexMaterial) ]],
            constant MaterialTextureTransforms &uvXforms           [[ buffer(TFSBufferIndexMaterialTextureTransforms) ]],
            constant LightData                 &lightData          [[ buffer(TFSBufferDirectionalLightData) ]],
            sampler                            sampler2d           [[ sampler(0) ]],
            texture2d<half>                    baseColorTexture    [[ texture(TFSTextureIndexBaseColor) ]],
            texture2d<half>                    normalTexture       [[ texture(TFSTextureIndexNormal) ]],
            depth2d_array<float>               shadowArray         [[ texture(TFSTextureIndexShadow) ]]) {
    float2 baseUV   = in.uv;
    float2 normalUV = in.uv;
    if (uvXforms.hasTextureTransforms) {
        baseUV   = ApplyUVTransform(in.uv, uvXforms.baseColorUVTransform);
        normalUV = ApplyUVTransform(in.uv, uvXforms.normalUVTransform);
    }
    
    float4 color = ResolveBaseColor(in.useObjectColor,
                                    in.objectColor,
                                    material.color,
                                    baseColorTexture,
                                    sampler2d,
                                    baseUV);

    // Per-fragment view-space depth from the perspective-correctly interpolated
    // worldPosition. worldPos - cameraPos is Sterbenz-exact in float32 for
    // visible fragments, avoiding the precision collapse of writing it per-vertex.
    float fragViewSpaceDepth = distance(in.worldPosition, sceneConstants.cameraPosition);
    color.a = Lighting::CalculateShadow(in.worldPosition,
                                        fragViewSpaceDepth,
                                        in.worldNormal,
                                        lightData,
                                        shadowArray);

    float4 normal = float4(normalize(in.worldNormal), 1.0);

    if (!in.useObjectColor && !is_null_texture(normalTexture)) {
        normal = float4(normalTexture.sample(sampler2d, normalUV));
    }
    
    GBufferOut out {
        .albedo = color,
        .normal = normal,
        .position = float4(in.worldPosition, 1.0)
    };
    return out;
}
