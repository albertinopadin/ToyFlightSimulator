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

// Maximum number of shadow cascades a single directional light can use.
// LightData has fixed-size arrays sized to this constant so the shader
// doesn't need a dynamic-array binding. Runtime `cascadeCount` (1..4) on
// LightData selects how many of the slots are populated.
//
// 4 is the sweet spot for FlightboxWithPhysics-scale scenes: 4 × 2048² ×
// depth32Float = 64 MB total, vs the old 1 × 8192² = 256 MB. Bumping to 5
// or 6 yields diminishing returns and a larger LightData per-fragment cost.
#define TFS_MAX_SHADOW_CASCADES 4

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
    simd_float4 objectColor;
    bool useObjectColor;
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
    simd_float3 ambient;
    simd_float3 diffuse;
    simd_float3 specular;

    float shininess;
    float opacity;

    bool isLit;
} MaterialProperties;

// 2D affine UV transforms per texture slot. Layout matches glTF KHR_texture_transform's
// `mat3` form, applied as `(M * float3(uv, 1)).xy`. Default-constructed values are identity.
// Sourced from MDLTextureSampler.transform during material import.
typedef struct {
    matrix_float3x3 baseColorUVTransform;
    matrix_float3x3 normalUVTransform;
    matrix_float3x3 specularUVTransform;
    matrix_float3x3 opacityUVTransform;
    bool hasTextureTransforms;  // true → at least one slot has a non-identity transform
} MaterialTextureTransforms;

typedef enum {
    Ambient,
    Directional,
    Spot,
    Point
} LightType;

typedef struct {
    LightType type;
    matrix_float4x4 modelMatrix;
    matrix_float4x4 viewProjectionMatrix;
    matrix_float4x4 shadowViewProjectionMatrix;
    matrix_float4x4 shadowTransformMatrix;

    // World-space unit vector pointing FROM lit surfaces TO the light source.
    // For Directional lights this is the canonical light direction used by the
    // lighting shader (`dot(normal, direction)`). Populated by LightObject.update().
    // For Point lights this is unused; the shader recomputes per-fragment from
    // `light.position - worldPosition`.
    simd_float3 direction;

    // Eye-space transform of `direction`, recomputed each frame from the active
    // view matrix. Still populated for any specular paths that want it in eye
    // space, but no longer the primary input for diffuse lighting.
    simd_float3 lightEyeDirection;

    simd_float3 position;
    simd_float3 color;
    float brightness;
    float radius;  // TODO: This only applies to point lights; perhaps should have Directional/PointLightData
    simd_float3 attenuation;

    float ambientIntensity;
    float diffuseIntensity;
    float specularIntensity;

    // === Cascaded Shadow Maps (CSM) ===
    // World→cascade-NDC matrix per cascade. Cascade 0 is the closest to the
    // camera (sharpest, smallest world coverage); cascade N-1 is the farthest
    // (loosest, largest coverage). Only the first `cascadeCount` entries are
    // populated; remaining entries are identity. Populated by LightObject.update().
    matrix_float4x4 cascadeViewProjectionMatrices[TFS_MAX_SHADOW_CASCADES];

    // View-space depth boundaries between cascades. cascadeSplitDepths[i] is
    // the FAR distance of cascade i (and the near of cascade i+1). The last
    // populated entry equals the main camera's far plane. Compared against
    // `abs(view-space z)` per fragment to pick a cascade.
    float cascadeSplitDepths[TFS_MAX_SHADOW_CASCADES];

    // Per-cascade depth range in world units (cascade_far - cascade_near in
    // the cascade's own ortho frustum). Used to convert worldSlack into an
    // NDC-space depth-compare epsilon for that cascade.
    float cascadeDepthRange[TFS_MAX_SHADOW_CASCADES];

    // Per-cascade world-space slack. Scaled with cascade extent so larger
    // (distant) cascades get a proportionally larger slack to avoid acne on
    // their lower-resolution texels.
    float cascadeWorldSlack[TFS_MAX_SHADOW_CASCADES];

    // Number of populated cascades (1..TFS_MAX_SHADOW_CASCADES). The shader's
    // cascade-selection loop only iterates this many entries.
    uint32_t cascadeCount;

    // === Legacy single-cascade fields ===
    // shadowDepthRange / shadowWorldSlack still consumed by GBuffer.metal's
    // sample_compare path until it gets refactored. They mirror cascade 0
    // (cascadeDepthRange[0] / cascadeWorldSlack[0]).
    float shadowDepthRange;
    float shadowWorldSlack;
} LightData;

// Buffer index values shared between shader and C code to ensure Metal shader buffer inputs match
// Metal API buffer set calls
typedef enum {
    TFSBufferIndexMeshVertex        = 0,
    TFSBufferIndexMeshGenerics      = 1,
    TFSBufferFrameData              = 2,
    TFSBufferDirectionalLightsNum   = 3,
    TFSBufferDirectionalLightData   = 4,
    TFSBufferPointLightsData        = 5,
    TFSBufferPointLightsPosition    = 6,
    TFSBufferModelConstants         = 7,
    TFSBufferIndexSceneConstants    = 8,
    TFSBufferIndexMaterial                  = 9,
    TFSBufferIndexTerrain                   = 10,
    TFSBufferIndexJointBuffer               = 11,
    TFSBufferIndexMaterialTextureTransforms = 12,
    TFSBufferIndexShadowCascadeVP           = 13
} TFSBufferIndices;

// Attribute index values shared between shader and C code to ensure Metal shader vertex
// attribute indices match the Metal API vertex descriptor attribute indices
typedef enum {
    TFSVertexAttributePosition     = 0,
    TFSVertexAttributeColor        = 1,
    TFSVertexAttributeTexcoord     = 2,
    TFSVertexAttributeNormal       = 3,
    TFSVertexAttributeTangent      = 4,
    TFSVertexAttributeBitangent    = 5,
    TFSVertexAttributeJoints       = 6,
    TFSVertexAttributeJointWeights = 7
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
    TFSTextureIndexSkyBox    = 6,
    
    TFSTextureIndexGrass     = 7,
    TFSTextureIndexCliff     = 8,
    TFSTextureIndexSnow      = 9,
    TFSTextureIndexHeightMap = 10
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
    uint32_t framebuffer_width;
    uint32_t framebuffer_height;

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
//    float direction;
    vector_float3 direction;
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

// Temporary:
typedef struct {
    vector_float2 size;
    float height;
    uint32_t maxTessellation;
} Terrain;

#endif /* TFSCommon_h */
