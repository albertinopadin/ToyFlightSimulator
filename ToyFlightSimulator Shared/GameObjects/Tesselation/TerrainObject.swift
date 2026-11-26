//
//  TerrainObject.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/19/25.
//

import MetalKit

/// Where a terrain's heights come from. Both sources are drawn by the same shader code
/// (Tessellation.metal). Only the height texture and the numbers in the `Terrain` struct
/// differ.
enum TerrainHeightSource {
    /// The image `mountain.png`. Its texels reach the shader as numbers from 0 to 1.
    case heightMapImage
    /// Heights computed by `ProceduralTerrain` and baked into a texture of 32-bit floats, in
    /// meters.
    case procedural(params: ProceduralTerrainParameters)
}

final class TerrainObject: GameObject, Tessellatable {
    /// Patches along one side of the terrain. A patch is one quad that the GPU's tessellator
    /// divides into triangles.
    static let patchesPerSide: Int = 32
    /// Cells along one edge of a patch at the lowest tessellation factor. This is the floor in
    /// `compute_tessellation` (`max(4.0, …)` in Tessellation.metal). The two must change
    /// together: only while they are equal does the procedural bake have exactly one sample
    /// for every vertex at that factor.
    static let cellsPerPatchEdgeAtLowestTessellation: Int = 4
    /// Samples along one side of a procedural bake: 32 patches × 4 cells + 1 = 129. The + 1 is
    /// there because 128 cells in a row have 129 corners.
    static let proceduralSamplesPerSide: Int = TerrainObject.patchesPerSide * TerrainObject.cellsPerPatchEdgeAtLowestTessellation + 1

    var patches: (horizontal: Int, vertical: Int) { (horizontal: Self.patchesPerSide, vertical: Self.patchesPerSide) }
    var patchCount: Int { patches.horizontal * patches.vertical }

    var controlPointsBuffer: MTLBuffer?
    var tessellationFactorsBuffer: MTLBuffer?

    /// The numbers the shaders need: the size, the height decode and the colour thresholds
    /// (see `Terrain` in TFSCommon.h). Bound to the compute, vertex and fragment stages.
    var terrain: Terrain
    /// One texel per height sample. `var`, because `follow` puts a new texture in its place
    /// at every recentre. Written on the update thread only. The render thread reads it
    /// after the update handshake, when the update thread is waiting.
    private(set) var heightMap: MTLTexture
    let grassTexture: MTLTexture
    let cliffTexture: MTLTexture
    let snowTexture: MTLTexture

    let heightSource: TerrainHeightSource

    // The four properties below describe a procedural bake. The image source does not use them.

    /// Distance between neighbouring height samples, in meters. nil for the image source: its
    /// texels are not tied to positions in meters. Optional and not a default number, so that
    /// code that needs the spacing must first deal with a terrain that has none.
    let sampleSpacing: Double?
    /// The sample the middle of the terrain sits on, as indices on the world-wide sample grid
    /// (see `ProceduralTerrain.bakeHeightSamples`). Sample (0, 0) is at the origin of the
    /// scene's original frame. Both start at 0 and only `follow` changes them, always to a
    /// multiple of 4 samples (one patch). A floating-origin shift does not change them: an
    /// index names a place in the original frame.
    var centerSampleIndexX: Int = 0
    var centerSampleIndexZ: Int = 0
    /// The baked heights in meters, row by row: the same numbers the height texture holds.
    /// Empty for the image source. `follow` replaces the array at every recentre.
    var heightSamples: [Float] = []

    static func createControlPoints(patches: (horizontal: Int, vertical: Int),
                                    size: (width: Float, height: Float)) -> [TerrainControlPoint] {
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
        
        return points.map { TerrainControlPoint(position: $0) }
    }
    
