//
//  Base.metal
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/25/22.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"
#import "Lighting.metal"

struct FragmentOutput {
    half4 color0 [[ color(0) ]];
    half4 color1 [[ color(1) ]];
};

vertex RasterizerData base_vertex(const VertexIn vIn [[ stage_in ]],
                                  constant SceneConstants &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
                                  constant ModelConstants &modelConstants [[ buffer(TFSBufferModelConstants) ]]) {
    float4 worldPosition = modelConstants.modelMatrix * float4(vIn.position, 1);
    
    RasterizerData rd = {
        // Order of matrix multiplication is important here:
        .position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * worldPosition,
        .color = vIn.color,
        .textureCoordinate = vIn.textureCoordinate,
        .totalGameTime = sceneConstants.totalGameTime,
        .worldPosition = worldPosition.xyz,
        .toCameraVector = sceneConstants.cameraPosition - worldPosition.xyz,
        .surfaceNormal = normalize(modelConstants.modelMatrix * float4(vIn.normal, 1.0)).xyz,
        .surfaceTangent = normalize(modelConstants.modelMatrix * float4(vIn.tangent, 1.0)).xyz,
        .surfaceBitangent = normalize(modelConstants.modelMatrix * float4(vIn.bitangent, 1.0)).xyz
    };
    
    return rd;
}

fragment FragmentOutput base_fragment(RasterizerData rd [[ stage_in ]]) {
    float4 color = rd.color;
    float3 unitNormal = normalize(rd.surfaceNormal);
    
    FragmentOutput out = {
        .color0 = half4(color.r, color.g, color.b, color.a),
        .color1 = half4(unitNormal.x, unitNormal.y, unitNormal.z, 1.0)
    };
    
    return out;
}


fragment FragmentOutput material_fragment(RasterizerData rd [[ stage_in ]],
                                          constant MaterialProperties &material [[ buffer(TFSBufferIndexMaterial) ]],
                                          constant int &lightCount [[ buffer(TFSBufferDirectionalLightsNum) ]],
                                          constant LightData *lightData [[ buffer(TFSBufferDirectionalLightData) ]],
                                          sampler sampler2d [[ sampler(0) ]],
                                          texture2d<float> baseColorMap [[ texture(TFSTextureIndexBaseColor) ]],
                                          texture2d<float> normalMap [[ texture(TFSTextureIndexNormal) ]]) {
    float2 texCoord = rd.textureCoordinate;
    float4 color = rd.color;
    
    if (material.useMaterialColor) {
        color = material.color;
    }
    
    if (!is_null_texture(baseColorMap)) {
        color = baseColorMap.sample(sampler2d, texCoord);
    }
    
    float3 unitNormal;
    if (material.isLit) {
        unitNormal = normalize(rd.surfaceNormal);
        if (!is_null_texture(normalMap)) {
            float3 sampleNormal = normalMap.sample(sampler2d, texCoord).rgb * 2 - 1;
            float3x3 TBN { rd.surfaceTangent, rd.surfaceBitangent, rd.surfaceNormal };
            unitNormal = TBN * sampleNormal;
        }
        
        float3 unitToCameraVector = normalize(rd.toCameraVector);
        
        float3 phongIntensity = Lighting::GetPhongIntensity(material,
                                                            lightData,
                                                            lightCount,
                                                            rd.worldPosition,
                                                            unitNormal,
                                                            unitToCameraVector);
        color *= float4(phongIntensity, 1.0);
    }
    
    FragmentOutput out = {
        .color0 = half4(color.r, color.g, color.b, color.a),
        .color1 = half4(unitNormal.x, unitNormal.y, unitNormal.z, 1.0)
    };
    
    return out;
}
