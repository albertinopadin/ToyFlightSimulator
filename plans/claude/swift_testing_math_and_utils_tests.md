# Swift Testing Migration Plan — Math & Utils

## Context

The ToyFlightSimulator test suite currently contains only two XCTest files (`NodeTests.swift`, `RendererTests.swift`) covering `Node` hierarchy and `Renderer` lifecycle. The stable, mostly-pure code in `ToyFlightSimulator Shared/Math/` and `ToyFlightSimulator Shared/Utils/` has **no test coverage**, despite being foundational for rendering correctness (projection matrices, rotation decomposition, coordinate-system conversion, caching, and locking).

This plan introduces tests using Apple's **Swift Testing** framework (not XCTest) for:

- `Math.swift` — axis constants, `Float` radian/degree conversions, `matrix_float4x4` mutating ops, left-handed perspective
- `Transform.swift` — enum of pure matrix-construction functions, TRS decomposition, Euler decomposition, coordinate-swap presets
- `MathUtils.swift` — `align`/`gcd`/`lcm`/`mipmapLevelCount`, `SIMD4.xyz`, `float4x4` convenience initializers, `simd_quatf.rotate`
- `Utils/TFSCache.swift` — thread-safe NSCache wrapper (insert/value/remove/subscript/count)
- `Utils/TFSLock.swift` + `Utils/LockUtils.swift` — semaphore serialization and `withLock` helper
- `Utils/MDLMaterialSemantic+Extensions.swift` — `allCases` and `toString()` mapping
- `Utils/TimeIt.swift` — `timeit` nanosecond timing helper

Out of scope (requires refactor or Metal setup): `ModelIO+Extensions.swift` (force-casts, needs unsafe input), `MTKMesh+Extensions.swift` (requires live MTKMesh + Metal buffer), `Float.randomZeroToOne` (non-deterministic).

### Why Swift Testing

- Modern API: `@Test`, `@Suite`, `#expect`, `#require` — clearer than XCTest
- Parameterized tests via `@Test(arguments:)` — math code has many "table of cases" scenarios
- Tags/traits for filtering and categorization
- Parallel execution by default
- Coexists with XCTest; existing `NodeTests`/`RendererTests` remain untouched

### Compatibility

The test target in `project.pbxproj` declares deployment targets of **iOS 26.0 / macOS 26.0**, comfortably above Swift Testing's Xcode 16 baseline (iOS 18 / macOS 15). Swift Testing is built into the toolchain — **no Swift Package dependency needed**. `import Testing` works out of the box.

The main app targets (iOS 16 / macOS 14) are irrelevant here because Swift Testing runs only inside the test bundle.

---

## Design Decisions

### File organization

Place new tests alongside existing ones in `ToyFlightSimulatorTests/`:

```
ToyFlightSimulatorTests/
  NodeTests.swift                      (existing XCTest)
  RendererTests.swift                  (existing XCTest)
  Math/
    MathTests.swift                    (new, Swift Testing)
    TransformTests.swift               (new, Swift Testing)
    MathUtilsTests.swift               (new, Swift Testing)
  Utils/
    TFSCacheTests.swift                (new, Swift Testing)
    TFSLockTests.swift                 (new, covers TFSLock + LockUtils)
    MDLMaterialSemanticTests.swift     (new)
    TimeItTests.swift                  (new)
  TestSupport/
    ApproxEqual.swift                  (new, shared float helpers)
    TestTags.swift                     (new, tag definitions)
```

Subfolders keep Math and Utils tests discoverable. All new files use `@testable import ToyFlightSimulator` so internal members like `TFSCache` are reachable.

### Floating-point comparison

Swift Testing has no built-in `XCTAssertEqual(_, _, accuracy:)` equivalent. A tiny helper matches the tolerance patterns used in `NodeTests.swift` (0.001 for matrix/vector work):

