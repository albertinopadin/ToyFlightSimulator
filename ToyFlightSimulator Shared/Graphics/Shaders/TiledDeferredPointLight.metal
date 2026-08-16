//
//  TiledDeferredPointLight.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/3/24.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"
#import "Lighting.metal"

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
    // Volume sizing (radius / mesh inscribed radius) is baked into the light's modelMatrix
    // CPU-side (LightObject.setLightRadius) — the same contract as the single-pass volume
    // vertices in PointLights.metal.
    float4 world = lightDatas[instanceId].modelMatrix * float4(in.position.xyz, 1);
    float4 position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * world;

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
    
    // CalculatePointLighting reads only material.color; feeding it the G-buffer
    // albedo tints the light's contribution by the surface it hits.
    MaterialProperties material {
        .color = gBuffer.albedo
    };

    float3 color = Lighting::CalculatePointLighting(lightDatas[in.instanceId], worldPosition, normal, material);
    return float4(color, 1);
}
