//
//  SinglePassDeferredRenderer.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/28/23.
//

import MetalKit

final class SinglePassDeferredLightingRenderer: Renderer, ShadowRendering {
    // Create quad for fullscreen composition drawing
    private let _quadVertices: [TFSSimpleVertex] = [
        .init(position: .init(x: -1, y: -1)),
        .init(position: .init(x: -1, y:  1)),
        .init(position: .init(x:  1, y: -1)),
        
        .init(position: .init(x:  1, y: -1)),
        .init(position: .init(x: -1, y:  1)),
        .init(position: .init(x:  1, y:  1))
    ]
    
    private let _quadVertexBuffer: MTLBuffer!
    
    var shadowMap: MTLTexture
    var shadowRenderPassDescriptor: MTLRenderPassDescriptor
    // For protocol conformance:
    var shadowResolveTexture: MTLTexture? = nil
    
    private let _gBufferAndLightingRenderPassDescriptor: MTLRenderPassDescriptor = {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[TFSRenderTargetAlbedo.index].storeAction = .dontCare
        descriptor.colorAttachments[TFSRenderTargetNormal.index].storeAction = .dontCare
        descriptor.colorAttachments[TFSRenderTargetDepth.index].storeAction = .dontCare
        
        // To make empty space (no nodes/skybox) look black instead of Snow...
        descriptor.colorAttachments[TFSRenderTargetLighting.index].loadAction = .clear
        descriptor.colorAttachments[TFSRenderTargetLighting.index].clearColor = Preferences.ClearColor
        return descriptor
    }()
    
    private var gBufferTextures = SinglePassDeferredGBufferTextures()
    
    override var metalView: MTKView {
        didSet {
            let mv = metalView
            MainActor.assumeIsolated {
                mv.depthStencilPixelFormat = .depth32Float_stencil8
            }
            let drawableSize = CGSize(width: Double(Renderer.ScreenSize.x), height: Double(Renderer.ScreenSize.y))
            updateDrawableSize(size: drawableSize)
        }
    }
    
    
    
    init() {
        _quadVertexBuffer = Engine.Device.makeBuffer(bytes: _quadVertices,
                                                     length: MemoryLayout<TFSSimpleVertex>.stride * _quadVertices.count)
        shadowMap = Self.makeShadowMap(label: "Shadow Map")
        shadowRenderPassDescriptor = Self.makeShadowRenderPassDescriptor(shadowMapTexture: shadowMap)
        super.init(type: .SinglePassDeferredLighting)
    }
    
    init(_ mtkView: MTKView) {
        _quadVertexBuffer = Engine.Device.makeBuffer(bytes: _quadVertices,
                                                     length: MemoryLayout<TFSSimpleVertex>.stride * _quadVertices.count)
        shadowMap = Self.makeShadowMap(label: "Shadow Map")
        shadowRenderPassDescriptor = Self.makeShadowRenderPassDescriptor(shadowMapTexture: shadowMap)
        super.init(mtkView, type: .SinglePassDeferredLighting)
        let drawableSize = CGSize(width: Double(Renderer.ScreenSize.x), height: Double(Renderer.ScreenSize.y))
        print("[SPDL Renderer init] drawable size: \(drawableSize)")
        updateDrawableSize(size: drawableSize)
    }
    
    func setGBufferTextures(renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.setFragmentTexture(gBufferTextures.albedoSpecular, index: TFSRenderTargetAlbedo.index)
        renderEncoder.setFragmentTexture(gBufferTextures.normalShadow, index: TFSRenderTargetNormal.index)
        renderEncoder.setFragmentTexture(gBufferTextures.depth, index: TFSRenderTargetDepth.index)
    }
    
    func setGBufferTextures(_ renderPassDescriptor: MTLRenderPassDescriptor) {
        renderPassDescriptor.colorAttachments[TFSRenderTargetAlbedo.index].texture = gBufferTextures.albedoSpecular
        renderPassDescriptor.colorAttachments[TFSRenderTargetNormal.index].texture = gBufferTextures.normalShadow
        renderPassDescriptor.colorAttachments[TFSRenderTargetDepth.index].texture = gBufferTextures.depth
    }
    
