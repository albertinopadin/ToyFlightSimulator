//
//  TerrainObject.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/19/25.
//

import MetalKit

final class TerrainObject: GameObject, Tessellatable {
    var patches: (horizontal: Int, vertical: Int) { (horizontal: 32, vertical: 32) }
    var patchCount: Int { patches.horizontal * patches.vertical }
    
    var controlPointsBuffer: MTLBuffer?
    var tessellationFactorsBuffer: MTLBuffer?
    
    var terrain: Terrain
    let heightMap: MTLTexture
    let grassTexture: MTLTexture
    let cliffTexture: MTLTexture
    let snowTexture: MTLTexture
    
    static func createControlPoints(patches: (horizontal: Int, vertical: Int),
                                    size: (width: Float, height: Float)) -> [ControlPoint] {
        var points: [float3] = []
        let width = 1 / Float(patches.horizontal)
        let height = 1 / Float(patches.vertical)
        
        for row in 0..<patches.vertical {
            for index in 0..<patches.horizontal {
                let column = Float(index)
                let left = width * column
                let bottom = height * Float(row)
                let right = width * column + width
                let top = height * Float(row) + height
                
                points.append([left, 0, top])
                points.append([right, 0, top])
                points.append([right, 0, bottom])
                points.append([left, 0, bottom])
            }
        }
        
        // Convert to Metal coordinates
        points = points.map {
            [
                $0.x * size.width - size.width / 2,
                0,
                $0.z * size.height - size.height / 2
            ]
        }
        
        return points.map { ControlPoint(position: $0) }
    }
    
    convenience init(size: float2 = [2, 2], height: Float = 1.0) {
        self.init(terrain: Terrain(size: size,
                                   height: height,
                                   maxTessellation: UInt32(TessellatedRendering.maxTessellation)))
    }
    
    init(terrain: Terrain) {
        guard let heightMap = Assets.Textures[.MountainHeightMap],
              let grassTexture = Assets.Textures[.Grass],
              let cliffTexture = Assets.Textures[.Cliff],
              let snowTexture = Assets.Textures[.Snow]
        else {
            fatalError("[TerrainObject init] Missing required textures!")
        }
        
        self.terrain = terrain
        self.heightMap = heightMap
        self.grassTexture = grassTexture
        self.cliffTexture = cliffTexture
        self.snowTexture = snowTexture
        super.init(name: "Terrain", modelType: .Quad)
        let controlPointsSize = (width: self.terrain.size.x, height: self.terrain.size.y)
        self.controlPointsBuffer = makeControlPointsBuffer(size: controlPointsSize)
        self.tessellationFactorsBuffer = makeTessellationFactorsBuffer()
    }
    
    // TODO: Should these two functions live in Tessellatables ???
    func makeControlPointsBuffer(size: (width: Float, height: Float) = (2, 2)) -> MTLBuffer? {
        let controlPoints = Self.createControlPoints(patches: self.patches, size: size)
        return Engine.Device.makeBuffer(bytes: controlPoints, length: ControlPoint.stride(controlPoints.count))
    }
    
    func makeTessellationFactorsBuffer() -> MTLBuffer? {
        let count = self.patchCount * (4 + 2)  // 4 edge factors & 2 inside factors
        let size = count * Float.size / 2
        return Engine.Device.makeBuffer(length: size, options: .storageModePrivate)
    }
    //
    
    func computeUpdate(_ computeEncoder: any MTLComputeCommandEncoder) {
        computeEncoder.setBuffer(tessellationFactorsBuffer, offset: 0, index: 2)
        computeEncoder.setBytes(&self.modelMatrix, length: float4x4.stride, index: 4)
        computeEncoder.setBuffer(controlPointsBuffer, offset: 0, index: 5)
        computeEncoder.setBytes(&terrain, length: Terrain.stride, index: TFSBufferIndexTerrain.index)
        
        let tessellationComputePipelineState = Graphics.ComputePipelineStates[.Tessellation]
        let width = min(patchCount, tessellationComputePipelineState.threadExecutionWidth)
        let gridSize = MTLSize(width: patchCount, height: 1, depth: 1)
        let threadsPerGroup = MTLSize(width: width, height: 1, depth: 1)
        
        computeEncoder.dispatchThreadgroups(gridSize, threadsPerThreadgroup: threadsPerGroup)
    }
    
    func setRenderState(_ renderEncoder: any MTLRenderCommandEncoder) {
        renderEncoder.setTessellationFactorBuffer(tessellationFactorsBuffer, offset: 0, instanceStride: 0)
        renderEncoder.setVertexBuffer(controlPointsBuffer, offset: 0, index: 0)  // TFSBufferIndexMeshPositions.index
        renderEncoder.setVertexBytes(&terrain, length: Terrain.stride, index: TFSBufferIndexTerrain.index)
        renderEncoder.setVertexTexture(heightMap, index: TFSTextureIndexHeightMap.index)
        
        renderEncoder.setFragmentTexture(grassTexture, index: TFSTextureIndexGrass.index)
        renderEncoder.setFragmentTexture(cliffTexture, index: TFSTextureIndexCliff.index)
        renderEncoder.setFragmentTexture(snowTexture, index: TFSTextureIndexSnow.index)
    }
}
