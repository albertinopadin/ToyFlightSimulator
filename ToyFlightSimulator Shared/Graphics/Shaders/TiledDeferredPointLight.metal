//
//  TiledDeferredPointLight.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/3/24.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"

// TODO: Move to lighting file:
float3 calculatePointLighting(LightData light, float3 fragmentWorldPosition, float3 normal, ShaderMaterial material) {
    float d = distance(light.position, fragmentWorldPosition);
    float3 lightDirection = normalize(light.position - fragmentWorldPosition);
    
    float attenuation = 1.0 / (light.attenuation.x + light.attenuation.y * d + light.attenuation.z * d * d);
    float diffuseIntensity = saturate(dot(normal, lightDirection));
    float3 color = light.color * material.color.xyz * diffuseIntensity;
    color *= attenuation;
    if (color.r + color.g + color.b < 0.01) {
        color = 0;
    }
    return color;
}

struct PointLightIn {
    float4 position [[ attribute(TFSVertexAttributePosition) ]];
};

struct PointLightOut {
    float4 position [[ position ]];
    uint instanceId [[ flat ]];
};

vertex PointLightOut
tiled_deferred_point_light_vertex(         PointLightIn   in              [[ stage_in ]],
                                  constant SceneConstants &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
                                  constant ModelConstants &modelConstants [[ buffer(TFSBufferModelConstants) ]],
                                  constant LightData      *lightDatas     [[ buffer(TFSBufferPointLightsData) ]],
                                           uint           instanceId      [[ instance_id ]])
{
    float4 lightPosition = float4(lightDatas[instanceId].position, 0);
    float4 position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * (in.position + lightPosition);
    PointLightOut out {
        .position = position,
        .instanceId = instanceId
    };
    return out;
}

fragment float4 
tiled_deferred_point_light_fragment(         PointLightOut  in              [[ stage_in ]],
                                    constant SceneConstants &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
                                    constant ModelConstants &modelConstants [[ buffer(TFSBufferModelConstants) ]],
                                    constant LightData      *lightDatas     [[ buffer(TFSBufferPointLightsData) ]],
                                             GBufferOut     gBuffer)
{
    float3 normal = gBuffer.normal.xyz;
    float3 worldPosition = gBuffer.position.xyz;
    
    ShaderMaterial material {
        .color = 1
    };
    
    LightData light = lightDatas[in.instanceId];
    float3 color = calculatePointLighting(light, worldPosition, normal, material);
    color *= 0.9;
    return float4(color, 1);
}