    /// Makes the height texture of a procedural bake: one texel per sample, one 32-bit float
    /// per texel (`r32Float`), holding the height in meters as it is.
    ///
    /// `heightSamples` is stored row by row (`ProceduralTerrain.bakeHeightSamples`), and
    /// `replace` copies the rows in the order they are stored. Element
    /// `row * samplesPerSide + column` becomes texel (column, row), which is the texel the
    /// shader reads with `read(uint2(column, row))`. `bytesPerRow` is the number of bytes from
    /// the start of one row to the start of the next: `samplesPerSide` Floats of 4 bytes each.
    ///
    /// `heightSamples` must hold `samplesPerSide * samplesPerSide` values. `replace` reads
    /// that many Floats and does not check the array's length, so a shorter array would be
    /// read past its end. The `precondition` stops the program before that can happen, in
    /// Debug and in Release builds.
    ///
    /// Static, so that a test can call it without building a `TerrainObject`.
    static func makeHeightTexture(heightSamples: [Float], samplesPerSide: Int) -> MTLTexture {
        precondition(heightSamples.count == samplesPerSide * samplesPerSide,
                     "[TerrainObject makeHeightTexture] heightSamples array is not of size samplesPerSide^2; heightSamples size: \(heightSamples.count), samplesPerSide: \(samplesPerSide)")
        let heightTextureDescriptor = MTLTextureDescriptor()
        heightTextureDescriptor.textureType = .type2D
        heightTextureDescriptor.pixelFormat = .r32Float
        heightTextureDescriptor.width = samplesPerSide
        heightTextureDescriptor.height = samplesPerSide
        heightTextureDescriptor.mipmapLevelCount = 1
        heightTextureDescriptor.usage = .shaderRead
        
        guard let heightTexture = Engine.Device.makeTexture(descriptor: heightTextureDescriptor) else {
            fatalError("[TerrainObject procedural init] Could not create height texture")
        }
        
        let wholeTextureRegion = MTLRegion(origin: .init(x: 0, y: 0, z: 0),
                                           size: .init(width: samplesPerSide, height: samplesPerSide, depth: 1))
        heightTexture.replace(region: wholeTextureRegion,
                              mipmapLevel: 0,
                              withBytes: heightSamples,
                              bytesPerRow: samplesPerSide * 4)
        heightTexture.label = "Procedural Terrain Height Map"
        return heightTexture
    }
    
    /// Builds a terrain whose heights come from `ProceduralTerrain`: a square with sides of
    /// `sideLength` meters, centred on the origin of the scene's original frame.
    ///
    /// The bake has 129 samples per side, which span 128 cells, so the sample spacing is
    /// `sideLength / 128`. The texture holds meters. The height decode in the `Terrain` struct
    /// is therefore scale 1 and offset 0, and the colour thresholds are in meters: grass below
    /// -50 m, snow from 200 m up, rock between.
    ///
    /// Do not scale or rotate the returned object. A scale would multiply the heights, and on
    /// a tilted terrain the height is no longer a function of world x and z.
    static func makeProceduralTerrain(params: ProceduralTerrainParameters, sideLength: Float) -> TerrainObject {
        let samplesPerSide = Self.proceduralSamplesPerSide
        let sampleSpacing = (sideLength / Float(samplesPerSide - 1)).toDouble()
        // -64 with 129 samples: the grid is centred on sample (0, 0), which lands in the middle
        // texel (column 64, row 64).
        let firstSampleIndex = 0 - (samplesPerSide - 1) / 2
        let heightSamples = ProceduralTerrain.bakeHeightSamples(firstSampleIndexX: firstSampleIndex,
                                                                firstSampleIndexZ: firstSampleIndex,
                                                                samplesPerSide: samplesPerSide,
                                                                sampleSpacing: sampleSpacing,
                                                                params: params)
        let heightTexture = Self.makeHeightTexture(heightSamples: heightSamples, samplesPerSide: samplesPerSide)
        let terrain = Terrain(size: [sideLength, sideLength],
                              maxTessellation: UInt32(TessellatedRendering.maxTessellation),
                              heightScale: 1,
                              heightOffset: 0,
                              grassBelowHeight: -50,
                              snowAboveHeight: 200,
                              colorTextureRepeatCount: 128)
        return TerrainObject(terrain: terrain,
                             heightTexture: heightTexture,
                             heightSource: .procedural(params: params),
                             sampleSpacing: sampleSpacing,
                             heightSamples: heightSamples)
    }
    
