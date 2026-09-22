//
//  DirectionalLight.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/27/23.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"
#import "ShaderHelpers.h"
#import "Lighting.metal"

struct QuadInOut
{
    float4 position [[position]];
    float3 eye_position;
};

vertex QuadInOut
deferred_directional_lighting_vertex(constant SceneConstants  & sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
                                     uint                       vid            [[ vertex_id ]])
{
    // This pass keeps its own vertex (rather than binding full_screen_vertex)
    // only to interpolate the eye ray below; the geometry is the shared
    // full-screen triangle. All vertices sit at z = 0, w = 1, so the ray
    // interpolates exactly linearly across the screen.
    float4 position = FullScreenTriangleVertex(vid).position;
    float4 unprojected_eye_coord = sceneConstants.projectionMatrixInverse * position;
    
    QuadInOut out = {
        .position = position,
        .eye_position = unprojected_eye_coord.xyz / unprojected_eye_coord.w
    };
    
    return out;
}

// Only Version 2.3 of the macOS Metal shading language, where Apple Silicon was introduced,
// and the iOS version of the shading language can use the GBufferData structure an an input.
fragment AccumLightBuffer
deferred_directional_lighting_fragment(QuadInOut            in         [[ stage_in ]],
                              constant LightData            &lightData [[ buffer(TFSBufferDirectionalLightData) ]],
                                       GBufferData          GBuffer)
{
    // Everything here is EYE space: the G-buffer stores the unit normal rotated by the
    // view matrix, LightManager rotates the sun direction with the same matrix each frame
    // (lightEyeDirection), and the camera sits at the origin. N, L and V must share one
    // frame or the dot products are meaningless (root cause 2c in the shading doc).
    float3 albedo = float3(GBuffer.albedo_specular.rgb);
    float specular = GBuffer.albedo_specular.a;
    // The rgba8Snorm normal target changes the length slightly; renormalize before use.
    float3 eyeNormal = normalize(float3(GBuffer.normal_shadow.xyz));
    // Raw PCF visibility, 0 (fully shadowed) .. 1 (unblocked), written by the G-buffer pass.
    // It scales only the direct light inside the shared function; ambient is never shadowed.
    half litFraction = GBuffer.normal_shadow.a;
    float3 eyeToLight = lightData.lightEyeDirection;
    float3 eyePosition = ReconstructEyePosition(in.eye_position, GBuffer.depth);
    float3 eyeToCamera = -normalize(eyePosition);
    // Landing-order step 2 (landed 2026-09-22): the strength is the per-pixel value GBuffer.metal
    // writes into albedo_specular.a (the specular map's red channel, else material.specular.r,
    // 0.25 by default). This G-buffer has no free channel for the exponent (normal_shadow.a is
    // the shadow, depth is a single float), so every pixel shades with DEFAULT_SHININESS, 32,
    // the MaterialProperties default; the tiled path stores the per-material exponent instead.
    // Before Step 6 the alpha was a constant 1.0, which with exponent 1 clipped every lit
    // surface to white (the table under Step 4 in the shading doc).
    float3 color = Lighting::ShadeDirectionalBlinnPhong(albedo,
                                                        eyeNormal,
                                                        eyeToLight,
                                                        eyeToCamera,
                                                        lightData,
                                                        specular,
                                                        Lighting::DEFAULT_SHININESS,
                                                        litFraction);
    
    AccumLightBuffer output = {
        .lighting = half4(half3(color), 1)
    };
    
    return output;
}