```swift
// TestSupport/ApproxEqual.swift
import simd

let defaultTolerance: Float = 1e-4

func approxEqual(_ a: Float, _ b: Float, tolerance: Float = defaultTolerance) -> Bool {
    abs(a - b) <= tolerance
}

func approxEqual(_ a: SIMD3<Float>, _ b: SIMD3<Float>, tolerance: Float = defaultTolerance) -> Bool {
    approxEqual(a.x, b.x, tolerance: tolerance) &&
    approxEqual(a.y, b.y, tolerance: tolerance) &&
    approxEqual(a.z, b.z, tolerance: tolerance)
}

func approxEqual(_ a: SIMD4<Float>, _ b: SIMD4<Float>, tolerance: Float = defaultTolerance) -> Bool {
    approxEqual(a.x, b.x, tolerance: tolerance) &&
    approxEqual(a.y, b.y, tolerance: tolerance) &&
    approxEqual(a.z, b.z, tolerance: tolerance) &&
    approxEqual(a.w, b.w, tolerance: tolerance)
}

func approxEqual(_ a: simd_float4x4, _ b: simd_float4x4, tolerance: Float = defaultTolerance) -> Bool {
    approxEqual(a.columns.0, b.columns.0, tolerance: tolerance) &&
    approxEqual(a.columns.1, b.columns.1, tolerance: tolerance) &&
    approxEqual(a.columns.2, b.columns.2, tolerance: tolerance) &&
    approxEqual(a.columns.3, b.columns.3, tolerance: tolerance)
}

func approxEqual(_ a: simd_float3x3, _ b: simd_float3x3, tolerance: Float = defaultTolerance) -> Bool {
    approxEqual(a.columns.0, b.columns.0, tolerance: tolerance) &&
    approxEqual(a.columns.1, b.columns.1, tolerance: tolerance) &&
    approxEqual(a.columns.2, b.columns.2, tolerance: tolerance)
}
```

### Tags

```swift
// TestSupport/TestTags.swift
import Testing

extension Tag {
    @Tag static var math: Self
    @Tag static var utils: Self
    @Tag static var concurrency: Self
}
```

Enables running a subset, e.g. `xcodebuild test ... -only-testing:ToyFlightSimulatorTests ... (filter by tag)` or via the Xcode UI.

---

## Test File Designs

### 1. `MathTests.swift`

Covers `Math.swift`. Exercises axis constants, `Float` conversions, mutating matrix ops, and the static left-handed perspective.

```swift
import Testing
import simd
@testable import ToyFlightSimulator

@Suite("Math.swift", .tags(.math))
struct MathTests {

    // MARK: - Axis constants

    @Test("Axis constants are unit vectors along their respective axes")
    func axisConstants() {
        #expect(X_AXIS == SIMD3<Float>(1, 0, 0))
        #expect(Y_AXIS == SIMD3<Float>(0, 1, 0))
        #expect(Z_AXIS == SIMD3<Float>(0, 0, 1))
    }

    // MARK: - Float radian/degree conversion

    @Test("toRadians converts common angles", arguments: [
        (Float(0),    Float(0)),
        (Float(90),   Float.pi / 2),
        (Float(180),  Float.pi),
        (Float(360),  2 * Float.pi),
        (Float(-90), -Float.pi / 2),
    ])
    func toRadians(degrees: Float, expected: Float) {
        #expect(approxEqual(degrees.toRadians, expected))
    }

    @Test("toDegrees is the inverse of toRadians")
    func roundTrip() {
        for deg in stride(from: Float(-360), through: 360, by: 45) {
            #expect(approxEqual(deg.toRadians.toDegrees, deg))
        }
    }

    // MARK: - matrix_float4x4 mutating ops

    @Test("translate mutates an identity matrix into a pure translation")
    func translateFromIdentity() {
        var m = matrix_identity_float4x4
        m.translate(direction: SIMD3<Float>(2, 3, 4))
        let expected = Transform.translationMatrix(SIMD3<Float>(2, 3, 4))
        #expect(approxEqual(m, expected))
    }

    @Test("scale mutates an identity matrix into a pure scale")
    func scaleFromIdentity() {
        var m = matrix_identity_float4x4
        m.scale(axis: SIMD3<Float>(2, 3, 4))
        let expected = Transform.scaleMatrix(SIMD3<Float>(2, 3, 4))
        #expect(approxEqual(m, expected))
    }

    @Test("rotate by 90° around Y maps +X to -Z")
    func rotateAroundY() {
        var m = matrix_identity_float4x4
        m.rotate(angle: .pi / 2, axis: Y_AXIS)
        let rotatedX = m * SIMD4<Float>(1, 0, 0, 0)
        #expect(approxEqual(rotatedX.xyz, SIMD3<Float>(0, 0, -1)))
    }

    // MARK: - Static perspective

    @Test("perspective produces a finite matrix for typical camera params")
    func perspectiveIsFinite() {
        let m = matrix_float4x4.perspective(degreesFov: 65,
                                            aspectRatio: 16.0 / 9.0,
                                            near: 0.1,
                                            far: 1000)
        #expect(m.columns.0.x.isFinite)
        #expect(m.columns.1.y.isFinite)
        #expect(m.columns.2.z.isFinite)
        // Left-handed Metal convention: w column encodes -near*far/(far-near)
        #expect(m.columns.3.z < 0)
        #expect(m.columns.2.w == 1)   // projective w comes from +z_eye
    }

    @Test("perspective matches Transform.perspectiveProjection when given equivalent inputs")
    func perspectiveMatchesTransform() {
        let fovDeg: Float = 60
        let aspect: Float = 1.5
        let near: Float = 0.1
        let far: Float = 100
        let a = matrix_float4x4.perspective(degreesFov: fovDeg,
                                            aspectRatio: aspect,
                                            near: near,
                                            far: far)
        let b = Transform.perspectiveProjection(fovDeg.toRadians, aspect, near, far)
        #expect(approxEqual(a, b))
    }
}
```

