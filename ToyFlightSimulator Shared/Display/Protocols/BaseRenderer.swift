//
//  BaseRenderer.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/11/25.
//

import MetalKit

protocol BaseRenderer: RenderPassEncoder, ComputePassEncoder {
    var baseRenderPassDescriptor: MTLRenderPassDescriptor { get set }
}

extension BaseRenderer {
    static func createBaseRenderPassDescriptor(screenWidth: Int, screenHeight: Int) -> MTLRenderPassDescriptor {
        // --- BASE COLOR 0 TEXTURE ---
        makeBaseTexture(type: .BaseColorRender_0, screenWidth: screenWidth, screenHeight: screenHeight)
        
        // --- BASE COLOR 1 TEXTURE ---
        makeBaseTexture(type: .BaseColorRender_1, screenWidth: screenWidth, screenHeight: screenHeight)
        
        // --- BASE DEPTH TEXTURE ---
        makeBaseDepthTexture(screenWidth: screenWidth, screenHeight: screenHeight)
        
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = Assets.Textures[.BaseColorRender_0]
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].loadAction = .clear
    
        descriptor.colorAttachments[1].texture = Assets.Textures[.BaseColorRender_1]
        descriptor.colorAttachments[1].storeAction = .store
        descriptor.colorAttachments[1].loadAction = .clear
    
        descriptor.depthAttachment.texture = Assets.Textures[.BaseDepthRender]
        descriptor.depthAttachment.storeAction = .store
        descriptor.depthAttachment.loadAction = .clear
        
        return descriptor
    }
    
    static func updateBaseRenderPassDescriptor(_ baseRPD: inout MTLRenderPassDescriptor, screenWidth: Int, screenHeight: Int) {
        // --- BASE COLOR 0 TEXTURE ---
        makeBaseTexture(type: .BaseColorRender_0, screenWidth: screenWidth, screenHeight: screenHeight)
        
        // --- BASE COLOR 1 TEXTURE ---
        makeBaseTexture(type: .BaseColorRender_1, screenWidth: screenWidth, screenHeight: screenHeight)
        
        // --- BASE DEPTH TEXTURE ---
        makeBaseDepthTexture(screenWidth: screenWidth, screenHeight: screenHeight)
        
        baseRPD.colorAttachments[0].texture = Assets.Textures[.BaseColorRender_0]
        baseRPD.colorAttachments[1].texture = Assets.Textures[.BaseColorRender_1]
        baseRPD.depthAttachment.texture = Assets.Textures[.BaseDepthRender]
    }
    
    static func makeBaseTexture(type: TextureType, screenWidth: Int, screenHeight: Int) {
        let baseTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Preferences.MainPixelFormat,
                                                                             width: screenWidth,
                                                                             height: screenHeight,
                                                                             mipmapped: false)
        // Defining render target
        baseTextureDescriptor.usage = [.renderTarget, .shaderRead]
        guard let tex = Engine.Device.makeTexture(descriptor: baseTextureDescriptor) else {
            fatalError("[BaseRenderer makeBaseTexture] Failed to create base texture.")
        }
        
        Assets.Textures.setTexture(textureType: type, texture: tex)
    }
    
    static func makeBaseDepthTexture(screenWidth: Int, screenHeight: Int) {
        let depthTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Preferences.MainDepthPixelFormat,
                                                                              width: screenWidth,
                                                                              height: screenHeight,
                                                                              mipmapped: false)
        // Defining render target
        depthTextureDescriptor.usage = [.renderTarget, .shaderRead]
        depthTextureDescriptor.storageMode = .private
        Assets.Textures.setTexture(textureType: .BaseDepthRender,
                                   texture: Engine.Device.makeTexture(descriptor: depthTextureDescriptor)!)
    }
}
