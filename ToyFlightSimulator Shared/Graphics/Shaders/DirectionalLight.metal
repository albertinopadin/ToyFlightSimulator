//
//  DirectionalLight.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/27/23.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"

struct QuadInOut
{
    float4 position [[position]];
    float3 eye_position;
};

vertex QuadInOut
deferred_directional_lighting_vertex(constant TFSSimpleVertex * vertices       [[ buffer(TFSBufferIndexMeshVertex) ]],
                                     constant SceneConstants  & sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
                                     uint                       vid            [[ vertex_id ]])
{
    float4 position = float4(vertices[vid].position, 0, 1);
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
deferred_directional_lighting_fragment(QuadInOut            in        [[ stage_in ]],
                                       constant LightData & lightData [[ buffer(TFSBufferDirectionalLightData) ]],
                                       GBufferData          GBuffer)
{
    float depth = GBuffer.depth;
    half4 normal_shadow = GBuffer.normal_shadow;
    half4 albedo_specular = GBuffer.albedo_specular;
    half3 lightDirection = half3(-lightData.position);
    half sun_diffuse_intensity = saturate(-dot(lightDirection, normal_shadow.xyz));
    half minimum_sun_diffuse_intensity = 0.4h;
    sun_diffuse_intensity = max(sun_diffuse_intensity, minimum_sun_diffuse_intensity);
    
    half3 sun_color = half3(lightData.color.xyz);

    half3 diffuse_contribution = albedo_specular.xyz * sun_diffuse_intensity * sun_color;

    // Calculate specular contribution from directional light
    
    // Used eye_space depth to determine the position of the fragment in eye_space
    float3 eye_space_fragment_pos = normalize(in.eye_position) * depth;

//    float4 eye_light_direction = lightData.eyeDirection;

    // Specular Contribution
    float3 halfway_vector = normalize(eye_space_fragment_pos - lightData.position);

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
    
    AccumLightBuffer output = {
        .lighting = half4(color, 1)
    };
    
    return output;
}
