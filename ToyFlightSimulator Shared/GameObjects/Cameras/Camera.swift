//
//  Camera.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/22.
//

import simd

enum CameraType {
    case Debug
    case Attached
}

class Camera: GameObject {
    // Cameras live in CameraManager, not in SceneManager's batched collections.
    override var objectType: GameObjectType { .none }

    var fieldOfView: Float!
    var near: Float!
    var far: Float!
    
    var cameraType: CameraType!
    var projectionMatrix: matrix_float4x4 = matrix_identity_float4x4
    
    private var _viewMatrix = matrix_identity_float4x4
    /// worldMatrixGeneration value `_viewMatrix` was derived from
    /// (.max == never computed).
    private var _viewMatrixGeneration: UInt64 = .max
    var viewMatrix: matrix_float4x4 {
        get {
            // Reading modelMatrix first brings the world cache (and its
            // generation) current; the inverse is recomputed only when the
            // world matrix actually changed. This covers both own-transform
            // changes and parent propagation — the old updateModelMatrix
            // override only caught the former and needed an extra hook in
            // AttachedCamera.update() for the latter.
            let world = modelMatrix
            if _viewMatrixGeneration != worldMatrixGeneration {
                _viewMatrix = computeViewMatrix(from: world)
                _viewMatrixGeneration = worldMatrixGeneration
            }
            return _viewMatrix
        }

        set {
            _viewMatrix = newValue
            _viewMatrixGeneration = worldMatrixGeneration
        }
    }

    /// How this camera derives its view matrix from its world matrix.
    /// Base: plain inverse. AttachedCamera overrides with a scale-stripped
    /// inverse so a scaled parent doesn't warp the view.
    func computeViewMatrix(from world: float4x4) -> float4x4 {
        world.inverse
    }
    
    init(name: String,
         cameraType: CameraType,
         aspectRatio: Float,
         fieldOfView: Float = 45.0,
         near: Float = 0.1,
         far: Float = 1000) {
        super.init(name: name, modelType: .None)
        self.cameraType = cameraType
        self.fieldOfView = fieldOfView
        self.near = near
        self.far = far
        
        self.projectionMatrix = Transform.perspectiveProjection(fieldOfView.toRadians,
                                                                aspectRatio,
                                                                near,
                                                                far)
    }

    func setAspectRatio(_ aspectRatio: Float) {
        projectionMatrix = Transform.perspectiveProjection(fieldOfView.toRadians,
                                                           aspectRatio,
                                                           near,
                                                           far)
    }
    
    // updateModelMatrix() override removed: viewMatrix is derived lazily by
    // the generation-checked getter above.
}
