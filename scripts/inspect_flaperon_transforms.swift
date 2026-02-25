//
//  inspect_flaperon_transforms.swift
//  ToyFlightSimulator
//
//  Diagnostic script to dump rest/bind transforms for control surface bones
//  from a USDZ file. Used to investigate bone local coordinate frames.
//
//  Usage: swift inspect_flaperon_transforms.swift <usdz-path>
//

import Foundation
import ModelIO
import simd

func inspectFlaperonTransforms(_ path: String) {
    let url = URL(fileURLWithPath: path)
    let asset = MDLAsset(url: url)

    for i in 0..<asset.count {
        walkForSkeleton(asset.object(at: i))
    }
}

func walkForSkeleton(_ object: MDLObject) {
    for i in 0..<object.components.count {
        if let animBind = object.components[i] as? MDLAnimationBindComponent,
           let skeleton = animBind.skeleton {
            dumpFlaperonData(skeleton: skeleton)
        }
    }
    for child in object.children.objects {
        walkForSkeleton(child)
    }
}

func matrixString(_ m: float4x4) -> String {
    let cols = (0..<4).map { col in
        let c = m[col]
        return String(format: "[%+.4f, %+.4f, %+.4f, %+.4f]", c.x, c.y, c.z, c.w)
    }
    return cols.joined(separator: "\n         ")
}

func decomposeMatrix(_ m: float4x4) -> (translation: SIMD3<Float>, rotation: simd_quatf, scale: SIMD3<Float>) {
    let col0 = SIMD3<Float>(m[0].x, m[0].y, m[0].z)
    let col1 = SIMD3<Float>(m[1].x, m[1].y, m[1].z)
    let col2 = SIMD3<Float>(m[2].x, m[2].y, m[2].z)
    let sx = length(col0)
    let sy = length(col1)
    let sz = length(col2)
    let scale = SIMD3<Float>(sx, sy, sz)
    let translation = SIMD3<Float>(m[3].x, m[3].y, m[3].z)

    let rotMatrix = float3x3(col0 / sx, col1 / sy, col2 / sz)
    let q = simd_quatf(rotMatrix)
    return (translation, q, scale)
}

func dumpFlaperonData(skeleton: MDLSkeleton) {
    let jointPaths = skeleton.jointPaths
    let restTransforms = skeleton.jointRestTransforms.float4x4Array
    let bindTransforms = skeleton.jointBindTransforms.float4x4Array

    let targetNames = ["LeftFlaperon", "RightFlaperon", "LeftAileron", "RightAileron",
                       "LeftRudder", "RightRudder", "LeftHorzStablizer", "RightHorzStablizer",
                       "Armature"]

    for (idx, jp) in jointPaths.enumerated() {
        let name = (jp as NSString).lastPathComponent
        guard targetNames.contains(where: { name.contains($0) }) else { continue }

        let rest = restTransforms[idx]
        let bind = bindTransforms[idx]
        let (rTrans, rRot, rScale) = decomposeMatrix(rest)
        let (bTrans, bRot, bScale) = decomposeMatrix(bind)

        print("=== Joint [\(idx)]: \(jp) ===")
        print("  REST TRANSFORM:")
        print("    Matrix: \(matrixString(rest))")
        print("    Translation: \(rTrans)")
        print("    Rotation (quat): \(rRot)  (axis: \(rRot.axis), angle: \(rRot.angle * 180 / .pi)°)")
        print("    Scale: \(rScale)")
        print("  BIND TRANSFORM:")
        print("    Matrix: \(matrixString(bind))")
        print("    Translation: \(bTrans)")
        print("    Rotation (quat): \(bRot)  (axis: \(bRot.axis), angle: \(bRot.angle * 180 / .pi)°)")
        print("    Scale: \(bScale)")
        print("")
    }
}

let args = CommandLine.arguments.dropFirst()
if args.isEmpty {
    fputs("Usage: swift inspect_flaperon_transforms.swift <usdz-path>\n", stderr)
    exit(1)
}
for arg in args { inspectFlaperonTransforms(arg) }
