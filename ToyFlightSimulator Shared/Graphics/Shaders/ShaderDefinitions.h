//
//  Shared.metal
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/25/22.
//

#ifndef SHARED_METAL
#define SHARED_METAL

#include <metal_stdlib>
using namespace metal;

#import "TFSCommon.h"

struct VertexIn {
    float3 position             [[ attribute(TFSVertexAttributePosition) ]];
    float4 color                [[ attribute(TFSVertexAttributeColor) ]];
    float2 textureCoordinate    [[ attribute(TFSVertexAttributeTexcoord) ]];
    float3 normal               [[ attribute(TFSVertexAttributeNormal) ]];
    float3 tangent              [[ attribute(TFSVertexAttributeTangent) ]];
    float3 bitangent            [[ attribute(TFSVertexAttributeBitangent) ]];
};

struct RasterizerData {
    float4 position [[ position ]];
    float4 color;
    float4 objectColor;
    float2 textureCoordinate;
    float totalGameTime;
    
    float3 worldPosition;  // To get vector to light
    float3 toCameraVector;

    float3 surfaceNormal;
    float3 surfaceTangent;
    float3 surfaceBitangent;
    
    uint32_t instanceId;
    bool useObjectColor;
};

// Raster order group definitions
#define TFSLightingROG  0
#define TFSGBufferROG   1

// G-buffer outputs using Raster Order Groups
typedef struct {
    simd_half4 lighting         [[color(TFSRenderTargetLighting), raster_order_group(TFSLightingROG)]];
    simd_half4 albedo_specular  [[color(TFSRenderTargetAlbedo),   raster_order_group(TFSGBufferROG)]];
    simd_half4 normal_shadow    [[color(TFSRenderTargetNormal),   raster_order_group(TFSGBufferROG)]];
    float depth                 [[color(TFSRenderTargetDepth),    raster_order_group(TFSGBufferROG)]];
} GBufferData;

// Final buffer outputs using Raster Order Groups
typedef struct {
    simd_half4 lighting [[color(TFSRenderTargetLighting), raster_order_group(TFSLightingROG)]];
} AccumLightBuffer;

#endif

// For Tiled Deferred Renderer:
struct GBufferOut {
    float4 albedo   [[ color(TFSRenderTargetAlbedo) ]];
    float4 normal   [[ color(TFSRenderTargetNormal) ]];
    float4 position [[ color(TFSRenderTargetPosition) ]];
};

struct VertexOut {
    float4 position [[ position ]];
    float3 normal;
    float2 uv;
    float3 worldPosition;
    float3 worldNormal;
    float3 worldTangent;
    float3 worldBitangent;
    float4 shadowPosition;
    uint instanceId;
    float4 objectColor;
    bool useObjectColor;
};

// Temp:
struct TessellationVertexOut {
    float4 position [[ position ]];
    float4 color;
};

//struct ControlPoint {
//    vector_float3 position             [[ attribute(TFSVertexAttributePosition) ]];
//    vector_float4 color                [[ attribute(TFSVertexAttributeColor) ]];
//    vector_float2 textureCoordinate    [[ attribute(TFSVertexAttributeTexcoord) ]];
//    vector_float3 normal               [[ attribute(TFSVertexAttributeNormal) ]];
//    vector_float3 tangent              [[ attribute(TFSVertexAttributeTangent) ]];
//    vector_float3 bitangent            [[ attribute(TFSVertexAttributeBitangent) ]];
//};
