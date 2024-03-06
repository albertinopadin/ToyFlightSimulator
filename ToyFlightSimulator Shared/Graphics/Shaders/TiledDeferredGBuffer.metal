//
//  TiledDeferredGBuffer.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/2/24.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"

// TODO: Extract into lighting file:
float calculateShadow(float4 shadowPosition, depth2d<float> shadowTexture) {
    // shadow calculation
    float3 position = shadowPosition.xyz / shadowPosition.w;
    float2 xy = position.xy;
    xy = xy * 0.5 + 0.5;
    xy.y = 1 - xy.y;
    constexpr sampler s(coord::normalized, 
                        filter::nearest,
                        address::clamp_to_edge,
                        compare_func:: less);
    float shadow_sample = shadowTexture.sample(s, xy);
    return (position.z > shadow_sample + 0.001) ? 0.5 : 1;
}

vertex VertexOut 
tiled_deferred_gbuffer_vertex(VertexIn                in              [[ stage_in ]],
                              constant SceneConstants &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
                              constant ModelConstants &modelConstants [[ buffer(TFSBufferModelConstants) ]],
                              constant LightData      &lightData      [[ buffer(TFSBufferDirectionalLightData) ]]) {
    float4 worldPosition = modelConstants.modelMatrix * float4(in.position, 1);
    float4 position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * worldPosition;
    
    VertexOut out {
        .position = position,
        .normal = in.normal,
        .uv = in.textureCoordinate,
        .worldPosition = worldPosition.xyz / worldPosition.w,
        .worldNormal = modelConstants.normalMatrix * in.normal,
        .worldTangent = modelConstants.normalMatrix * in.tangent,
        .worldBitangent = modelConstants.normalMatrix * in.bitangent,
        .shadowPosition = lightData.shadowViewProjectionMatrix * worldPosition
    };
    return out;
}

fragment GBufferOut 
tiled_deferred_gbuffer_fragment(VertexOut               in                  [[ stage_in ]],
                                constant ShaderMaterial &material           [[ buffer(TFSBufferIndexMaterial) ]],
                                sampler                 sampler2d           [[ sampler(0) ]],
                                texture2d<half>         baseColorTexture    [[ texture(TFSTextureIndexBaseColor) ]],
                                texture2d<half>         normalTexture       [[ texture(TFSTextureIndexNormal) ]],
                                depth2d<float>          shadowTexture       [[ texture(TFSTextureIndexShadow) ]]) {
    float4 color = material.color;
    
    if (material.useBaseTexture) {
        color = float4(baseColorTexture.sample(sampler2d, in.uv));
    }
    
    color.a = calculateShadow(in.shadowPosition, shadowTexture);
    
    float4 normal = float4(normalize(in.worldNormal), 1.0);
    
    if (material.useNormalMapTexture) {
        normal = float4(normalTexture.sample(sampler2d, in.uv));
    }
    
    GBufferOut out {
        .albedo = color,
        .normal = normal,
        .position = float4(in.worldPosition, 1.0)
    };
    return out;
}

