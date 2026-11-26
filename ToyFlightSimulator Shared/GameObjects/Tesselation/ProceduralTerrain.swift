//
//  ProceduralTerrain.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 11/24/26.
//


/// The numbers that choose a terrain. The same parameters always give the same terrain.
///
/// A value that exists is valid. The fields are `let`, and the only way to make a value is the
/// initializer below, which checks `octaveCount`. Every argument has a default, so a caller
/// names only what it changes: `ProceduralTerrainParameters(seed: 7)`.
struct ProceduralTerrainParameters {
    /// Selects the world: a different seed gives different, unrelated terrain.
    let seed: UInt32
    /// Width of the lattice cells of the widest octave, in meters. It sets the size of the
    /// largest hills.
    let baseCellSize: Double
    /// The largest height the function can return, in meters. Heights lie between
    /// `-heightAmplitude` and `+heightAmplitude`.
    let heightAmplitude: Double
    /// How many octaves (layers of noise) are added together. At least 1; the initializer
    /// checks it. With 0, `fractalNoise` would divide zero by zero and every height would be
    /// NaN (not a number).
    let octaveCount: UInt32
    /// Each octave's cells are this many times narrower than the cells of the octave before it.
    let lacunarity: Double
    /// Each octave is this many times as tall as the octave before it.
    let gain: Double
    
    /// Stops the program when `octaveCount` is 0. `precondition` is checked in Debug and in
    /// Release builds, so a parameters value with no octaves cannot exist.
    init(seed: UInt32 = 2026,
         baseCellSize: Double = 3_200,
         heightAmplitude: Double = 600,
         octaveCount: UInt32 = 4,
         lacunarity: Double = 2,
         gain: Double = 0.5) {
        precondition(octaveCount >= 1, "ProceduralTerrainParameters needs at least one octave")
        self.seed = seed
        self.baseCellSize = baseCellSize
        self.heightAmplitude = heightAmplitude
        self.octaveCount = octaveCount
        self.lacunarity = lacunarity
        self.gain = gain
    }
}

/// Procedural terrain: the height of the ground is computed from a position and a seed, with
/// no stored terrain data. `heightInMeters` is the whole generator. The functions above it are
/// its steps, from the bottom up:
///
/// 1. `scrambleBits` and `hashOfLatticePoint` give every point of a grid of whole numbers (the
///    lattice) a fixed pseudo-random number.
/// 2. `latticeValue` turns that number into a value from -1 to +1.
/// 3. `valueNoise` blends the four lattice values around a point into a smooth surface.
/// 4. `fractalNoise` adds several of those surfaces (octaves), each narrower and lower than
///    the one before, so that large hills carry smaller bumps.
///
/// `bakeHeightSamples`, below `heightInMeters`, evaluates the generator on a square grid of
/// samples and returns the heights as an array of Floats. That array is what a height texture
/// is later made from.
///
/// The last two functions are for a terrain that follows the aircraft (`TerrainObject.follow`).
/// `recenteredCenterSampleIndex` decides, for one axis, whether the baked grid must move and
/// which sample it is then centred on. `storedPositionOfTerrainCenter` says where the terrain
/// node is stored so that its middle sits on that sample.
///
/// Every function is pure: the result depends only on the arguments. The same position and
/// seed give the same height on every call, in any order, with no state to keep. Positions are
/// Double, in meters, in the scene's original frame (a stored position plus
/// `SceneManager.floatingOriginOffset`), so the terrain does not move when the floating origin
/// shifts. There is no engine state and no Metal here: a test can call every function.
///
/// Plan, worked example and references:
/// plans/claude/procedural_terrain_generation_2026-11-22.md (Milestones 1, 2 and 4).
enum ProceduralTerrain {
    /// Scrambles the 32 bits of `value`, so that two inputs that differ in one bit give
    /// unrelated outputs. This is the "lowbias32" hash (Chris Wellons, "Prospecting for Hash
    /// Functions", 2018).
    ///
    /// Each step mixes bits in one direction. `x ^= x >> n` folds the high bits into the low
    /// bits. A multiply by a large odd constant spreads the low bits into the high bits.
    ///
    /// The multiplies use `&*`, which wraps: it keeps the low 32 bits of the product and
    /// discards the rest. A plain `*` on UInt32 stops the program when the product does not fit.
    ///
    /// `scrambleBits(0)` is 0, because every step maps 0 to 0.
    static func scrambleBits(_ value: UInt32) -> UInt32 {
        var x = value
        x ^= x >> 16
        x &*= 0x7feb352d
        x ^= x >> 15
        x &*= 0x846ca68b
        x ^= x >> 16
        return x
    }
    
