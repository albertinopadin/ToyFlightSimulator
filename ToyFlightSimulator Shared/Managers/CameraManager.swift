//
//  CameraManager.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/22.
//

final class CameraManager {
    /// Registration order is the contract: it defines the 'C'-cycle order AND
    /// the slot indices for direct selection (slot 0 = first registered).
    /// Identity-deduped — re-registering a camera keeps its original slot
    /// (aircraft swaps re-add the persistent chase camera every time).
    nonisolated(unsafe) private static var _cameras: [Camera] = []
    nonisolated(unsafe) public static var CurrentCamera: Camera?

    public static func RegisterCamera(camera: Camera) {
        if !_cameras.contains(where: { $0 === camera }) {
            _cameras.append(camera)
        }
    }

    /// Makes a camera current (registering it first if needed — cannot miss
    /// and nil out CurrentCamera like the old set-by-type lookup could).
    public static func SetCamera(_ camera: Camera) {
        RegisterCamera(camera: camera)
        makeCurrent(camera)
    }

    /// Slot-indexed selection: the binding point for future number-row /
    /// F-key camera hotkeys (slot N = Nth addCamera call in the scene).
    /// Out-of-range index is a no-op. Update-thread only, like every other
    /// gameplay CurrentCamera mutation.
    public static func SetCamera(at index: Int) {
        guard _cameras.indices.contains(index) else { return }
        makeCurrent(_cameras[index])
    }

    /// Advances to the next registered camera in registration order,
    /// wrapping ('C' key). No-op in single-camera scenes.
    public static func CycleCamera() {
        guard let next = nextCameraIndex(after: currentCameraIndex(),
                                         count: _cameras.count) else { return }
        SetCamera(at: next)
    }

    /// Pure cycle rule, unit-testable without touching the live registry
    /// (tests run app-hosted; mutating the real registry would hijack the
    /// running scene's camera). nil = stay put: fewer than two cameras, or
    /// no current camera (pre-scene / mid-teardown — don't grab one).
    static func nextCameraIndex(after currentIndex: Int?, count: Int) -> Int? {
        guard count >= 2, let currentIndex else { return nil }
        return (currentIndex + 1) % count
    }

    private static func currentCameraIndex() -> Int? {
        guard let current = CurrentCamera else { return nil }
        return _cameras.firstIndex(where: { $0 === current })
    }

    /// Single selection funnel. The aspect-ratio refresh matters here:
    /// SetAspectRatio only updates the CURRENT camera, so a camera that was
    /// inactive during a window resize has a stale projection.
    private static func makeCurrent(_ camera: Camera) {
        camera.setAspectRatio(Renderer.AspectRatio)
        CurrentCamera = camera
    }

    public static func RemoveAllCameras() {
        _cameras.removeAll()
        CurrentCamera = nil
    }

    public static func SetAspectRatio(_ aspectRatio: Float) {
        CurrentCamera?.setAspectRatio(aspectRatio)
    }

    public static func Update(deltaTime: Double) {
        for camera in _cameras {
            // Parented cameras (e.g. AttachedCamera) are updated during the
            // scene graph traversal. Only update unparented cameras here:
            guard camera.parent == nil else { continue }
            camera.update()
        }
    }

    /// Returns the active camera's world position, or `.zero` if no camera is active.
    public static func GetCurrentCameraPosition() -> float3 {
        CurrentCamera?.modelMatrix.columns.3.xyz ?? .zero
    }
}
