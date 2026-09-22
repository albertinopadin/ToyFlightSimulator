//
//  OrderIndependentTransparency.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 12/27/22.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"
#import "ShaderHelpers.h"
#import "Lighting.metal"

// Heavily inspired from: https://developer.apple.com/documentation/metal/metal_sample_code_library/implementing_order-independent_transparency_with_image_blocksd

static constexpr constant short kNumLayers = 4;

struct TransparentFragmentValues {
    rgba8unorm<half4> colors [[ raster_order_group(0) ]] [kNumLayers];
    half depths [[ raster_order_group(0) ]] [kNumLayers];
};

struct TransparentFragmentStore {
    TransparentFragmentValues values [[ imageblock_data ]];
};

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
    half4 finalColor = half4(rd.color);
    finalColor.xyz *= finalColor.w;
    
    // View-space depth as the sort key ([[position]].w = 1/clipW, and clipW is
    // view depth for both forward- and reverse-Z projections; the old
    // z_ndc/w key inverted the sort under reverse-Z). Ascending order keeps
    // the NEAREST kNumLayers fragments, layer 0 = nearest.
    half depth = half(1.0 / rd.position.w);
    
    for (short i = 0; i < kNumLayers; ++i) {
        half layerDepth = fragmentValues.depths[i];
        half4 layerColor = fragmentValues.colors[i];
        
        bool insert (depth <= layerDepth);
        fragmentValues.colors[i] = insert ? finalColor : layerColor;
        fragmentValues.depths[i] = insert ? depth : layerDepth;
        
        finalColor = insert ? layerColor : finalColor;
        depth = insert ? layerDepth : depth;
    }
    
    TransparentFragmentStore out = {
        .values = fragmentValues
    };
    
    return out;
}

fragment TransparentFragmentStore
transparent_material_fragment(
                RasterizerData                     rd              [[ stage_in ]],
                constant MaterialProperties        &material       [[ buffer(TFSBufferIndexMaterial) ]],
                constant MaterialTextureTransforms &uvXforms       [[ buffer(TFSBufferIndexMaterialTextureTransforms) ]],
                constant int                       &lightCount     [[ buffer(TFSBufferDirectionalLightsNum) ]],
                constant LightData                 *lightData      [[ buffer(TFSBufferDirectionalLightData) ]],
                sampler                            sampler2d       [[ sampler(0) ]],
                texture2d<float>                   baseColorMap    [[ texture(TFSTextureIndexBaseColor) ]],
                texture2d<float>                   normalMap       [[ texture(TFSTextureIndexNormal) ]],
                TransparentFragmentValues          fragmentValues  [[ imageblock_data ]]) {
    // Per-slot UV transforms (glTF KHR_texture_transform): each texture has its own matrix,
    // identity for slots without one, so both UVs start from the raw coordinate and the
    // normal map is sampled with ITS transform, as in material_fragment (Base.metal).
    float2 baseUV = rd.textureCoordinate;
    float2 normalUV = rd.textureCoordinate;
    if (uvXforms.hasTextureTransforms) {
        baseUV = ApplyUVTransform(rd.textureCoordinate, uvXforms.baseColorUVTransform);
        normalUV = ApplyUVTransform(rd.textureCoordinate, uvXforms.normalUVTransform);
    }
    
    // material.color, not the interpolated vertex color, is the untextured fallback: the
    // vertex color defaults to black (secondary item 2 in the shading doc).
    float4 baseColor = ResolveBaseColor(rd.useObjectColor,
                                        rd.objectColor,
                                        material.color,
                                        baseColorMap,
                                        sampler2d,
                                        baseUV);
    
    float3 unitNormal = normalize(rd.surfaceNormal);
    
    if (!is_null_texture(normalMap) && !rd.useObjectColor) {
        float3 normalSample = normalMap.sample(sampler2d, normalUV).rgb;
        unitNormal = ApplyNormalMapWorld(normalSample, rd.surfaceTangent, rd.surfaceBitangent, rd.surfaceNormal);
    }
    
    // Same forward Blinn-Phong as material_fragment (Base.metal), which explains the
    // lightCount guard, the unreachable point-light branch, litFraction = 1 (no shadow
    // map here) and the specular inputs: material.specular.r as the strength and
    // material.shininess as the exponent since Step 6 landed.
    float3 litColor;
    if (lightCount == 0 || !material.isLit) {
        litColor = baseColor.rgb;
    } else {
        float3 toCamera = normalize(rd.toCameraVector);
        litColor = 0;
        for (int i = 0; i < lightCount; i++) {
            constant LightData &light = lightData[i];
            float3 toLight;
            if (light.type == Directional) {
                toLight = light.direction;
            } else {
                toLight = normalize(light.position - rd.worldPosition);
            }
            
            litColor += Lighting::ShadeDirectionalBlinnPhong(baseColor.rgb,
                                                             unitNormal,
                                                             toLight,
                                                             toCamera,
                                                             light,
                                                             material.specular.r,
                                                             material.shininess,
                                                             1.0);
        }
    }
    
    TransparentFragmentStore out;
    // Light the straight color first, then premultiply by the opacity ONCE (next line):
    // the image-block layers and their resolve expect premultiplied color, as before.
    half4 finalColor = half4(half3(litColor), ResolveOpacity(baseColor.a, material.opacity));
    
    finalColor.rgb *= finalColor.a;
    
    // View-space depth as the sort key ([[position]].w = 1/clipW, and clipW is
    // view depth for both forward- and reverse-Z projections; the old
    // z_ndc/w key inverted the sort under reverse-Z). Ascending order keeps
    // the NEAREST kNumLayers fragments, layer 0 = nearest.
    half depth = half(1.0 / rd.position.w);
    
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
