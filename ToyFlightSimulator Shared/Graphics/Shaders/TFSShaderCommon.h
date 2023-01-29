//
//  TFSShaderCommon.h
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/24/23.
//

#ifndef TFSShaderCommon_h
#define TFSShaderCommon_h

// Raster order group definitions
#define TFSLightingROG  0
#define TFSGBufferROG   1

// G-buffer outputs using Raster Order Groups
struct GBufferData
{
    half4 lighting        [[color(TFSRenderTargetLighting), raster_order_group(TFSLightingROG)]];
    half4 albedo_specular [[color(TFSRenderTargetAlbedo),   raster_order_group(TFSGBufferROG)]];
    half4 normal_shadow   [[color(TFSRenderTargetNormal),   raster_order_group(TFSGBufferROG)]];
    float depth           [[color(TFSRenderTargetDepth),    raster_order_group(TFSGBufferROG)]];
};

// Final buffer outputs using Raster Order Groups
struct AccumLightBuffer
{
    half4 lighting [[color(TFSRenderTargetLighting), raster_order_group(TFSLightingROG)]];
};

#endif /* TFSShaderCommon_h */
