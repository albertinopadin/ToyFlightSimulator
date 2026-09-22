//
//  MetalTypes.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/25/22.
//

import simd

public typealias float2 = SIMD2<Float>
public typealias float3 = SIMD3<Float>
public typealias float4 = SIMD4<Float>

protocol sizeable {}

extension sizeable {
    static var size: Int {
        return MemoryLayout<Self>.size
    }
    
    static var stride: Int {
        return MemoryLayout<Self>.stride
    }
    
    static func size(_ count: Int) -> Int {
        return MemoryLayout<Self>.size * count
    }
    
    static func stride(_ count: Int) -> Int {
        return MemoryLayout<Self>.stride * count
    }
}

extension UInt32: sizeable {}
extension Int32:  sizeable {}
extension Float:  sizeable {}
extension SIMD2:  sizeable {}
extension SIMD3:  sizeable {}
extension SIMD4:  sizeable {}

extension float4x4: sizeable {}

extension Particle: sizeable {}
extension Terrain: sizeable {}

public protocol HasNormal {
    var normal: float3 { get set }
}

struct Vertex: HasNormal, sizeable {
    var position: float3 = [0, 0, 0]
    var color: float4 = [0, 0, 0, 1]
    var textureCoordinate: float2 = [0, 0]
    var normal: float3 = [0, 0, 1]
    var tangent: float3 = [1, 0, 0]
    var bitangent: float3 = [0, 1, 0]
    var joints: simd_ushort4 = [0, 0, 0, 0]  // TODO: There can be more joints than just 4
    var jointWeights: float4 = [0, 0, 0, 0]
}

typealias ControlPoint = Vertex

struct TerrainControlPoint: sizeable {
    var position: float3 = [0, 0, 0]
}

extension ModelConstants: sizeable {}

extension SceneConstants: sizeable {}

/// Blinn-Phong material parameters, bound per submesh at `TFSBufferIndexMaterial`.
///
/// What the shaders read (`Lighting::ShadeDirectionalBlinnPhong` and the fragments that call it):
/// - `color`: the untextured albedo fallback (`ResolveBaseColor`), the MTL `Kd` line or the USD
///   `diffuseColor` input. PINK_DEBUG_COLOR makes a missing base color visible instead of silently gray.
/// - `specular.r`: highlight strength (the MTL `Ks` line, or the specular map's red channel when one is
///   bound). 0.25 is the shading doc's default for the unnormalized Blinn-Phong lobe: bright enough to
///   read as a highlight, low enough that a fully lit surface plus its highlight does not clip.
/// - `shininess`: highlight exponent (the MTL `Ns` line). 32 is a lobe about 12° wide at half brightness
///   and corresponds to a UsdPreviewSurface roughness of 0.49 through Karis's power = 2/roughness⁴ − 2,
///   so USD assets (which carry roughness, never an exponent) land near their own default of 0.5.
/// - `opacity`, `isLit`: `ResolveOpacity` and the unlit early-out.
///
/// Legacy, not read by the shading path: `ambient` and `diffuse` fed the old per-light Phong
/// (`Lighting::GetPhongIntensity`, kept as reference). The new ambient term is `albedo × ambientIntensity`
/// and never multiplies a material value. `Material.setProperties` still fills both from the MDL import.
/// See debugging/claude/renderer_shading_color_mismatch_2026-09-20.md (Step 6) and
/// research/claude/modelio_material_semantics_blinn_phong_2026-09-21.md.
extension MaterialProperties: sizeable {
    init(color: float4 = PINK_DEBUG_COLOR,
         ambient: float3 = [0.1, 0.1, 0.1],
         diffuse: float3 = [1, 1, 1],
         specular: float3 = [0.25, 0.25, 0.25],
         shininess: Float = 32.0,
         opacity: Float = 1.0,
         lit: Bool = true) {
        self.init(color: color,
                  ambient: ambient,
                  diffuse: diffuse,
                  specular: specular,
                  shininess: shininess,
                  opacity: opacity,
                  isLit: lit)
    }

    init() {
        self.init(color: PINK_DEBUG_COLOR,
                  ambient: [0.1, 0.1, 0.1],
                  diffuse: [1, 1, 1],
                  specular: [0.25, 0.25, 0.25],
                  shininess: 32.0,
                  opacity: 1.0,
                  isLit: true)
    }
}

extension MaterialTextureTransforms: sizeable {
    init() {
        self.init(baseColorUVTransform: matrix_identity_float3x3,
                  normalUVTransform:    matrix_identity_float3x3,
                  specularUVTransform:  matrix_identity_float3x3,
                  opacityUVTransform:   matrix_identity_float3x3,
                  hasTextureTransforms: false)
    }
}

extension LightData: sizeable {
    // TODO: Make these properties configurable from the init:
    init() {
        let identity = matrix_identity_float4x4
        self.init(type: Directional,
                  modelMatrix: identity,
                  viewProjectionMatrix: identity,
                  direction: [0, 1, 0],
                  lightEyeDirection: [0, 0, 0],
                  position: [0, 0, 0],
                  color: [1, 1, 1],
                  brightness: 1.0,
                  radius: 1.0,
                  attenuation: [0.5, 0.5, 0.5],
                  ambientIntensity: 1.0,
                  diffuseIntensity: 1.0,
                  specularIntensity: 1.0,
                  shadowWorldSlack: 0.25,
                  cascadeCount: 0,
                  cascadeViewProjectionMatrices: (identity, identity, identity, identity),
                  cascadeSplitDepths: (0, 0, 0, 0),
                  cascadeDepthRanges: (1, 1, 1, 1))
    }
}

protocol TFSIndices: RawRepresentable<UInt32> {
    var index: Int { get }
}

extension TFSIndices {
    var index: Int {
        return Int(self.rawValue)
    }
}

extension TFSBufferIndices: TFSIndices { }
extension TFSVertexAttributes: TFSIndices { }
extension TFSTextureIndices: TFSIndices { }
extension TFSRenderTargetIndices: TFSIndices { }