### 2. `TransformTests.swift`

Covers every static function in the `Transform` enum plus `float4x4.identity`. Heavy use of parameterized tests for the coordinate-swap matrices and round-trip TRS decomposition.

```swift
import Testing
import simd
@testable import ToyFlightSimulator

@Suite("Transform", .tags(.math))
struct TransformTests {

    // MARK: - translation / scale / normal

    @Test("translationMatrix places translation in column 3")
    func translationMatrixBasics() {
        let t = SIMD3<Float>(5, -3, 2)
        let m = Transform.translationMatrix(t)
        #expect(m.columns.3 == SIMD4<Float>(5, -3, 2, 1))
        #expect(m.columns.0 == SIMD4<Float>(1, 0, 0, 0))
    }

    @Test("scaleMatrix places scale on the diagonal")
    func scaleMatrixBasics() {
        let m = Transform.scaleMatrix(SIMD3<Float>(2, 3, 4))
        #expect(m.columns.0.x == 2)
        #expect(m.columns.1.y == 3)
        #expect(m.columns.2.z == 4)
        #expect(m.columns.3.w == 1)
    }

    @Test("normalMatrix extracts the upper-left 3x3")
    func normalMatrixBasics() {
        let model = Transform.rotationMatrix(radians: 1.2, axis: SIMD3<Float>(0, 1, 0))
            * Transform.scaleMatrix(SIMD3<Float>(2, 2, 2))
        let n = Transform.normalMatrix(from: model)
        #expect(approxEqual(n.columns.0, model.columns.0.xyz))
        #expect(approxEqual(n.columns.1, model.columns.1.xyz))
        #expect(approxEqual(n.columns.2, model.columns.2.xyz))
    }

    // MARK: - rotationMatrix

    @Test("rotationMatrix normalizes a non-unit axis")
    func rotationNormalizesAxis() {
        let a = Transform.rotationMatrix(radians: .pi / 3, axis: SIMD3<Float>(0, 2, 0))
        let b = Transform.rotationMatrix(radians: .pi / 3, axis: SIMD3<Float>(0, 1, 0))
        #expect(approxEqual(a, b))
    }

    @Test("rotating a vector 90° around Z maps +X to +Y (left-handed)")
    func rotationZ() {
        let r = Transform.rotationMatrix(radians: .pi / 2, axis: SIMD3<Float>(0, 0, 1))
        let v = r * SIMD4<Float>(1, 0, 0, 0)
        #expect(approxEqual(v.xyz, SIMD3<Float>(0, 1, 0)))
    }

    // MARK: - projections

    @Test("orthographicProjection maps the view volume corners into NDC")
    func orthoCorners() {
        let m = Transform.orthographicProjection(-1, 1, -1, 1, 0, 10)
        let nearCenter = m * SIMD4<Float>(0, 0, 0, 1)
        let farCenter  = m * SIMD4<Float>(0, 0, 10, 1)
        #expect(approxEqual(nearCenter.z, 0))   // left-handed Metal: near→0
        #expect(approxEqual(farCenter.z,  1))   // far→1
    }

    @Test("perspectiveProjection places near plane at z=0 in NDC")
    func perspNearPlane() {
        let m = Transform.perspectiveProjection(Float(60).toRadians, 1.0, 0.1, 100)
        let pt = m * SIMD4<Float>(0, 0, 0.1, 1)
        #expect(approxEqual(pt.z / pt.w, 0, tolerance: 1e-3))
    }

    // MARK: - look

    @Test("look-at with eye behind origin, looking forward, produces identity-like view")
    func lookForward() {
        let view = Transform.look(eye:    SIMD3<Float>(0, 0, -1),
                                  target: SIMD3<Float>(0, 0,  0),
                                  up:     SIMD3<Float>(0, 1,  0))
        // Transforming the target point should yield the origin in view space.
        let t = view * SIMD4<Float>(0, 0, 0, 1)
        #expect(approxEqual(t.xyz, SIMD3<Float>(0, 0, 1)))
    }

    // MARK: - decomposeToEulers

    @Test("decomposeToEulers recovers a small rotation about Y")
    func decomposeEulersY() {
        let angle: Float = 0.3
        let r = Transform.rotationMatrix(radians: angle, axis: SIMD3<Float>(0, 1, 0))
        let eulers = Transform.decomposeToEulers(r)
        #expect(approxEqual(eulers.y, -angle, tolerance: 1e-3))
    }

    @Test("decomposeToEulers handles gimbal-lock singularity without NaN")
    func decomposeEulersSingularity() {
        // Near-singular matrix: rotation ≈ 90° around X (sy → 0)
        let r = Transform.rotationMatrix(radians: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        let eulers = Transform.decomposeToEulers(r)
        #expect(eulers.x.isFinite)
        #expect(eulers.y.isFinite)
        #expect(eulers.z.isFinite)
    }

    // MARK: - Coordinate swap matrices

    @Test("transform presets are orthonormal (determinant ±1)",
          arguments: [
            Transform.transformZXYToXYZ,
            Transform.transformXZYToXYZ,
            Transform.transformXYMinusZToXYZ,
            Transform.transformXMinusZYToXYZ,
            Transform.transformYMinusZXToXYZ,
          ])
    func presetsOrthonormal(m: float4x4) {
        let det = m.determinant
        #expect(approxEqual(abs(det), 1.0))
    }

    // MARK: - decomposeTRS / matrixFromTR

    @Test("decomposeTRS round-trips T * R * S")
    func decomposeTRSRoundTrip() {
        let t = SIMD3<Float>(1, 2, 3)
        let r = Transform.rotationMatrix(radians: 0.7, axis: SIMD3<Float>(0, 1, 0))
        let s = SIMD3<Float>(2, 3, 4)
        let composed = Transform.translationMatrix(t) * r * Transform.scaleMatrix(s)

        let (tt, rr, ss) = Transform.decomposeTRS(composed)
        #expect(approxEqual(tt, t))
        #expect(approxEqual(ss, s))
        #expect(approxEqual(rr, r))
    }

    @Test("matrixFromTR yields identity translation+rotation when given identity rotation")
    func matrixFromTRIdentityRotation() {
        let m = Transform.matrixFromTR(translation: SIMD3<Float>(1, 2, 3),
                                       rotation: .identity)
        #expect(m.columns.3 == SIMD4<Float>(1, 2, 3, 1))
    }

    // MARK: - float4x4.identity

    @Test("float4x4.identity equals matrix_identity_float4x4")
    func identity() {
        #expect(float4x4.identity == matrix_identity_float4x4)
    }
}
```

