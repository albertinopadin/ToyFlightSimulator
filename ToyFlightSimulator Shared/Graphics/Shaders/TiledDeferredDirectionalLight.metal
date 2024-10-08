//
//  TiledDeferredDirectionalLight.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/3/24.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"
#import "Lighting.metal"

constant float3 vertices[6] = {
    float3(-1,  1,  0),    // triangle 1
    float3( 1, -1,  0),
    float3(-1, -1,  0),
    float3(-1,  1,  0),    // triangle 2
    float3( 1,  1,  0),
    float3( 1, -1,  0)
};

struct VertexQuadOut {
    float4 position [[ position ]];
};

vertex VertexQuadOut tiled_deferred_vertex_quad(uint vertexId [[ vertex_id ]]) {
    VertexQuadOut out {
        .position = float4(vertices[vertexId], 1)
    };
    return out;
}

fragment float4
tiled_deferred_directional_light_fragment(         VertexQuadOut  in         [[ stage_in ]],
                                          constant LightData      &lightData [[ buffer(TFSBufferDirectionalLightData) ]],
                                                   GBufferOut     gBuffer) {
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