    /// One pseudo-random number for a lattice point and a seed. The same three inputs always
    /// give the same number. Change any one of them and the number changes completely.
    ///
    /// The hash is nested: hash(x + hash(z + hash(seed))). The result therefore depends on all
    /// three inputs and on which is which: (1, 0) and (0, 1) give different numbers. (The
    /// nesting is from Perlin's 1985 noise, as described by Jarzynski and Olano, "Hash
    /// Functions for GPU Rendering", 2020, section 4.2.)
    ///
    /// `UInt32(truncatingIfNeeded:)` keeps the lowest 32 bits of a signed lattice index and
    /// reads them as unsigned, so -1 becomes 4,294,967,295. `UInt32(latticeX)` would stop the
    /// program on a negative index. The adds use `&+` so that they wrap, like the multiplies in
    /// `scrambleBits`. Only 32 bits of each index are used, so the pattern repeats every 2^32
    /// lattice cells.
    static func hashOfLatticePoint(latticeX: Int, latticeZ: Int, seed: UInt32) -> UInt32 {
        let seedHash = scrambleBits(seed)
        let zHash = scrambleBits(UInt32(truncatingIfNeeded: latticeZ) &+ seedHash)
        return scrambleBits(UInt32(truncatingIfNeeded: latticeX) &+ zHash)
    }
    
    /// The fixed random value of a lattice point: at least -1 and less than +1.
    ///
    /// The top 24 bits of the hash are a whole number from 0 to 16,777,215. Dividing it by
    /// 8,388,608 (2^23) gives a number from 0 up to, but not including, 2. Subtracting 1 moves
    /// that to -1 up to +1.
    ///
    /// The division and the subtraction must be done in Double. In UInt32 the division drops
    /// the fraction (3,133,549 / 8,388,608 is 0), and 0 - 1 does not fit in an unsigned number.
    static func latticeValue(latticeX: Int, latticeZ: Int, seed: UInt32) -> Double {
        let top24Bits = hashOfLatticePoint(latticeX: latticeX, latticeZ: latticeZ, seed: seed) >> 8
        return Double(top24Bits) / 8388608 - 1
    }
    
    /// Perlin's fade curve, 6t⁵ - 15t⁴ + 10t³ (Ken Perlin, "Improving Noise", 2002), written so
    /// that it needs only multiplies and adds.
    ///
    /// `t` is how far the point is across a lattice cell, from 0 to 1. The result is the blend
    /// weight: 0 at t = 0, 0.5 at t = 0.5 and 1 at t = 1. The curve is flat at both ends (zero
    /// slope and zero curvature), so neighbouring cells join without a visible crease.
    static func fadeCurve(t: Double) -> Double {
        t * t * t * (t * (t * 6 - 15) + 10)
    }
    
    /// The value that is `weight` of the way from `start` to `end`: `start` at weight 0, `end`
    /// at weight 1. Often called "lerp" (linear interpolation).
    static func linearBlend(start: Double, end: Double, weight: Double) -> Double {
        start + (end - start) * weight
    }
    
    /// Smooth noise from -1 to +1. `x` and `z` are in noise space: one unit is one lattice cell.
    ///
    /// The point lies in one cell of the lattice. Each of the cell's four corners has a fixed
    /// random value (`latticeValue`). The result is those four values, blended by how far the
    /// point is across the cell. At a lattice point the result is exactly that point's value.
    ///
    /// The lattice index is the floor of the coordinate (the nearest whole number below it),
    /// not the coordinate cut off toward zero: `floor(-0.15625)` is -1, `Int(-0.15625)` is 0.
    /// The two differ for every negative coordinate. With the floor, the fraction runs from 0
    /// up to 1 on both sides of zero.
    static func valueNoise(x: Double, z: Double, seed: UInt32) -> Double {
        // The cell the point is in, and how far across that cell the point is on each axis.
        let latticeX = Int(floor(x))
        let latticeZ = Int(floor(z))
        let fractionX = x - Double(latticeX)
        let fractionZ = z - Double(latticeZ)
        // The fixed random values at the four corners of the cell.
        let valueAtLowXLowZ     = latticeValue(latticeX: latticeX,     latticeZ: latticeZ,     seed: seed)
        let valueAtHighXLowZ    = latticeValue(latticeX: latticeX + 1, latticeZ: latticeZ,     seed: seed)
        let valueAtLowXHighZ    = latticeValue(latticeX: latticeX,     latticeZ: latticeZ + 1, seed: seed)
        let valueAtHighXHighZ   = latticeValue(latticeX: latticeX + 1, latticeZ: latticeZ + 1, seed: seed)
        // Blend along X on the cell's two edges (low Z and high Z), then along Z between the
        // two results.
        let weightX = fadeCurve(t: fractionX)
        let weightZ = fadeCurve(t: fractionZ)
        let alongLowZEdge = linearBlend(start: valueAtLowXLowZ, end: valueAtHighXLowZ, weight: weightX)
        let alongHighZEdge = linearBlend(start: valueAtLowXHighZ, end: valueAtHighXHighZ, weight: weightX)
        return linearBlend(start: alongLowZEdge, end: alongHighZEdge, weight: weightZ)
    }
    
