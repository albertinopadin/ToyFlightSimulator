//
//  CameraManager.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/22.
//

final class CameraManager {
    private static var _cameras: [CameraType: Camera] = [:]
    public static var CurrentCamera: Camera!
    
    public static func RegisterCamera(camera: Camera) {
        _cameras.updateValue(camera, forKey: camera.cameraType)
    }
    
    public static func SetCamera(_ cameraType: CameraType) {
        CurrentCamera = _cameras[cameraType]
    }
    
    public static func RemoveAllCameras() {
        _cameras.removeAll()
    }
    
    public static func SetAspectRatio(_ aspectRatio: Float) {
        CurrentCamera.setAspectRatio(aspectRatio)
    }
    
    public static func Update(deltaTime: Double) {
        // Update all cameras so we can easily switch
        for camera in _cameras.values {
            camera.update()
        }
    }
}