### 3. `MathUtilsTests.swift`

Covers integer utilities, `SIMD4.xyz`, `float4x4` convenience initializers, and `simd_quatf.rotate`.

```swift
import Testing
import simd
@testable import ToyFlightSimulator

@Suite("MathUtils", .tags(.math))
struct MathUtilsTests {

    // MARK: - align / gcd / lcm / mipmapLevelCount

    @Test("align rounds up to alignment boundary", arguments: [
        (0,   16,  0),
        (1,   16, 16),
        (16,  16, 16),
        (17,  16, 32),
        (255, 64, 256),
    ])
    func alignCases(value: Int, alignment: Int, expected: Int) {
        #expect(align(value, upTo: alignment) == expected)
    }

    @Test("gcd of common pairs", arguments: [
        (12, 18,  6),
        (17, 13,  1),
        (100, 10, 10),
        (0,  5,   5),   // documents current behavior: gcd(0, n) == n
    ])
    func gcdCases(m: Int, n: Int, expected: Int) {
        #expect(gcd(m, n) == expected)
    }

    @Test("lcm of common pairs", arguments: [
        (4, 6, 12),
        (3, 5, 15),
        (7, 1,  7),
    ])
    func lcmCases(m: Int, n: Int, expected: Int) {
        #expect(lcm(m, n) == expected)
    }

    @Test("mipmapLevelCount handles size 0 and common texture sizes", arguments: [
        (0,    1),
        (1,    1),
        (2,    2),
        (256,  9),
        (1024, 11),
        (4096, 13),
    ])
    func mipmapCases(size: Int, expected: Int) {
        #expect(mipmapLevelCount(for: size) == expected)
    }

    // MARK: - SIMD4.xyz

    @Test("SIMD4.xyz drops the w component")
    func simd4xyz() {
        let v = SIMD4<Float>(1, 2, 3, 4)
        #expect(v.xyz == SIMD3<Float>(1, 2, 3))
    }

    // MARK: - float4x4 convenience initializers

    @Test("init(scale:) places scale on the diagonal")
    func initScale() {
        let m = float4x4(scale: SIMD3<Float>(2, 3, 4))
        #expect(m.columns.0.x == 2)
        #expect(m.columns.1.y == 3)
        #expect(m.columns.2.z == 4)
    }

    @Test("init(translate:) places translation in column 3")
    func initTranslate() {
        let m = float4x4(translate: SIMD3<Float>(5, 6, 7))
        #expect(m.columns.3 == SIMD4<Float>(5, 6, 7, 1))
    }

    @Test("init(rotateAbout:byAngle:) does NOT normalize its axis (documents current behavior)")
    func rotateAboutDoesNotNormalize() {
        // Passing a non-unit axis produces a non-rotation matrix;
        // this guards against accidental behavior change.
        let m = float4x4(rotateAbout: SIMD3<Float>(0, 2, 0), byAngle: .pi / 2)
        let v = m * SIMD4<Float>(1, 0, 0, 0)
        // A correct rotation would give (0,0,-1) or (0,0,1); with a scale-2 axis it will not.
        #expect(!approxEqual(v.xyz, SIMD3<Float>(0, 0, -1)))
    }

    @Test("init(rotateAbout:byAngle:) with a unit axis rotates correctly")
    func rotateAboutUnitAxis() {
        let m = float4x4(rotateAbout: SIMD3<Float>(0, 1, 0), byAngle: .pi / 2)
        let v = m * SIMD4<Float>(1, 0, 0, 0)
        #expect(approxEqual(v.xyz, SIMD3<Float>(0, 0, -1)))
    }

    @Test("init(lookAt:from:up:) points +Z toward the target")
    func initLookAt() {
        let m = float4x4(lookAt: SIMD3<Float>(0, 0,  10),
                         from:   SIMD3<Float>(0, 0, -10),
                         up:     SIMD3<Float>(0, 1,  0))
        // Column 2 = forward direction; should be +Z.
        #expect(approxEqual(m.columns.2.xyz, SIMD3<Float>(0, 0, 1)))
        #expect(approxEqual(m.columns.3.xyz, SIMD3<Float>(0, 0, -10)))
    }

    @Test("upperLeft3x3 discards translation column")
    func upperLeft3x3() {
        let r = Transform.rotationMatrix(radians: 0.4, axis: SIMD3<Float>(0, 1, 0))
        let m = Transform.translationMatrix(SIMD3<Float>(7, 8, 9)) * r
        let up = m.upperLeft3x3
        #expect(approxEqual(up, r.upperLeft3x3))
    }

    // MARK: - simd_quatf.rotate

    @Test("quaternion rotate agrees with equivalent rotation matrix")
    func quatRotate() {
        let angle: Float = 0.6
        let axis = SIMD3<Float>(0, 1, 0)
        let q = simd_quatf(angle: angle, axis: axis)
        let v = SIMD3<Float>(1, 0, 0)
        let rotatedQuat = q.rotate(v)
        let rotatedMat  = (Transform.rotationMatrix(radians: angle, axis: axis)
                           * SIMD4<Float>(v, 0)).xyz
        #expect(approxEqual(rotatedQuat, rotatedMat, tolerance: 1e-5))
    }
}
```

