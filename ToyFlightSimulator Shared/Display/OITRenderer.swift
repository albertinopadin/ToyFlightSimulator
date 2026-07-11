//
//  OITRenderer.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/21/23.
//

import MetalKit

final class OITRenderer: Renderer, @unchecked Sendable {
    #if os(iOS)
    public var alreadySetScreenSize: Bool = false  // Hack to prevent iOS from lowering resolution
    #endif
    private var _forwardRenderPassDescriptor: MTLRenderPassDescriptor!
    private let _optimalTileSize: MTLSize = MTLSize(width: 32, height: 16, depth: 1)
    
    override var metalView: MTKView {
        didSet {
            let mv = metalView
            MainActor.assumeIsolated {
                // The final pass renders through view.currentRenderPassDescriptor,
                // and the .Final PSO bakes single-sample color with NO depth
                // attachment — undo whatever sampleCount/depth format a previous
                // (tiled/MSAA) renderer left on the reused MTKView. Matches the
                // fresh-launch view state OIT has always required (see the
                // depth32Float_stencil8 note in Engine.InitRenderer).
                mv.sampleCount = 1
                mv.depthStencilPixelFormat = .invalid
            }
            createForwardRenderPassDescriptor(screenWidth: Int(Renderer.ScreenSize.x),
                                              screenHeight: Int(Renderer.ScreenSize.y))
        }
    }
    
    init() {
        super.init(type: .OrderIndependentTransparency)
    }
    
    init(_ mtkView: MTKView) {
        super.init(mtkView, type: .OrderIndependentTransparency)
        createForwardRenderPassDescriptor(screenWidth: Int(Renderer.ScreenSize.x),
                                          screenHeight: Int(Renderer.ScreenSize.y))
    }
    
    
    private func createForwardRenderPassDescriptor(screenWidth: Int, screenHeight: Int) {
        // --- BASE COLOR 0 TEXTURE ---
        let base0TextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Preferences.MainPixelFormat,
                                                                              width: screenWidth,
                                                                              height: screenHeight,
                                                                              mipmapped: false)
        // Defining render target
        base0TextureDescriptor.usage = [.renderTarget, .shaderRead]
        Assets.Textures.setTexture(textureType: .BaseColorRender_0,
                                   texture: Engine.Device.makeTexture(descriptor: base0TextureDescriptor)!)
        
