//
//  TessellationRendering.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/13/25.
//

import MetalKit

protocol TessellationRendering: ComputePassEncoding, RenderPassEncoding {}

extension TessellationRendering {
    var edgeFactors: [Float] { [4] }
    var insideFactors: [Float] { [4] }
    
    func encodeTessellationComputePass(into commandBuffer: MTLCommandBuffer) {
        encodeComputePass(into: commandBuffer, label: "Tessellation Compute Pass") { computeEncoder in
            let tessellationComputePipelineState = Graphics.ComputePipelineStates[.Tessellation]
            computeEncoder.setComputePipelineState(tessellationComputePipelineState)
            
            computeEncoder.setBytes(self.edgeFactors, length: Float.size * self.edgeFactors.count, index: 0)
            computeEncoder.setBytes(self.insideFactors, length: Float.size * self.insideFactors.count, index: 1)
            
            var cameraPosition = float4(CameraManager.GetCurrentCameraPosition(), 0)
            computeEncoder.setBytes(&cameraPosition, length: float4.stride, index: 3)
            
            ComputeManager.ComputeTerrainTessellation(with: computeEncoder)
        }
    }
    
    func encodeTessellationRenderPass(with renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Tessellation") {
//            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TessellationGBuffer])
            setRenderPipelineState(renderEncoder, state: .TessellationGBuffer)
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.TiledDeferredGBuffer])
            DrawManager.DrawTessellatables(with: renderEncoder)
        }
    }
}

final class TessellatedRendering: TessellationRendering {
    public static let maxTessellation: Int = Engine.Device.supportsFamily(.apple5) ? 64 : 16
}