### 4. `TFSCacheTests.swift`

Covers the public surface and exercises concurrency. Uses String keys and Int values for simplicity.

```swift
import Testing
@testable import ToyFlightSimulator

@Suite("TFSCache", .tags(.utils))
struct TFSCacheTests {

    @Test("Newly-created cache is empty")
    func initiallyEmpty() {
        let cache = TFSCache<String, Int>()
        #expect(cache.count == 0)
        #expect(cache.value(forKey: "absent") == nil)
    }

    @Test("insert then value retrieves the same value")
    func insertRetrieve() {
        let cache = TFSCache<String, Int>()
        cache.insert(42, forKey: "answer")
        #expect(cache.value(forKey: "answer") == 42)
    }

    @Test("Subscript setter inserts, getter retrieves, nil removes")
    func subscriptFlow() {
        let cache = TFSCache<String, Int>()
        cache["a"] = 1
        cache["b"] = 2
        #expect(cache["a"] == 1)
        #expect(cache["b"] == 2)
        cache["a"] = nil
        #expect(cache["a"] == nil)
    }

    @Test("removeValue makes key inaccessible via value(forKey:)")
    func removeValueWorks() {
        let cache = TFSCache<String, Int>()
        cache.insert(1, forKey: "x")
        cache.removeValue(forKey: "x")
        #expect(cache.value(forKey: "x") == nil)
    }

    @Test("Concurrent inserts do not crash and all values land",
          .tags(.concurrency),
          .timeLimit(.minutes(1)))
    func concurrentInserts() async {
        let cache = TFSCache<Int, Int>()
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<1_000 {
                group.addTask { cache.insert(i * 2, forKey: i) }
            }
        }
        for i in 0..<1_000 {
            #expect(cache.value(forKey: i) == i * 2)
        }
    }
}
```

