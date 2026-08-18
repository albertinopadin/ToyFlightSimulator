//
//  TiledDeferredDirectionalLight.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/3/24.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"
#import "ShaderHelpers.h"
#import "Lighting.metal"

fragment float4
tiled_deferred_directional_light_fragment(         FullScreenVertexOut  in         [[ stage_in ]],
                                          constant LightData            &lightData [[ buffer(TFSBufferDirectionalLightData) ]],
                                                   GBufferOut           gBuffer) {
    float4 albedo = gBuffer.albedo;
    float3 normal = gBuffer.normal.xyz;
    
    MaterialProperties material;
    material.color = albedo;
    material.shininess = 0.1;   // Shininess == 1 results in all black screen
    material.ambient = 1.0;     // Should be ambient occlusion
    
    float3 color = 0;
    
    // TODO: Add to shader input:
    uint lightCount = 1;
    
    for (uint i = 0; i < lightCount; i++) {
        color += Lighting::CalculateDirectionalLighting(lightData, normal, material);
    }
    
    color *= albedo.a;
    return float4(color, 1);
}
