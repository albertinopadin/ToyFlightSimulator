//
//  PointLights.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/27/23.
//

#include <metal_stdlib>
using namespace metal;

#include "TFSShaderTypes.h"
#include "TFSShaderCommon.h"
#include "Shared.metal"

struct LightMaskOut
{
    float4 position [[ position ]];
};

//vertex LightMaskOut
//light_mask_vertex(const device float4         * vertices        [[ buffer(TFSBufferIndexMeshPositions) ]],
//                  const device TFSPointLight  * light_data      [[ buffer(TFSBufferPointLightsData) ]],
//                  const device vector_float4  * light_positions [[ buffer(TFSBufferPointLightsPosition) ]],
//                  constant SceneConstants     & sceneConstants  [[ buffer(TFSBufferIndexSceneConstants) ]],
//                  uint                          iid             [[ instance_id ]],
//                  uint                          vid             [[ vertex_id ]])
//{
//    LightMaskOut out;
//
//    // Transform light to position relative to the temple
//    float4 vertex_eye_position = float4(vertices[vid].xyz * light_data[iid].light_radius + light_positions[iid].xyz, 1);
//
//    out.position = sceneConstants.projectionMatrix * vertex_eye_position;
//
//    return out;
//}

vertex LightMaskOut
light_mask_vertex(const device float4         * vertices        [[ buffer(TFSBufferIndexMeshPositions) ]],
                  const device LightData      * light_data      [[ buffer(TFSBufferPointLightsData) ]],
                  constant SceneConstants     & sceneConstants  [[ buffer(TFSBufferIndexSceneConstants) ]],
                  uint                          iid             [[ instance_id ]],
                  uint                          vid             [[ vertex_id ]])
{
    LightMaskOut out;

    // Transform light to position relative to the scene
//    float4 vertex_eye_position = float4(vertices[vid].xyz * light_data[iid].radius + light_data[iid].position, 1);
//    float4 vertex_eye_position = light_data[iid].modelMatrix * vertices[vid] * float4(light_data[iid].radius + light_data[iid].position, 1);
//    float4 vertex_eye_position = light_data[iid].modelMatrix * vertices[vid] * light_data[iid].radius;
//    float4 vertex_eye_position = float4(light_data[iid].radius + light_data[iid].position, 1);
//    out.position = sceneConstants.projectionMatrix * vertex_eye_position;
//    float4 modelPosition = vertices[vid] * light_data[iid].radius;
    float4 modelPosition = vertices[vid];
    float4 worldPosition = light_data[iid].modelMatrix * modelPosition;
    float4 eyePosition = sceneConstants.viewMatrix * worldPosition;
    out.position = sceneConstants.projectionMatrix * eyePosition;
    return out;
}


struct LightInOut
{
    float4 position [[position]];
    float3 eye_position;
    uint   iid [[flat]];
};

//vertex LightInOut
//deferred_point_lighting_vertex(const device float4         * vertices        [[ buffer(TFSBufferIndexMeshPositions) ]],
//                               const device TFSPointLight  * light_data      [[ buffer(TFSBufferPointLightsData) ]],
//                               const device vector_float4  * light_positions [[ buffer(TFSBufferPointLightsPosition) ]],
//                               constant SceneConstants     & sceneConstants  [[ buffer(TFSBufferIndexSceneConstants) ]],
//                               uint                          iid             [[ instance_id ]],
//                               uint                          vid             [[ vertex_id ]])
//{
//    LightInOut out;
//
//    // Transform light to position relative to the temple
//    float3 vertex_eye_position = vertices[vid].xyz * light_data[iid].light_radius + light_positions[iid].xyz;
//
//    out.position = sceneConstants.projectionMatrix * float4(vertex_eye_position, 1);
//
//    // Sending light position in view space to next stage
//    out.eye_position = vertex_eye_position;
//
//    out.iid = iid;
//
//    return out;
//}

