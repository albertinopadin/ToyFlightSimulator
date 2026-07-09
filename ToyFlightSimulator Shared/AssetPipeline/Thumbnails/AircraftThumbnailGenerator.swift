//
//  AircraftThumbnailGenerator.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 7/9/26.
//
//  Offscreen SceneKit render of an aircraft model in the X-Plane picker pose.
//  No view/window involved: SCNRenderer draws straight into an image, so this
//  is safe to run off the main thread while the game (paused behind the menu)
//  owns the MTKView. Seam kept narrow so an in-engine Metal renderer could
//  replace it later without touching the grid, cache, or store.
//

import Foundation
import SceneKit
import SceneKit.ModelIO
import ModelIO
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum AircraftThumbnailError: Error {
    case missingModel(String)
    case snapshotFailed(String)
}

enum AircraftThumbnailGenerator {
    /// Renders one aircraft thumbnail. Synchronous & expensive (asset load
    /// dominates) -- call from a background actor/queue only.
    static func render(spec: AircraftThumbnailSpec,
                       config: ThumbnailCameraConfig = ThumbnailCameraConfig()) throws -> CGImage {
        guard let url = spec.modelURL else {
            throw AircraftThumbnailError.missingModel(spec.modelName)
        }

        // Load. USDZ via SceneKit's native importer (best PBR fidelity);
        // OBJ via ModelIO (loadTextures() is mandatory or materials are bare).
        let loaded: SCNScene
        switch spec.modelExtension {
            case .USDZ, .USDC:
                loaded = try SCNScene(url: url, options: nil)
            case .OBJ:
                let asset = MDLAsset(url: url)
                asset.loadTextures()
                loaded = SCNScene(mdlAsset: asset)
                sanitizeObjMaterials(in: loaded)
        }

        // Stage: model under a pivot, posed nose-right toward the camera.
        // Background left unset -> transparent pixels; the SwiftUI card
        // provides its own backdrop.
        let stage = SCNScene()

        let modelNode = SCNNode()
        for child in loaded.rootNode.childNodes {
            modelNode.addChildNode(child)
        }
        let heading = simd_quatf(angle: config.headingDegrees.toRadians, axis: [0, 1, 0])
        modelNode.simdOrientation = heading * spec.uprighting * spec.extraRotation

        let pivot = SCNNode()
        pivot.addChildNode(modelNode)
        stage.rootNode.addChildNode(pivot)

        // Recenter: boundingSphere is in pivot space (includes the child's
        // rotation), so shifting the child by -center puts the sphere at origin.
        let (center, radius) = pivot.boundingSphere
        guard radius > 0 else {
            throw AircraftThumbnailError.snapshotFailed("empty bounds for \(spec.modelName)")
        }
        modelNode.simdPosition -= simd_float3(Float(center.x), Float(center.y), Float(center.z))

        // Camera: on the +Z side, elevated, looking at the origin.
        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(config.verticalFovDegrees)
        camera.automaticallyAdjustsZRange = true
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        let elevation = config.elevationDegrees.toRadians
        let distance = config.cameraDistance(boundingRadius: Float(radius))
        cameraNode.simdPosition = distance * simd_float3(0, sin(elevation), cos(elevation))
        cameraNode.simdLook(at: .zero, up: [0, 1, 0], localFront: [0, 0, -1])
        stage.rootNode.addChildNode(cameraNode)

        // Three-light rig: key upper-front-left, soft fill, ambient floor.
        stage.rootNode.addChildNode(makeDirectionalLight(intensity: 1400,
                                                         eulerDegrees: (pitch: -40, yaw: -30)))
        stage.rootNode.addChildNode(makeDirectionalLight(intensity: 350,
                                                         eulerDegrees: (pitch: -20, yaw: 140)))
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 300
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        stage.rootNode.addChildNode(ambientNode)

        // Offscreen snapshot.
        let renderer = SCNRenderer(device: nil, options: nil)   // system default MTLDevice
        renderer.scene = stage
        renderer.pointOfView = cameraNode
        renderer.autoenablesDefaultLighting = false
        let size = CGSize(width: config.pixelWidth, height: config.pixelHeight)
        let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)

        guard let cgImage = cgImage(from: image) else {
            throw AircraftThumbnailError.snapshotFailed(spec.modelName)
        }
        return cgImage
    }

    /// ModelIO's OBJ->SceneKit material bridge has two quirks that can render
    /// a model invisible or blown out (seen with the F-16, MTL `d 1.0`):
    /// - `transparent.contents` arrives as a scalar NSNumber whose alpha reads
    ///   as 0 under the default .aOne transparency mode -> opacity 0.
    /// - `emission` arrives fully white under the PBR lighting model.
    /// Both slots are meaningless for these simple MTL files, so reset them.
    private static func sanitizeObjMaterials(in scene: SCNScene) {
        scene.rootNode.enumerateHierarchy { node, _ in
            node.geometry?.materials.forEach { material in
                if material.transparent.contents is NSNumber {
                    material.transparent.contents = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
                }
                material.emission.contents = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
            }
        }
    }

    private static func makeDirectionalLight(intensity: CGFloat,
                                             eulerDegrees: (pitch: Float, yaw: Float)) -> SCNNode {
        let light = SCNLight()
        light.type = .directional
        light.intensity = intensity
        let node = SCNNode()
        node.light = light
        node.simdEulerAngles = simd_float3(eulerDegrees.pitch.toRadians,
                                           eulerDegrees.yaw.toRadians,
                                           0)
        return node
    }

    #if canImport(AppKit)
    private static func cgImage(from image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
    #elseif canImport(UIKit)
    private static func cgImage(from image: UIImage) -> CGImage? {
        image.cgImage
    }
    #endif
}
