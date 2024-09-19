//
//  SinglePassDeferredTransparency.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/15/24.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"

vertex VertexOut
single_pass_deferred_transparency_vertex(   VertexIn       in              [[ stage_in ]],
                                   constant SceneConstants &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
                                   constant ModelConstants *modelConstants [[ buffer(TFSBufferModelConstants) ]],
                                   constant LightData      &lightData      [[ buffer(TFSBufferDirectionalLightData) ]],
                                   uint                    instanceId      [[ instance_id ]]) {
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
        .shadowPosition = lightData.shadowViewProjectionMatrix * worldPosition
    };
    return out;
}

fragment float4
single_pass_deferred_transparency_fragment(   VertexOut          in                  [[ stage_in ]],
                                     constant MaterialProperties &material           [[ buffer(TFSBufferIndexMaterial) ]],
                                     sampler                     sampler2d           [[ sampler(0) ]],
                                     texture2d<half>             baseColorTexture    [[ texture(TFSTextureIndexBaseColor) ]]) {
    float4 color = material.color;
    
    if (!material.useMaterialColor && !is_null_texture(baseColorTexture)) {
        color = float4(baseColorTexture.sample(sampler2d, in.uv));
    }
    
    color.a = material.opacity;
    return color;
}