vertex LightInOut
deferred_point_lighting_vertex(const device float4         * vertices        [[ buffer(TFSBufferIndexMeshPositions) ]],
                               const device LightData      * light_data      [[ buffer(TFSBufferPointLightsData) ]],
                               constant SceneConstants     & sceneConstants  [[ buffer(TFSBufferIndexSceneConstants) ]],
                               uint                          iid             [[ instance_id ]],
                               uint                          vid             [[ vertex_id ]])
{
    LightInOut out;

    // Transform light to position relative to the scene
//    float3 vertex_eye_position = vertices[vid].xyz * light_data[iid].radius + light_data[iid].position;
//    float4 vertex_eye_position = light_data[iid].modelMatrix * vertices[vid] * float4(light_data[iid].radius + light_data[iid].position, 1);
//    float4 vertex_eye_position = light_data[iid].modelMatrix * vertices[vid] * light_data[iid].radius;
//    float3 vertex_eye_position = light_data[iid].radius + light_data[iid].position;
//    float3 vertex_eye_position = float3(0,0,0);
//    float3 vertex_eye_position = sceneConstants.cameraPosition * light_data[iid].radius + light_data[iid].position;

//    out.position = sceneConstants.projectionMatrix * float4(vertex_eye_position, 1);
//    out.position = sceneConstants.projectionMatrix * vertex_eye_position;
//    float4 modelPosition = vertices[vid] * light_data[iid].radius;
    float4 modelPosition = vertices[vid];
    float4 worldPosition = light_data[iid].modelMatrix * modelPosition;
    float4 eyePosition = sceneConstants.viewMatrix * worldPosition;
    out.position = sceneConstants.projectionMatrix * eyePosition;

    // Sending light position in view space to next stage
//    out.eye_position = vertex_eye_position;
//    out.eye_position = vertex_eye_position.xyz;
    out.eye_position = eyePosition.xyz;

    out.iid = iid;

    return out;
}

//half4
//deferred_point_lighting_fragment_common(LightInOut               in,
//                                        device TFSPointLight   * light_data,
//                                        device vector_float4   * light_positions,
////                                        constant TFSFrameData  & frameData,
//                                        half4                    lighting,
//                                        float                    depth,
//                                        half4                    normal_shadow,
//                                        half4                    albedo_specular)
//{
//    // Used eye_space depth to determine the position of the fragment in eye_space
//    float3 eye_space_fragment_pos = in.eye_position * (depth / in.eye_position.z);
//
//    float3 light_eye_position = light_positions[in.iid].xyz;
//    float light_distance = length(light_eye_position - eye_space_fragment_pos);
//    float light_radius = light_data[in.iid].light_radius;
//
//    if (light_distance < light_radius)
//    {
//        float4 eye_space_light_pos = float4(light_eye_position,1);
//
//        float3 eye_space_fragment_to_light = eye_space_light_pos.xyz - eye_space_fragment_pos;
//
//        float3 light_direction = normalize(eye_space_fragment_to_light);
//
//        half3 light_color = half3(light_data[in.iid].light_color);
//
//        // Diffuse contribution
//        half4 diffuse_contribution = half4(float4(albedo_specular)*max(dot(float3(normal_shadow.xyz), light_direction),0.0f))*half4(light_color,1);
//
//        // Specular Contribution
//        float3 halfway_vector = normalize(eye_space_fragment_to_light - eye_space_fragment_pos);
//
////        half specular_intensity = half(frameData.fairy_specular_intensity);
////        half specular_shininess = normal_shadow.w * half(frameData.shininess_factor);
//        
//        // Hardcoding for now:
//        half specular_intensity = half(32.0f);
//        half specular_shininess = normal_shadow.w * half(1.0f);
//
//        half specular_factor = powr(max(dot(half3(normal_shadow.xyz),half3(halfway_vector)),0.0h), specular_intensity);
//
//        half3 specular_contribution = specular_factor * half3(albedo_specular.xyz) * specular_shininess * light_color;
//
//        // Light falloff
//        float attenuation = 1.0 - (light_distance / light_radius);
//        attenuation *= attenuation;
//
//        lighting += (diffuse_contribution + half4(specular_contribution, 0)) * attenuation;
//    }
//
//    return lighting;
//}