    func encodeGBufferStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "GBuffer Generation Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.SinglePassDeferredGBufferMaterial])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.GBufferGeneration])
            // NOTE: For some reason, setting cull mode to back makes meshes appear 'extruded' or turned inside out.
//            renderEncoder.setCullMode(.back)
            renderEncoder.setStencilReferenceValue(128)
            renderEncoder.setFragmentTexture(shadowMap, index: TFSTextureIndexShadow.index)
            DrawManager.Draw(with: renderEncoder)
        }
    }
    
    func encodeDirectionalLightingStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Directional Lighting Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.SinglePassDeferredDirectionalLighting])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.DirectionalLighting])
            renderEncoder.setCullMode(.back)
            renderEncoder.setStencilReferenceValue(128)
            renderEncoder.setVertexBuffer(_quadVertexBuffer,
                                          offset: 0,
                                          index: TFSBufferIndexMeshPositions.index)
            
            // Draw full screen quad
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
    }
    
    // TODO: Need to create proper RPS and DSS:
    func encodeTransparencyStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Transparent Object Rendering") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.SinglePassDeferredTransparency])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.TiledDeferredGBuffer])
            DrawManager.Draw(with: renderEncoder, withTransparency: true)
        }
    }
    
    func encodeLightMaskStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Point Light Mask Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.LightMask])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.LightMask])
            renderEncoder.setStencilReferenceValue(128)
            renderEncoder.setCullMode(.front)
            SceneManager.SetPointLightConstants(with: renderEncoder)
//            SceneManager.RenderPointLightMeshes(with: renderEncoder)
            DrawManager.DrawIcosahedrons(with: renderEncoder)
        }
    }
    
    func encodePointLightStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Point Light Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.SinglePassDeferredPointLight])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.PointLight])  // <--- This is causing issues
//            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.Less])
            renderEncoder.setStencilReferenceValue(128)
            renderEncoder.setCullMode(.back)
//            SceneManager.SetPointLightConstants(renderCommandEncoder: renderEncoder)
            SceneManager.SetPointLightData(with: renderEncoder)
            DrawManager.DrawPointLights(with: renderEncoder)
        }
    }
    
    func encodeSkyboxStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Skybox Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.Skybox])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.Skybox])
//            renderEncoder.setCullMode(.front)
            renderEncoder.setCullMode(.back)  //<-- This or not setting the cull mode works. WTF?
            DrawManager.DrawSky(with: renderEncoder)
        }
    }
    
    // For testing:
    func encodeIcosahedronStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Icosahedron Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.Icosahedron])
//            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.Less])
//            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.DepthWriteDisabled])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.PointLight])
            renderEncoder.setStencilReferenceValue(128)
            // TODO: Doesn't quite work
            DrawManager.DrawIcosahedrons(with: renderEncoder)
        }
    }
    
    override func draw(in view: MTKView) {
        render {
            runDrawableCommands { commandBuffer in
                commandBuffer.label = "Shadow Commands"
                encodeShadowMapPass(into: commandBuffer)
            }
            
            runDrawableCommands { commandBuffer in
                commandBuffer.label = "GBuffer & Lighting Commands"
                
                if let drawableTexture = view.currentDrawable?.texture {
                    _gBufferAndLightingRenderPassDescriptor.colorAttachments[TFSRenderTargetLighting.index].texture = drawableTexture
                    _gBufferAndLightingRenderPassDescriptor.depthAttachment.texture = view.depthStencilTexture
                    _gBufferAndLightingRenderPassDescriptor.stencilAttachment.texture = view.depthStencilTexture
                    
                    encodeRenderPass(into: commandBuffer, using: _gBufferAndLightingRenderPassDescriptor, label: "GBuffer & Lighting Pass") {
                        renderEncoder in
                        SceneManager.SetSceneConstants(with: renderEncoder)
                        SceneManager.SetDirectionalLightConstants(with: renderEncoder)
                        
                        encodeGBufferStage(using: renderEncoder)
                        encodeDirectionalLightingStage(using: renderEncoder)
                        encodeTransparencyStage(using: renderEncoder)
                        encodeLightMaskStage(using: renderEncoder)
                        encodePointLightStage(using: renderEncoder)
    //                    encodeIcosahedronStage(using: renderEncoder)
                        encodeSkyboxStage(using: renderEncoder)
                    }
                }
                
                if let drawable = view.currentDrawable {
                    commandBuffer.present(drawable)
                }
            }
        }
    }
    
    override func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        print("[SinglePass drawableSizeWillChange] new size: \(size)")
        if !size.width.isNaN && !size.height.isNaN && !size.width.isInfinite && !size.height.isInfinite {
            updateDrawableSize(size: size)
        }
    }
    
    func updateDrawableSize(size: CGSize) {
        gBufferTextures.makeTextures(device: Engine.Device, size: size, storageMode: .memoryless)
        
        // Re-set GBuffer textures in the view render pass descriptor after they have been reallocated by a resize
        setGBufferTextures(_gBufferAndLightingRenderPassDescriptor)
        updateScreenSize(size: size)
    }
}
