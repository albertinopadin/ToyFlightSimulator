//
//  TerrainHeightTextureTests.swift
//  ToyFlightSimulatorTests
//
//  The height texture of the procedural terrain. `TerrainObject.makeHeightTexture` copies a
//  baked array of heights into a texture, and `TerrainObject.makeProceduralTerrain` builds a
//  terrain around one. The shader reads the texture one texel at a time with
//  `read(uint2(column, row))`, so two things must hold: the texture stores the Floats
//  unchanged, and element `row * samplesPerSide + column` of the array is texel (column, row).
//
//  One test is about the other height source, the image `mountain.png`. Both sources go
//  through the same shader code and differ only in the numbers of the `Terrain` struct, so
//  the image source must be given the numbers that reproduce the shader as it was before.
//
//  The tests under "follow" are the plan's Milestone 4: `TerrainObject.follow` keeps a
//  procedural terrain under a moving point. They check what one call changes: the centre
//  sample, the baked samples, the texture (a new one, with the old one left as it was) and
//  the stored position. `follow` is handed the focus and the floating-origin offset, so no
//  scene is needed. The rule that decides when to recentre is tested without Metal in
//  ProceduralTerrainTests; here it is only checked that `follow` applies it to each axis.
//  The samples a recentred terrain should hold come from `ProceduralTerrain.bakeHeightSamples`,
//  which ProceduralTerrainTests checks against the plan's numbers: `follow` is asked only
//  whether it bakes the right grid.
//
//  App-hosted only. `makeHeightTexture` needs a Metal device (`Engine.Device`), and building a
//  `TerrainObject` also loads the Quad model and the grass, cliff and snow textures. Nothing
//  here touches `Engine.renderer`, so the host-app launch race does not apply (the header of
//  AfterburnerEmitterTests describes the same pattern).
//
//  The expected heights of the 129 x 129 grid are not copied from the code under test. They
//  are the numbers ProceduralTerrainTests already uses, from Milestone 2 of
//  plans/claude/procedural_terrain_generation_2026-11-22.md. This file is that plan's
//  Milestone 3, part E, and the app-hosted half of its Milestone 4.
//

import Testing
import Metal
@testable import ToyFlightSimulator

@Suite("TerrainObject: the height texture, the two height sources and following a focus", .tags(.gameObjects))
struct TerrainHeightTextureTests {

    /// Reads a rectangle of texels back from a texture that stores one Float per texel.
    /// `column` and `row` name the rectangle's first texel. The result is row by row, like the
    /// array the texture was made from.
    ///
    /// The array starts out as NaN (not a number). NaN is not equal to anything, so a texel
    /// that `getBytes` did not write can never pass for a height.
    private func readFloats(from texture: MTLTexture,
                            column: Int,
                            row: Int,
                            width: Int,
                            height: Int) -> [Float] {
        var values = [Float](repeating: .nan, count: width * height)
        let region = MTLRegion(origin: MTLOrigin(x: column, y: row, z: 0),
                               size: MTLSize(width: width, height: height, depth: 1))
        values.withUnsafeMutableBytes { bytes in
            texture.getBytes(bytes.baseAddress!,
                             bytesPerRow: width * MemoryLayout<Float>.stride,
                             from: region,
                             mipmapLevel: 0)
        }
        return values
    }

    @Test("the texture holds the baked samples unchanged, in row order")
    func textureHoldsTheSamplesInRowOrder() throws {
        // A 9 x 9 grid centred on the origin: sample indices -4 ... 4 on both axes.
        let samplesPerSide = 9
        let heightSamples = ProceduralTerrain.bakeHeightSamples(firstSampleIndexX: -4,
                                                                firstSampleIndexZ: -4,
                                                                samplesPerSide: samplesPerSide,
                                                                sampleSpacing: 100,
                                                                params: ProceduralTerrainParameters())
        try #require(heightSamples.count == samplesPerSide * samplesPerSide)
        // The comparison below can only notice rows in the wrong order if the rows differ.
        let firstRow = Array(heightSamples[0..<samplesPerSide])
        let lastRow = Array(heightSamples[(samplesPerSide - 1) * samplesPerSide..<samplesPerSide * samplesPerSide])
        try #require(firstRow != lastRow)

        let heightTexture = TerrainObject.makeHeightTexture(heightSamples: heightSamples,
                                                            samplesPerSide: samplesPerSide)

        #expect(heightTexture.pixelFormat == .r32Float)
        #expect(heightTexture.width == samplesPerSide)
        #expect(heightTexture.height == samplesPerSide)
        #expect(heightTexture.mipmapLevelCount == 1)

        // `==` on purpose, not a tolerance: an r32Float texel is the same 32 bits as the Float
        // it was made from. A wrong bytesPerRow in makeHeightTexture shifts every row after
        // the first, and reversed rows put the last row first. Both fail here.
        let readBack = readFloats(from: heightTexture, column: 0, row: 0,
                                  width: samplesPerSide, height: samplesPerSide)
        #expect(readBack == heightSamples)
    }