    /// The sum of `octaveCount` octaves of value noise, scaled back into -1 to +1. This sum is
    /// often called fractal Brownian motion (fBm). `x` and `z` are in noise space.
    ///
    /// Octave 0 is the widest and the tallest. For each next octave the frequency is multiplied
    /// by `lacunarity`, so its cells are narrower, and the amplitude by `gain`, so it is lower.
    /// With the defaults (2 and 0.5) every octave is the same shape at half the size.
    ///
    /// Dividing by the sum of the amplitudes, the largest value the sum can reach, keeps the
    /// result between -1 and +1 for any octave count and gain.
    static func fractalNoise(x: Double, z: Double, params: ProceduralTerrainParameters) -> Double {
        var sum: Double = 0
        // amplitude: how tall the current octave is.
        // frequency: how many of the current octave's cells fit across one cell of octave 0.
        var amplitude: Double = 1
        var frequency: Double = 1
        var amplitudeTotal: Double = 0
        for octaveIdx in 0..<params.octaveCount {
            // Each octave has its own seed. With one seed for all of them, lattice point (0, 0)
            // would have the same value in every octave, and the origin of the world would
            // always be an extreme peak or pit.
            let octaveSeed = params.seed &+ octaveIdx
            sum += amplitude * valueNoise(x: x * frequency, z: z * frequency, seed: octaveSeed)
            amplitudeTotal += amplitude
            amplitude *= params.gain
            frequency *= params.lacunarity
        }
        return sum / amplitudeTotal
    }
    
    /// The height of the terrain at one point, in meters, between `-heightAmplitude` and
    /// `+heightAmplitude`.
    ///
    /// - Parameters:
    ///   - xInOriginalFrame: meters along X in the scene's original frame: a stored position
    ///     plus `SceneManager.floatingOriginOffset`, added in Double.
    ///   - zInOriginalFrame: the same along Z.
    ///   - params: which terrain; see `ProceduralTerrainParameters`.
    ///
    /// Dividing by `baseCellSize` converts meters to noise space, where a cell of the widest
    /// octave is 1 unit wide.
    static func heightInMeters(xInOriginalFrame: Double,
                               zInOriginalFrame: Double,
                               params: ProceduralTerrainParameters) -> Double {
        let noiseX = xInOriginalFrame / params.baseCellSize
        let noiseZ = zInOriginalFrame / params.baseCellSize
        return params.heightAmplitude * fractalNoise(x: noiseX, z: noiseZ, params: params)
    }
    
