//
//  TiledDeferredGBufferTextures.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/2/24.
//

import MetalKit

struct TiledDeferredGBufferTextures {
    enum TextureType: CaseIterable {
        case Albedo
        case Normal
        case Position
    }
    
//    static let albedoPixelFormat: MTLPixelFormat = .rgba8Unorm_srgb
    static let albedoPixelFormat: MTLPixelFormat = .bgra8Unorm
    static let normalPixelFormat: MTLPixelFormat = .rgba16Float
    static let positionPixelFormat: MTLPixelFormat = .rgba16Float

    var albedoTexture: MTLTexture!
    var normalTexture: MTLTexture!
    var positionTexture: MTLTexture!
    
    var width: UInt32 {
        UInt32(albedoTexture.width)
    }
    
    var height: UInt32 {
        UInt32(albedoTexture.height)
    }
    
    static func getPixelFormat(for textureType: Self.TextureType) -> MTLPixelFormat {
        switch textureType {
            case .Albedo:
                return albedoPixelFormat
            case .Normal:
                return normalPixelFormat
            case .Position:
                return positionPixelFormat
        }
    }
    
    mutating func makeTextures(device: MTLDevice, size: CGSize, storageMode: MTLStorageMode) {
        for textureType in Self.TextureType.allCases {
            let pixelFormat = Self.getPixelFormat(for: textureType)
            
            let gBufferTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat,
                                                                                    width: Int(size.width),
                                                                                    height: Int(size.height),
                                                                                    mipmapped: false)
            gBufferTextureDescriptor.usage = [.shaderRead, .renderTarget]
            gBufferTextureDescriptor.storageMode = storageMode
            gBufferTextureDescriptor.pixelFormat = pixelFormat
            
            switch textureType {
                case .Albedo:
                    albedoTexture = device.makeTexture(descriptor: gBufferTextureDescriptor)
                    albedoTexture.label = "Albedo GBuffer"
                case .Normal:
                    normalTexture = device.makeTexture(descriptor: gBufferTextureDescriptor)
                    normalTexture.label = "Normal GBuffer"
                case .Position:
                    positionTexture = device.makeTexture(descriptor: gBufferTextureDescriptor)
                    positionTexture.label = "Position GBuffer"
            }
            
        }
    }
}
