//
//  TransformComponent.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/1/26.
//


///// Copyright (c) 2025 Kodeco Inc.
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
///
/// This project and source code may use libraries or frameworks that are
/// released under various Open-Source licenses. Use of those libraries and
/// frameworks are governed by their own individual licenses.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import ModelIO

struct TransformComponent {
    let keyTransforms: [float4x4]
    let duration: Float
    var currentTransform: float4x4 = .identity

    init(object: MDLObject, startTime: TimeInterval, endTime: TimeInterval, basisTransform: float4x4? = nil) {
        duration = Float(endTime - startTime)
        
        let timeStride = stride(
            from: startTime,
            to: endTime,
            by: 1 / TimeInterval(FPS.FPS_120.rawValue)
        )
        
        keyTransforms = Array(timeStride).map { time in
            let globalTransform = MDLTransform.globalTransform(with: object, atTime: time)

            // Decompose the USDZ transform into T, R, S components.
            // The globalTransform's translation is in WORLD coordinates (after USDZ scale applied),
            // so we must normalize it by dividing by the scale to get model-local translation.
            // This allows GameObject.setScale() to be the sole source of scale.
            let (worldTranslation, rotation, scale) = Transform.decomposeTRS(globalTransform)

            // Normalize translation: convert from world coords back to model-local coords
            // by dividing by the USDZ scale. Avoid division by zero.
            let normalizedTranslation = float3(
                scale.x > 0.0001 ? worldTranslation.x / scale.x : worldTranslation.x,
                scale.y > 0.0001 ? worldTranslation.y / scale.y : worldTranslation.y,
                scale.z > 0.0001 ? worldTranslation.z / scale.z : worldTranslation.z
            )

            let transformWithoutScale = Transform.matrixFromTR(translation: normalizedTranslation, rotation: rotation)

            if let basisTransform {
                // Apply conjugation to convert transform to game coordinate system
                // This matches how basisTransform is applied in Skeleton.updatePose()
                let basisInverse = basisTransform.inverse
                return basisTransform * transformWithoutScale * basisInverse
            }
            return transformWithoutScale
        }
    }
    
    public func printKeyTransforms() {
        print("[TransformComponent key transform] count: \(keyTransforms.count)")
        for (i, kt) in keyTransforms.enumerated() {
            print("[TransformComponent key transform] key transform \(i):")
            prettyPrintMatrix(kt)
        }
    }
    
    private func prettyPrintMatrix(_ matrix: float4x4) {
        for i in 0..<4 {
            print("[TransformComponent key transform]:  \(stringWithPrecision(matrix[i].x)),     \(stringWithPrecision(matrix[i].y)),    \(stringWithPrecision(matrix[i].z)),     \(stringWithPrecision(matrix[i].w))")
        }
    }
    
    private func stringWithPrecision(_ num: any BinaryFloatingPoint, precision: Int = 4) -> String {
        return String(format: "%.\(precision)f", num as! CVarArg)
    }
    
//    mutating func setCurrentTransform(at time: Float) {
//        guard duration > 0 else {
//            currentTransform = .identity
//            return
//        }
//        let frame = Int(fmod(time, duration) * Float(FPS.FPS_120.rawValue))
//        if frame < keyTransforms.count {
//            currentTransform = keyTransforms[frame]
//        } else {
//            currentTransform = keyTransforms.last ?? .identity
//        }
//    }
    
    mutating func setCurrentTransform(at time: Float) {
        guard duration > 0 else {
            currentTransform = .identity
            return
        }
        let frame = Int(min(time, duration) * Float(FPS.FPS_120.rawValue))
        if frame < keyTransforms.count {
            currentTransform = keyTransforms[frame]
        } else {
            currentTransform = keyTransforms.last ?? .identity
        }
    }
}
