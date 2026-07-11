//
//  TiledDeferredRenderer.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/1/24.
//  Heavily inspired from https://www.kodeco.com/books/metal-by-tutorials/v4.0/chapters/15-tile-based-deferred-rendering

import MetalKit

final class TiledDeferredRenderer: Renderer, ShadowRendering, ParticleRendering, TiledGBufferRendering, LateDrawablePresenting, @unchecked Sendable {
    private let icosahedron = IcosahedronMesh()

    var gBufferTextures = TiledDeferredGBufferTextures()

    var shadowMapArray: MTLTexture
    var shadowRenderPassDescriptors: [MTLRenderPassDescriptor]

    // App-owned color target for the GBuffer/lighting pass; sampled by the composite pass.
    var lightingResolveTexture: MTLTexture!
    let compositeRenderPassDescriptor: MTLRenderPassDescriptor = TiledDeferredRenderer.makeCompositeRenderPassDescriptor()

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
        // Lighting attachment now writes into app-owned lightingResolveTexture, sampled by composite pass.
        descriptor.colorAttachments[TFSRenderTargetLighting.index].storeAction = .store
        return descriptor
    }()
    
    override var metalView: MTKView {
        didSet {
            let mv = metalView
            MainActor.assumeIsolated {
                mv.depthStencilPixelFormat = .depth32Float
                mv.clearDepth = Preferences.MainClearDepth
                // The MTKView is reused across runtime renderer switches; an
                // MSAA renderer may have left sampleCount = 4 on it.
                mv.sampleCount = 1
            }

            let drawableSize = CGSize(width: Double(Renderer.ScreenSize.x), height: Double(Renderer.ScreenSize.y))
            updateDrawableSize(size: drawableSize)
        }
    }
    
    init() {
        shadowMapArray = Self.makeShadowMapArray(label: "Shadow Texture Array")
        shadowRenderPassDescriptors = Self.makeShadowRenderPassDescriptors(shadowArray: shadowMapArray)
        super.init(type: .TiledDeferred)
    }

    init(_ mtkView: MTKView) {
        shadowMapArray = Self.makeShadowMapArray(label: "Shadow Texture Array")
        shadowRenderPassDescriptors = Self.makeShadowRenderPassDescriptors(shadowArray: shadowMapArray)
        super.init(mtkView, type: .TiledDeferred)
    }
    
    func encodeGBufferStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Tiled GBuffer Stage") {
            let psoType: RenderPipelineStateType = .TiledDeferredGBuffer
            setRenderPipelineState(renderEncoder, state: psoType)
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.TiledDeferredGBuffer])
            renderEncoder.setFragmentTexture(shadowMapArray, index: TFSTextureIndexShadow.index)
            DrawManager.DrawOpaque(with: renderEncoder, psoType: psoType)
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
            setRenderPipelineState(renderEncoder, state: .TiledDeferredDirectionalLight)
            // Draw full screen quad
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
    }
    
    func encodePointLightStage(using renderEncoder: MTLRenderCommandEncoder) {
        let pointLightCount = LightManager.PointLightCount
        if pointLightCount > 0 {
            encodeRenderStage(using: renderEncoder, label: "Point Light Stage") {
                setRenderPipelineState(renderEncoder, state: .TiledDeferredPointLight)
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
                                                    instanceCount: pointLightCount)
            }
        }
    }
    
    func encodeTransparencyStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Transparent Object Rendering") {
            let psoType: RenderPipelineStateType = .TiledDeferredTransparency
            setRenderPipelineState(renderEncoder, state: psoType)
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.TiledDeferredGBuffer])
            DrawManager.DrawTransparent(with: renderEncoder, psoType: psoType)
        }
    }
    
    override func draw(in view: MTKView) {
        render {
            // Early CB: shadow only.
            runDrawableCommands { commandBuffer in
                commandBuffer.label = "Shadow Commands"
                encodeShadowPassTiledDeferred(into: commandBuffer)
            }

            // Early CB: all view-independent work, into app-owned lightingResolveTexture.
            runDrawableCommands { commandBuffer in
                commandBuffer.label = "GBuffer & Lighting Commands"

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

            // Late CB: acquire drawable, composite, present.
            guard let drawable = view.currentDrawable else { return }

            runDrawableCommands { commandBuffer in
                commandBuffer.label = "Composite + Present"
                compositeRenderPassDescriptor
                    .colorAttachments[TFSRenderTargetLighting.index].texture = drawable.texture

                encodeRenderPass(into: commandBuffer,
                                 using: compositeRenderPassDescriptor,
                                 label: "Composite Pass") { renderEncoder in
                    encodeCompositeStage(using: renderEncoder)
                }

                commandBuffer.present(drawable)
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

        // App-owned color target bound once per resize; the early CB never touches the view.
        lightingResolveTexture = Self.makeLightingResolveTexture(size: size, label: "TiledDeferred Lighting Resolve")
        tiledDeferredRenderPassDescriptor
            .colorAttachments[TFSRenderTargetLighting.index].texture = lightingResolveTexture

        // Re-set GBuffer textures in the render pass descriptor after they have been reallocated by a resize
        setGBufferTextures(tiledDeferredRenderPassDescriptor)
        updateScreenSize(size: size)
    }
}