Note on the `count` property: `TFSCache._count` is only updated via the subscript setter (lines 74, 81 of `TFSCache.swift`), not via `insert(_:forKey:)` or `removeValue(_:)`. We intentionally avoid asserting specific `count` values outside of subscript-only flows — that nuance is worth documenting in a test name but not worth asserting a brittle expectation on. Flag as a follow-up to fix in code rather than lock in via tests.

### 5. `TFSLockTests.swift`

Covers both `TFSLock` (global semaphore serializer) and `LockUtils.withLock`.

```swift
import Testing
import os
@testable import ToyFlightSimulator

@Suite("Locking utilities", .tags(.utils, .concurrency))
struct LockTests {

    @Test("TFSLock.lock executes its block")
    func tfsLockRuns() {
        var ran = false
        TFSLock.lock { ran = true }
        #expect(ran)
    }

    @Test("TFSLock serializes concurrent increments of a shared counter",
          .timeLimit(.minutes(1)))
    func tfsLockSerializes() async {
        nonisolated(unsafe) var counter = 0
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<500 {
                group.addTask {
                    TFSLock.lock { counter += 1 }
                }
            }
        }
        #expect(counter == 500)
    }

    @Test("withLock returns the body's value")
    func withLockReturns() {
        let lock = OSAllocatedUnfairLock()
        let result = withLock(lock) { 7 * 6 }
        #expect(result == 42)
    }

    @Test("withLock releases the lock after body runs (second call succeeds immediately)")
    func withLockReleases() {
        let lock = OSAllocatedUnfairLock()
        _ = withLock(lock) { 1 }
        _ = withLock(lock) { 2 }
        // If the lock leaked, the second call would deadlock under the timeLimit.
    }
}
```

### 6. `MDLMaterialSemanticTests.swift`

```swift
import Testing
import ModelIO
@testable import ToyFlightSimulator

@Suite("MDLMaterialSemantic+Extensions", .tags(.utils))
struct MDLMaterialSemanticTests {

    @Test("allCases contains every semantic used in the switch statement")
    func allCasesNotEmpty() {
        #expect(MDLMaterialSemantic.allCases.count >= 25)
    }

    @Test("Every case in allCases maps to a non-UNKNOWN string")
    func everyCaseMapped() {
        for semantic in MDLMaterialSemantic.allCases {
            #expect(semantic.toString() != "UNKNOWN SEMANTIC",
                    "Semantic \(semantic) has no string mapping")
        }
    }

    @Test("toString returns stable, distinct names for core semantics")
    func coreSemantics() {
        #expect(MDLMaterialSemantic.baseColor.toString() == "Base Color")
        #expect(MDLMaterialSemantic.metallic.toString() == "Metallic")
        #expect(MDLMaterialSemantic.roughness.toString() == "Roughness")
    }
}
```

