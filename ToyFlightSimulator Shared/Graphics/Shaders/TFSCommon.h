//
//  TFSCommon.h
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/24/23.
//

#ifndef TFSCommon_h
#define TFSCommon_h

#ifndef __cplusplus
#define bool _Bool
#endif

#import <simd/simd.h>

#ifndef __METAL_VERSION__
/// 96-bit 3 component float vector type
typedef struct __attribute__ ((packed)) packed_float3 {
    float x;
    float y;
    float z;
} packed_float3;
#endif

typedef struct {
    matrix_float4x4 modelMatrix;
    matrix_float3x3 normalMatrix;
} ModelConstants;

typedef struct {
    float totalGameTime;
    matrix_float4x4 viewMatrix;
    matrix_float4x4 skyViewMatrix;
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 projectionMatrixInverse;
    simd_float3 cameraPosition;
} SceneConstants;

typedef struct {
    simd_float4 color;
    bool useMaterialColor;
    bool isLit;
    
    bool useBaseTexture;
    bool useNormalMapTexture;
    bool useSpecularTexture;
    
    simd_float3 ambient;
    simd_float3 diffuse;
    simd_float3 specular;
    float shininess;
} ShaderMaterial;

typedef enum {
    Ambient,
    Directional,
    Omni,
    Point
} LightType;

typedef struct {
    LightType type;
    matrix_float4x4 modelMatrix;
    matrix_float4x4 viewProjectionMatrix;
    matrix_float4x4 shadowViewProjectionMatrix;
    matrix_float4x4 shadowTransformMatrix;
    simd_float3 lightEyeDirection;
    
    simd_float3 position;
    simd_float3 color;
    float brightness;
    float radius;  // TODO: This only applies to point lights; perhaps should have Directional/PointLightData
    simd_float3 attenuation;
    
    float ambientIntensity;
    float diffuseIntensity;
    float specularIntensity;
} LightData;

// Buffer index values shared between shader and C code to ensure Metal shader buffer inputs match
// Metal API buffer set calls
typedef enum {
    TFSBufferIndexMeshPositions     = 0,
    TFSBufferIndexMeshGenerics      = 1,
    TFSBufferFrameData              = 2,
    TFSBufferDirectionalLightsNum   = 3,
    TFSBufferDirectionalLightData   = 4,
    TFSBufferPointLightsData        = 5,
    TFSBufferPointLightsPosition    = 6,
    TFSBufferModelConstants         = 7,
    TFSBufferIndexSceneConstants    = 8,
    TFSBufferIndexMaterial          = 9
    
} TFSBufferIndices;

// Attribute index values shared between shader and C code to ensure Metal shader vertex
// attribute indices match the Metal API vertex descriptor attribute indices
typedef enum {
    TFSVertexAttributePosition  = 0,
    TFSVertexAttributeColor     = 1,
    TFSVertexAttributeTexcoord  = 2,
    TFSVertexAttributeNormal    = 3,
    TFSVertexAttributeTangent   = 4,
    TFSVertexAttributeBitangent = 5
} TFSVertexAttributes;

// Texture index values shared between shader and C code to ensure Metal shader texture indices
// match indices of Metal API texture set calls
typedef enum {
    TFSTextureIndexBaseColor = 0,
    TFSTextureIndexSpecular  = 1,
    TFSTextureIndexNormal    = 2,
    TFSTextureIndexShadow    = 3,
    TFSTextureIndexAlpha     = 4,
    TFSTextureIndexParticle  = 5,
    
    TFSNumMeshTextures = TFSTextureIndexNormal + 1
    
} TFSTextureIndices;

typedef enum {
    TFSRenderTargetLighting  = 0,
    TFSRenderTargetAlbedo    = 1,
    TFSRenderTargetNormal    = 2,
    TFSRenderTargetDepth     = 3,
    TFSRenderTargetPosition  = 4
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

struct Particle {
    vector_float3 position;
    float direction;
    float speed;
    vector_float4 color;
    float life;
    float age;
    float size;
    float scale;
    float startScale;
    float endScale;
    vector_float3 startPosition;
};

#endif /* TFSCommon_h */
