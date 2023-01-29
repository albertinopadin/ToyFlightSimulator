//
//  GBufferTextures.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/23/23.
//

import Metal

struct GBufferTextures {
    var albedoSpecular: MTLTexture!
    var normalShadow: MTLTexture!
    var depth: MTLTexture!
    
    var width: UInt32 {
        UInt32(albedoSpecular.width)
    }
    
    var height: UInt32 {
        UInt32(albedoSpecular.height)
    }
    
    static let albedoSpecularFormat = MTLPixelFormat.rgba8Unorm_srgb
    static let normalShadowFormat = MTLPixelFormat.rgba8Snorm
    static let depthFormat = MTLPixelFormat.r32Float
    
    mutating func makeTextures(device: MTLDevice, size: CGSize, storageMode: MTLStorageMode) {
        let gBufferTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb,
                                                                                width: Int(size.width),
                                                                                height: Int(size.height),
                                                                                mipmapped: false)
        gBufferTextureDescriptor.textureType = .type2D
        gBufferTextureDescriptor.usage = [.shaderRead, .renderTarget]
        gBufferTextureDescriptor.storageMode = storageMode
        
        gBufferTextureDescriptor.pixelFormat = GBufferTextures.albedoSpecularFormat
        albedoSpecular = device.makeTexture(descriptor: gBufferTextureDescriptor)
        albedoSpecular.label = "Albedo + Specular GBuffer"
        
        gBufferTextureDescriptor.pixelFormat = GBufferTextures.normalShadowFormat
        normalShadow = device.makeTexture(descriptor: gBufferTextureDescriptor)
        normalShadow.label = "Normal + Shadow GBuffer"
        
        gBufferTextureDescriptor.pixelFormat = GBufferTextures.depthFormat
        depth = device.makeTexture(descriptor: gBufferTextureDescriptor)
        depth.label = "Depth GBuffer"
    }
}