    /// Bakes a square grid of height samples: evaluates `heightInMeters` at every sample of
    /// the grid and stores the results, in meters, as 32-bit floats.
    ///
    /// The grid is a window onto one grid of samples that covers the whole world. A sample is
    /// named by two whole numbers, its sample indices. The sample with index `i` along X and
    /// `k` along Z is at x = `i * sampleSpacing` and z = `k * sampleSpacing`, in the scene's
    /// original frame, for every bake. With 100 m spacing, sample index 5 along X is at 500 m
    /// and sample index -64 is at -6,400 m.
    ///
    /// - Parameters:
    ///   - firstSampleIndexX: the X sample index of column 0 of the grid. May be negative.
    ///   - firstSampleIndexZ: the Z sample index of row 0 of the grid. May be negative.
    ///   - samplesPerSide: how many samples one side of the grid has. Use an odd number, so
    ///     that the grid has a middle sample. A grid centred on the sample with index `center`
    ///     starts at `center - (samplesPerSide - 1) / 2`: with 129 samples, at `center - 64`.
    ///   - sampleSpacing: the distance between neighbouring samples, in meters.
    ///   - params: which terrain; see `ProceduralTerrainParameters`.
    /// - Returns: `samplesPerSide * samplesPerSide` heights in meters, stored row by row
    ///   ("row-major"): the sample in row `row` and column `column` is element
    ///   `row * samplesPerSide + column`. Columns run along +X and rows along +Z. Column
    ///   `column` holds the samples with X index `firstSampleIndexX + column`, and row `row`
    ///   holds the samples with Z index `firstSampleIndexZ + row`.
    ///
    /// The position of a sample is always its whole-number index times the spacing, computed
    /// in Double. It is never "the position of the grid's corner plus a number of steps". Two
    /// bakes that cover the same sample therefore compute it from the same inputs and store
    /// the same bits, wherever each grid starts. The terrain can then move by whole samples
    /// without the ground changing shape.
    ///
    /// `toFloat()` rounds the Double height to the nearest Float. For heights up to 600 m
    /// that moves a height by at most 0.03 mm, half the gap between neighbouring Floats there.
    ///
    /// Plan: Milestone 2.
    static func bakeHeightSamples(firstSampleIndexX: Int,
                                  firstSampleIndexZ: Int,
                                  samplesPerSide: Int,
                                  sampleSpacing: Double,
                                  params: ProceduralTerrainParameters) -> [Float] {
        var heightSamples = Array<Float>(repeating: 0, count: samplesPerSide * samplesPerSide)
        for row in 0..<samplesPerSide {
            // The whole-number sample index first, then one multiply in Double: the same
            // sample index gives the same position in every bake.
            let zInOriginalFrame = Double(firstSampleIndexZ + row) * sampleSpacing
            for column in 0..<samplesPerSide {
                let xInOriginalFrame = Double(firstSampleIndexX + column) * sampleSpacing
                let height = heightInMeters(xInOriginalFrame: xInOriginalFrame,
                                            zInOriginalFrame: zInOriginalFrame,
                                            params: params)
                // Row-major: row 0 fills the first `samplesPerSide` elements, row 1 the next
                // `samplesPerSide`, and so on.
                heightSamples[row * samplesPerSide + column] = height.toFloat()
            }
        }
        return heightSamples
    }

    /// Decides, for one axis, whether a terrain that follows a moving point must be
    /// recentred: moved so that the point is near its middle again. Returns the sample index
    /// the terrain is centred on from now on, or nil when it can stay where it is.
    /// `TerrainObject.follow` calls this once for X and once for Z.
    ///
    /// A baked grid is a window of fixed size onto a world that has no edge (see
    /// `bakeHeightSamples`). The point the window is kept around is called the focus: the
    /// aircraft. Two rules decide when the window moves and where it moves to.
    ///
    /// **When: only once the focus is more than `recenterThresholdInSamples` from the
    /// centre.** A focus exactly at the threshold does not recentre. nil is the usual
    /// result, and it costs one division and one comparison. (`FloatingOrigin.getOffset`
    /// has the same shape: it returns nil when no shift is due.)
    ///
    /// **Where: to the multiple of `snapStepInSamples` nearest the focus**, not to the focus
    /// itself. The centre therefore only ever moves by whole snap steps. `follow` passes a
    /// step of 4 samples, which is one patch at the lowest tessellation factor. Every sample
    /// and every vertex of the moved terrain then lands on a point of the world that had one
    /// before, and `bakeHeightSamples` gives such a sample the same bits in every bake. The
    /// ground that was already on screen keeps its shape. A terrain centred on the focus
    /// itself would slide its vertices over the ground on every tick, and the hills would
    /// seem to swim.
    ///
    /// Together the two rules keep the terrain from being baked again and again. Right after
    /// a recentre the focus is at most half a snap step from the new centre. With a threshold
    /// of one whole snap step, which is what `follow` passes (4 and 4), the focus must travel
    /// at least another half step (200 m) before the next recentre. A focus that goes back
    /// and forth across one line causes one bake, not one per crossing.
    ///
    /// A focus exactly halfway between two multiples goes to the even one
    /// (`.toNearestOrEven`). With a step of 4, a focus at sample 10 is 2 samples from both 8
    /// and 12. 10 / 4 is 2.5, which rounds to the even 2, so the result is 8. `round()` sends
    /// a tie away from zero and would give 12. Either answer gives a correct terrain. The
    /// rule is the one `FloatingOrigin.getOffset` uses for its whole meters.
    ///
    /// Example with 100 m spacing, a step of 4 and a threshold of 4, from centre 0: a focus at
    /// 400 m gives nil, 400.5 m gives 4, and 1,000.5 m gives 12 (10.005 / 4 = 2.50125, which
    /// rounds to 3).
    ///
    /// - Parameters:
    ///   - currentCenterSampleIndex: the sample index the terrain is centred on now, on this
    ///     axis.
    ///   - focusPositionInOriginalFrame: the focus's coordinate on this axis, in meters, in
    ///     the scene's original frame: a stored position plus
    ///     `SceneManager.floatingOriginOffset`, added in Double.
    ///   - sampleSpacing: the distance between neighbouring samples, in meters.
    ///   - snapStepInSamples: the centre is a multiple of this many samples. It is a Double
    ///     because the focus is divided by it, but it must hold a whole number: the rounded
    ///     quotient is multiplied by `Int(snapStepInSamples)`, and `Int(_:)` drops a fraction.
    ///     A step of 2.5 would divide by 2.5 and multiply by 2.
    ///   - recenterThresholdInSamples: how far the focus may be from the centre, in samples,
    ///     before a recentre is due. It must be at least half the snap step. Below that, a
    ///     focus can be past the threshold while the nearest multiple is still the current
    ///     centre; the function then returns the centre it was given, on every call, and
    ///     `follow` would bake on every tick. At exactly half a step there is no travel left
    ///     between recentres, so a focus that crosses a halfway line back and forth causes a
    ///     bake per crossing.
    /// - Returns: the new centre sample index, a multiple of the snap step, or nil when the
    ///   focus is within the threshold.
    ///
    /// The focus must be a finite number. NaN (not a number) compares false with everything,
    /// so it gets past the threshold check, and the conversion to `Int` then stops the
    /// program. An infinite focus stops it at the same line.
    ///
    /// Plan: Milestone 4.
    static func recenteredCenterSampleIndex(currentCenterSampleIndex: Int,
                                            focusPositionInOriginalFrame: Double,
                                            sampleSpacing: Double,
                                            snapStepInSamples: Double,
                                            recenterThresholdInSamples: Double) -> Int? {
        // Meters to samples. A whole number here means the focus is exactly on a sample.
        let focusInSamples = focusPositionInOriginalFrame / sampleSpacing
        if abs(focusInSamples - Double(currentCenterSampleIndex)) <= recenterThresholdInSamples {
            return nil
        }

        // How many snap steps from sample 0 the focus is, rounded to a whole number of steps.
        // Times the step, that is the multiple of the step nearest the focus.
        let nearestStep = Int((focusInSamples / snapStepInSamples).rounded(.toNearestOrEven))
        return nearestStep * Int(snapStepInSamples)
    }

