//
//  RenderPassEncoding.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/11/25.
//

import MetalKit

protocol RenderPassEncoding {}

extension RenderPassEncoding {
    func setRenderPipelineState(_ renderEncoder: MTLRenderCommandEncoder, state: RenderPipelineStateType) {
        RenderState.PreviousPipelineStateType = RenderState.CurrentPipelineStateType
        RenderState.CurrentPipelineStateType = state
        renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[state])
    }
    
    func encodeRenderPass(into commandBuffer: MTLCommandBuffer,
                          using descriptor: MTLRenderPassDescriptor,
                          label: String,
                          _ encodingBlock: (MTLRenderCommandEncoder) -> Void) {
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            fatalError("Failed to make render command encoder with: \(descriptor.description)")
        }
        
        renderEncoder.label = label
        encodingBlock(renderEncoder)
        renderEncoder.endEncoding()
    }
    
    func encodeRenderStage(using renderEncoder: MTLRenderCommandEncoder, label: String, _ encodingBlock: () -> Void) {
        renderEncoder.pushDebugGroup(label)
        encodingBlock()
        renderEncoder.popDebugGroup()
    }
}