half4
deferred_point_lighting_fragment_common(LightInOut               in,
                                        const device LightData * light_data,
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
        float4 eye_space_light_pos = float4(light_eye_position,1);

        float3 eye_space_fragment_to_light = eye_space_light_pos.xyz - eye_space_fragment_pos;

        float3 light_direction = normalize(eye_space_fragment_to_light);

        half3 light_color = half3(light_data[in.iid].color);

        // Diffuse contribution
        half4 diffuse_contribution = half4(float4(albedo_specular)*max(dot(float3(normal_shadow.xyz), light_direction),0.0f))*half4(light_color,1);

        // Specular Contribution
        float3 halfway_vector = normalize(eye_space_fragment_to_light - eye_space_fragment_pos);

//        half specular_intensity = half(frameData.fairy_specular_intensity);
//        half specular_shininess = normal_shadow.w * half(frameData.shininess_factor);
        
        // Hardcoding for now:
        half specular_intensity = half(32.0f);
        half specular_shininess = normal_shadow.w * half(1.0f);

        half specular_factor = powr(max(dot(half3(normal_shadow.xyz),half3(halfway_vector)),0.0h), specular_intensity);

        half3 specular_contribution = specular_factor * half3(albedo_specular.xyz) * specular_shininess * light_color;

        // Light falloff
        float attenuation = 1.0 - (light_distance / light_radius);
        attenuation *= attenuation;

        lighting += (diffuse_contribution + half4(specular_contribution, 0)) * attenuation;
    }

//    return lighting;
//    return half4(float4(light_data[in.iid].color, 1));
    return half4(1.0, 0.0, 0.0, 1.0);
}

fragment AccumLightBuffer
deferred_point_lighting_fragment(LightInOut                in           [[ stage_in ]],
                                 const device LightData  * light_data   [[ buffer(TFSBufferPointLightsData) ]],
                                 GBufferData               GBuffer)
{
    AccumLightBuffer output;
//    output.lighting = deferred_point_lighting_fragment_common(in,
//                                                              light_data,
//                                                              GBuffer.lighting, 
//                                                              GBuffer.depth,
//                                                              GBuffer.normal_shadow,
//                                                              GBuffer.albedo_specular);
    
    output.lighting = half4(1.0, 0.0, 0.0, 1.0);

    return output;
}


// For testing:

vertex LightInOut icosahedron_vertex(const device float4         * vertices        [[ buffer(TFSBufferIndexMeshPositions) ]],
                                     constant ModelConstants     & modelConstants  [[ buffer(TFSBufferModelConstants) ]],
                                     constant SceneConstants     & sceneConstants  [[ buffer(TFSBufferIndexSceneConstants) ]],
                                     uint                          vid             [[ vertex_id ]]) {
    LightInOut out;
    
    float4 modelPosition = vertices[vid];
    float4 worldPosition = modelConstants.modelMatrix * modelPosition;
    float4 eyePosition = sceneConstants.viewMatrix * worldPosition;
    out.position = sceneConstants.projectionMatrix * eyePosition;

    // Sending light position in view space to next stage
    out.eye_position = eyePosition.xyz;
    return out;
}

fragment AccumLightBuffer icosahedron_fragment(LightInOut                in              [[ stage_in ]],
                                               constant ModelConstants & modelConstants  [[ buffer(TFSBufferModelConstants) ]],
                                               constant Material       & material        [[ buffer(TFSBufferIndexMaterial) ]],
                                               GBufferData               GBuffer)
{
    AccumLightBuffer output;
    output.lighting = half4(material.color);
    return output;
}
