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
    static float shadow(float3 worldPosition,
                        depth2d<float, access::sample> depthMap,
                        float4x4 viewProjectionMatrix) {
        float4 shadowNDC = (viewProjectionMatrix * float4(worldPosition, 1));
        shadowNDC.xyz /= shadowNDC.w;
        float2 shadowCoords = shadowNDC.xy * 0.5 + 0.5;
        shadowCoords.y = 1 - shadowCoords.y;

        constexpr sampler shadowSampler(coord::normalized,
                                        address::clamp_to_edge,
                                        filter::linear,
                                        compare_func::greater_equal);
        float depthBias = 5e-3f;
        float shadowCoverage = depthMap.sample_compare(shadowSampler, shadowCoords, shadowNDC.z - depthBias);
        return shadowCoverage;
    }
    
    static float3 GetPhongIntensity(constant Material &material,
                                    constant LightData *lightDatas,
                                    int lightCount,
                                    float3 worldPosition,
                                    float3 unitNormal,
                                    float3 unitToCameraVector,
                                    depth2d<float, access::sample> shadowMap) {
        float3 totalAmbient = float3(0, 0, 0);
        float3 totalDiffuse = float3(0, 0, 0);
        float3 totalSpecular = float3(0, 0, 0);
        
        float specularExponent = 50.0;
        
        for (int i = 0; i < lightCount; i++) {
            LightData lightData = lightDatas[i];
            
            float3 unitToLightVector = normalize(lightData.position - worldPosition);
            float3 unitReflectionVector = normalize(reflect(-unitToLightVector, unitNormal));
            
            float ambientFactor = 0;
            float diffuseFactor = 0;
            float specularFactor = 0;
            
            switch (lightData.type) {
                case LightTypeAmbient:
                    ambientFactor = 1.0;
                    break;
                case LightTypeDirectional: {
                    float shadowFactor = 1 - shadow(worldPosition, shadowMap, lightData.viewProjectionMatrix);
//                    float3 V = normalize(float3(0) - in.viewPosition);
                    float3 V = normalize(float3(0) - unitToCameraVector);
//                    float3 L = normalize(-lightData.direction);
                    float3 H = normalize(unitToLightVector + V);
                    diffuseFactor = shadowFactor * saturate(dot(unitNormal, unitToLightVector));
                    specularFactor = shadowFactor * powr(saturate(dot(unitNormal, H)), specularExponent);
                    break;
                }
                    
            }
            
            // Ambient Lighting
            float3 ambientness = material.ambient * lightData.ambientIntensity;
            float3 ambientColor = clamp(ambientness * lightData.color * lightData.brightness * ambientFactor, 0.0, 1.0);
            
            // Diffuse Lighting
            float3 diffuseness = material.diffuse * lightData.diffuseIntensity;
            float nDotL = max(dot(unitNormal, unitToLightVector), 0.0);
            float correctedNDotL = max(nDotL, 0.3);
            float3 rawDiffuseColor = diffuseness * correctedNDotL * lightData.color * lightData.brightness * diffuseFactor;
            float3 diffuseColor = clamp(rawDiffuseColor, 0.0, 1.0);
            totalDiffuse += diffuseColor;
            
            // Check for back of object relative to light;
            // Only then add ambient
            if (nDotL <= 0) {
                totalAmbient += ambientColor;
            }
            
            // Specular Lighting
            float3 specularness = material.specular * lightData.specularIntensity;
            float rDotV = max(dot(unitReflectionVector, unitToCameraVector), 0.0);
            float specularExp = pow(rDotV, material.shininess);
            float3 rawSpecularColor = specularness * specularExp * lightData.color * lightData.brightness * specularFactor;
            float3 specularColor = clamp(rawSpecularColor, 0.0, 1.0);
            totalSpecular += specularColor;
        }
        
        return totalAmbient + totalDiffuse + totalSpecular;
    }
};

#endif

