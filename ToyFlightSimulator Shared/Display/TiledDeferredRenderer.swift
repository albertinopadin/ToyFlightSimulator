//
//  TiledDeferredRenderer.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/1/24.
//  Heavily inspired from https://www.kodeco.com/books/metal-by-tutorials/v4.0/chapters/15-tile-based-deferred-rendering

import MetalKit

class TiledDeferredRenderer: Renderer {
    private static var ShadowTextureSize: Int = 4096
    
    private var gBufferTextures = TiledDeferredGBufferTextures()
    
    private var shadowTexture: MTLTexture
    private var shadowRenderPassDescriptor: MTLRenderPassDescriptor
    
    private let tiledDeferredRenderPassDescriptor: MTLRenderPassDescriptor = {
        let descriptor = MTLRenderPassDescriptor()
        
        let renderTargets: [TFSRenderTargetIndices] = [
            TFSRenderTargetAlbedo,
            TFSRenderTargetNormal,
            TFSRenderTargetPosition
        ]
        
        for renderTarget in renderTargets {
            descriptor.colorAttachments[renderTarget.index].loadAction = .clear
            descriptor.colorAttachments[renderTarget.index].storeAction = .dontCare
        }
        
        // To make empty space (no nodes/skybox) look black instead of Snow...
        descriptor.colorAttachments[TFSRenderTargetLighting.index].loadAction = .clear
        descriptor.colorAttachments[TFSRenderTargetLighting.index].clearColor = Preferences.ClearColor
        return descriptor
    }()
    
    override var metalView: MTKView {
        didSet {
//            metalView.depthStencilPixelFormat = .depth32Float_stencil8  // ???
//            metalView.depthStencilPixelFormat = TiledDeferredGBufferTextures.depthPixelFormat
            metalView.depthStencilPixelFormat = .depth32Float
            let drawableSize = CGSize(width: Double(Renderer.ScreenSize.x), height: Double(Renderer.ScreenSize.y))
            updateDrawableSize(size: drawableSize)
        }
    }
    
