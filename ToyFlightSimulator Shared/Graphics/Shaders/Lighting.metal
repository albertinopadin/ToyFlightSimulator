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
    // the cascade's frustum depth range. For an orthographic projection, NDC
    // depth is linear in view-space depth, so `worldSlack / depthRange` converts
    // the slack into the right NDC units regardless of frustum scale. Clamped to
    // a small floor so cleared / unset LightData (depthRange == 0) never produces
    // division-by-zero or all-shadowed output.
    static float NDCShadowEpsilon(float worldSlack, float depthRange) {
        return worldSlack / max(depthRange, 1.0);
    }

    // Slope-scaled bias: surfaces nearly parallel to the light direction get up
    // to SLOPE_BIAS_FACTOR× the base slack. Prevents acne on near-vertical
    // surfaces (F-22 rudders, sphere sides) without Peter-panning the ground.
    static float SlopeScaledWorldBias(float baseSlack, float3 normal, float3 lightDir) {
        float nDotL = saturate(dot(normalize(normal), lightDir));
        float slope = 1.0 - nDotL;
        constexpr float SLOPE_BIAS_FACTOR = 20.0;
        return baseSlack * (1.0 + slope * SLOPE_BIAS_FACTOR);
    }

    // Interval-based cascade selection: the first cascade whose far depth exceeds
    // this fragment's view-space depth. Falls back to the LAST cascade if the
    // fragment is beyond all of them (not cascade 0, which would put a far
    // fragment in the smallest, sharpest cascade — wrong).
    static uint SelectCascade(constant LightData &light, float viewSpaceDepth) {
        for (uint i = 0; i < light.cascadeCount; ++i) {
            if (viewSpaceDepth < light.cascadeSplitDepths[i]) return i;
        }
        return light.cascadeCount > 0 ? light.cascadeCount - 1 : 0;
    }

    // Cascade-aware shadow factor in [0.5, 1.0]. Selects a cascade by view-space
    // depth, projects worldPosition by that cascade's VP, and samples a 3×3
    // hardware-PCF kernel. Each sample_compare with filter::linear performs a
    // hardware 2×2 bilinear filter on the comparison result, so the effective
    // kernel is ~4×4 weighted.
    static float CalculateShadow(float3 worldPosition,
                                 float  fragViewSpaceDepth,
                                 float3 worldNormal,
                                 constant LightData &light,
                                 depth2d_array<float> shadowArray) {
        if (light.cascadeCount == 0) { return 1.0; }

        uint cascadeIdx = SelectCascade(light, fragViewSpaceDepth);
        float4 shadowPos = light.cascadeViewProjectionMatrices[cascadeIdx]
                         * float4(worldPosition, 1.0);
        float3 ndc = shadowPos.xyz / shadowPos.w;
        float2 xy  = ndc.xy * 0.5 + 0.5;
        xy.y = 1.0 - xy.y;

        // Cascade fallthrough: texel snap can shift a fragment slightly outside
        // the depth-selected cascade's XY box. Try the next cascade before
        // returning fully lit.
        if (any(xy < 0.0) || any(xy > 1.0) || ndc.z < 0.0 || ndc.z > 1.0) {
            if (cascadeIdx + 1 < light.cascadeCount) {
                cascadeIdx += 1;
                shadowPos = light.cascadeViewProjectionMatrices[cascadeIdx]
                          * float4(worldPosition, 1.0);
                ndc = shadowPos.xyz / shadowPos.w;
                xy  = ndc.xy * 0.5 + 0.5;
                xy.y = 1.0 - xy.y;
                if (any(xy < 0.0) || any(xy > 1.0) || ndc.z < 0.0 || ndc.z > 1.0) {
                    return 1.0;
                }
            } else {
                return 1.0;
            }
        }

        float biasWorld = SlopeScaledWorldBias(light.shadowWorldSlack, worldNormal, light.direction);
        float epsilon   = NDCShadowEpsilon(biasWorld, light.cascadeDepthRanges[cascadeIdx]);
        float refZ      = ndc.z - epsilon;

        constexpr sampler pcfSampler(coord::normalized,
                                     filter::linear,
                                     address::clamp_to_edge,
                                     compare_func::less);
        float invW = 1.0 / float(shadowArray.get_width());
        float invH = 1.0 / float(shadowArray.get_height());
        float litSum = 0.0;
        for (int dy = -1; dy <= 1; ++dy) {
            for (int dx = -1; dx <= 1; ++dx) {
                float2 offset = float2(float(dx) * invW, float(dy) * invH);
                litSum += shadowArray.sample_compare(pcfSampler, xy + offset, cascadeIdx, refZ);
            }
        }
        // Map [0, 1] PCF result to a [0.5, 1.0] shadow factor.
        return 0.5 + 0.5 * (litSum * (1.0 / 9.0));
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

