//
//  AircraftThumbnailStore.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 7/9/26.
//
//  Main-actor observable state + a background actor that serializes the
//  expensive SceneKit renders (one at a time). @Observable is safe in Shared
//  code: every target meets Observation's floor (macOS 26 / iOS 26 / tvOS 18).
//

import Foundation
import CoreGraphics
import Observation

@Observable @MainActor
final class AircraftThumbnailStore {
    private(set) var thumbnails: [AircraftType: CGImage] = [:]
    @ObservationIgnored private var inFlight: Set<AircraftType> = []
    private let worker = Worker()
    private let config = ThumbnailCameraConfig()

    func ensureAllThumbnails() {
        for aircraft in AircraftType.allCases {
            ensureThumbnail(for: aircraft)
        }
    }

    func ensureThumbnail(for aircraft: AircraftType) {
        guard thumbnails[aircraft] == nil, !inFlight.contains(aircraft) else { return }
        inFlight.insert(aircraft)
        let config = self.config
        Task {
            let image = await worker.thumbnail(for: aircraft, config: config)
            inFlight.remove(aircraft)
            if let image {
                thumbnails[aircraft] = image
            }
        }
    }

    /// Serializes disk-check + render off the main actor.
    private actor Worker {
        func thumbnail(for aircraft: AircraftType,
                       config: ThumbnailCameraConfig) -> CGImage? {
            let spec = AircraftThumbnailSpec.spec(for: aircraft)
            let key = spec.cacheKey(config: config)

            let bypassCache = ProcessInfo.processInfo.environment["TFS_REGEN_THUMBNAILS"] == "1"
            if !bypassCache,
               let cached = AircraftThumbnailCache.load(caseName: spec.caseName, key: key) {
                print("[AircraftThumbnailStore] Cache hit: \(spec.caseName)")
                return cached
            }

            do {
                let start = DispatchTime.now().uptimeNanoseconds
                let image = try AircraftThumbnailGenerator.render(spec: spec, config: config)
                AircraftThumbnailCache.store(image, caseName: spec.caseName, key: key)
                let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                print("[AircraftThumbnailStore] Rendered \(spec.caseName) in \(String(format: "%.0f", ms)) ms")
                return image
            } catch {
                print("[AircraftThumbnailStore] Failed to render \(spec.modelName): \(error)")
                return nil
            }
        }
    }
}
