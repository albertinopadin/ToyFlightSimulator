//
//  DirectionalLight.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/27/23.
//

#include <metal_stdlib>
using namespace metal;

// Include header shared between this Metal shader code and C code executing Metal API commands
#include "TFSShaderTypes.h"

// Include header shared between all Metal shader code files
#include "TFSShaderCommon.h"

#include "Shared.metal"

struct QuadInOut
{
    float4 position [[position]];
    float3 eye_position;
};

vertex QuadInOut
deferred_directional_lighting_vertex(constant TFSSimpleVertex * vertices       [[ buffer(TFSBufferIndexMeshPositions) ]],
                                     constant SceneConstants  & sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
                                     uint                       vid            [[ vertex_id ]])
{
    QuadInOut out;
    out.position = float4(vertices[vid].position, 0, 1);
    float4 unprojected_eye_coord = sceneConstants.projectionMatrixInverse * out.position;
    out.eye_position = unprojected_eye_coord.xyz / unprojected_eye_coord.w;
    return out;
}

// Only Version 2.3 of the macOS Metal shading language, where Apple Silicon was introduced,
// and the iOS version of the shading language can use the GBufferData structure an an input.
fragment AccumLightBuffer
deferred_directional_lighting_fragment(QuadInOut            in        [[ stage_in ]],
                                       constant LightData & lightData [[ buffer(TFSBufferDirectionalLightData) ]],
                                       GBufferData          GBuffer)
{
    float depth = GBuffer.depth;
    half4 normal_shadow = GBuffer.normal_shadow;
    half4 albedo_specular = GBuffer.albedo_specular;
    
    half sun_diffuse_intensity = dot(normal_shadow.xyz, half3(lightData.eyeDirection.xyz));

    sun_diffuse_intensity = max(sun_diffuse_intensity, 0.h);

    half3 sun_color = half3(lightData.color.xyz);

    half3 diffuse_contribution = albedo_specular.xyz * sun_diffuse_intensity * sun_color;

    // Calculate specular contribution from directional light
    
    // Used eye_space depth to determine the position of the fragment in eye_space
    float3 eye_space_fragment_pos = normalize(in.eye_position) * depth;

    float4 eye_light_direction = lightData.eyeDirection;

    // Specular Contribution
    float3 halfway_vector = normalize(eye_space_fragment_pos - eye_light_direction.xyz);

    half specular_intensity = half(lightData.specularIntensity);
    
    half shininess = half(1.0);
    
    half specular_shininess = albedo_specular.w * shininess;

    half specular_factor = powr(max(dot(half3(normal_shadow.xyz), half3(halfway_vector)), 0.0h), specular_intensity);

    half3 specular_contribution = specular_factor * half3(albedo_specular.xyz) * specular_shininess * sun_color;

    half3 color = diffuse_contribution + specular_contribution;

    // Shadow Contribution
    half shadowSample = normal_shadow.w;

    // Lighten the shadow to account for some ambience
    shadowSample += .1h;

    // Account for values greater than 1.0 (after lightening shadow)
    shadowSample = saturate(shadowSample);

    color *= shadowSample;
    
    AccumLightBuffer output;
    output.lighting = half4(color, 1);
    return output;
}
