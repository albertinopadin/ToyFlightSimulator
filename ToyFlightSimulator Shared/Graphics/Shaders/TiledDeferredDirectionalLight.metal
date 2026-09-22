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
    float3 normal = gBuffer.normalSpecular.xyz;
    
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


// Sun pass for the three tiled renderers. Every shading input is per pixel and comes from the
// G-buffer: albedo with the lit fraction in .a, the world-space normal with the material's
// specular strength in normalSpecular.a, the world-space position with the material's exponent
// in positionShininess.w (both rgba16Float, so the exponent is exact for integers up to 2048 and
// overflows to +inf above 65,504), plus the camera position from SceneConstants.
//
// No material buffer is bound for this stage, on purpose: this full-screen triangle shares the
// G-buffer stage's encoder, so a MaterialProperties parameter here would read whatever
// DrawManager.drawSubmeshes bound LAST, and that draw order comes from iterating a Swift
// Dictionary (SceneManager.modelDatas), which changes from launch to launch.
fragment float4
tiled_deferred_directional_light_fragment(FullScreenVertexOut  in               [[ stage_in ]],
                                 constant LightData            &lightData       [[ buffer(TFSBufferDirectionalLightData) ]],
                                 constant SceneConstants       &sceneConstants  [[ buffer(TFSBufferIndexSceneConstants) ]],
                                          GBufferOut           gBuffer) {
    float3 albedo = gBuffer.albedo.rgb;
    float litFraction = gBuffer.albedo.a;
    float specular = gBuffer.normalSpecular.a;
    float shininess = gBuffer.positionShininess.w;
    float3 normal = normalize(gBuffer.normalSpecular.xyz);
    float3 worldPosition = gBuffer.positionShininess.xyz;
    float3 toLight = lightData.direction;
    float3 toCamera = normalize(sceneConstants.cameraPosition - worldPosition);
    float3 color = Lighting::ShadeDirectionalBlinnPhong(albedo,
                                                        normal,
                                                        toLight,
                                                        toCamera,
                                                        lightData,
                                                        specular,
                                                        shininess,
                                                        litFraction);
    return float4(color, 1);
}