        // --- BASE DEPTH TEXTURE ---
        let depthTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Preferences.MainDepthPixelFormat,
                                                                              width: screenWidth,
                                                                              height: screenHeight,
                                                                              mipmapped: false)
        // Defining render target
        depthTextureDescriptor.usage = [.renderTarget, .shaderRead]
        depthTextureDescriptor.storageMode = .private
        Assets.Textures.setTexture(textureType: .BaseDepthRender,
                                   texture: Engine.Device.makeTexture(descriptor: depthTextureDescriptor)!)
        
        _forwardRenderPassDescriptor = MTLRenderPassDescriptor()
        _forwardRenderPassDescriptor.colorAttachments[0].texture = Assets.Textures[.BaseColorRender_0]
        _forwardRenderPassDescriptor.colorAttachments[0].storeAction = .store
        _forwardRenderPassDescriptor.colorAttachments[0].loadAction = .clear
        
        _forwardRenderPassDescriptor.depthAttachment.texture = Assets.Textures[.BaseDepthRender]
        _forwardRenderPassDescriptor.depthAttachment.storeAction = .store
        _forwardRenderPassDescriptor.depthAttachment.loadAction = .clear
        _forwardRenderPassDescriptor.depthAttachment.clearDepth = Preferences.MainClearDepth
        
        // For Order-Independent Blending:
        _forwardRenderPassDescriptor.tileWidth = _optimalTileSize.width
        _forwardRenderPassDescriptor.tileHeight = _optimalTileSize.height
        _forwardRenderPassDescriptor.imageblockSampleLength = Graphics.RenderPipelineStates[.OrderIndependentTransparent].imageblockSampleLength
    }
    
    func drawOpaqueObjects(with renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Opaque Object Rendering") {
            renderEncoder.setCullMode(.none)
            let psoType: RenderPipelineStateType = .OpaqueMaterial
            setRenderPipelineState(renderEncoder, state: psoType)
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.CloserOrEqualWrite])
            DrawManager.DrawOpaque(with: renderEncoder, psoType: psoType)
            DrawManager.DrawSky(with: renderEncoder)
        }
    }
    
    func drawTransparentObjects(with renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Transparent Object Rendering") {
            renderEncoder.setCullMode(.none)
            let psoType: RenderPipelineStateType = .OrderIndependentTransparent
            setRenderPipelineState(renderEncoder, state: psoType)
//            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.Blend])
//            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.CloserOrEqualNoWrite])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.CloserNoWrite])
            DrawManager.DrawTransparent(with: renderEncoder, psoType: psoType)
        }
    }
    
    func orderIndependentTransparencyRenderPass(commandBuffer: MTLCommandBuffer) {
        encodeRenderPass(into: commandBuffer,
                   using: _forwardRenderPassDescriptor,
                   label: "Order Independent Transparency Render Pass") { renderEncoder in
            encodeRenderStage(using: renderEncoder, label: "[Tile Render] Init Image Block") {
                setRenderPipelineState(renderEncoder, state: .TileRender)
                renderEncoder.dispatchThreadsPerTile(_optimalTileSize)
            }
            
            SceneManager.SetSceneConstants(with: renderEncoder)
            SceneManager.SetDirectionalLightData(with: renderEncoder)
            drawOpaqueObjects(with: renderEncoder)
            drawTransparentObjects(with: renderEncoder)
            
            encodeRenderStage(using: renderEncoder, label: "Blend Fragments") {
                setRenderPipelineState(renderEncoder, state: .Blend)
                renderEncoder.setCullMode(.none)
                renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.AlwaysNoWrite])
                // Draw full screen quad:
                renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            }
        }
    }
    
    @MainActor
    func finalRenderPass(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        encodeRenderPass(into: commandBuffer, using: renderPassDescriptor, label: "Final Render Pass") { renderEncoder in
            encodeRenderStage(using: renderEncoder, label: "Final Render") {
                setRenderPipelineState(renderEncoder, state: .Final)
                renderEncoder.setFragmentTexture(Assets.Textures[.BaseColorRender_0], index: 0)
                DrawManager.DrawFullScreenQuad(with: renderEncoder)
            }
        }
    }
    
    override func draw(in view: MTKView) {
        render {
            runDrawableCommands { commandBuffer in
                commandBuffer.label = "Order Independent Transparency Render Command Buffer"
                
                orderIndependentTransparencyRenderPass(commandBuffer: commandBuffer)
                // Intermediate renders go here
                
                guard let drawable = view.currentDrawable,
                      let renderPassDescriptor = view.currentRenderPassDescriptor else {
                    return
                }
                
                finalRenderPass(renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
                commandBuffer.present(drawable)
            }
        }
    }
    
    override func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        print("[OIT drawableSizeWillChange] new size: \(size)")
        if !size.width.isNaN && !size.height.isNaN && !size.width.isInfinite && !size.height.isInfinite {
            #if os(iOS)
            if !alreadySetScreenSize {
                updateScreenSize(size: size)
                createForwardRenderPassDescriptor(screenWidth: Int(Renderer.ScreenSize.x),
                                                  screenHeight: Int(Renderer.ScreenSize.y))
                alreadySetScreenSize = true
            } else {
                print("[OIT drawableSizeWillChange] Already set screen size on iOS")
            }
            #endif
            
            #if os(macOS)
            updateScreenSize(size: size)
            createForwardRenderPassDescriptor(screenWidth: Int(Renderer.ScreenSize.x),
                                              screenHeight: Int(Renderer.ScreenSize.y))
            #endif
        }
    }
}
