//
//  Tessellatable.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/22/25.
//

import MetalKit

protocol Tessellatable: GameObject {
    var patches: (horizontal: Int, vertical: Int) { get }
    var patchCount: Int { get }
    var controlPointsBuffer: MTLBuffer? { get }
    var tessellationFactorsBuffer: MTLBuffer? { get }
    
    static func createControlPoints(patches: (horizontal: Int, vertical: Int),
                                    size: (width: Float, height: Float)) -> [ControlPoint]
    
    func computeUpdate(_ computeEncoder: MTLComputeCommandEncoder)
    func setRenderState(_ renderEncoder: MTLRenderCommandEncoder)
}