    static func makeShadowTexture(label: String) -> MTLTexture {
        let shadowTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,
                                                                               width: Self.ShadowTextureSize,
                                                                               height: Self.ShadowTextureSize,
                                                                               mipmapped: false)
        shadowTextureDescriptor.resourceOptions = .storageModePrivate
        shadowTextureDescriptor.usage = [.renderTarget, .shaderRead]
        guard let shadowTex = Engine.Device.makeTexture(descriptor: shadowTextureDescriptor) else {
            fatalError("Failed to create shadow texture")
        }
        shadowTex.label = label
        return shadowTex
    }
    
    static func makeShadowRenderPassDescriptor(shadowTexture: MTLTexture) -> MTLRenderPassDescriptor {
        let mShadowRenderPassDescriptor = MTLRenderPassDescriptor()
        mShadowRenderPassDescriptor.depthAttachment.texture = shadowTexture
        mShadowRenderPassDescriptor.depthAttachment.loadAction = .clear
        mShadowRenderPassDescriptor.depthAttachment.storeAction = .store
        return mShadowRenderPassDescriptor
    }
    
    init() {
        shadowTexture = Self.makeShadowTexture(label: "Shadow Texture")
        shadowRenderPassDescriptor = Self.makeShadowRenderPassDescriptor(shadowTexture: shadowTexture)
        super.init(type: .TiledDeferred)
    }
    
    init(_ mtkView: MTKView) {
        shadowTexture = Self.makeShadowTexture(label: "Shadow Texture")
        shadowRenderPassDescriptor = Self.makeShadowRenderPassDescriptor(shadowTexture: shadowTexture)
        super.init(mtkView, type: .TiledDeferred)
    }
    
    func setGBufferTextures(_ renderPassDescriptor: MTLRenderPassDescriptor) {
        renderPassDescriptor.colorAttachments[TFSRenderTargetAlbedo.index].texture = gBufferTextures.albedoTexture
        renderPassDescriptor.colorAttachments[TFSRenderTargetNormal.index].texture = gBufferTextures.normalTexture
        renderPassDescriptor.colorAttachments[TFSRenderTargetPosition.index].texture = gBufferTextures.positionTexture
        setDepthAndStencilTextures(renderPassDescriptor)
    }
    
    func setDepthAndStencilTextures(_ renderPassDescriptor: MTLRenderPassDescriptor) {
        renderPassDescriptor.depthAttachment.texture = gBufferTextures.depthTexture
        renderPassDescriptor.depthAttachment.storeAction = .dontCare
        renderPassDescriptor.stencilAttachment.texture = gBufferTextures.depthTexture
        renderPassDescriptor.stencilAttachment.storeAction = .dontCare
    }
    
    func encodeShadowPass(into commandBuffer: MTLCommandBuffer) {
        encodePass(into: commandBuffer, using: shadowRenderPassDescriptor, label: "Shadow Pass") { renderEncoder in
            encodeStage(using: renderEncoder, label: "Shadow Texture Stage") {
                renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledDeferredShadow])
                renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.TiledDeferredShadow])
                SceneManager.SetDirectionalLightConstants(with: renderEncoder)
                SceneManager.RenderShadows(with: renderEncoder)
            }
        }
    }
    
    func encodeGBufferStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeStage(using: renderEncoder, label: "Tiled GBuffer Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledDeferredGBuffer])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.TiledDeferredGBuffer])
            renderEncoder.setFragmentTexture(shadowTexture, index: TFSTextureIndexShadow.index)
            SceneManager.SetDirectionalLightConstants(with: renderEncoder)
            SceneManager.RenderTiledDeferredGBuffer(with: renderEncoder)
        }
    }
    
    func encodeDirectionalLightStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeStage(using: renderEncoder, label: "Directional Light Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledDeferredDirectionalLight])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.TiledDeferredLight])
            SceneManager.SetSceneConstants(with: renderEncoder)
            SceneManager.SetDirectionalLightConstants(with: renderEncoder)
            // Draw full screen quad
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
    }
    
    override func draw(in view: MTKView) {
        // FIXME - this should be set independent of the frame rate:
        SceneManager.Update(deltaTime: 1.0 / Float(view.preferredFramesPerSecond))
        
//        let commandBuffer = beginDrawableCommands()
        var commandBuffer = beginFrame()
        commandBuffer.label = "Shadow Commands"
        
        encodeShadowPass(into: commandBuffer)
        commandBuffer.commit()
        
        commandBuffer = beginDrawableCommands()
        commandBuffer.label = "GBuffer & Lighting Commands"
        
        if let drawableTexture = view.currentDrawable?.texture {
            tiledDeferredRenderPassDescriptor.colorAttachments[TFSRenderTargetLighting.index].texture = drawableTexture
//            tiledDeferredRenderPassDescriptor.depthAttachment.texture = view.depthStencilTexture
//            tiledDeferredRenderPassDescriptor.stencilAttachment.texture = view.depthStencilTexture
            
            // Possible redundant binding:
//            tiledDeferredRenderPassDescriptor.depthAttachment.texture = gBufferTextures.depthTexture
//            tiledDeferredRenderPassDescriptor.stencilAttachment.texture = gBufferTextures.depthTexture
            
            encodePass(into: commandBuffer,
                       using: tiledDeferredRenderPassDescriptor,
                       label: "GBuffer & Lighting Pass") { renderEncoder in
                SceneManager.SetSceneConstants(with: renderEncoder)
                
                encodeGBufferStage(using: renderEncoder)
                encodeDirectionalLightStage(using: renderEncoder)
//                encodePointLightStage(using: renderEncoder)
            }
        }
        
        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        
        commandBuffer.commit()
    }
    
    override func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        if !size.width.isNaN && !size.height.isNaN && !size.width.isInfinite && !size.height.isInfinite {
            updateDrawableSize(size: size)
        }
    }
    
    func updateDrawableSize(size: CGSize) {
        gBufferTextures.makeTextures(device: Engine.Device, size: size, storageMode: .memoryless)
        // Re-set GBuffer textures in the view render pass descriptor after they have been reallocated by a resize
        setGBufferTextures(tiledDeferredRenderPassDescriptor)
        updateScreenSize(size: size)
    }
}
