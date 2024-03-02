//
//  TileDeferredPipeline.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/2/24.
//

import MetalKit

extension RenderPipelineState {
    static func setGBufferPixelFormatsForTiledDeferredPipeline(descriptor: MTLRenderPipelineDescriptor) {
        descriptor.colorAttachments[TFSRenderTargetAlbedo.index].pixelFormat = TiledDeferredGBufferTextures.albedoPixelFormat
        descriptor.colorAttachments[TFSRenderTargetNormal.index].pixelFormat = TiledDeferredGBufferTextures.normalPixelFormat
        descriptor.colorAttachments[TFSRenderTargetPosition.index].pixelFormat =
            TiledDeferredGBufferTextures.positionPixelFormat
    }
}

struct TileDeferredGBufferPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        createRenderPipelineState(label: "Tile Deferred GBuffer") { descriptor in
            descriptor.vertexFunction = Graphics.Shaders[.TiledDeferredGBufferVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.TiledDeferredGBufferFragment]
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
        }
    }()
}
