//
//  GBufferTextures.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/23/23.
//

import Metal

struct SinglePassDeferredGBufferTextures {
    enum TextureType: CaseIterable {
        case AlbedoSpecular
        case NormalShadow
        case Depth
    }
    
    static let albedoSpecularFormat = MTLPixelFormat.rgba8Unorm_srgb
    static let normalShadowFormat = MTLPixelFormat.rgba8Snorm
    static let depthFormat = MTLPixelFormat.r32Float
    
    var albedoSpecular: MTLTexture!
    var normalShadow: MTLTexture!
    var depth: MTLTexture!
    
    var width: UInt32 {
        UInt32(albedoSpecular.width)
    }
    
    var height: UInt32 {
        UInt32(albedoSpecular.height)
    }
    
    static func getPixelFormat(for textureType: Self.TextureType) -> MTLPixelFormat {
        switch textureType {
            case .AlbedoSpecular:
                return albedoSpecularFormat
            case .NormalShadow:
                return normalShadowFormat
            case .Depth:
                return depthFormat
        }
    }
    
    mutating func makeTextures(device: MTLDevice, size: CGSize, storageMode: MTLStorageMode) {
        for textureType in Self.TextureType.allCases {
            let pixelFormat = Self.getPixelFormat(for: textureType)
            
            let gBufferTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat,
                                                                                    width: Int(size.width),
                                                                                    height: Int(size.height),
                                                                                    mipmapped: false)
            gBufferTextureDescriptor.textureType = .type2D
            gBufferTextureDescriptor.usage = [.shaderRead, .renderTarget]
            gBufferTextureDescriptor.storageMode = storageMode
            gBufferTextureDescriptor.pixelFormat = pixelFormat
            
            switch textureType {
                case .AlbedoSpecular:
                    albedoSpecular = device.makeTexture(descriptor: gBufferTextureDescriptor)
                    albedoSpecular.label = "Albedo + Specular GBuffer"
                case .NormalShadow:
                    normalShadow = device.makeTexture(descriptor: gBufferTextureDescriptor)
                    normalShadow.label = "Normal + Shadow GBuffer"
                case .Depth:
                    depth = device.makeTexture(descriptor: gBufferTextureDescriptor)
                    depth.label = "Depth GBuffer"
            }
            
        }
    }
}
