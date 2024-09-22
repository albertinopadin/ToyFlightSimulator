//
//  OITRenderer.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/21/23.
//

import MetalKit

class OITRenderer: Renderer {
    #if os(iOS)
    public var alreadySetScreenSize: Bool = false  // Hack to prevent iOS from lowering resolution
    #endif
    private var _forwardRenderPassDescriptor: MTLRenderPassDescriptor!
    private let _optimalTileSize: MTLSize = MTLSize(width: 32, height: 16, depth: 1)
    
    override var metalView: MTKView {
        didSet {
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
        
        // For Order-Independent Blending:
        _forwardRenderPassDescriptor.tileWidth = _optimalTileSize.width
        _forwardRenderPassDescriptor.tileHeight = _optimalTileSize.height
        _forwardRenderPassDescriptor.imageblockSampleLength = Graphics.RenderPipelineStates[.OrderIndependentTransparent].imageblockSampleLength
    }
    
    func drawOpaqueObjects(with renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Opaque Object Rendering") {
            renderEncoder.setCullMode(.none)
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.OpaqueMaterial])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.LessEqualWrite])
            DrawManager.Draw(with: renderEncoder)
            DrawManager.DrawSky(with: renderEncoder)
        }
    }
    
    func drawTransparentObjects(with renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Transparent Object Rendering") {
            renderEncoder.setCullMode(.none)
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.OrderIndependentTransparent])
//            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.Blend])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.LessEqualNoWrite])
            DrawManager.Draw(with: renderEncoder, withTransparency: true)
        }
    }
    
    func orderIndependentTransparencyRenderPass(view: MTKView, commandBuffer: MTLCommandBuffer) {
        encodeRenderPass(into: commandBuffer,
                   using: _forwardRenderPassDescriptor,
                   label: "Order Independent Transparency Render Pass") { renderEncoder in
            encodeRenderStage(using: renderEncoder, label: "[Tile Render] Init Image Block") {
                renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TileRender])
                renderEncoder.dispatchThreadsPerTile(_optimalTileSize)
            }
            
            SceneManager.SetSceneConstants(with: renderEncoder)
            SceneManager.SetDirectionalLightData(with: renderEncoder)
            drawOpaqueObjects(with: renderEncoder)
            drawTransparentObjects(with: renderEncoder)
            
            encodeRenderStage(using: renderEncoder, label: "Blend Fragments") {
                renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.Blend])
                renderEncoder.setCullMode(.none)
                renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.AlwaysNoWrite])
                // Draw full screen quad:
                renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            }
        }
    }
    
    func finalRenderPass(view: MTKView, commandBuffer: MTLCommandBuffer) {
        encodeRenderPass(into: commandBuffer, using: view.currentRenderPassDescriptor!, label: "Final Render Pass") { renderEncoder in
            encodeRenderStage(using: renderEncoder, label: "Final Render") {
                renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.Final])
                renderEncoder.setFragmentTexture(Assets.Textures[.BaseColorRender_0], index: 0)
                DrawManager.DrawFullScreenQuad(with: renderEncoder)
            }
        }
    }
    
    override func draw(in view: MTKView) {
        super.draw(in: view)
        
        runDrawableCommands { commandBuffer in
            commandBuffer.label = "Order Independent Transparency Render Command Buffer"
            
            orderIndependentTransparencyRenderPass(view: view, commandBuffer: commandBuffer)
            // Intermediate renders go here
            finalRenderPass(view: view, commandBuffer: commandBuffer)
            
            commandBuffer.present(view.currentDrawable!)
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
