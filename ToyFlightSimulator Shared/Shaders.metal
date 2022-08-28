//
//  Shaders.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/25/22.
//

#include <metal_stdlib>
using namespace metal;


enum LightType : uint {
    LightTypeAmbient,
    LightTypeDirectional,
    LightTypeOmnidirectional
};

struct Light {
    float4x4 viewProjectionMatrix;
    float3 intensity;
    float3 position;    // World-space position
    float3 direction;   // View-space direction
    LightType type;
};

struct VertexIn {
    float3 position  [[ attribute(0) ]];
    float3 normal    [[ attribute(1) ]];
};

struct VertexOut {
    float4 position [[ position ]];
    float3 worldPosition;
    float3 viewPosition;
    float3 normal;
    float4 color;
};

struct NodeConstants {
    float4x4 modelMatrix;
    float4 color;
};

struct InstanceConstants {
    float4x4 modelMatrix;
    float4 color;
};

struct FrameConstants {
    float4x4 projectionMatrix;
    float4x4 viewMatrix;
    float3x3 inverseViewDirectionMatrix;
    uint lightCount;
};

float distanceAttenuation(constant Light &light, float3 toLight) {
    switch(light.type) {
        case LightTypeOmnidirectional: {
            float lightDistSq = dot(toLight, toLight);
            return 1.0f / max(lightDistSq, 1e-4);
            break;
        }
        default:
            return 1.0;
    }
}

vertex VertexOut vertex_main(VertexIn in [[ stage_in ]],
                             constant InstanceConstants *instances [[ buffer(2) ]],
                             constant FrameConstants &frame [[ buffer(3) ]],
                             uint instanceID [[ instance_id ]])
{
    constant InstanceConstants &instance = instances[instanceID];
    
    float4x4 modelMatrix = instance.modelMatrix;
    float4x4 modelViewMatrix = frame.viewMatrix * instance.modelMatrix;
    
    float4 worldPosition = modelMatrix * float4(in.position, 1.0);
    float4 viewPosition = frame.viewMatrix * worldPosition;
    float4 viewNormal = modelViewMatrix * float4(in.normal, 0.0);
    
    VertexOut out;
    out.position = frame.projectionMatrix * viewPosition;
    out.worldPosition = worldPosition.xyz;
    out.viewPosition = viewPosition.xyz;
    out.normal = viewNormal.xyz;
    out.color = instance.color;
    return out;
}

fragment float4 fragment_main(VertexOut in [[ stage_in ]],
                              constant FrameConstants &frame [[ buffer(3) ]],
                              constant Light *lights [[ buffer(4) ]])
{
    float4 baseColor = in.color;
    float specularExponent = 150.0;

    float3 N = normalize(in.normal);
    float3 V = normalize(float3(0) - in.viewPosition);

    float3 litColor { 0 };

    for (uint i = 0; i < frame.lightCount; ++i) {
        float ambientFactor = 0;
        float diffuseFactor = 0;
        float specularFactor = 0;

        constant Light &light = lights[i];

        switch(light.type) {
            case LightTypeAmbient:
                ambientFactor = 1;
                break;
            case LightTypeDirectional: {
                float3 L = normalize(-light.direction);
                float3 H = normalize(L + V);
                diffuseFactor = saturate(dot(N, L));
                specularFactor = powr(saturate(dot(N, H)), specularExponent);
                break;
            }
            case LightTypeOmnidirectional: {
                float3 toLight = light.position - in.viewPosition;
                float attenuation = distanceAttenuation(light, toLight);

                float3 L = normalize(toLight);
                float3 H = normalize(L + V);
                diffuseFactor = attenuation * saturate(dot(N, L));
                specularFactor = attenuation * powr(saturate(dot(N, H)), specularExponent);
                break;
            }
        }

//        litColor += (ambientFactor + diffuseFactor + specularFactor) * light.intensity * baseColor.rgb;
        litColor += (ambientFactor + diffuseFactor) * light.intensity * baseColor.rgb +
                     specularFactor * light.intensity;
    }

    return float4(litColor * baseColor.a, baseColor.a);
}

