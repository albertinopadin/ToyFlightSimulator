//
//  ShaderTypes.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/21/23.
//

#ifndef TFSShaderTypes_h
#define TFSShaderTypes_h

#include <simd/simd.h>

#ifndef __METAL_VERSION__
/// 96-bit 3 component float vector type
typedef struct __attribute__ ((packed)) packed_float3 {
    float x;
    float y;
    float z;
} packed_float3;
#endif

// Buffer index values shared between shader and C code to ensure Metal shader buffer inputs match
// Metal API buffer set calls
//typedef enum TFSBufferIndices
//{
//    TFSBufferIndexMeshPositions     = 0,
//    TFSBufferIndexMeshGenerics      = 1,
//    TFSBufferFrameData              = 2,
//    TFSBufferPointLightsData        = 3,
//    TFSBufferPointLightsPosition    = 4,
//    TFSBufferDirectionalLightData   = 5,
//    TFSBufferModelConstants         = 6,
//    TFSBufferIndexSceneConstants    = 7,
//    TFSBufferIndexMaterial          = 8
//    
//} TFSBufferIndices;

typedef enum TFSBufferIndices
{
    TFSBufferIndexMeshPositions     = 0,
    TFSBufferIndexMeshGenerics      = 1,
    TFSBufferFrameData              = 2,
    TFSBufferDirectionalLightData   = 3,
    TFSBufferPointLightsData        = 4,
    TFSBufferPointLightsPosition    = 5,
    TFSBufferModelConstants         = 6,
    TFSBufferIndexSceneConstants    = 7,
    TFSBufferIndexMaterial          = 8
    
} TFSBufferIndices;

// Attribute index values shared between shader and C code to ensure Metal shader vertex
// attribute indices match the Metal API vertex descriptor attribute indices
//typedef enum TFSVertexAttributes
//{
//    TFSVertexAttributePosition  = 0,
//    TFSVertexAttributeColor     = 1,
//    TFSVertexAttributeTexcoord  = 2,
//    TFSVertexAttributeNormal    = 3,
//    TFSVertexAttributeTangent   = 4,
//    TFSVertexAttributeBitangent = 5
//} TFSVertexAttributes;

typedef enum TFSBaseVertexAttributes
{
    TFSVertexAttributePosition  = 0,
    TFSVertexAttributeColor     = 1,
    TFSVertexAttributeTexcoord  = 2,
    TFSVertexAttributeNormal    = 3,
    TFSVertexAttributeTangent   = 4,
    TFSVertexAttributeBitangent = 5
} TFSBaseVertexAttributes;

//typedef enum TFSBaseVertexAttributes
//{
//    TFSVertexAttributePosition  = 0,
//    TFSVertexAttributeTexcoord  = 1,
//    TFSVertexAttributeNormal    = 2,
//    TFSVertexAttributeTangent   = 3,
//    TFSVertexAttributeBitangent = 4,
//    TFSVertexAttributeColor     = 5,
//} TFSBaseVertexAttributes;

typedef enum TFSGltfVertexAttributes
{
    TFSGltfVertexAttributePosition  = 0,
    TFSGltfVertexAttributeTexcoord  = 1,
    TFSGltfVertexAttributeNormal    = 2,
    TFSGltfVertexAttributeTangent   = 3,
    TFSGltfVertexAttributeBitangent = 4,
    TFSGltfVertexAttributeColor     = 5,
} TFSGltfVertexAttributes;

//union VertexAttributes {
//    <#union fields#>
//};

// Works for USD:
//typedef enum TFSVertexAttributes
//{
//    TFSVertexAttributePosition  = 0,
//    TFSVertexAttributeTexcoord  = 1,
//    TFSVertexAttributeNormal    = 2,
//    TFSVertexAttributeColor     = 3,
//    TFSVertexAttributeTangent   = 4,
//    TFSVertexAttributeBitangent = 5
//} TFSVertexAttributes;

// Should work for (my) GLTF...???
//typedef enum TFSVertexAttributes
//{
//    TFSVertexAttributeNormal    = 0,
//    TFSVertexAttributeTexcoord  = 1,
//    TFSVertexAttributePosition  = 2,
//    TFSVertexAttributeColor     = 3,
//    TFSVertexAttributeTangent   = 4,
//    TFSVertexAttributeBitangent = 5
//} TFSVertexAttributes;

// Texture index values shared between shader and C code to ensure Metal shader texture indices
// match indices of Metal API texture set calls
typedef enum TFSTextureIndices
{
    TFSTextureIndexBaseColor = 0,
    TFSTextureIndexSpecular  = 1,
    TFSTextureIndexNormal    = 2,
    TFSTextureIndexShadow    = 3,
    TFSTextureIndexAlpha     = 4,
    
    TFSNumMeshTextures = TFSTextureIndexNormal + 1
    
} TFSTextureIndices;

typedef enum TFSRenderTargetIndices
{
    TFSRenderTargetLighting  = 0,
    TFSRenderTargetAlbedo    = 1,
    TFSRenderTargetNormal    = 2,
    TFSRenderTargetDepth     = 3
} TFSRenderTargetIndices;
   

// Structures shared between shader and C code to ensure the layout of data accessed in
//    Metal shaders matches the layout of data set in C code

// Data constant across all threads, vertices, and fragments
typedef struct
{
    // Per Frame frameData
    matrix_float4x4 projection_matrix;
    matrix_float4x4 projection_matrix_inverse;
    matrix_float4x4 view_matrix;
    uint framebuffer_width;
    uint framebuffer_height;

    // Per Mesh frameData
    matrix_float4x4 temple_modelview_matrix;
    matrix_float4x4 temple_model_matrix;
    matrix_float3x3 temple_normal_matrix;
    float shininess_factor;

    float fairy_size;
    float fairy_specular_intensity;

    matrix_float4x4 sky_modelview_matrix;
    matrix_float4x4 shadow_mvp_matrix;
    matrix_float4x4 shadow_mvp_xform_matrix;

    vector_float4 sun_eye_direction;
    vector_float4 sun_color;
    float sun_specular_intensity;
} TFSFrameData;

// Per-light characteristics
typedef struct
{
    vector_float3 light_color;
    float light_radius;
    float light_speed;
} TFSPointLight;

typedef struct {
    vector_float2 position;
} TFSSimpleVertex;
    
typedef struct {
    packed_float3 position;
} TFSShadowVertex;

    
#endif /* TFSShaderTypes_h */