    @Test("texel (column, row) holds element row * samplesPerSide + column")
    func texelAtColumnAndRowIsTheMatchingElement() {
        // Every element says where it is: 1000 * row + column. No two are equal, and swapping
        // row and column changes the number (row 7, column 2 is 7002; the swap is 2007).
        let samplesPerSide = 9
        var heightSamples = [Float](repeating: 0, count: samplesPerSide * samplesPerSide)
        for row in 0..<samplesPerSide {
            for column in 0..<samplesPerSide {
                heightSamples[row * samplesPerSide + column] = Float(1000 * row + column)
            }
        }

        let heightTexture = TerrainObject.makeHeightTexture(heightSamples: heightSamples,
                                                            samplesPerSide: samplesPerSide)

        // One texel at a time, addressed the way the shader's read(uint2(column, row)) does.
        let expectedTexels: [(column: Int, row: Int, value: Float)] = [
            (0, 0,    0),
            (8, 0,    8),  // the end of the first row
            (0, 8, 8000),  // the start of the last row
            (2, 7, 7002),
            (7, 2, 2007),
            (8, 8, 8008),
        ]
        for expected in expectedTexels {
            let texel = readFloats(from: heightTexture, column: expected.column, row: expected.row,
                                   width: 1, height: 1)
            #expect(texel == [expected.value],
                    "texel (column \(expected.column), row \(expected.row)) was \(texel)")
        }
    }

    @Test("the procedural grid has one sample for every vertex at the lowest tessellation factor")
    func samplesPerSideMatchesThePatchGrid() {
        // 32 patches of 4 cells, plus 1, because 128 cells in a row have 129 corners.
        #expect(TerrainObject.proceduralSamplesPerSide == 129)
        #expect(TerrainObject.proceduralSamplesPerSide
                == TerrainObject.patchesPerSide * TerrainObject.cellsPerPatchEdgeAtLowestTessellation + 1)
        // An odd count, so that the grid has a middle sample to centre on.
        #expect(TerrainObject.proceduralSamplesPerSide % 2 == 1)
    }

    @Test("a procedural terrain is a 129 x 129 bake centred on the origin, in meters")
    func proceduralTerrainIsABakeCentredOnTheOrigin() throws {
        let samplesPerSide = 129
        let proceduralTerrain = TerrainObject.makeProceduralTerrain(params: ProceduralTerrainParameters(),
                                                                    sideLength: 12_800)

        // 12,800 m across 128 cells.
        #expect(proceduralTerrain.sampleSpacing == 100)
        #expect(proceduralTerrain.centerSampleIndexX == 0)
        #expect(proceduralTerrain.centerSampleIndexZ == 0)
        if case .procedural = proceduralTerrain.heightSource {
            // expected
        } else {
            Issue.record("the height source was \(proceduralTerrain.heightSource), not .procedural")
        }

        // The grid starts at sample index -64 on both axes, which is (-6400, -6400) m, so the
        // origin is the middle sample. The three heights are the plan's Milestone 2 numbers.
        let heightSamples = proceduralTerrain.heightSamples
        try #require(heightSamples.count == samplesPerSide * samplesPerSide)
        let expectedSamples: [(column: Int, row: Int, height: Float, place: String)] = [
            (0,     0, -328.78198, "(-6400, -6400) m, the first sample"),
            (64,   64, -172.99075, "(0, 0) m, the middle sample"),
            (96,  128,  533.9311,  "(3200, 6400) m, in the last row"),
        ]
        for expected in expectedSamples {
            let bakedSample = heightSamples[expected.row * samplesPerSide + expected.column]
            #expect(abs(bakedSample - expected.height) <= 1e-3,
                    "the sample at \(expected.place) was \(bakedSample) m")
        }

        // The texture the terrain is drawn with holds exactly those samples.
        let heightTexture = proceduralTerrain.heightMap
        #expect(heightTexture.pixelFormat == .r32Float)
        try #require(heightTexture.width == samplesPerSide && heightTexture.height == samplesPerSide)
        let readBack = readFloats(from: heightTexture, column: 0, row: 0,
                                  width: samplesPerSide, height: samplesPerSide)
        #expect(readBack == heightSamples)

        // The texture already holds meters, so the shader's decode
        // (heightOffset + texel * heightScale) must leave a texel as it is.
        #expect(proceduralTerrain.terrain.size == [12_800, 12_800])
        #expect(proceduralTerrain.terrain.heightScale == 1)
        #expect(proceduralTerrain.terrain.heightOffset == 0)
    }

    @Test("the image source decodes a texel as the old shader did: (r * 2 - 1) * height")
    func imageSourceKeepsTheOldHeightDecode() {
        // A height of 3 and not the default 1. With 1, a number that should be multiplied by
        // `height` and is not would still pass, and so would one that is multiplied and
        // should not be.
        let height: Float = 3
        let imageTerrain = TerrainObject(size: [8, 8], height: height)
        let terrain = imageTerrain.terrain

        // r is a texel of the image as the shader sees it, from 0 to 1. The shader now
        // computes heightOffset + r * heightScale. Before the procedural source existed it
        // computed (r * 2 - 1) * height. 0.25 and 0.65 are the texel values at which the old
        // shader changed from grass to rock and from rock to snow when height was 1.
        let texelValues: [Float] = [0, 0.25, 0.5, 0.65, 1]
        for texelValue in texelValues {
            let decodedHeight = terrain.heightOffset + texelValue * terrain.heightScale
            let oldDecodedHeight = (texelValue * 2 - 1) * height
            #expect(abs(decodedHeight - oldDecodedHeight) <= 1e-5,
                    "texel \(texelValue) decodes to \(decodedHeight), the old shader gave \(oldDecodedHeight)")
        }

        // The old shader compared the decoded height with these two literals whatever
        // `height` was, and stretched each colour texture once across the terrain.
        #expect(terrain.grassBelowHeight == -0.5)
        #expect(terrain.snowAboveHeight == 0.3)
        #expect(terrain.colorTextureRepeatCount == 1)
        #expect(terrain.size == [8, 8])

        // The image has no grid of samples in meters: no spacing and no baked heights.
        #expect(imageTerrain.sampleSpacing == nil)
        #expect(imageTerrain.heightSamples.isEmpty)
        if case .heightMapImage = imageTerrain.heightSource {
            // expected
        } else {
            Issue.record("the height source was \(imageTerrain.heightSource), not .heightMapImage")
        }
    }

    // MARK: - follow

    /// The terrain the scene builds: 12,800 m on a side, so 129 samples 100 m apart, centred
    /// on sample (0, 0) and stored at the origin.
    private func makeTerrainCentredOnTheOrigin() -> TerrainObject {
        TerrainObject.makeProceduralTerrain(params: ProceduralTerrainParameters(), sideLength: 12_800)
    }

    /// The bake `follow` should hold after it recentres on the given sample: 129 x 129
    /// samples, 100 m apart, with 64 samples on each side of the centre.
    private func bakeCentredOn(sampleIndexX: Int, sampleIndexZ: Int) -> [Float] {
        ProceduralTerrain.bakeHeightSamples(firstSampleIndexX: sampleIndexX - 64,
                                            firstSampleIndexZ: sampleIndexZ - 64,
                                            samplesPerSide: 129,
                                            sampleSpacing: 100,
                                            params: ProceduralTerrainParameters())
    }

    /// Every texel of a 129 x 129 height texture, row by row.
    private func readAllFloats(from heightTexture: MTLTexture) -> [Float] {
        readFloats(from: heightTexture, column: 0, row: 0, width: 129, height: 129)
    }

    @Test("follow changes nothing while the focus is within 400 m of the centre on both axes")
    func followDoesNothingWithinTheThreshold() {
        let proceduralTerrain = makeTerrainCentredOnTheOrigin()
        let textureBefore = proceduralTerrain.heightMap
        let heightSamplesBefore = proceduralTerrain.heightSamples

        // Exactly at the threshold on both axes: 400 m is 4 samples. The height of the focus
        // (750 m) plays no part.
        proceduralTerrain.follow(focusPositionInOriginalFrame: [400, 750, -400], floatingOriginOffset: .zero)

        #expect(proceduralTerrain.centerSampleIndexX == 0)
        #expect(proceduralTerrain.centerSampleIndexZ == 0)
        #expect(proceduralTerrain.getPosition() == float3(0, 0, 0))
        // `===`: the very same texture object, so no bake happened.
        #expect(proceduralTerrain.heightMap === textureBefore)
        #expect(proceduralTerrain.heightSamples == heightSamplesBefore)
    }

    @Test("past the threshold, follow recentres on the nearest patch, bakes that grid and puts a new texture in place")
    func followRecentresAndBakesANewTexture() throws {
        let samplesPerSide = 129
        let proceduralTerrain = makeTerrainCentredOnTheOrigin()
        let oldTexture = proceduralTerrain.heightMap
        let oldHeightSamples = proceduralTerrain.heightSamples
        try #require(oldHeightSamples.count == samplesPerSide * samplesPerSide)

        // X: 1,000.5 m is 10.005 samples; the nearest multiple of 4 is 12.
        // Z: -450 m is -4.5 samples; the nearest multiple of 4 is -4.
        // The two axes get different answers on purpose, so that a mix-up of X and Z fails.
        proceduralTerrain.follow(focusPositionInOriginalFrame: [1000.5, 750, -450], floatingOriginOffset: .zero)

        #expect(proceduralTerrain.centerSampleIndexX == 12)
        #expect(proceduralTerrain.centerSampleIndexZ == -4)
        // No floating-origin shift has happened (the offset is zero), so the stored position
        // is the centre sample's own position: (12 x 100, 0, -4 x 100) m. The terrain's base
        // stays at height 0; the focus's 750 m is not copied.
        #expect(proceduralTerrain.getPosition() == float3(1200, 0, -400))

        // The samples are the bake of the grid around the new centre, and not the old ones.
        let newHeightSamples = proceduralTerrain.heightSamples
        try #require(newHeightSamples.count == samplesPerSide * samplesPerSide)
        #expect(newHeightSamples == bakeCentredOn(sampleIndexX: 12, sampleIndexZ: -4))
        #expect(newHeightSamples != oldHeightSamples)

        // The ground itself did not move. The sample at the world's origin, -172.99075 m in
        // the plan's Milestone 2, was the middle sample (column 64, row 64) of the old grid.
        // The new grid starts at sample index (12 - 64, -4 - 64) = (-52, -68), so the same
        // sample is now at column 0 - (-52) = 52 and row 0 - (-68) = 68, with the same bits.
        let sampleAtTheOriginBefore = oldHeightSamples[64 * samplesPerSide + 64]
        let sampleAtTheOriginAfter = newHeightSamples[68 * samplesPerSide + 52]
        #expect(abs(sampleAtTheOriginBefore - (-172.99075)) <= 1e-3)
        #expect(sampleAtTheOriginAfter.bitPattern == sampleAtTheOriginBefore.bitPattern)

        // A new texture object holds the new samples. The old texture still holds the old
        // ones: frames that were already encoded read it until they finish on the GPU, so
        // `follow` must not write to it.
        let newTexture = proceduralTerrain.heightMap
        #expect(newTexture !== oldTexture)
        #expect(readAllFloats(from: newTexture) == newHeightSamples)
        #expect(readAllFloats(from: oldTexture) == oldHeightSamples)

        // The same focus again: it is now 1.995 and 0.5 samples from the centre, so nothing
        // is baked and the texture stays the same object.
        proceduralTerrain.follow(focusPositionInOriginalFrame: [1000.5, 750, -450], floatingOriginOffset: .zero)
        #expect(proceduralTerrain.heightMap === newTexture)
        #expect(proceduralTerrain.centerSampleIndexX == 12)
        #expect(proceduralTerrain.centerSampleIndexZ == -4)
    }

    @Test("follow recentres only the axis that is past the threshold")
    func followRecentresOnlyTheAxisPastTheThreshold() {
        // X is past the threshold (10.005 samples) and Z is not (3.99 samples).
        let terrainMovedAlongX = makeTerrainCentredOnTheOrigin()
        terrainMovedAlongX.follow(focusPositionInOriginalFrame: [1000.5, 0, 399], floatingOriginOffset: .zero)
        #expect(terrainMovedAlongX.centerSampleIndexX == 12)
        #expect(terrainMovedAlongX.centerSampleIndexZ == 0)
        #expect(terrainMovedAlongX.getPosition() == float3(1200, 0, 0))
        #expect(terrainMovedAlongX.heightSamples == bakeCentredOn(sampleIndexX: 12, sampleIndexZ: 0))

        // The other way round: Z is past the threshold (-10.005 samples; divided by 4 that is
        // -2.50125, which rounds to -3) and X is not (-3.99 samples).
        let terrainMovedAlongZ = makeTerrainCentredOnTheOrigin()
        terrainMovedAlongZ.follow(focusPositionInOriginalFrame: [-399, 0, -1000.5], floatingOriginOffset: .zero)
        #expect(terrainMovedAlongZ.centerSampleIndexX == 0)
        #expect(terrainMovedAlongZ.centerSampleIndexZ == -12)
        #expect(terrainMovedAlongZ.getPosition() == float3(0, 0, -1200))
        #expect(terrainMovedAlongZ.heightSamples == bakeCentredOn(sampleIndexX: 0, sampleIndexZ: -12))
    }

    @Test("after floating-origin shifts, follow stores the centre minus the offset, and bakes the same ground")
    func followStoresThePositionInTheCurrentFrame() {
        let proceduralTerrain = makeTerrainCentredOnTheOrigin()

        // The plan's small example. The focus is at (52,010, 1,200, -17,190) m in the
        // original frame: 520.1 and -171.9 samples, whose nearest multiples of 4 are 520 and
        // -172. The floating origin has shifted by (52,812, 432, -17,640) m in total.
        proceduralTerrain.follow(focusPositionInOriginalFrame: [52_010, 1_200, -17_190],
                                 floatingOriginOffset: [52_812, 432, -17_640])

        #expect(proceduralTerrain.centerSampleIndexX == 520)
        #expect(proceduralTerrain.centerSampleIndexZ == -172)
        // The centre sample is at (52,000, 0, -17,200) m in the original frame. The stored
        // position is in the current frame: that minus the offset. y is -432 because the
        // terrain's base is at height 0 and the origin has moved 432 m up.
        #expect(proceduralTerrain.getPosition() == float3(-812, -432, 440))
        // The offset moves where the terrain is stored, not which ground it shows: the bake
        // depends on the centre sample alone.
        #expect(proceduralTerrain.heightSamples == bakeCentredOn(sampleIndexX: 520, sampleIndexZ: -172))
        #expect(readAllFloats(from: proceduralTerrain.heightMap) == proceduralTerrain.heightSamples)
    }

    @Test("follow does nothing for the image source")
    func followDoesNothingForTheImageSource() {
        let imageTerrain = TerrainObject(size: [8, 8])
        imageTerrain.setPosition(3, 4, 5)
        let textureBefore = imageTerrain.heightMap

        // 100 km from the centre on both axes: a procedural terrain would recentre.
        imageTerrain.follow(focusPositionInOriginalFrame: [100_000, 0, -100_000], floatingOriginOffset: .zero)

        #expect(imageTerrain.heightMap === textureBefore)
        #expect(imageTerrain.getPosition() == float3(3, 4, 5))
        #expect(imageTerrain.centerSampleIndexX == 0)
        #expect(imageTerrain.centerSampleIndexZ == 0)
        #expect(imageTerrain.heightSamples.isEmpty)
    }
}
