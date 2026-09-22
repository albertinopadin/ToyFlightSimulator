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

// Kept as reference for the future - the idea is to add materials and multiple directional lights:
fragment float4
og_tiled_deferred_directional_light_fragment(         FullScreenVertexOut  in         [[ stage_in ]],
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


// Sun pass for the three tiled renderers. Shading inputs come from the G-buffer (albedo, lit
// fraction in albedo.a, world-space normal and position) and the camera position bound with
// SceneConstants.
//
// The MaterialProperties parameter is NOT a per-pixel material. This full-screen triangle is
// encoded in the same render encoder right after the G-buffer stage, so the bytes at
// TFSBufferIndexMaterial are whatever DrawManager.drawSubmeshes bound LAST for the opaque draw
// order: every tiled pixel shares that one submesh's strength and exponent, and which submesh
// it is depends on model registration order (an F-16 material gives 1.0 / 16, a setColor object
// 0.25 / 32). The tiled G-buffer stores no strength or exponent (normal.w is written as 1.0 and
// never read). Two ways to make this explicit, from the shading doc's Step 2: bind a known
// MaterialProperties for this stage in each tiled renderer's encodeDirectionalLightStage, or
// write material.specular.r into normal.w in the G-buffer pass and read it here (per-material
// strength, still a shared exponent).
fragment float4
tiled_deferred_directional_light_fragment(
                                          FullScreenVertexOut  in               [[ stage_in ]],
                                 constant MaterialProperties   &material        [[ buffer(TFSBufferIndexMaterial) ]],
                                 constant LightData            &lightData       [[ buffer(TFSBufferDirectionalLightData) ]],
                                 constant SceneConstants       &sceneConstants  [[ buffer(TFSBufferIndexSceneConstants) ]],
                                          GBufferOut           gBuffer) {
    float3 albedo = gBuffer.albedo.rgb;
    float litFraction = gBuffer.albedo.a;
    float3 normal = normalize(gBuffer.normal.xyz);
    float3 worldPosition = gBuffer.position.xyz;
    float3 toLight = lightData.direction;
    float3 toCamera = normalize(sceneConstants.cameraPosition - worldPosition);
    float3 color = Lighting::ShadeDirectionalBlinnPhong(albedo,
                                                        normal,
                                                        toLight,
                                                        toCamera,
                                                        lightData,
                                                        material.specular.r,
                                                        material.shininess,
                                                        litFraction);
    return float4(color, 1);
}
