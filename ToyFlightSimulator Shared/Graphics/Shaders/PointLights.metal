//
//  PointLights.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/27/23.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"

typedef struct {
    float4 position [[ position ]];
} LightMaskOut;

vertex LightMaskOut
light_mask_vertex(const device float4         * vertices        [[ buffer(TFSBufferIndexMeshPositions) ]],
                  const device LightData      * light_data      [[ buffer(TFSBufferPointLightsData) ]],
                  constant SceneConstants     & sceneConstants  [[ buffer(TFSBufferIndexSceneConstants) ]],
                  uint                          iid             [[ instance_id ]],
                  uint                          vid             [[ vertex_id ]]) {
    float4 modelPosition = vertices[vid];
    float4 worldPosition = light_data[iid].modelMatrix * modelPosition;
    float4 eyePosition = sceneConstants.viewMatrix * worldPosition;
    
    LightMaskOut out = {
        .position = sceneConstants.projectionMatrix * eyePosition
    };
    
    return out;
}


typedef struct {
    float4 position [[ position ]];
    float3 eye_position;
    uint   iid [[ flat ]];
} LightInOut;


vertex LightInOut
deferred_point_lighting_vertex(const device float4          *vertices        [[ buffer(TFSBufferIndexMeshPositions) ]],
                               const device LightData       *light_data      [[ buffer(TFSBufferPointLightsData) ]],
                               constant SceneConstants      &sceneConstants  [[ buffer(TFSBufferIndexSceneConstants) ]],
                               uint                          iid             [[ instance_id ]],
                               uint                          vid             [[ vertex_id ]]) {
    float4 modelPosition = vertices[vid];
    float4 worldPosition = light_data[iid].modelMatrix * modelPosition;
    float4 eyePosition = sceneConstants.viewMatrix * worldPosition;
    
    LightInOut out = {
        .position = sceneConstants.projectionMatrix * eyePosition,
        .eye_position = eyePosition.xyz,
        .iid = iid
    };

    return out;
}

half4
deferred_point_lighting_fragment_common(LightInOut               in,
                                        const device LightData  *light_data,
                                        half4                    lighting,
                                        float                    depth,
                                        half4                    normal_shadow,
                                        half4                    albedo_specular)
{
    // Used eye_space depth to determine the position of the fragment in eye_space
    float3 eye_space_fragment_pos = in.eye_position * (depth / in.eye_position.z);

    float3 light_eye_position = light_data[in.iid].position;
    float light_distance = length(light_eye_position - eye_space_fragment_pos);
    float light_radius = light_data[in.iid].radius;

    if (light_distance < light_radius)
    {
        float4 eye_space_light_pos = float4(light_eye_position, 1);

        float3 eye_space_fragment_to_light = eye_space_light_pos.xyz - eye_space_fragment_pos;

        float3 light_direction = normalize(eye_space_fragment_to_light);

        half3 light_color = half3(light_data[in.iid].color);

        // Diffuse contribution
        half4 diffuse_contribution = half4(float4(albedo_specular) * max(dot(float3(normal_shadow.xyz), light_direction), 0.0f)) * half4(light_color, 1);

        // Specular Contribution
        float3 halfway_vector = normalize(eye_space_fragment_to_light - eye_space_fragment_pos);

//        half specular_intensity = half(frameData.fairy_specular_intensity);
//        half specular_shininess = normal_shadow.w * half(frameData.shininess_factor);
        
        // Hardcoding for now:
        half specular_intensity = half(32.0f);
        half specular_shininess = normal_shadow.w * half(1.0f);

        half specular_factor = powr(max(dot(half3(normal_shadow.xyz),half3(halfway_vector)), 0.0h), specular_intensity);

        half3 specular_contribution = specular_factor * half3(albedo_specular.xyz) * specular_shininess * light_color;

        // Light falloff
        float attenuation = 1.0 - (light_distance / light_radius);
        attenuation *= attenuation;

//        lighting += (diffuse_contribution + half4(specular_contribution, 0)) * attenuation;
        lighting += (diffuse_contribution + half4(specular_contribution, 1)) * attenuation;
    }

    return lighting;
//    return half4(float4(light_data[in.iid].color, 0.5));
//    return half4(1.0, 0.0, 0.0, 1.0);
}

fragment AccumLightBuffer
deferred_point_lighting_fragment(LightInOut                in           [[ stage_in ]],
                                 const device LightData   *light_data   [[ buffer(TFSBufferPointLightsData) ]],
                                 GBufferData               GBuffer) {
    half4 lighting = deferred_point_lighting_fragment_common(in,
                                                             light_data,
                                                             GBuffer.lighting,
                                                             GBuffer.depth,
                                                             GBuffer.normal_shadow,
                                                             GBuffer.albedo_specular);
    
    AccumLightBuffer output = {
//        .lighting = half4(1.0, 0.0, 0.0, 1.0)
        .lighting = lighting
    };
    
    return output;
}


// For testing:
vertex LightInOut icosahedron_vertex(const device float4          *vertices        [[ buffer(TFSBufferIndexMeshPositions) ]],
                                     constant ModelConstants      &modelConstants  [[ buffer(TFSBufferModelConstants) ]],
                                     constant SceneConstants      &sceneConstants  [[ buffer(TFSBufferIndexSceneConstants) ]],
                                     uint                          vid             [[ vertex_id ]]) {
    float4 modelPosition = vertices[vid];
    float4 worldPosition = modelConstants.modelMatrix * modelPosition;
    float4 eyePosition = sceneConstants.viewMatrix * worldPosition;
    
    LightInOut out = {
        .position = sceneConstants.projectionMatrix * eyePosition,
        .eye_position = eyePosition.xyz
    };
    
    return out;
}

fragment AccumLightBuffer
icosahedron_fragment(           LightInOut              in               [[ stage_in ]],
                     constant   ModelConstants          &modelConstants  [[ buffer(TFSBufferModelConstants) ]],
                     constant   MaterialProperties      &material        [[ buffer(TFSBufferIndexObjectMaterial) ]],
                                GBufferData             GBuffer) {
    AccumLightBuffer output = {
        .lighting = half4(material.color)
    };
    
    return output;
}
