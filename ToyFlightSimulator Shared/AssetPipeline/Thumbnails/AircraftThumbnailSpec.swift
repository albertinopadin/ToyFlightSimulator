//
//  AircraftThumbnailSpec.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 7/9/26.
//

import Foundation
import CryptoKit
import simd

/// Shared camera/pose constants for the X-Plane style aircraft "photo":
/// nose pointing screen-right, yawed toward the viewer, camera slightly above.
struct ThumbnailCameraConfig {
    /// Bump to invalidate every cached thumbnail after changing framing,
    /// lighting, per-aircraft orientation constants, or generator behavior.
    /// v2: OBJ material sanitize + tightened framing margin.
    static let specVersion = 2

    /// Yaw applied after uprighting (nose = +X): negative swings the nose
    /// from +X toward +Z, i.e. toward the camera. X-Plane pose ≈ -45°.
    var headingDegrees: Float = -45
    /// Camera height angle above the horizon.
    var elevationDegrees: Float = 18
    /// Vertical field of view. Longer lens = flatter perspective.
    var verticalFovDegrees: Float = 30
    /// Distance factor on the sphere-fitting distance. Below 1.0 is safe
    /// because a jet's vertical extent is far smaller than its bounding
    /// sphere; this trades unused sky for card presence.
    var framingMargin: Float = 0.92
    /// Output size in pixels (16:10, 2x a ~320pt-wide card).
    var pixelWidth: Int = 1280
    var pixelHeight: Int = 800

    /// Camera distance so a bounding sphere of `radius` fits the frustum in
    /// both axes: d = r / sin(min half-FOV), padded by framingMargin.
    func cameraDistance(boundingRadius: Float) -> Float {
        let halfV = (verticalFovDegrees / 2).toRadians
        let aspect = Float(pixelWidth) / Float(pixelHeight)
        let halfH = atan(tan(halfV) * aspect)
        let halfMin = min(halfV, halfH)
        return (boundingRadius / sin(halfMin)) * framingMargin
    }
}

/// How to photograph one aircraft: which asset to load and how to rotate it
/// so its nose points +X, upright, in SceneKit's right-handed Y-up world.
/// The generator applies the shared heading/elevation on top.
struct AircraftThumbnailSpec {
    let aircraft: AircraftType
    let modelName: String
    let modelExtension: ModelExtension
    /// Loaded asset -> canonical nose +X / up +Y. Seeded from ModelLibrary's
    /// basis transforms; SceneKit composes the full USD xform stack (unlike
    /// the engine's flattened-vertex import), so USDZ values are verified
    /// visually and tuned here (bump specVersion when changing).
    let uprighting: simd_quatf
    /// Escape hatch for assets whose scene graph doesn't upright them.
    let extraRotation: simd_quatf

    init(aircraft: AircraftType,
         modelName: String,
         modelExtension: ModelExtension,
         uprightingYawDegrees: Float,
         extraRotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])) {
        self.aircraft = aircraft
        self.modelName = modelName
        self.modelExtension = modelExtension
        self.uprighting = simd_quatf(angle: uprightingYawDegrees.toRadians, axis: [0, 1, 0])
        self.extraRotation = extraRotation
    }

    var modelURL: URL? {
        Bundle.main.url(forResource: modelName, withExtension: modelExtension.rawValue)
    }

    /// Enum case name ("f16"), not the display rawValue -- stable file prefix.
    var caseName: String { String(describing: aircraft) }

    /// One spec per AircraftType. Model names/extensions mirror
    /// ModelLibrary.makeLibrary() -- keep in sync when aircraft are added.
    static func spec(for aircraft: AircraftType) -> AircraftThumbnailSpec {
        switch aircraft {
            case .f16:
                return .init(aircraft: aircraft, modelName: "f16r", modelExtension: .OBJ,
                             uprightingYawDegrees: -90)   // raw nose -Z
            case .f18:
                return .init(aircraft: aircraft, modelName: "FA-18F", modelExtension: .OBJ,
                             uprightingYawDegrees: -90)   // raw nose -Z
            case .f22:
                return .init(aircraft: aircraft, modelName: "F-22_Raptor", modelExtension: .USDZ,
                             uprightingYawDegrees: -90)   // TUNE: stage-dependent
            case .f22_cgtrader:
                // Z-up authored, nose -Y (SceneKit does not upright this one):
                // pitch -90 about X (nose -Y -> +Z, up +Z -> +Y), then yaw +90.
                return .init(aircraft: aircraft, modelName: "cgtrader_F22", modelExtension: .USDZ,
                             uprightingYawDegrees: 90,
                             extraRotation: simd_quatf(angle: Float(-90).toRadians, axis: [1, 0, 0]))
            case .f35:
                return .init(aircraft: aircraft, modelName: "F-35A_Lightning_II", modelExtension: .USDZ,
                             uprightingYawDegrees: 90)    // raw nose +Z
        }
    }

    /// Cache key: changes when the pose constants, output size, spec version,
    /// or the model file itself (size + mtime fingerprint) change.
    func cacheKey(config: ThumbnailCameraConfig) -> String {
        var components: [String] = [
            "v\(ThumbnailCameraConfig.specVersion)",
            caseName, modelName, modelExtension.rawValue,
            "\(uprighting.vector)", "\(extraRotation.vector)",
            "\(config.headingDegrees)", "\(config.elevationDegrees)",
            "\(config.verticalFovDegrees)", "\(config.framingMargin)",
            "\(config.pixelWidth)x\(config.pixelHeight)",
        ]
        if let url = modelURL,
           let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            components.append("\(size)-\(mtime)")
        }
        let digest = SHA256.hash(data: Data(components.joined(separator: "|").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
