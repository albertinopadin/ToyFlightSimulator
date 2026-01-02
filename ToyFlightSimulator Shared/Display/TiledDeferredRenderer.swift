//
//  TiledDeferredRenderer.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/1/24.
//  Heavily inspired from https://www.kodeco.com/books/metal-by-tutorials/v4.0/chapters/15-tile-based-deferred-rendering

import MetalKit

final class TiledDeferredRenderer: Renderer, ShadowRendering, ParticleRendering {
    private let icosahedron = IcosahedronMesh()
    
    private var gBufferTextures = TiledDeferredGBufferTextures()
    
    var shadowMap: MTLTexture
    var shadowRenderPassDescriptor: MTLRenderPassDescriptor
    // For protocol conformance:
    var shadowResolveTexture: MTLTexture? = nil
    
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
            let mv = metalView
            MainActor.assumeIsolated {
                mv.depthStencilPixelFormat = .depth32Float
            }
            
            let drawableSize = CGSize(width: Double(Renderer.ScreenSize.x), height: Double(Renderer.ScreenSize.y))
            updateDrawableSize(size: drawableSize)
        }
    }
    
    init() {
        shadowMap = Self.makeShadowMap(label: "Shadow Texture")
        shadowRenderPassDescriptor = Self.makeShadowRenderPassDescriptor(shadowMapTexture: shadowMap)
        super.init(type: .TiledDeferred)
    }
    
    init(_ mtkView: MTKView) {
        shadowMap = Self.makeShadowMap(label: "Shadow Texture")
        shadowRenderPassDescriptor = Self.makeShadowRenderPassDescriptor(shadowMapTexture: shadowMap)
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
    
    func encodeGBufferStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Tiled GBuffer Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledDeferredGBuffer])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.TiledDeferredGBuffer])
            renderEncoder.setFragmentTexture(shadowMap, index: TFSTextureIndexShadow.index)
            DrawManager.DrawOpaque(with: renderEncoder)
        }
    }
    
    func encodeLightingStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Lighting Stage") {
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.TiledDeferredLight])
            encodeDirectionalLightStage(using: renderEncoder)
            encodePointLightStage(using: renderEncoder)
        }
    }
    
    func encodeDirectionalLightStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Directional Light Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledDeferredDirectionalLight])
            // Draw full screen quad
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
    }
    
    func encodePointLightStage(using renderEncoder: MTLRenderCommandEncoder) {
        let pointLights = LightManager.GetPointLightData()
        if !pointLights.isEmpty {
            encodeRenderStage(using: renderEncoder, label: "Point Light Stage") {
                renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledDeferredPointLight])
                guard let mesh = self.icosahedron._metalKitMesh,
                      let submesh = self.icosahedron.submeshes.first else {
                    print("No icosahedron mesh or submesh found.")
                    return
                }
                for (index, vertexBuffer) in mesh.vertexBuffers.enumerated() {
                    renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: 0, index: index)
                }
                renderEncoder.drawIndexedPrimitives(type: .triangle,
                                                    indexCount: submesh.indexCount,
                                                    indexType: submesh.indexType,
                                                    indexBuffer: submesh.indexBuffer,
                                                    indexBufferOffset: submesh.indexBufferOffset,
                                                    instanceCount: pointLights.count)
            }
        }
    }
    
    func encodeTransparencyStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Transparent Object Rendering") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledDeferredTransparency])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.TiledDeferredGBuffer])
            DrawManager.DrawTransparent(with: renderEncoder)
        }
    }
    
    override func draw(in view: MTKView) {
        render {
            runDrawableCommands { commandBuffer in
                commandBuffer.label = "Shadow Commands"
                encodeShadowPassTiledDeferred(into: commandBuffer)
            }
            
            runDrawableCommands { commandBuffer in
                commandBuffer.label = "GBuffer & Lighting Commands"
                
                if let drawableTexture = view.currentDrawable?.texture {
                    tiledDeferredRenderPassDescriptor.colorAttachments[TFSRenderTargetLighting.index].texture = drawableTexture
                    
                    encodeParticleComputePass(into: commandBuffer)
                    
                    encodeRenderPass(into: commandBuffer,
                                     using: tiledDeferredRenderPassDescriptor,
                                     label: "GBuffer & Lighting Pass") { renderEncoder in
                        SceneManager.SetSceneConstants(with: renderEncoder)
                        SceneManager.SetDirectionalLightConstants(with: renderEncoder)
                        SceneManager.SetPointLightData(with: renderEncoder)
                        
                        encodeGBufferStage(using: renderEncoder)
                        encodeLightingStage(using: renderEncoder)
                        encodeTransparencyStage(using: renderEncoder)
                        encodeParticleRenderStage(using: renderEncoder)
                    }
                }
                
                if let drawable = view.currentDrawable {
                    commandBuffer.present(drawable)
                }
            }
        }
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
