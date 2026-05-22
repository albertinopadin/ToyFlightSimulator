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

    // Slope-scaled world-space bias: surfaces tilted relative to the sun get
    // a larger depth-compare slack than surfaces facing the sun directly.
    // Eliminates shadow acne on grazing-angle surfaces (e.g. F-22 rudders,
    // wing edges) while keeping the slack small for flat ground (which is
    // perpendicular to a near-overhead sun and needs only minimal bias).
    //
    // Formula: bias = baseSlack * (1 + slope * SLOPE_BIAS_FACTOR)
    //   where slope = 1 - saturate(dot(normal, lightDir))
    //
    // - normal · lightDir = 1  → surface faces sun → slope = 0 → bias = baseSlack
    // - normal · lightDir = 0  → surface parallel to sun → slope = 1 → bias = baseSlack * (1 + FACTOR)
    // - normal · lightDir < 0  → surface back-faces sun → still slope = 1 (saturated)
    //
    // SLOPE_BIAS_FACTOR = 20: empirically chosen so vertical surfaces (F-22
    // rudders relative to overhead sun) get ~20× the flat-ground bias.
    static float SlopeScaledWorldBias(float baseSlack, float3 normal, float3 lightDir) {
        float nDotL = saturate(dot(normalize(normal), lightDir));
        float slope = 1.0 - nDotL;
        constexpr float SLOPE_BIAS_FACTOR = 20.0;
        return baseSlack * (1.0 + slope * SLOPE_BIAS_FACTOR);
    }

    // Pick the closest cascade whose split distance still includes this
    // fragment. `viewSpaceDepth` should be `|view * worldPos|.z` (always
    // non-negative; computed in the vertex shader). Falls back to the last
    // cascade if the fragment is past every split.
    static uint SelectCascade(constant LightData &light, float viewSpaceDepth) {
        for (uint i = 0; i < light.cascadeCount; ++i) {
            if (viewSpaceDepth < light.cascadeSplitDepths[i]) {
                return i;
            }
        }

        return light.cascadeCount > 0 ? light.cascadeCount - 1 : 0;
//        return 0;
    }

    // Cascade-aware shadow sample. Returns 1.0 (fully lit) or 0.5 (shadowed).
    //   - worldPosition: fragment's world-space position
    //   - viewSpaceDepth: fragment's view-space |z| (for cascade selection)
    //   - worldNormal: fragment's WORLD-SPACE surface normal (NOT eye-space).
    //                  Used for slope-scaled bias to suppress acne on tilted
    //                  surfaces like F-22 rudders or wing edges.
    //   - light: directional light with populated cascade arrays
    //   - shadowArray: texture2DArray<depth32Float>, arrayLength=cascadeCount
    static float CalculateShadow(float3 worldPosition,
                                 float viewSpaceDepth,
                                 float3 worldNormal,
                                 constant LightData &light,
                                 depth2d_array<float> shadowArray) {
        if (light.cascadeCount == 0) return 1.0;  // light not yet populated

        uint cascadeIdx = SelectCascade(light, viewSpaceDepth);

        // Transform world position into the selected cascade's NDC.
        float4 shadowPosition = light.cascadeViewProjectionMatrices[cascadeIdx] *
                                float4(worldPosition, 1.0);
        float3 position = shadowPosition.xyz / shadowPosition.w;
        float2 xy = position.xy;
        xy = xy * 0.5 + 0.5;
        xy.y = 1 - xy.y;

        // Fragment outside the cascade's frustum: try the next-further-out
        // cascade (texel-snapping can shift a fragment slightly outside the
        // depth-selected cascade's XY box). Falls through to fully-lit if
        // even the last cascade misses.
        if (any(xy < 0.0) || any(xy > 1.0) || position.z < 0.0 || position.z > 1.0) {
            if (cascadeIdx + 1 < light.cascadeCount) {
                cascadeIdx += 1;
                shadowPosition = light.cascadeViewProjectionMatrices[cascadeIdx] *
                                 float4(worldPosition, 1.0);
                position = shadowPosition.xyz / shadowPosition.w;
                xy = position.xy * 0.5 + 0.5;
                xy.y = 1 - xy.y;
                if (any(xy < 0.0) || any(xy > 1.0) || position.z < 0.0 || position.z > 1.0) {
                    return 1.0;
                }
            } else {
                return 1.0;
            }
        }

        // Slope-scaled world-space bias: tilted surfaces get a larger slack
        // than flat surfaces facing the sun. Suppresses acne on F-22 rudders
        // / wing edges without peter-panning ground shadows.
        float worldBias = SlopeScaledWorldBias(light.cascadeWorldSlack[cascadeIdx],
                                               worldNormal,
                                               light.direction);
        float epsilon = NDCShadowEpsilon(worldBias,
                                         light.cascadeDepthRange[cascadeIdx]);

        // Wide 3x3 hardware PCF kernel. Each sample_compare call with
        // filter::linear + compare_func::less performs a 4-tap hardware
        // bilinear depth-compare. We do that 9 times in a 3x3 grid with
        // texel-spaced offsets, giving an effective 36-texel average per
        // fragment.
        //
        // Why this wide instead of 4-tap:
        // The texel snap quantizes cascade motion to integer texel steps.
        // Each snap shifts the shadow-map texel grid by exactly 1 texel in
        // world space. With a tight 4-tap PCF, the eye can still pick up
        // these per-snap shifts as a 1-texel flicker (perceived "swim").
        // A 3x3 kernel smooths the shadow into a soft analog gradient where
        // 1-texel snap-jumps fall well below the kernel's smoothing radius
        // and become imperceptible.
        constexpr sampler pcfSampler(coord::normalized,
                                     filter::linear,
                                     address::clamp_to_edge,
                                     compare_func::less);

        float litSum = 0.0;
        // 1.0 / shadowMapResolution gives the UV step per texel. The 4096²
        // resolution is set by ShadowRendering.ShadowMapSize on the host;
        // get_width()/get_height() reads it back here so the shader stays
        // resolution-agnostic.
        float invW = 1.0 / float(shadowArray.get_width());
        float invH = 1.0 / float(shadowArray.get_height());
        float refZ = position.z - epsilon;
        for (int dy = -1; dy <= 1; ++dy) {
            for (int dx = -1; dx <= 1; ++dx) {
                float2 offset = float2(float(dx) * invW, float(dy) * invH);
                litSum += shadowArray.sample_compare(pcfSampler,
                                                     xy + offset,
                                                     cascadeIdx,
                                                     refZ);
            }
        }
        float litFraction = litSum * (1.0 / 9.0);

        // Map [0, 1] lit-fraction to [0.5, 1.0] shadow factor.
        return 0.5 + 0.5 * litFraction;
    }

    // MSAA-resolved cascade arrays are non-MSAA texture2DArray<float>, so the
    // MSAA helper is now an alias of CalculateShadow. Kept for source-compat
    // with existing call sites in TiledMSAAGBuffer.metal; can be removed
    // once those call sites switch to CalculateShadow directly.
    static float CalculateShadowMSAA(float3 worldPosition,
                                     float viewSpaceDepth,
                                     float3 worldNormal,
                                     constant LightData &light,
                                     depth2d_array<float> shadowArray) {
        return CalculateShadow(worldPosition, viewSpaceDepth, worldNormal, light, shadowArray);
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

