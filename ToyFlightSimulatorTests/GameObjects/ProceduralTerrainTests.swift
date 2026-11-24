//
//  ProceduralTerrainTests.swift
//  ToyFlightSimulatorTests
//
//  The procedural terrain height function, one step at a time: the bit scrambler, the hash
//  of a lattice point, the lattice value, the fade curve, value noise, the sum of octaves and
//  the height in meters. Every function is pure (no engine state, no Metal), so each test
//  calls it directly.
//
//  No expected number is copied from the output of the code under test. Each one comes from
//  the worked example in plans/claude/procedural_terrain_generation_2026-11-22.md, which two
//  independent scripts computed (one in Swift, one in Python), or from arithmetic that the
//  comment next to it shows. The worked example uses the default parameters (seed 2026, base
//  cell 3,200 m, amplitude 600 m, 4 octaves) at x = 1,000 m, z = -500 m. In noise space that
//  point is (0.3125, -0.15625). The negative z is on purpose: it is where "floor" and "cut off
//  toward zero" give different lattice cells.
//

import Testing
@testable import ToyFlightSimulator

@Suite("ProceduralTerrain: the height function", .tags(.gameObjects))
struct ProceduralTerrainTests {

    /// The seed of the worked example. It is also the default seed.
    private let workedExampleSeed: UInt32 = 2026

    /// The four corners of the lattice cell that holds the worked example's point in octave 0.
    /// `hash` is what hashOfLatticePoint returns. `value` is what latticeValue returns: the
    /// top 24 bits of the hash, divided by 8,388,608, minus 1.
    private let workedExampleCorners: [(latticeX: Int, latticeZ: Int, hash: UInt32, value: Double)] = [
        (0, -1, 0x2fd06d87, -0.626452),
        (1, -1, 0x548d2c8c, -0.339442),
        (0,  0, 0x58eb345b, -0.305322),
        (1,  0, 0xce553f58,  0.611977),
    ]

    // MARK: - scrambleBits

    @Test("scrambleBits gives the values of the lowbias32 hash")
    func scrambleBitsMatchesReferenceValues() {
        #expect(ProceduralTerrain.scrambleBits(0) == 0)
        #expect(ProceduralTerrain.scrambleBits(1) == 0x688990c0)
        #expect(ProceduralTerrain.scrambleBits(2026) == 0x41cfd7c2)
        // The largest input: both multiplies overflow 32 bits here, so a missing wrap shows.
        #expect(ProceduralTerrain.scrambleBits(0xffff_ffff) == 0x6768824a)
    }

    // MARK: - hashOfLatticePoint

    // This is the test that catches a missing wrap, a wrong nesting order, or a negative
    // index that was clamped to 0 instead of keeping its low 32 bits.
    @Test("the hash of a lattice point matches the worked example")
    func latticeHashMatchesWorkedExample() {
        for corner in workedExampleCorners {
            let hash = ProceduralTerrain.hashOfLatticePoint(latticeX: corner.latticeX,
                                                            latticeZ: corner.latticeZ,
                                                            seed: workedExampleSeed)
            #expect(hash == corner.hash, "lattice point (\(corner.latticeX), \(corner.latticeZ))")
        }
    }

    @Test("the hash changes when X and Z are swapped, and when the seed changes")
    func latticeHashDependsOnEveryInput() {
        let hash = ProceduralTerrain.hashOfLatticePoint(latticeX: 1, latticeZ: 0, seed: 2026)
        #expect(hash != ProceduralTerrain.hashOfLatticePoint(latticeX: 0, latticeZ: 1, seed: 2026))
        #expect(hash != ProceduralTerrain.hashOfLatticePoint(latticeX: 1, latticeZ: 0, seed: 2027))
    }