(Expected string values will be read from the actual extension source when writing the file; the three examples above are placeholders to be verified.)

### 7. `TimeItTests.swift`

```swift
import Testing
import Foundation
@testable import ToyFlightSimulator

@Suite("TimeIt", .tags(.utils))
struct TimeItTests {

    @Test("timeit returns a non-negative duration")
    func nonNegative() {
        let ns = timeit { _ = (0..<1000).reduce(0, +) }
        #expect(ns >= 0)
    }

    @Test("timeit measures roughly the expected duration for a sleep",
          .timeLimit(.minutes(1)))
    func sleepDuration() {
        let ns = timeit {
            Thread.sleep(forTimeInterval: 0.05)  // 50ms
        }
        // Lower bound only: scheduling jitter can stretch this arbitrarily.
        #expect(ns >= 40_000_000)    // >= 40ms
    }
}
```

---

## Critical Files

Read-only references (used by tests):

- `ToyFlightSimulator Shared/Math/Math.swift`
- `ToyFlightSimulator Shared/Math/Transform.swift`
- `ToyFlightSimulator Shared/Math/MathUtils.swift`
- `ToyFlightSimulator Shared/Utils/TFSCache.swift`
- `ToyFlightSimulator Shared/Utils/TFSLock.swift`
- `ToyFlightSimulator Shared/Utils/LockUtils.swift`
- `ToyFlightSimulator Shared/Utils/MDLMaterialSemantic+Extensions.swift`
- `ToyFlightSimulator Shared/Utils/TimeIt.swift`

Files to create:

- `ToyFlightSimulatorTests/TestSupport/ApproxEqual.swift`
- `ToyFlightSimulatorTests/TestSupport/TestTags.swift`
- `ToyFlightSimulatorTests/Math/MathTests.swift`
- `ToyFlightSimulatorTests/Math/TransformTests.swift`
- `ToyFlightSimulatorTests/Math/MathUtilsTests.swift`
- `ToyFlightSimulatorTests/Utils/TFSCacheTests.swift`
- `ToyFlightSimulatorTests/Utils/TFSLockTests.swift`
- `ToyFlightSimulatorTests/Utils/MDLMaterialSemanticTests.swift`
- `ToyFlightSimulatorTests/Utils/TimeItTests.swift`

Files to modify:

- `ToyFlightSimulator.xcodeproj/project.pbxproj` — add new test files to the `ToyFlightSimulatorTests` target. The target already uses a file-system-synchronized group, so Xcode should pick up new files automatically on first open; if not, the files must be added to the test target's build phase.

## Verification

After the files are added and the target builds:

```bash
xcodebuild test \
  -project ToyFlightSimulator.xcodeproj \
  -scheme "ToyFlightSimulator macOS" \
  -sdk macosx \
  -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Expected outcome:

- All existing XCTest tests in `NodeTests.swift` and `RendererTests.swift` continue to pass.
- All new Swift Testing tests pass.
- Xcode's Test Navigator shows the new `@Suite`-decorated test suites grouped under "Math" and "Utils".

Tag-filtered runs (Xcode UI or command-line `-only-testing:`) let us run only the math tests, only the utils tests, or only concurrency tests.

## Out of Scope (Follow-ups)

- **`ModelIO+Extensions.swift`** uses `as!` force casts that `fatalError` on unexpected types. A safer API (throwing or returning `nil`) should come before tests.
- **`MTKMesh+Extensions.invertNormals`** requires a live `MTKMesh` backed by a Metal device. Tests need a `MTLDevice` fixture or a refactor that extracts the normal-inversion math.
- **`Float.randomZeroToOne`** uses `arc4random()` and is non-deterministic — skip, or refactor to inject a generator.
- **`TFSCache._count` divergence** (only mutated in subscript setter) is a latent bug. Left untested to avoid locking in behavior; fix in a separate change.
- Porting existing `NodeTests`/`RendererTests` from XCTest to Swift Testing — deliberately deferred to keep this change scoped.
