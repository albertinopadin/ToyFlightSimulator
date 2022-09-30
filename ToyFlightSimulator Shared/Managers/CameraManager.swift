//
//  CameraManager.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/22.
//

class CameraManager {
    private var _cameras: [CameraType: Camera] = [:]
    public var currentCamera: Camera!
    
    public func registerCamera(camera: Camera) {
        self._cameras.updateValue(camera, forKey: camera.cameraType)
    }
    
    public func setCamera(_ cameraType: CameraType) {
        self.currentCamera = _cameras[cameraType]
    }
    
    internal func update(deltaTime: Float) {
        // Update all cameras so we can easily switch
        for camera in _cameras.values {
            camera.update()
        }
    }
}
