//
//  RenderPipelineState.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2/27/24.
//

import MetalKit

protocol RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState { get set }
}

extension RenderPipelineState {
    static func createRenderPipelineState(descriptor: MTLRenderPipelineDescriptor) -> MTLRenderPipelineState {
        do {
            return try Engine.Device.makeRenderPipelineState(descriptor: descriptor)
        } catch let error as NSError {
            fatalError("ERROR::CREATE::RENDER_PIPELINE_STATE::__::\(error) for \(descriptor.label!)")
        }
    }
    
    static func createTileRenderPipelineState(tileRenderPipelineDescriptor: MTLTileRenderPipelineDescriptor) ->
        MTLRenderPipelineState {
        do {
            return try Engine.Device.makeRenderPipelineState(tileDescriptor: tileRenderPipelineDescriptor,
                                                             options: .bindingInfo,
                                                             reflection: nil)
        } catch {
            fatalError(error.localizedDescription)
        }
    }
    
    static func createRenderPipelineState(label: String,
                                          block: (MTLRenderPipelineDescriptor) -> Void) -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = label
        block(descriptor)
        do {
            return try Engine.Device.makeRenderPipelineState(descriptor: descriptor)
        } catch let error as NSError {
            fatalError("ERROR::CREATE::RENDER_PIPELINE_STATE::__::\(error) for \(label)")
        }
    }
    
    static func createTileRenderPipelineState(label: String,
                                              tileBlock: (MTLTileRenderPipelineDescriptor) -> Void) -> MTLRenderPipelineState {
        let descriptor = MTLTileRenderPipelineDescriptor()
        descriptor.label = label
        tileBlock(descriptor)
        do {
            return try Engine.Device.makeRenderPipelineState(tileDescriptor: descriptor,
                                                             options: .argumentInfo,
                                                             reflection: nil)
        } catch {
            fatalError(error.localizedDescription)
        }
    }
    
    static func enableBlending(colorAttachmentDescriptor: MTLRenderPipelineColorAttachmentDescriptor) {
        colorAttachmentDescriptor.isBlendingEnabled = true
        colorAttachmentDescriptor.sourceRGBBlendFactor = .sourceAlpha
        colorAttachmentDescriptor.destinationRGBBlendFactor = .oneMinusSourceAlpha
        colorAttachmentDescriptor.rgbBlendOperation = .add
        colorAttachmentDescriptor.sourceAlphaBlendFactor = .sourceAlpha
        colorAttachmentDescriptor.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        colorAttachmentDescriptor.alphaBlendOperation = .add
    }
    
    static func getRenderPipelineDescriptor(vertexDescriptorType: VertexDescriptorType,
                                            vertexShaderType: ShaderType,
                                            fragmentShaderType: ShaderType,
                                            enableAlphaBlending: Bool = true,
                                            colorAttachments: Int = 1) -> MTLRenderPipelineDescriptor {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        for i in 0..<colorAttachments {
            renderPipelineDescriptor.colorAttachments[i].pixelFormat = Preferences.MainPixelFormat
        }
        renderPipelineDescriptor.depthAttachmentPixelFormat = Preferences.MainDepthPixelFormat
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[vertexDescriptorType]
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[vertexShaderType]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[fragmentShaderType]
        
        if enableAlphaBlending {
            enableBlending(colorAttachmentDescriptor: renderPipelineDescriptor.colorAttachments[TFSRenderTargetLighting.index])
        }
        
        return renderPipelineDescriptor
    }
}