    /// Where the terrain node must be stored so that its middle sits on the given sample.
    ///
    /// The centre sample is a place in the scene's original frame: its sample index times the
    /// spacing, the rule `bakeHeightSamples` uses for every sample. A node's stored position
    /// is in the current frame, the one the floating origin has shifted to.
    /// `floatingOriginOffset` is the position of the current origin in the original frame, so
    /// the stored position is the centre minus that offset.
    ///
    /// y is the height of the terrain's base. The base is at height 0 in the original frame,
    /// so it is stored at `-floatingOriginOffset.y`.
    ///
    /// Example: with 100 m spacing, centre sample (520, -172) is at (52,000, 0, -17,200) m in
    /// the original frame. With an offset of (52,812, 432, -17,640) the stored position is
    /// (-812, -432, 440). The stored y is -432 because the origin has moved 432 m up.
    ///
    /// The subtraction is done in Double, and only the result is narrowed to Float. Far from
    /// the original origin the centre and the offset are both large and their difference is
    /// small. A Float holds every whole number only up to 16,777,216 (2^24). Beyond
    /// 16,777 km, or with a spacing that is not a whole number of meters, narrowing the two
    /// first would round each of them before the subtraction: at 123,456 km the gap between
    /// neighbouring Floats is 8 m.
    ///
    /// - Parameters:
    ///   - centerSampleIndexX: the X sample index of the terrain's middle. A Double here, so
    ///     the caller converts its whole-number index: `Double(centerSampleIndexX)`.
    ///   - centerSampleIndexZ: the same along Z.
    ///   - sampleSpacing: the distance between neighbouring samples, in meters.
    ///   - floatingOriginOffset: `SceneManager.floatingOriginOffset`, in meters.
    /// - Returns: the position to hand to `setPosition`, in meters, in the current frame.
    ///
    /// Plan: Milestone 4.
    static func storedPositionOfTerrainCenter(centerSampleIndexX: Double,
                                              centerSampleIndexZ: Double,
                                              sampleSpacing: Double,
                                              floatingOriginOffset: double3) -> float3 {
        let centerInOriginalFrame: double3 = [centerSampleIndexX * sampleSpacing, 0, centerSampleIndexZ * sampleSpacing]
        return (centerInOriginalFrame - floatingOriginOffset).toFloat3()
    }
}
