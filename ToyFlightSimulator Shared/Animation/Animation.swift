//
//  Animation.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 12/31/25.
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

import Foundation

struct Keyframe<Value> {
    var time: Float = 0
    var value: Value
}

struct Animation {
    var translations: [Keyframe<float3>] = []
    var rotations: [Keyframe<simd_quatf>] = []
    var scales: [Keyframe<float3>] = []

    var repeatAnimation = true

    /// T·R·S pose at `time`, with per-track identity fallbacks.
    /// (Extracted from AnimationClip.getPose so index-resolved callers can
    /// sample without the per-joint jointPath dictionary lookup.)
    func getPose(at time: Float) -> float4x4 {
        let rotation = getRotation(at: time) ?? simd_quatf(matrix_identity_float4x4)
        let translation = getTranslation(at: time) ?? float3.zero
        let scale = getScale(at: time) ?? float3.one
        return Transform.translationMatrix(translation) * float4x4(rotation) * Transform.scaleMatrix(scale)
    }

    func getTranslation(at time: Float) -> float3? {
        guard let lastKeyframe = translations.last else {
            return nil
        }
        var currentTime = time
        if let first = translations.first,
            first.time >= currentTime
        {
            return first.value
        }
        if currentTime >= lastKeyframe.time,
            !repeatAnimation
        {
            return lastKeyframe.value
        }
        currentTime = fmod(currentTime, lastKeyframe.time)
        // A3+: scan for the bracketing pair directly — the old code
        // materialized an array of ALL (prev, next) pairs per sample just to
        // call first(where:). Same first-match semantics, zero allocation.
        for i in 1..<translations.count where currentTime < translations[i].time {
            let previousKey = translations[i - 1]
            let nextKey = translations[i]
            let interpolant = (currentTime - previousKey.time) / (nextKey.time - previousKey.time)
            return simd_mix(previousKey.value, nextKey.value, float3(repeating: interpolant))
        }
        return nil
    }

    func getRotation(at time: Float) -> simd_quatf? {
        guard let lastKeyframe = rotations.last else {
            return nil
        }
        var currentTime = time
        if let first = rotations.first,
            first.time >= currentTime
        {
            return first.value
        }
        if currentTime >= lastKeyframe.time,
            !repeatAnimation
        {
            return lastKeyframe.value
        }
        currentTime = fmod(currentTime, lastKeyframe.time)
        // A3+: direct scan, no per-sample pairs array (see getTranslation).
        for i in 1..<rotations.count where currentTime < rotations[i].time {
            let previousKey = rotations[i - 1]
            let nextKey = rotations[i]
            let interpolant = (currentTime - previousKey.time) / (nextKey.time - previousKey.time)
            return simd_slerp(previousKey.value, nextKey.value, interpolant)
        }
        return nil
    }

    func getScale(at time: Float) -> float3? {
        guard let lastKeyframe = scales.last else {
            return nil
        }
        var currentTime = time
        if let first = scales.first,
            first.time >= currentTime
        {
            return first.value
        }
        if currentTime >= lastKeyframe.time {
            return lastKeyframe.value
        }

        currentTime = fmod(currentTime, lastKeyframe.time)
        // A3+: direct scan, no per-sample pairs array (see getTranslation).
        for i in 1..<scales.count where currentTime < scales[i].time {
            let previousKey = scales[i - 1]
            let nextKey = scales[i]
            let interpolant = (currentTime - previousKey.time) / (nextKey.time - previousKey.time)
            return simd_mix(previousKey.value, nextKey.value, float3(repeating: interpolant))
        }
        return nil
    }
}
