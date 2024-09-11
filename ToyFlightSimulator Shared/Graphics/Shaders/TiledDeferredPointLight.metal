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
    
    MaterialProperties material {
        .color = 1
    };
    
    LightData light = lightDatas[in.instanceId];
    float3 color = Lighting::CalculatePointLighting(light, worldPosition, normal, material);
    color *= 0.9;
    return float4(color, 1);
}