    @Test("only the low 32 bits of a lattice index are used, so the pattern repeats every 2^32 cells")
    func latticeHashRepeatsEveryTwoToThe32Cells() {
        let cellsPerRepeat = 4_294_967_296  // 2^32
        // -1 and 4,294,967,295 have the same low 32 bits (all of them set).
        #expect(ProceduralTerrain.hashOfLatticePoint(latticeX: -1, latticeZ: 5, seed: 2026)
                == ProceduralTerrain.hashOfLatticePoint(latticeX: -1 + cellsPerRepeat, latticeZ: 5, seed: 2026))
        #expect(ProceduralTerrain.hashOfLatticePoint(latticeX: 3, latticeZ: -7, seed: 2026)
                == ProceduralTerrain.hashOfLatticePoint(latticeX: 3, latticeZ: -7 - cellsPerRepeat, seed: 2026))
    }

    // MARK: - latticeValue

    @Test("the lattice value matches the worked example")
    func latticeValueMatchesWorkedExample() {
        for corner in workedExampleCorners {
            let value = ProceduralTerrain.latticeValue(latticeX: corner.latticeX,
                                                       latticeZ: corner.latticeZ,
                                                       seed: workedExampleSeed)
            #expect(abs(value - corner.value) <= 1e-6,
                    "lattice point (\(corner.latticeX), \(corner.latticeZ)) gave \(value)")
        }
    }

    @Test("every lattice value is at least -1 and less than +1, and the values fill that range")
    func latticeValueStaysInRange() {
        // 41 x 41 lattice points around the origin, negative indices included, for 5 seeds:
        // 8,405 values.
        var lowestValue = Double.infinity
        var highestValue = -Double.infinity
        for seed: UInt32 in [0, 1, 2026, 2027, 0xffff_ffff] {
            for latticeX in -20...20 {
                for latticeZ in -20...20 {
                    let value = ProceduralTerrain.latticeValue(latticeX: latticeX, latticeZ: latticeZ, seed: seed)
                    lowestValue = min(lowestValue, value)
                    highestValue = max(highestValue, value)
                }
            }
        }
        #expect(lowestValue >= -1)
        #expect(highestValue < 1)
        // The values are spread over the whole range, not bunched in one part of it.
        #expect(lowestValue < -0.99)
        #expect(highestValue > 0.99)
    }

    @Test("seed 0 at lattice point (0, 0) gives exactly -1, the lowest value there is")
    func latticeValueOfTheAllZeroInput() {
        // scrambleBits(0) is 0, so every level of the nested hash is 0: 0 / 8,388,608 - 1 = -1.
        #expect(ProceduralTerrain.latticeValue(latticeX: 0, latticeZ: 0, seed: 0) == -1)
    }

    // MARK: - fadeCurve and linearBlend

    @Test("the fade curve is 0 at 0, one half at one half, and 1 at 1")
    func fadeCurveValues() {
        // Every input is a multiple of 1/4, so every step of the arithmetic is exact in Double.
        #expect(ProceduralTerrain.fadeCurve(t: 0) == 0)
        #expect(ProceduralTerrain.fadeCurve(t: 0.25) == 0.103515625)
        #expect(ProceduralTerrain.fadeCurve(t: 0.5) == 0.5)
        #expect(ProceduralTerrain.fadeCurve(t: 0.75) == 0.896484375)
        #expect(ProceduralTerrain.fadeCurve(t: 1) == 1)
    }

    @Test("the fade curve is flat at both ends")
    func fadeCurveIsFlatAtBothEnds() {
        // One thousandth of the way in, the fifth-degree curve has moved about 10 x 0.001^3 =
        // 0.00000001. A straight line would have moved 0.001, and the simpler curve
        // 3t^2 - 2t^3 would have moved 0.000003. Both fail this test.
        #expect(ProceduralTerrain.fadeCurve(t: 0.001) < 1e-7)
        #expect(1 - ProceduralTerrain.fadeCurve(t: 0.999) < 1e-7)
    }

    @Test("linearBlend is start at weight 0, end at weight 1, and in proportion between them")
    func linearBlendValues() {
        #expect(ProceduralTerrain.linearBlend(start: -2, end: 6, weight: 0) == -2)
        #expect(ProceduralTerrain.linearBlend(start: -2, end: 6, weight: 0.25) == 0)
        #expect(ProceduralTerrain.linearBlend(start: -2, end: 6, weight: 0.5) == 2)
        #expect(ProceduralTerrain.linearBlend(start: -2, end: 6, weight: 1) == 6)
    }

    // MARK: - valueNoise

    @Test("at a lattice point, value noise is exactly that point's lattice value")
    func valueNoiseEqualsLatticeValueAtLatticePoints() {
        // The plan's number for lattice point (1, 2).
        #expect(abs(ProceduralTerrain.valueNoise(x: 1, z: 2, seed: workedExampleSeed) - 0.964206) <= 1e-6)

        // At a lattice point both fractions are 0, so both weights are 0 and nothing is
        // blended in: the comparison is exact. In four of the five points X and Z differ, so
        // code that reads one axis where it means the other cannot pass.
        for (latticeX, latticeZ) in [(1, 2), (0, 0), (-3, 5), (7, -4), (-6, -2)] {
            let noise = ProceduralTerrain.valueNoise(x: Double(latticeX), z: Double(latticeZ),
                                                     seed: workedExampleSeed)
            let value = ProceduralTerrain.latticeValue(latticeX: latticeX, latticeZ: latticeZ,
                                                       seed: workedExampleSeed)
            #expect(noise == value, "lattice point (\(latticeX), \(latticeZ))")
        }
    }

    @Test("value noise takes the floor of a negative coordinate (worked example, octave 0)")
    func valueNoiseUsesFloorForNegativeCoordinates() {
        // (0.3125, -0.15625) lies in cell (0, -1), 0.84375 of the way across it along Z.
        // Cutting -0.15625 off toward zero would give cell (0, 0) and a negative fraction.
        let noise = ProceduralTerrain.valueNoise(x: 0.3125, z: -0.15625, seed: workedExampleSeed)
        #expect(abs(noise - (-0.153138)) <= 1e-6, "value noise gave \(noise)")
    }

    @Test("value noise matches all four octaves of the worked example")
    func valueNoiseMatchesWorkedExampleOctaves() {
        // Octave i reads the point at 2^i times its coordinates, with seed 2026 + i.
        let octaves: [(x: Double, z: Double, seed: UInt32, noise: Double)] = [
            (0.3125, -0.15625, 2026, -0.153138),
            (0.625,  -0.3125,  2027, -0.533755),
            (1.25,   -0.625,   2028, -0.612561),
            (2.5,    -1.25,    2029,  0.268727),
        ]
        for octave in octaves {
            let noise = ProceduralTerrain.valueNoise(x: octave.x, z: octave.z, seed: octave.seed)
            #expect(abs(noise - octave.noise) <= 1e-6, "seed \(octave.seed) gave \(noise)")
        }
    }

    @Test("value noise has no step where two lattice cells meet")
    func valueNoiseIsContinuousAcrossCellEdges() {
        let stepAcrossTheEdge = 1e-9
        let positionInsideACell = 0.37
        for edge in [-1.0, 0.0, 1.0] {
            // Cross the edge along X, then cross the same edge along Z.
            let changeAlongX = abs(
                ProceduralTerrain.valueNoise(x: edge - stepAcrossTheEdge, z: positionInsideACell, seed: workedExampleSeed)
                - ProceduralTerrain.valueNoise(x: edge + stepAcrossTheEdge, z: positionInsideACell, seed: workedExampleSeed))
            let changeAlongZ = abs(
                ProceduralTerrain.valueNoise(x: positionInsideACell, z: edge - stepAcrossTheEdge, seed: workedExampleSeed)
                - ProceduralTerrain.valueNoise(x: positionInsideACell, z: edge + stepAcrossTheEdge, seed: workedExampleSeed))
            #expect(changeAlongX < 1e-6, "crossing x = \(edge)")
            #expect(changeAlongZ < 1e-6, "crossing z = \(edge)")
        }
    }

    @Test("value noise stays between -1 and +1 between the lattice points")
    func valueNoiseStaysInRange() {
        // 61 x 61 points from -3.9 to 3.9, 0.13 apart: 3,721 values, none on a lattice point.
        // A blend of four values between -1 and +1, with weights between 0 and 1, cannot
        // leave that range. A fraction outside 0 ... 1 can.
        var lowestNoise = Double.infinity
        var highestNoise = -Double.infinity
        for xStep in -30...30 {
            for zStep in -30...30 {
                let noise = ProceduralTerrain.valueNoise(x: Double(xStep) * 0.13, z: Double(zStep) * 0.13,
                                                         seed: workedExampleSeed)
                lowestNoise = min(lowestNoise, noise)
                highestNoise = max(highestNoise, noise)
            }
        }
        #expect(lowestNoise >= -1)
        #expect(highestNoise <= 1)
    }

    // MARK: - fractalNoise

    @Test("with one octave, fractal noise is value noise")
    func fractalNoiseWithOneOctaveIsValueNoise() {
        let oneOctave = ProceduralTerrainParameters(octaveCount: 1)
        // One octave of amplitude 1, divided by an amplitude total of 1: exact.
        #expect(ProceduralTerrain.fractalNoise(x: 0.3125, z: -0.15625, params: oneOctave)
                == ProceduralTerrain.valueNoise(x: 0.3125, z: -0.15625, seed: oneOctave.seed))
    }

    @Test("fractal noise matches the worked example")
    func fractalNoiseMatchesWorkedExample() {
        // (-0.153138 - 0.5 x 0.533755 - 0.25 x 0.612561 + 0.125 x 0.268727) / 1.875 = -0.287768.
        // 1.875 is the sum of the amplitudes 1 + 0.5 + 0.25 + 0.125.
        let noise = ProceduralTerrain.fractalNoise(x: 0.3125, z: -0.15625, params: ProceduralTerrainParameters())
        #expect(abs(noise - (-0.287768)) <= 1e-6, "fractal noise gave \(noise)")
    }

    // MARK: - heightInMeters

    @Test("the height matches the worked example and three more points")
    func heightMatchesWorkedExample() {
        // Meters, in the scene's original frame. (0, 0) and (6400, 6400) have x equal to z;
        // the other two do not, so they also catch code that mixes up the two axes.
        let expectedHeights: [(x: Double, z: Double, height: Double)] = [
            (1_000,  -500, -172.6609),
            (0,         0, -172.9908),
            (3_200, 6_400,  533.9311),
            (6_400, 6_400, -110.4141),
        ]
        for expected in expectedHeights {
            let height = ProceduralTerrain.heightInMeters(xInOriginalFrame: expected.x,
                                                          zInOriginalFrame: expected.z,
                                                          params: ProceduralTerrainParameters())
            #expect(abs(height - expected.height) <= 1e-3,
                    "height at (\(expected.x), \(expected.z)) was \(height) m")
        }
    }

    @Test("the same inputs give the same height, and another seed gives another height")
    func heightIsDeterministicAndDependsOnTheSeed() {
        let defaultParameters = ProceduralTerrainParameters()
        let firstHeight = ProceduralTerrain.heightInMeters(xInOriginalFrame: 1_000, zInOriginalFrame: -500,
                                                           params: defaultParameters)
        // A call for another point in between must not change the answer: there is no state.
        _ = ProceduralTerrain.heightInMeters(xInOriginalFrame: -7_300, zInOriginalFrame: 4_100,
                                             params: defaultParameters)
        let secondHeight = ProceduralTerrain.heightInMeters(xInOriginalFrame: 1_000, zInOriginalFrame: -500,
                                                            params: defaultParameters)
        #expect(firstHeight == secondHeight)

        let otherSeed = ProceduralTerrainParameters(seed: 7)
        let heightWithOtherSeed = ProceduralTerrain.heightInMeters(xInOriginalFrame: 1_000, zInOriginalFrame: -500,
                                                                   params: otherSeed)
        #expect(heightWithOtherSeed != firstHeight)
    }

    @Test("the amplitude scales the height, and the base cell size scales the ground distance")
    func heightScalesWithAmplitudeAndBaseCellSize() {
        let defaultHeight = ProceduralTerrain.heightInMeters(xInOriginalFrame: 1_000, zInOriginalFrame: -500,
                                                             params: ProceduralTerrainParameters())

        // Twice the amplitude: every height doubles. Doubling is exact in Double.
        let twiceAsTall = ProceduralTerrainParameters(heightAmplitude: 1_200)
        #expect(ProceduralTerrain.heightInMeters(xInOriginalFrame: 1_000, zInOriginalFrame: -500, params: twiceAsTall)
                == 2 * defaultHeight)

        // Twice the base cell size: the same terrain, stretched to twice the size on the
        // ground, so the point twice as far out has the height this point had. 2,000 / 6,400
        // and 1,000 / 3,200 are both exactly 0.3125.
        let twiceAsWide = ProceduralTerrainParameters(baseCellSize: 6_400)
        #expect(ProceduralTerrain.heightInMeters(xInOriginalFrame: 2_000, zInOriginalFrame: -1_000, params: twiceAsWide)
                == defaultHeight)
    }

    @Test("the height stays within the amplitude, and the terrain is not flat")
    func heightStaysWithinTheAmplitude() {
        // 73 x 73 points over a square of about 100 km, 1,370 m apart: 5,329 heights. 1,370 m
        // is not a multiple of any octave's cell size, so the points fall at many different
        // places inside the cells.
        let parameters = ProceduralTerrainParameters()
        var lowestHeight = Double.infinity
        var highestHeight = -Double.infinity
        for x in stride(from: -50_000.0, through: 50_000.0, by: 1_370.0) {
            for z in stride(from: -50_000.0, through: 50_000.0, by: 1_370.0) {
                let height = ProceduralTerrain.heightInMeters(xInOriginalFrame: x, zInOriginalFrame: z,
                                                              params: parameters)
                lowestHeight = min(lowestHeight, height)
                highestHeight = max(highestHeight, height)
            }
        }
        #expect(lowestHeight >= -parameters.heightAmplitude)
        #expect(highestHeight <= parameters.heightAmplitude)
        // There are real hills and valleys: at least one of these points is more than 300 m
        // below zero and at least one is more than 300 m above it.
        #expect(lowestHeight < -300)
        #expect(highestHeight > 300)
    }

    @Test("5,000 km from the origin, a step of 1 mm still changes the height by less than 1 cm")
    func heightIsSmoothFarFromTheOrigin() {
        // This is why positions are Double. A Float 5,000 km out can only hold multiples of
        // 0.5 m, so two points 1 mm apart would be the same point or half a meter apart.
        let parameters = ProceduralTerrainParameters()
        let farX = 5_000_000.0  // meters
        let farZ = -3_000_000.0
        let height = ProceduralTerrain.heightInMeters(xInOriginalFrame: farX, zInOriginalFrame: farZ,
                                                      params: parameters)
        let heightOneMillimeterOn = ProceduralTerrain.heightInMeters(xInOriginalFrame: farX + 0.001,
                                                                     zInOriginalFrame: farZ + 0.001,
                                                                     params: parameters)
        #expect(height.isFinite)
        #expect(height != heightOneMillimeterOn)
        #expect(abs(height - heightOneMillimeterOn) < 0.01)
    }
}
