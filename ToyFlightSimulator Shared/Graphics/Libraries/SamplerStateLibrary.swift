//
//  SamplerStateLibrary.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/26/22.
//

import MetalKit
import os

enum SamplerStateType {
    case None
    case Linear_Anisotropy1x
    case Linear_Anisotropy2x
    case Linear_Anisotropy4x
    case Linear_Anisotropy8x
    case Linear_Anisotropy16x
}

/// Player-selectable max anisotropy levels for the linear texture sampler.
/// The raw value is the actual `MTLSamplerDescriptor.maxAnisotropy` (1...16).
/// Drives the menu picker and maps to a pre-built `SamplerStateType` variant.
enum MaxAnisotropy: Int, CaseIterable, Identifiable {
    case x1  = 1
    case x2  = 2
    case x4  = 4
    case x8  = 8
    case x16 = 16

    var id: Int { rawValue }

    /// Human-readable label for the UI (e.g. "8x").
    var label: String { "\(rawValue)x" }

    /// Pre-built sampler variant corresponding to this anisotropy level.
    var samplerType: SamplerStateType {
        switch self {
            case .x1:  return .Linear_Anisotropy1x
            case .x2:  return .Linear_Anisotropy2x
            case .x4:  return .Linear_Anisotropy4x
            case .x8:  return .Linear_Anisotropy8x
            case .x16: return .Linear_Anisotropy16x
        }
    }
}

final class SamplerStateLibrary: Library<SamplerStateType, MTLSamplerState>, @unchecked Sendable {
    private var library: [SamplerStateType: SamplerState] = [:]

    // The currently-selected linear sampler. All 5 anisotropy variants are
    // pre-built once in makeLibrary() and never mutated; switching anisotropy
    // only re-points this reference. Written from the UI thread (menu) and read
    // from the render thread (per draw), so every access is guarded by the lock.
    private let currentLinearLock = OSAllocatedUnfairLock()
    nonisolated(unsafe) private var _currentLinear: MTLSamplerState!

    override func makeLibrary() {
        library.updateValue(Linear_SamplerState(maxAnisotropy: 1),  forKey: .Linear_Anisotropy1x)
        library.updateValue(Linear_SamplerState(maxAnisotropy: 2),  forKey: .Linear_Anisotropy2x)
        library.updateValue(Linear_SamplerState(maxAnisotropy: 4),  forKey: .Linear_Anisotropy4x)
        library.updateValue(Linear_SamplerState(maxAnisotropy: 8),  forKey: .Linear_Anisotropy8x)
        library.updateValue(Linear_SamplerState(maxAnisotropy: 16), forKey: .Linear_Anisotropy16x)
        // Every MaxAnisotropy case maps to a key inserted above, so this is a safe invariant.
        _currentLinear = library[Preferences.SelectedMaxAnisotropy.samplerType]!.samplerState
    }

    override subscript(type: SamplerStateType) -> MTLSamplerState? {
        return library[type]?.samplerState
    }

    /// The active linear sampler for the player's selected anisotropy level.
    /// Read on the render hot path; always returns a fully-constructed,
    /// immutable sampler object (never mutated after creation).
    var currentLinearSamplerState: MTLSamplerState {
        withLock(currentLinearLock) { _currentLinear }
    }

    /// Switch the active linear sampler to the pre-built variant for the given
    /// anisotropy level. Called from the UI thread when the player changes the
    /// menu preference. No Metal objects are created here — just a reference swap.
    func setLinearMaxAnisotropy(_ maxAnisotropy: MaxAnisotropy) {
        guard let sampler = library[maxAnisotropy.samplerType]?.samplerState else { return }
        withLock(currentLinearLock) { _currentLinear = sampler }
    }
}

protocol SamplerState {
    var name: String { get }
    var samplerState: MTLSamplerState { get }
}

struct Linear_SamplerState: SamplerState {
    var name: String
    var samplerState: MTLSamplerState

    init(maxAnisotropy: Int) {
        self.name = "Linear Sampler State \(maxAnisotropy)x Anisotropy"
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.maxAnisotropy = maxAnisotropy
        samplerDescriptor.lodMinClamp = 0
        samplerDescriptor.label = name
        self.samplerState = Engine.Device.makeSamplerState(descriptor: samplerDescriptor)!
    }
}