    /// A terrain whose heights come from the image `mountain.png`. `height` is the largest
    /// local height: the terrain runs from `-height` to `+height`.
    convenience init(size: float2 = [2, 2], height: Float = 1.0) {
        guard let heightTexture = Assets.Textures[.MountainHeightMap] else {
            fatalError("[TerrainObject cinit] Missing Height map texture")
        }

        // These numbers reproduce the shader as it was before the procedural source existed.
        // A texel of the image arrives as r, from 0 to 1, and the old decode was
        // (r * 2 - 1) * height. Written as offset + r * scale, that is -height + r * (2 * height).
        // The two thresholds are the old shader's literals. It compared them with the decoded
        // height whatever `height` was, so they are not multiplied by `height` here either.
        // One repeat is the old tiling of 1: each colour texture is stretched once across the
        // whole terrain.
        let terrain = Terrain(size: size,
                              maxTessellation: UInt32(TessellatedRendering.maxTessellation),
                              heightScale: height * 2,
                              heightOffset: -height,
                              grassBelowHeight: -0.5,
                              snowAboveHeight: 0.3,
                              colorTextureRepeatCount: 1)
        self.init(terrain: terrain, heightTexture: heightTexture, heightSource: .heightMapImage)
    }
    
    
    
    /// The initializer both height sources end in. The caller supplies the height texture and
    /// the `Terrain` struct that says how the shaders decode it. `sampleSpacing` and
    /// `heightSamples` belong to the procedural source. The image source leaves both out, and
    /// they are stored as nil and as an empty array.
    init(terrain: Terrain,
         heightTexture: MTLTexture,
         heightSource: TerrainHeightSource,
         sampleSpacing: Double? = nil,
         heightSamples: [Float]? = nil) {
        guard let grassTexture = Assets.Textures[.Grass],
              let cliffTexture = Assets.Textures[.Cliff],
              let snowTexture = Assets.Textures[.Snow]
        else {
            fatalError("[TerrainObject init] Missing grass, cliff, and/or snow textures!")
        }
        
        self.terrain = terrain
        self.heightSource = heightSource
        self.sampleSpacing = sampleSpacing
        if let heightSamples {
            self.heightSamples = heightSamples
        }
        self.heightMap = heightTexture
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
        return Engine.Device.makeBuffer(bytes: controlPoints, length: TerrainControlPoint.stride(controlPoints.count))
    }
    
    func makeTessellationFactorsBuffer() -> MTLBuffer? {
        let count = self.patchCount * (4 + 2)  // 4 edge factors & 2 inside factors
        let size = count * Float.size / 2
        return Engine.Device.makeBuffer(length: size, options: .storageModePrivate)
    }
    //

