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

struct LightMaskOut
{
    float4 position [[ position ]];
};

vertex LightMaskOut
light_mask_vertex(const device float4         * vertices        [[ buffer(TFSBufferIndexMeshPositions) ]],
                  const device TFSPointLight  * light_data      [[ buffer(TFSBufferIndexLightsData) ]],
                  const device vector_float4  * light_positions [[ buffer(TFSBufferIndexLightsPosition) ]],
                  constant TFSFrameData       & frameData       [[ buffer(TFSBufferFrameData) ]],
                  uint                          iid             [[ instance_id ]],
                  uint                          vid             [[ vertex_id ]])
{
    LightMaskOut out;

    // Transform light to position relative to the temple
    float4 vertex_eye_position = float4(vertices[vid].xyz * light_data[iid].light_radius + light_positions[iid].xyz, 1);

    out.position = frameData.projection_matrix * vertex_eye_position;

    return out;
}


struct LightInOut
{
    float4 position [[position]];
    float3 eye_position;
    uint   iid [[flat]];
};

vertex LightInOut
deferred_point_lighting_vertex(const device float4         * vertices        [[ buffer(TFSBufferIndexMeshPositions) ]],
                               const device TFSPointLight  * light_data      [[ buffer(TFSBufferIndexLightsData) ]],
                               const device vector_float4  * light_positions [[ buffer(TFSBufferIndexLightsPosition) ]],
                               constant TFSFrameData       & frameData       [[ buffer(TFSBufferFrameData) ]],
                               uint                          iid             [[ instance_id ]],
                               uint                          vid             [[ vertex_id ]])
{
    LightInOut out;

    // Transform light to position relative to the temple
    float3 vertex_eye_position = vertices[vid].xyz * light_data[iid].light_radius + light_positions[iid].xyz;

    out.position = frameData.projection_matrix * float4(vertex_eye_position, 1);

    // Sending light position in view space to next stage
    out.eye_position = vertex_eye_position;

    out.iid = iid;

    return out;
}

half4
deferred_point_lighting_fragment_common(LightInOut               in,
                                        device TFSPointLight   * light_data,
                                        device vector_float4   * light_positions,
                                        constant TFSFrameData  & frameData,
                                        half4                    lighting,
                                        float                    depth,
                                        half4                    normal_shadow,
                                        half4                    albedo_specular)
{
    // Used eye_space depth to determine the position of the fragment in eye_space
    float3 eye_space_fragment_pos = in.eye_position * (depth / in.eye_position.z);

    float3 light_eye_position = light_positions[in.iid].xyz;
    float light_distance = length(light_eye_position - eye_space_fragment_pos);
    float light_radius = light_data[in.iid].light_radius;

    if (light_distance < light_radius)
    {
        float4 eye_space_light_pos = float4(light_eye_position,1);

        float3 eye_space_fragment_to_light = eye_space_light_pos.xyz - eye_space_fragment_pos;

        float3 light_direction = normalize(eye_space_fragment_to_light);

        half3 light_color = half3(light_data[in.iid].light_color);

        // Diffuse contribution
        half4 diffuse_contribution = half4(float4(albedo_specular)*max(dot(float3(normal_shadow.xyz), light_direction),0.0f))*half4(light_color,1);

        // Specular Contribution
        float3 halfway_vector = normalize(eye_space_fragment_to_light - eye_space_fragment_pos);

        half specular_intensity = half(frameData.fairy_specular_intensity);

        half specular_shininess = normal_shadow.w * half(frameData.shininess_factor);

        half specular_factor = powr(max(dot(half3(normal_shadow.xyz),half3(halfway_vector)),0.0h), specular_intensity);

        half3 specular_contribution = specular_factor * half3(albedo_specular.xyz) * specular_shininess * light_color;

        // Light falloff
        float attenuation = 1.0 - (light_distance / light_radius);
        attenuation *= attenuation;

        lighting += (diffuse_contribution + half4(specular_contribution, 0)) * attenuation;
    }

    return lighting;
}

fragment AccumLightBuffer
deferred_point_lighting_fragment(
    LightInOut               in              [[ stage_in ]],
    constant TFSFrameData  & frameData       [[ buffer(TFSBufferFrameData) ]],
    device TFSPointLight   * light_data      [[ buffer(TFSBufferIndexLightsData) ]],
    device vector_float4   * light_positions [[ buffer(TFSBufferIndexLightsPosition) ]],
    GBufferData              GBuffer)
{
    AccumLightBuffer output;
    output.lighting =
        deferred_point_lighting_fragment_common(in, light_data, light_positions, frameData,
                                                GBuffer.lighting, GBuffer.depth, GBuffer.normal_shadow, GBuffer.albedo_specular);

    return output;
}
