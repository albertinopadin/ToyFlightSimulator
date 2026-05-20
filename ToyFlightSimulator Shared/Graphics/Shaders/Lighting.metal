//
//  Lighting.metal
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/25/22.
//

#ifndef LIGHTING_METAL
#define LIGHTING_METAL

#include <metal_stdlib>
using namespace metal;

#import "TFSCommon.h"

class Lighting {
public:
    static float3 GetPhongIntensity(MaterialProperties material,
                                    constant LightData *lightData,
                                    int lightCount,
                                    float3 worldPosition,
                                    float3 unitNormal,
                                    float3 unitToCameraVector) {
        float3 totalAmbient = float3(0, 0, 0);
        float3 totalDiffuse = float3(0, 0, 0);
        float3 totalSpecular = float3(0, 0, 0);
        
        for (int i = 0; i < lightCount; i++) {
            LightData iLightData = lightData[i];
            
            float3 unitToLightVector = normalize(iLightData.position - worldPosition);
            float3 unitReflectionVector = normalize(reflect(-unitToLightVector, unitNormal));
            
            // Ambient Lighting
            float3 ambientness = material.ambient * iLightData.ambientIntensity;
            float3 ambientColor = clamp(ambientness * iLightData.color * iLightData.brightness, 0.0, 1.0);
            
            // Diffuse Lighting
            float3 diffuseness = material.diffuse * iLightData.diffuseIntensity;
            float nDotL = max(dot(unitNormal, unitToLightVector), 0.0);
            float correctedNDotL = max(nDotL, 0.3);
            float3 diffuseColor = clamp(diffuseness * correctedNDotL * iLightData.color * iLightData.brightness, 0.0, 1.0);
            totalDiffuse += diffuseColor;
            
            // Check for back of object relative to light;
            // Only then add ambient
            if (nDotL <= 0) {
                totalAmbient += ambientColor;
            }
            
            // Specular Lighting
            float3 specularness = material.specular * iLightData.specularIntensity;
            float rDotV = max(dot(unitReflectionVector, unitToCameraVector), 0.0);
            float specularExp = pow(rDotV, material.shininess);
            float3 specularColor = clamp(specularness * specularExp * iLightData.color * iLightData.brightness, 0, 1.0);
            totalSpecular += specularColor;
        }
        
        return totalAmbient + totalDiffuse + totalSpecular;
    }
    
    static float3 CalculateDirectionalLighting(LightData light, float3 normal, MaterialProperties material) {
        float4 baseColor = material.color;
        float3 metallic = material.shininess;
        float3 ambientOcclusion = material.ambient;

        // `light.direction` is a world-space unit vector from surfaces toward the
        // light source, populated by LightObject.update(). No per-fragment normalize
        // needed; no dependence on the (now decoupled) shadow camera position.
        float nDotL = saturate(dot(normal, light.direction));
        float3 diffuse = float3(baseColor) * (1.0 - metallic);
        return diffuse * nDotL * ambientOcclusion * light.color;
    }
    
    // Compute the NDC-space depth-compare epsilon from a world-space slack and
    // the shadow camera's frustum depth range. For an orthographic projection,
    // NDC depth is linear in view-space depth, so `worldSlack / depthRange`
    // converts the slack into the right NDC units regardless of frustum scale.
    // Clamped to a small floor so cleared / unset LightData (depthRange == 0)
    // never produces division-by-zero or all-shadowed output.
    static float NDCShadowEpsilon(float worldSlack, float depthRange) {
        return worldSlack / max(depthRange, 1.0);
    }

    static float CalculateShadow(float4 shadowPosition,
                                 depth2d<float> shadowTexture,
                                 float worldSlack,
                                 float depthRange) {
        float3 position = shadowPosition.xyz / shadowPosition.w;
        float2 xy = position.xy;
        xy = xy * 0.5 + 0.5;
        xy.y = 1 - xy.y;

        // Outside the shadow frustum we have no occluder info. Treat as fully lit
        // rather than letting clamp_to_edge return the boundary texel's depth
        // (which produces ground self-shadow past the frustum edge). Also guard
        // the forward-Z near/far range: position.z outside [0, 1] means the
        // fragment is in front of the shadow near plane or behind the far plane.
        if (any(xy < 0.0) || any(xy > 1.0) || position.z < 0.0 || position.z > 1.0) {
            return 1.0;
        }

        constexpr sampler s(coord::normalized,
                            filter::nearest,
                            address::clamp_to_edge,
                            compare_func:: less);
        float shadow_sample = shadowTexture.sample(s, xy);
        float epsilon = NDCShadowEpsilon(worldSlack, depthRange);
        return (position.z > shadow_sample + epsilon) ? 0.5 : 1;
    }

    static float CalculateShadowMSAA(float4 shadowPosition,
                                     depth2d_ms<float> shadowTexture,
                                     float worldSlack,
                                     float depthRange) {
        float3 position = shadowPosition.xyz / shadowPosition.w;
        float2 xy = position.xy;
        xy = xy * 0.5 + 0.5;
        xy.y = 1 - xy.y;

        // See CalculateShadow for rationale: out-of-frustum reads as fully lit.
        if (any(xy < 0.0) || any(xy > 1.0) || position.z < 0.0 || position.z > 1.0) {
            return 1.0;
        }

        uint2 coords = uint2(uint(xy.x * shadowTexture.get_width()),
                             uint(xy.y * shadowTexture.get_height()));
        uint numSamples = shadowTexture.get_num_samples();

        float shadow = 0;
        for (uint i = 0; i < numSamples; ++i) {
            shadow += shadowTexture.read(coords, i);
        }
        shadow /= numSamples;

        float epsilon = NDCShadowEpsilon(worldSlack, depthRange);
        return (position.z > shadow + epsilon) ? 0.5 : 1;
    }
    
    static float3 CalculatePointLighting(LightData light,
                                         float3 fragmentWorldPosition,
                                         float3 normal, MaterialProperties material) {
        float d = distance(light.position, fragmentWorldPosition);
        float3 lightDirection = normalize(light.position - fragmentWorldPosition);
        
        float attenuation = 1.0 / (light.attenuation.x + light.attenuation.y * d + light.attenuation.z * d * d);
        float diffuseIntensity = saturate(dot(normal, lightDirection));
        float3 color = light.color * material.color.xyz * diffuseIntensity;
        color *= attenuation;
        if (color.r + color.g + color.b < 0.01) {
            color = 0;
        }
        return color;
    }
};

#endif

