//
//  LightManager.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/22.
//

import MetalKit
import os

final class LightManager {
    private static let lightLock = OSAllocatedUnfairLock()
    nonisolated(unsafe) private static var _lightObjects: [LightObject] = []

    // Pre-bucketed lists keep GetLightObjects(lightType:) and the data-fetch
    // paths from re-filtering the master list every render frame.
    nonisolated(unsafe) private static var _directionalLights: [LightObject] = []
    nonisolated(unsafe) private static var _pointLights: [LightObject] = []

    // Scratch buffers reused by the encoder-bound Set* methods to avoid
    // per-frame [LightData] allocations. Render-thread use only.
    nonisolated(unsafe) private static var _directionalDataScratch: [LightData] = []
    nonisolated(unsafe) private static var _pointDataScratch: [LightData] = []

    public static func AddLightObject(_ lightObject: LightObject) {
        withLock(lightLock) {
            Self._lightObjects.append(lightObject)
            switch lightObject.lightType {
                case Directional: Self._directionalLights.append(lightObject)
                case Point:       Self._pointLights.append(lightObject)
                default: break
            }
        }
    }

    public static func GetLightObjects(lightType: LightType) -> [LightObject] {
        withLock(lightLock) {
            switch lightType {
                case Directional: return Self._directionalLights
                case Point:       return Self._pointLights
                default:          return Self._lightObjects.filter { $0.lightType == lightType }
            }
        }
    }

    public static func RemoveAllLights() {
        withLock(lightLock) {
            Self._lightObjects.removeAll()
            Self._directionalLights.removeAll()
            Self._pointLights.removeAll()
        }
    }

    public static func GetDirectionalLightData(viewMatrix: float4x4) -> [LightData] {
        withLock(lightLock) {
            for light in Self._directionalLights {
                light.lightData.lightEyeDirection =
                    normalize(viewMatrix * float4(light.getPosition(), 1)).xyz
            }
            return Self._directionalLights.map { $0.lightData }
        }
    }

    public static func GetPointLightData() -> [LightData] {
        withLock(lightLock) {
            return Self._pointLights.map { $0.lightData }
        }
    }

    public static func SetDirectionalLightData(_ renderEncoder: MTLRenderCommandEncoder,
                                               cameraPosition: float3,
                                               viewMatrix: float4x4) {
        // Fill scratch buffer in place under the lock, then encode without holding it.
        let count: Int = withLock(lightLock) {
            Self._directionalDataScratch.removeAll(keepingCapacity: true)
            for light in Self._directionalLights {
                light.lightData.lightEyeDirection =
                    normalize(viewMatrix * float4(light.getPosition(), 1)).xyz
                Self._directionalDataScratch.append(light.lightData)
            }
            return Self._directionalDataScratch.count
        }

        var lightCount = count
        renderEncoder.setFragmentBytes(&lightCount,
                                       length: Int32.size,
                                       index: TFSBufferDirectionalLightsNum.index)
        Self._directionalDataScratch.withUnsafeMutableBufferPointer { buf in
            if let base = buf.baseAddress {
                renderEncoder.setFragmentBytes(base,
                                               length: LightData.stride(count),
                                               index: TFSBufferDirectionalLightData.index)
            }
        }
    }

    public static func SetPointLightData(_ renderEncoder: MTLRenderCommandEncoder) {
        let count: Int = withLock(lightLock) {
            Self._pointDataScratch.removeAll(keepingCapacity: true)
            for light in Self._pointLights {
                Self._pointDataScratch.append(light.lightData)
            }
            return Self._pointDataScratch.count
        }

        Self._pointDataScratch.withUnsafeMutableBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            let length = LightData.stride(count)
            renderEncoder.setVertexBytes(base, length: length, index: TFSBufferPointLightsData.index)
            renderEncoder.setFragmentBytes(base, length: length, index: TFSBufferPointLightsData.index)
        }
    }
}
