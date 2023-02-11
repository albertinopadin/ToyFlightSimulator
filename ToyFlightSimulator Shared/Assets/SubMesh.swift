//
//  SubMesh.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2/6/23.
//

import MetalKit

// Index Information
class Submesh {
    private var _indices: [UInt32] = []
    
    private var _indexCount: Int = 0
    public var indexCount: Int { return _indexCount }
    
    private var _indexBuffer: MTLBuffer!
    public var indexBuffer: MTLBuffer { return _indexBuffer }
    
    private var _primitiveType: MTLPrimitiveType = .triangle
    public var primitiveType: MTLPrimitiveType { return _primitiveType }
    
    private var _indexType: MTLIndexType = .uint32
    public var indexType: MTLIndexType { return _indexType }
    
    private var _indexBufferOffset: Int = 0
    public var indexBufferOffset: Int { return _indexBufferOffset }
    
    private var _material = Material()
    private var _baseColorTexture: MTLTexture!
    private var _normalMapTexture: MTLTexture!
    private var _specularTexture: MTLTexture!
    
    init(indices: [UInt32]) {
        self._indices = indices
        self._indexCount = indices.count
        createIndexBuffer()
    }
    
    init(mtkSubmesh: MTKSubmesh, mdlSubmesh: MDLSubmesh) {
        _indexBuffer = mtkSubmesh.indexBuffer.buffer
        _indexBufferOffset = mtkSubmesh.indexBuffer.offset
        _indexCount = mtkSubmesh.indexCount
        _indexType = mtkSubmesh.indexType
        _primitiveType = mtkSubmesh.primitiveType
        
        print("Creating textures and material for \(mtkSubmesh.name)")
        createTextures(mdlSubmesh.material!)
        createMaterial(mdlSubmesh.material!)
    }
    
    private func texture(for semantic: MDLMaterialSemantic,
                         in material: MDLMaterial?,
                         textureOrigin: MTKTextureLoader.Origin) -> MTLTexture? {
        guard let material = material else { return nil }
        
        let textureLoader = MTKTextureLoader(device: Engine.Device)
//        guard let materialProperty = material?.property(with: semantic) else { return nil }
//        guard let sourceTexture = materialProperty.textureSamplerValue?.texture else { return nil }
//        let options: [MTKTextureLoader.Option: Any] = [
//            .origin: textureOrigin as Any,
//            .generateMipmaps: true,
//            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
//            .textureStorageMode: MTLStorageMode.private.rawValue
//        ]
//        let tex = try? textureLoader.newTexture(texture: sourceTexture, options: options)
//        return tex
        
        var newTexture: MTLTexture!
        
        for property in material.properties(with: semantic) {
            let options: [MTKTextureLoader.Option: Any] = [
                .origin: textureOrigin as Any,
                .generateMipmaps: true,
                .textureUsage: MTLTextureUsage.shaderRead.rawValue,
                .textureStorageMode: MTLStorageMode.private.rawValue
            ]
            
            switch property.type {
            case .string:
                if let stringValue = property.stringValue {
                    newTexture = try? textureLoader.newTexture(name: stringValue,
                                                                scaleFactor: 1.0,
                                                                bundle: nil,
                                                                options: options)
                }
            case .URL:
                if let textureURL = property.urlValue {
                    newTexture = try? textureLoader.newTexture(URL: textureURL, options: options)
                }
            case .texture:
                let sourceTexture = property.textureSamplerValue!.texture!
                newTexture = try? textureLoader.newTexture(texture: sourceTexture, options: options)
            case .none:
                print("Material property is none!")
                newTexture = nil
            default:
//                fatalError("Texture data for material property not found - name: \(material.name), class name: \(material.className), debug desc: \(material.debugDescription)")
                newTexture = nil
            }
        }
        
//        let tex = try? textureLoader.newTexture(texture: sourceTexture, options: options)
//        return tex
        return newTexture
    }
    
    private func createTextures(_ mdlMaterial: MDLMaterial) {
        _baseColorTexture = texture(for: .baseColor, in: mdlMaterial, textureOrigin: .bottomLeft)
        _normalMapTexture = texture(for: .tangentSpaceNormal, in: mdlMaterial, textureOrigin: .bottomLeft)
        _specularTexture = texture(for: .specular, in: mdlMaterial, textureOrigin: .bottomLeft)
    }
    
    private func createMaterial(_ mdlMaterial: MDLMaterial) {
        if let ambient = mdlMaterial.property(with: .emission)?.float3Value { _material.ambient = ambient }
        if let diffuse = mdlMaterial.property(with: .baseColor)?.float3Value { _material.diffuse = diffuse }
        if let specular = mdlMaterial.property(with: .specular)?.float3Value { _material.specular = specular }
        if let shininess = mdlMaterial.property(with: .specularExponent)?.floatValue { _material.shininess = shininess }
    }
    
    private func createIndexBuffer() {
        if _indices.count > 0 {
            _indexBuffer = Engine.Device.makeBuffer(bytes: _indices,
                                                    length: UInt32.stride(_indices.count),
                                                    options: [])
        }
    }
    
    func applyTextures(renderCommandEncoder: MTLRenderCommandEncoder,
                       customBaseColorTextureType: TextureType,
                       customNormalMapTextureType: TextureType,
                       customSpecularTextureType: TextureType) {
        _material.useBaseTexture = customBaseColorTextureType != .None || _baseColorTexture != nil
        _material.useNormalMapTexture = customNormalMapTextureType != .None || _normalMapTexture != nil
        _material.useSpecularTexture = customSpecularTextureType != .None || _normalMapTexture != nil
        
        renderCommandEncoder.setFragmentSamplerState(Graphics.SamplerStates[.Linear], index: 0)
        
        let baseColorTex = customBaseColorTextureType == .None ?
                            _baseColorTexture : Assets.Textures[customBaseColorTextureType]
        if baseColorTex != nil {
            renderCommandEncoder.setFragmentTexture(baseColorTex, index: Int(TFSTextureIndexBaseColor.rawValue))
        }
        
        let normalMapTex = customNormalMapTextureType == .None ?
                            _normalMapTexture : Assets.Textures[customNormalMapTextureType]
        if normalMapTex != nil {
            renderCommandEncoder.setFragmentTexture(normalMapTex, index: Int(TFSTextureIndexNormal.rawValue))
        }
        
        let specularTex = customSpecularTextureType == .None ? _specularTexture : Assets.Textures[customSpecularTextureType]
        if specularTex != nil {
            renderCommandEncoder.setFragmentTexture(specularTex, index: Int(TFSTextureIndexSpecular.rawValue))
        }
    }
    
    func applyMaterials(renderCommandEncoder: MTLRenderCommandEncoder, customMaterial: Material?) {
        var mat = customMaterial == nil ? _material : customMaterial
        renderCommandEncoder.setFragmentBytes(&mat, length: Material.stride, index: Int(TFSBufferIndexMaterial.rawValue))
    }
}

