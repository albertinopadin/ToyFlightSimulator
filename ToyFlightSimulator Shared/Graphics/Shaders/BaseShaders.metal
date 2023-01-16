//
//  BaseShaders.metal
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/25/22.
//

#include <metal_stdlib>
#include "Lighting.metal"
#include "Shared.metal"

using namespace metal;

struct FragmentOutput {
    half4 color0 [[ color(0) ]];
    half4 color1 [[ color(1) ]];
};

// Warren Moore / 30 Days of Metal:
vertex float4 shadow_vertex_shader(VertexIn in [[stage_in]],
                                   constant float4x4 &modelViewProjectionMatrix [[buffer(2)]]) {
    return modelViewProjectionMatrix * float4(in.position, 1.0);
}

// 2etime:
vertex float4 depth_vertex_shader(const VertexIn in [[stage_in]],
                                  constant LightData &lightData [[ buffer(3) ]],
                                  constant ModelConstants &modelConstants [[ buffer(2) ]]) {
    float4 worldPosition = lightData.lightSpaceMatrix * modelConstants.modelMatrix * float4(in.position, 1);
    return worldPosition;
}

vertex RasterizerData base_vertex_shader(const VertexIn vIn [[ stage_in ]],
                                         constant SceneConstants &sceneConstants [[ buffer(1) ]],
                                         constant ModelConstants &modelConstants [[ buffer(2) ]]) {
    RasterizerData rd;
    
    float4 worldPosition = modelConstants.modelMatrix * float4(vIn.position, 1);
    // Order of matrix multiplication is important here:
    rd.position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * worldPosition;
    rd.color = vIn.color;
    rd.textureCoordinate = vIn.textureCoordinate;
    rd.totalGameTime = sceneConstants.totalGameTime;
    rd.worldPosition = worldPosition.xyz;
    rd.toCameraVector = sceneConstants.cameraPosition - worldPosition.xyz;

    rd.surfaceNormal = normalize(modelConstants.modelMatrix * float4(vIn.normal, 0.0)).xyz;
    rd.surfaceTangent = normalize(modelConstants.modelMatrix * float4(vIn.tangent, 0.0)).xyz;
    rd.surfaceBitangent = normalize(modelConstants.modelMatrix * float4(vIn.bitangent, 0.0)).xyz;
    
    return rd;
}

fragment FragmentOutput base_fragment_shader(RasterizerData rd [[ stage_in ]],
                                             constant int &lightCount [[ buffer(2) ]],
                                             constant LightData *lightDatas [[ buffer(3) ]],
                                             sampler sampler2d [[ sampler(0) ]],
                                             texture2d<float> baseColorMap [[ texture(0) ]],
                                             texture2d<float> normalMap [[ texture(1) ]]) {
    float4 color = rd.color;
    float3 unitNormal = normalize(rd.surfaceNormal);
    
    FragmentOutput out;
    out.color0 = half4(color.r, color.g, color.b, color.a);
    out.color1 = half4(unitNormal.x, unitNormal.y, unitNormal.z, 1.0);
    return out;
}


//fragment FragmentOutput material_fragment_shader(RasterizerData rd [[ stage_in ]],
//                                                 constant Material &material [[ buffer(1) ]],
//                                                 constant int &lightCount [[ buffer(2) ]],
//                                                 constant LightData *lightDatas [[ buffer(3) ]],
//                                                 sampler sampler2d [[ sampler(0) ]],
//                                                 texture2d<float> baseColorMap [[ texture(0) ]],
//                                                 texture2d<float> normalMap [[ texture(1) ]],
//                                                 const depth2d<float> shadowMap [[ texture(2) ]]) {
//    float2 texCoord = rd.textureCoordinate;
//    float4 color = rd.color;
//
//    if (material.useMaterialColor) {
//        color = material.color;
//    }
//
//    if (material.useBaseTexture) {
//        color = baseColorMap.sample(sampler2d, texCoord);
//    }
//
//    float3 unitNormal;
//    if (material.isLit) {
//        unitNormal = normalize(rd.surfaceNormal);
//        if (material.useNormalMapTexture) {
//            float3 sampleNormal = normalMap.sample(sampler2d, texCoord).rgb * 2 - 1;
//            float3x3 TBN { rd.surfaceTangent, rd.surfaceBitangent, rd.surfaceNormal };
//            unitNormal = TBN * sampleNormal;
//        }
//
//        float3 unitToCameraVector = normalize(rd.toCameraVector);
//
////        float3 phongIntensity = Lighting::GetPhongIntensity(material,
////                                                            lightDatas,
////                                                            lightCount,
////                                                            rd.worldPosition,
////                                                            unitNormal,
////                                                            unitToCameraVector,
////                                                            shadowMap);
//
//        float3 phongIntensity = Lighting::GetPhongIntensity(material,
//                                                            lightDatas,
//                                                            lightCount,
//                                                            rd.worldPosition,
//                                                            unitNormal,
//                                                            unitToCameraVector);
//
//        color *= float4(phongIntensity, 1.0);
//    }
//
//    FragmentOutput out;
//    out.color0 = half4(color.r, color.g, color.b, color.a);
//    out.color1 = half4(unitNormal.x, unitNormal.y, unitNormal.z, 1.0);
//    return out;
//}

fragment FragmentOutput material_fragment_shader(RasterizerData rd [[ stage_in ]],
                                                 constant Material &material [[ buffer(1) ]],
                                                 constant int &lightCount [[ buffer(2) ]],
                                                 constant LightData *lightDatas [[ buffer(3) ]],
                                                 sampler sampler2d [[ sampler(0) ]],
                                                 texture2d<float> baseColorMap [[ texture(0) ]],
                                                 texture2d<float> normalMap [[ texture(1) ]]) {
    float2 texCoord = rd.textureCoordinate;
    float4 color = rd.color;
    
    if (material.useMaterialColor) {
        color = material.color;
    }
    
    if (material.useBaseTexture) {
        color = baseColorMap.sample(sampler2d, texCoord);
    }
    
    float3 unitNormal;
    if (material.isLit) {
        unitNormal = normalize(rd.surfaceNormal);
        if (material.useNormalMapTexture) {
            float3 sampleNormal = normalMap.sample(sampler2d, texCoord).rgb * 2 - 1;
            float3x3 TBN { rd.surfaceTangent, rd.surfaceBitangent, rd.surfaceNormal };
            unitNormal = TBN * sampleNormal;
        }
        
        float3 unitToCameraVector = normalize(rd.toCameraVector);
        
        float3 phongIntensity = Lighting::GetPhongIntensity(material,
                                                            lightDatas,
                                                            lightCount,
                                                            rd.worldPosition,
                                                            unitNormal,
                                                            unitToCameraVector);
        color *= float4(phongIntensity, 1.0);
    }
    
    FragmentOutput out;
    out.color0 = half4(color.r, color.g, color.b, color.a);
    out.color1 = half4(unitNormal.x, unitNormal.y, unitNormal.z, 1.0);
    return out;
}
