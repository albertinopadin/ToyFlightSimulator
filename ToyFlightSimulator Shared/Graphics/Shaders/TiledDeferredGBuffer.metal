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

vertex VertexOut 
tiled_deferred_gbuffer_vertex(VertexIn                in              [[ stage_in ]],
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

