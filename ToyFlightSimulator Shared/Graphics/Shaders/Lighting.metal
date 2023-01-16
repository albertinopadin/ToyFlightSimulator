//
//  Lighting.metal
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/25/22.
//

#ifndef LIGHTING_METAL
#define LIGHTING_METAL

#include <metal_stdlib>
#include "Shared.metal"
using namespace metal;

class Lighting {
public:
    // From Warren Moore's 30 Days of Metal:
    // https://medium.com/@warrenm/thirty-days-of-metal-day-19-directional-shadows-116cecbafcbb
//    static float shadow(float3 worldPosition,
//                        depth2d<float, access::sample> depthMap,
//                        float4x4 viewProjectionMatrix) {
//        float4 shadowNDC = (viewProjectionMatrix * float4(worldPosition, 1));
//        shadowNDC.xyz /= shadowNDC.w;
//        float2 shadowCoords = shadowNDC.xy * 0.5 + 0.5;
//        shadowCoords.y = 1 - shadowCoords.y;
//
//        constexpr sampler shadowSampler(coord::normalized,
//                                        address::clamp_to_edge,
//                                        filter::linear,
//                                        compare_func::greater_equal);
//        float depthBias = 5e-3f;
//        float shadowCoverage = depthMap.sample_compare(shadowSampler, shadowCoords, shadowNDC.z - depthBias);
//        return shadowCoverage;
//    }
    
    // From 2etime Discord: https://discord.com/channels/428977382515277824/428977382515277830/1059718599398404116
    static float shadow(float4 lightSpaceFragmentPosition, const depth2d<float> shadowMap) {
        float2 shadowUv = lightSpaceFragmentPosition.xy * float2(0.5, -0.5) + 0.5;
        
        constexpr sampler s(coord::normalized,
                            filter::linear,
                            address::clamp_to_border,
                            border_color::opaque_white,
                            compare_func::less);
        
        float bias = 0.000001;
        float currentDepth = lightSpaceFragmentPosition.z;
        float pcfDepth = shadowMap.sample(s, shadowUv.xy);
        float shadow = currentDepth - bias > pcfDepth ? 0.2 : 0.0;
        return 1 - ceil(shadow);
    }
    
    static float3 GetPhongIntensity(constant Material &material,
                                    constant LightData *lightDatas,
                                    int lightCount,
                                    float3 worldPosition,
                                    float3 unitNormal,
                                    float3 unitToCameraVector,
                                    const depth2d<float> shadowMap) {
//        float3 totalAmbient = float3(0, 0, 0);
//        float3 totalDiffuse = float3(0, 0, 0);
//        float3 totalSpecular = float3(0, 0, 0);

        float3 totalColor = float3(0, 0, 0);

//        float specularExponent = 50.0;

        for (int i = 0; i < lightCount; i++) {
            LightData lightData = lightDatas[i];

            float3 unitToLightVector = normalize(lightData.position - worldPosition);
            float3 unitReflectionVector = normalize(reflect(-unitToLightVector, unitNormal));

            // Warren Moore / 30 Days of Metal:
//            float ambientFactor = 0;
//            float diffuseFactor = 0;
//            float specularFactor = 0;
//
//            switch (lightData.type) {
//                case LightTypeAmbient:
//                    ambientFactor = 1.0;
//                    break;
//                case LightTypeDirectional: {
////                    float shadowFactor = 1 - shadow(worldPosition, shadowMap, lightData.viewProjectionMatrix);
////                    float3 V = normalize(float3(0) - in.viewPosition);
//                    float3 V = normalize(float3(0) - unitToCameraVector);
////                    float3 L = normalize(-lightData.direction);
//                    float3 H = normalize(unitToLightVector + V);
//                    diffuseFactor = shadowFactor * saturate(dot(unitNormal, unitToLightVector));
//                    specularFactor = shadowFactor * powr(saturate(dot(unitNormal, H)), specularExponent);
//                    break;
//                }
//            }

            // 2etime:
            float4 lightSpaceFragmentPosition = lightData.lightSpaceMatrix * float4(worldPosition, 1);
            float shadowCalc = shadow(lightSpaceFragmentPosition, shadowMap);

            // Ambient Lighting
            float3 ambientness = material.ambient * lightData.ambientIntensity;
            float3 ambientColor = clamp(ambientness * lightData.color * lightData.brightness, 0.0, 1.0);

            // Diffuse Lighting
            float3 diffuseness = material.diffuse * lightData.diffuseIntensity;
            float nDotL = max(dot(unitNormal, unitToLightVector), 0.0);
            float correctedNDotL = max(nDotL, 0.3);
            float3 rawDiffuseColor = diffuseness * correctedNDotL * lightData.color * lightData.brightness;
            float3 diffuseColor = clamp(rawDiffuseColor, 0.0, 1.0);
//            totalDiffuse += diffuseColor;

            // Check for back of object relative to light;
            // Only then add ambient
//            if (nDotL <= 0) {
//                totalAmbient += ambientColor;
//            }
            if (nDotL > 0) {
                ambientColor = 0;
            }

            // Specular Lighting
            float3 specularness = material.specular * lightData.specularIntensity;
            float rDotV = max(dot(unitReflectionVector, unitToCameraVector), 0.0);
            float specularExp = pow(rDotV, material.shininess);
            float3 rawSpecularColor = specularness * specularExp * lightData.color * lightData.brightness;
            float3 specularColor = clamp(rawSpecularColor, 0.0, 1.0);
//            totalSpecular += specularColor;
            if (shadowCalc <= 1) {
                specularColor = 0.0;
            }

            totalColor += shadowCalc * (ambientColor + diffuseColor + specularColor);
        }

//        return totalAmbient + totalDiffuse + totalSpecular;
        return totalColor;
    }
};

#endif