    /// Keeps a procedural terrain under the point it follows, the focus. Call it once per
    /// tick, on the update thread, before the scene traversal reaches this object's
    /// `update()`. Does nothing for the image source.
    ///
    /// - Parameters:
    ///   - focusPositionInOriginalFrame: the point to stay under (the aircraft), in meters,
    ///     in the scene's original frame. Only x and z are used.
    ///   - floatingOriginOffset: `SceneManager.floatingOriginOffset` as it is in this tick.
    ///     It is a parameter, not read in here, so that the caller hands over a focus and an
    ///     offset that belong together, and so that a test can call `follow` without a scene.
    ///
    /// On most ticks nothing happens: the focus is within 4 samples (400 m) of the centre on
    /// both axes, and the cost is one division and one comparison per axis
    /// (`ProceduralTerrain.recenteredCenterSampleIndex`). When the focus is farther than
    /// that on either axis, the terrain is recentred in four steps:
    ///
    /// 1. The centre moves to the multiple of one patch (4 samples) nearest the focus, on
    ///    each axis that is past the threshold. The other axis keeps its centre.
    /// 2. All 129 x 129 samples are baked again around the new centre. A sample that was on
    ///    the old grid comes out with the same bits as before (see `bakeHeightSamples`), so
    ///    the ground that stays on screen keeps its shape.
    /// 3. A new texture is made from the samples and takes the place of the old one. The old
    ///    texture is not written to. Frames that were encoded earlier and have not finished
    ///    on the GPU still use it, and a command buffer keeps the textures it uses alive
    ///    until it is done. Overwriting the old texture in place would let those frames draw
    ///    the new heights at the old position: a jump of one patch for a frame.
    /// 4. The node moves to the new centre, written in the current frame
    ///    (`ProceduralTerrain.storedPositionOfTerrainCenter`).
    ///
    /// The texture and the position must change in the same frame. That is why the scene
    /// calls `follow` from its `doUpdate`, which runs before its children's `update()`: this
    /// object's `update()` then caches the new position in `modelConstants` in the same tick,
    /// and the frame drawn after this tick uses the new texture with the new position.
    /// Called after `update()`, the new texture would be drawn at the old position for one
    /// frame.
    ///
    /// A floating-origin shift needs nothing from this function. The shift subtracts its
    /// offset from this node's stored position, as it does for every direct child of the
    /// scene, and adds the same offset to the total. The centre's place in the original
    /// frame does not change, so the centre sample indices and the texture stay valid.
    ///
    /// This is the simple version: every recentre bakes all 16,641 samples on the update
    /// thread. The plan measured that at 15.7 ms in an unoptimized build and 0.47 ms in an
    /// optimized one (Apple M1 Max). Its optimized version copies the samples the old grid
    /// already holds and bakes only the new strip.
    ///
    /// Plan: Milestone 4 of plans/claude/procedural_terrain_generation_2026-11-22.md.
    func follow(focusPositionInOriginalFrame: double3, floatingOriginOffset: double3) {
        switch heightSource {
            case .heightMapImage:
                return
            case .procedural(params: let params):
                // `sampleSpacing` is nil only for the image source, which returned above.
                // `makeProceduralTerrain` always stores one.
                if let sampleSpacing {
                    // 4 samples: one patch, which is 400 m with 100 m spacing. The threshold
                    // is the same distance. Why these two numbers work together is in the
                    // comment of `recenteredCenterSampleIndex`.
                    let snapStepInSamples = TerrainObject.cellsPerPatchEdgeAtLowestTessellation
                    let recenterThresholdInSamples = snapStepInSamples
                    // Each axis is asked by itself. nil means "this axis stays".
                    let newCenterX = ProceduralTerrain.recenteredCenterSampleIndex(
                        currentCenterSampleIndex: centerSampleIndexX,
                        focusPositionInOriginalFrame: focusPositionInOriginalFrame.x,
                        sampleSpacing: sampleSpacing,
                        snapStepInSamples: Double(snapStepInSamples),
                        recenterThresholdInSamples: Double(recenterThresholdInSamples))
                    let newCenterZ = ProceduralTerrain.recenteredCenterSampleIndex(
                        currentCenterSampleIndex: centerSampleIndexZ,
                        focusPositionInOriginalFrame: focusPositionInOriginalFrame.z,
                        sampleSpacing: sampleSpacing,
                        snapStepInSamples: Double(snapStepInSamples),
                        recenterThresholdInSamples: Double(recenterThresholdInSamples))
                    
                    // The usual case: the focus is within the threshold on both axes.
                    if newCenterX == nil && newCenterZ == nil { return }

                    // An axis that answered nil keeps its centre.
                    centerSampleIndexX = newCenterX ?? centerSampleIndexX
                    centerSampleIndexZ = newCenterZ ?? centerSampleIndexZ
                    // The same constant `makeProceduralTerrain` reads, so the bake and the
                    // texture keep their size. 64 samples lie on each side of the centre, so
                    // the grid starts 64 sample indices before it on both axes.
                    let samplesPerSide = TerrainObject.proceduralSamplesPerSide
                    let halfSideInSamples = (samplesPerSide - 1) / 2

                    // `timeit` returns how long the closure ran, in nanoseconds. Only the
                    // bake is timed, not the texture.
                    let bakeTime = timeit {
                        heightSamples = ProceduralTerrain.bakeHeightSamples(
                            firstSampleIndexX: centerSampleIndexX - halfSideInSamples,
                            firstSampleIndexZ: centerSampleIndexZ - halfSideInSamples,
                            samplesPerSide: samplesPerSide,
                            sampleSpacing: sampleSpacing,
                            params: params)
                    }

                    // A new texture, not `replace` on the old one: see step 3 above.
                    heightMap = Self.makeHeightTexture(heightSamples: heightSamples, samplesPerSide: samplesPerSide)
                    // The centre is a place in the original frame. The node stores positions
                    // in the current frame, so the offset is subtracted.
                    let newTerrainCenter = ProceduralTerrain.storedPositionOfTerrainCenter(
                        centerSampleIndexX: Double(centerSampleIndexX),
                        centerSampleIndexZ: Double(centerSampleIndexZ),
                        sampleSpacing: sampleSpacing,
                        floatingOriginOffset: floatingOriginOffset)
                    setPosition(newTerrainCenter)

                    // 1 nanosecond is 1e-6 milliseconds.
                    let timeInMilliseconds = Double(bakeTime) * 1e-6
                    DebugLog("Terrain recentred on sample (x: \(centerSampleIndexX), z: \(centerSampleIndexZ), bake took \(timeInMilliseconds) ms", DEBUG_PROCEDURAL_TERRAIN)
                }
        }
    }
    
