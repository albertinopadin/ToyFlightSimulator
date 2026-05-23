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

    // Sample one cascade's PCF-filtered lit fraction in [0, 1]. Projects
    // worldPosition by the cascade's VP and runs a (2*PCF_HALF+1)² hardware-PCF
    // kernel. Each sample_compare with filter::linear performs a hardware 2×2
    // bilinear filter on the comparison result, so the effective footprint is a
    // little wider than the tap count. `inBounds` is set false (and the return
    // value is meaningless) if the fragment projects outside this cascade's
    // [0,1] box; the caller decides whether to fall through to the next cascade.
    //
    // Kernel width is the main lever for animated-geometry swim: a wider kernel
    // sub-texel-averages the depth-compare threshold so per-frame skinning jitter
    // stays below the eye's discrimination threshold. 5×5 (PCF_HALF=2) is the
    // Stage-2 default; drop to 1 (3×3) if edges read too soft, raise to 3 (7×7)
    // if residual swim is still visible.
    static float SampleCascadePCF(float3 worldPosition,
                                  float3 worldNormal,
                                  constant LightData &light,
                                  depth2d_array<float> shadowArray,
                                  uint cascadeIdx,
                                  thread bool &inBounds) {
        float4 shadowPos = light.cascadeViewProjectionMatrices[cascadeIdx]
                         * float4(worldPosition, 1.0);
        float3 ndc = shadowPos.xyz / shadowPos.w;
        float2 xy  = ndc.xy * 0.5 + 0.5;
        xy.y = 1.0 - xy.y;

        if (any(xy < 0.0) || any(xy > 1.0) || ndc.z < 0.0 || ndc.z > 1.0) {
            inBounds = false;
            return 1.0;
        }
        inBounds = true;

        float biasWorld = SlopeScaledWorldBias(light.shadowWorldSlack, worldNormal, light.direction);
        float epsilon   = NDCShadowEpsilon(biasWorld, light.cascadeDepthRanges[cascadeIdx]);
        float refZ      = ndc.z - epsilon;

        constexpr sampler pcfSampler(coord::normalized,
                                     filter::linear,
                                     address::clamp_to_edge,
                                     compare_func::less);
        constexpr int   PCF_HALF    = 2;  // 2 → 5×5
        constexpr float PCF_DIVISOR = float((PCF_HALF * 2 + 1) * (PCF_HALF * 2 + 1));
        float invW = 1.0 / float(shadowArray.get_width());
        float invH = 1.0 / float(shadowArray.get_height());
        float litSum = 0.0;
        for (int dy = -PCF_HALF; dy <= PCF_HALF; ++dy) {
            for (int dx = -PCF_HALF; dx <= PCF_HALF; ++dx) {
                float2 offset = float2(float(dx) * invW, float(dy) * invH);
                litSum += shadowArray.sample_compare(pcfSampler, xy + offset, cascadeIdx, refZ);
            }
        }
        return litSum * (1.0 / PCF_DIVISOR);
    }

    // Cascade-aware shadow factor in [0.5, 1.0]. Selects a cascade by view-space
    // depth, PCF-samples it, and cross-fades into the next cascade in the last
    // CASCADE_BLEND_FRACTION of the cascade's depth range to hide the
    // resolution-change seam at cascade boundaries.
    static float CalculateShadow(float3 worldPosition,
                                 float  fragViewSpaceDepth,
                                 float3 worldNormal,
                                 constant LightData &light,
                                 depth2d_array<float> shadowArray) {
        if (light.cascadeCount == 0) { return 1.0; }

        uint cascadeIdx = SelectCascade(light, fragViewSpaceDepth);

        bool inBounds = false;
        float lit = SampleCascadePCF(worldPosition, worldNormal, light, shadowArray,
                                     cascadeIdx, inBounds);

        // Fallthrough: texel snap can nudge a fragment outside the depth-selected
        // cascade's XY box. Try the next cascade before giving up (fully lit).
        if (!inBounds) {
            if (cascadeIdx + 1 < light.cascadeCount) {
                cascadeIdx += 1;
                lit = SampleCascadePCF(worldPosition, worldNormal, light, shadowArray,
                                       cascadeIdx, inBounds);
                if (!inBounds) { return 1.0; }
            } else {
                return 1.0;
            }
        }

        // Cascade blending: ramp a blend weight over the last fraction of this
        // cascade's depth range and cross-fade into the next cascade's PCF result.
        if (cascadeIdx + 1 < light.cascadeCount) {
            constexpr float CASCADE_BLEND_FRACTION = 0.1;
            float cascadeFar  = light.cascadeSplitDepths[cascadeIdx];
            float cascadeNear = (cascadeIdx > 0) ? light.cascadeSplitDepths[cascadeIdx - 1] : 0.0;
            float span        = max(cascadeFar - cascadeNear, 1.0);
            float blendStart  = cascadeFar - span * CASCADE_BLEND_FRACTION;
            float blendWeight = saturate((fragViewSpaceDepth - blendStart)
                                       / max(cascadeFar - blendStart, 1e-4));
            if (blendWeight > 0.0) {
                bool nextInBounds = false;
                float litNext = SampleCascadePCF(worldPosition, worldNormal, light, shadowArray,
                                                 cascadeIdx + 1, nextInBounds);
                if (nextInBounds) {
                    lit = mix(lit, litNext, blendWeight);
                }
            }
        }

        // Map [0, 1] PCF result to a [0.5, 1.0] shadow factor.
        return 0.5 + 0.5 * lit;
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

