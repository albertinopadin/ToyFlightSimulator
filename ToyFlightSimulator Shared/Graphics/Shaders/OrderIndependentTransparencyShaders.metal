//
//  OrderIndependentTransparencyShaders.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 12/27/22.
//

#include <metal_stdlib>
#include "Lighting.metal"
#include "Shared.metal"
#include "TFSShaderTypes.h"

using namespace metal;

// Heavily inspired from: https://developer.apple.com/documentation/metal/metal_sample_code_library/implementing_order-independent_transparency_with_image_blocksd

static constexpr constant short kNumLayers = 4;

struct TransparentFragmentValues {
    rgba8unorm<half4> colors [[ raster_order_group(0) ]] [kNumLayers];
    half depths [[ raster_order_group(0) ]] [kNumLayers];
};

struct TransparentFragmentStore {
    TransparentFragmentValues values [[ imageblock_data ]];
};

// A vertex function that generates a full-screen quad pass:
vertex RasterizerData quad_pass_vertex(uint vid [[ vertex_id ]]) {
    RasterizerData out;
    
    float4 position;
    position.x = (vid == 2) ? 3.0 : -1.0;
    position.y = (vid == 0) ? -3.0 : 1.0;
    position.zw = 1.0;

    out.position = position;
    return out;
}

kernel void init_transparent_fragment_store(imageblock<TransparentFragmentValues, imageblock_layout_explicit> blockData,
                                            ushort2 localThreadID [[ thread_position_in_threadgroup ]]) {
    threadgroup_imageblock TransparentFragmentValues* fragmentValues = blockData.data(localThreadID);
    for (short i = 0; i < kNumLayers; ++i) {
        fragmentValues->colors[i] = half4(0.0h);
        fragmentValues->depths[i] = half(INFINITY);
    }
}

fragment TransparentFragmentStore transparent_fragment(RasterizerData rd [[ stage_in ]],
                                                       TransparentFragmentValues fragmentValues [[ imageblock_data ]]) {
    TransparentFragmentStore out;
    half4 finalColor = half4(rd.color);
    finalColor.xyz *= finalColor.w;
    
    // Get fragment distance from camera:
    half depth = rd.position.z / rd.position.w;
    
    for (short i = 0; i < kNumLayers; ++i) {
        half layerDepth = fragmentValues.depths[i];
        half4 layerColor = fragmentValues.colors[i];
        
        bool insert (depth <= layerDepth);
        fragmentValues.colors[i] = insert ? finalColor : layerColor;
        fragmentValues.depths[i] = insert ? depth : layerDepth;
        
        finalColor = insert ? layerColor : finalColor;
        depth = insert ? layerDepth : depth;
    }
    
    out.values = fragmentValues;
    return out;
}

fragment TransparentFragmentStore transparent_material_fragment(
                        RasterizerData rd [[ stage_in ]],
                        constant Material &material [[ buffer(TFSBufferIndexMaterial) ]],
                        constant int &lightCount [[ buffer(2) ]],
                        constant LightData *lightData [[ buffer(TFSBufferDirectionalLightData) ]],
                        sampler sampler2d [[ sampler(0) ]],
                        texture2d<float> baseColorMap [[ texture(TFSTextureIndexBaseColor) ]],
                        texture2d<float> normalMap [[ texture(TFSTextureIndexNormal) ]],
                        TransparentFragmentValues fragmentValues [[ imageblock_data ]]) {
                            
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
                                                            lightData,
                                                            lightCount,
                                                            rd.worldPosition,
                                                            unitNormal,
                                                            unitToCameraVector);
        color *= float4(phongIntensity, 1.0);
    }
    
    TransparentFragmentStore out;
    half4 finalColor = half4(color);
    finalColor.xyz *= finalColor.w;
    
    // Get fragment distance from camera:
    half depth = rd.position.z / rd.position.w;
    
    for (short i = 0; i < kNumLayers; ++i) {
        half layerDepth = fragmentValues.depths[i];
        half4 layerColor = fragmentValues.colors[i];
        
        bool insert (depth <= layerDepth);
        fragmentValues.colors[i] = insert ? finalColor : layerColor;
        fragmentValues.depths[i] = insert ? depth : layerDepth;
        
        finalColor = insert ? layerColor : finalColor;
        depth = insert ? layerDepth : depth;
    }
    
    out.values = fragmentValues;
    return out;
}

fragment half4 blend_fragments(TransparentFragmentValues fragmentValues [[ imageblock_data ]],
                               half4 forwardOpaqueColor [[ color(0), raster_order_group(0) ]]) {
    half4 out;
    
    out.xyz = forwardOpaqueColor.xyz;
    
    for (short i = kNumLayers - 1; i >= 0; --i) {
        half4 layerColor = fragmentValues.colors[i];
        out.xyz = layerColor.xyz + (1.0h - layerColor.w) * out.xyz;
    }
    
    out.w = 1.0;
    return out;
}