    func computeUpdate(_ computeEncoder: any MTLComputeCommandEncoder) {
        computeEncoder.setBuffer(tessellationFactorsBuffer, offset: 0, index: 2)
        // The world matrix cached by GameObject.update(), which DrawTessellatables also
        // binds, not the live self.modelMatrix: a floating-origin shift after the traversal
        // changes the live one before this pass is encoded (see TessellationRendering).
        computeEncoder.setBytes(&modelConstants.modelMatrix, length: float4x4.stride, index: 4)
        computeEncoder.setBuffer(controlPointsBuffer, offset: 0, index: 5)
        computeEncoder.setBytes(&terrain, length: Terrain.stride, index: TFSBufferIndexTerrain.index)
        
        let tessellationComputePipelineState = Graphics.ComputePipelineStates[.Tessellation]
        let width = min(patchCount, tessellationComputePipelineState.threadExecutionWidth)
        let gridSize = MTLSize(width: patchCount, height: 1, depth: 1)
        let threadsPerGroup = MTLSize(width: width, height: 1, depth: 1)
        
        computeEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerGroup)
    }
    
    func setRenderState(_ renderEncoder: any MTLRenderCommandEncoder) {
        renderEncoder.setTessellationFactorBuffer(tessellationFactorsBuffer, offset: 0, instanceStride: 0)
        renderEncoder.setVertexBuffer(controlPointsBuffer, offset: 0, index: TFSBufferIndexMeshVertex.index)
        renderEncoder.setVertexBytes(&terrain, length: Terrain.stride, index: TFSBufferIndexTerrain.index)
        renderEncoder.setVertexTexture(heightMap, index: TFSTextureIndexHeightMap.index)
        
        // The fragment functions read the colour thresholds and the repeat count from the same
        // struct. A binding belongs to one stage, so the vertex stage's does not reach them.
        renderEncoder.setFragmentBytes(&terrain, length: Terrain.stride, index: TFSBufferIndexTerrain.index)
        renderEncoder.setFragmentTexture(grassTexture, index: TFSTextureIndexGrass.index)
        renderEncoder.setFragmentTexture(cliffTexture, index: TFSTextureIndexCliff.index)
        renderEncoder.setFragmentTexture(snowTexture, index: TFSTextureIndexSnow.index)
    }
}
