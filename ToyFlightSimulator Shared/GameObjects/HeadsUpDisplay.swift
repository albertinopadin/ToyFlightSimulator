//
//  HeadsUpDisplay.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/16/23.
//

import MetalKit

class HeadsUpDisplay: GameObject {
    private var _horizonLine: Line
    private var _lastPosition: float3 = float3(0,0,0)
    private var _initialModelMatrix = matrix_identity_float4x4
    private var _greenSphere: Sphere
    private var _initUpdate: Bool = false
    init() {
        _horizonLine = Line(startPoint: float3(-1, 0, 0),
                            endPoint: float3(1, 0, 0),
                            color: GREEN_COLOR)
        
        _greenSphere = Sphere()
        var material = Material()
        material.color = GREEN_COLOR
        _greenSphere.useMaterial(material)
        _greenSphere.setPosition(0, 0, 0)
        _greenSphere.setScale(0.25)
        
        super.init(name: "Heads Up Display", meshType: .Quad, renderPipelineStateType: .HeadsUpDisplay)
        _renderPipelineStateType = .HeadsUpDisplay
        useBaseColorTexture(.HeadsUpDisplay)
        addChild(_horizonLine)
        addChild(_greenSphere)
    }
    
    override func update() {
        if _initUpdate {
            doUpdate()
            let deltaPosition = getHUDPosition() - _lastPosition
//            print("HUD position: \(getHUDPosition())")
//            if deltaPosition.z > 0 {
//                print("DELTA POSITION")
//            }
            _initialModelMatrix.translate(direction: deltaPosition)
            _horizonLine.parentModelMatrix = _initialModelMatrix
//            _horizonLine.parentModelMatrix.translate(direction: deltaPosition)
            _horizonLine.update()
            _lastPosition = getHUDPosition()
        } else {
            super.update()
            _lastPosition = getHUDPosition()
            _initialModelMatrix = modelMatrix
            _initUpdate.toggle()
        }
    }
    
    private func getHUDPosition() -> float3 {
        return modelMatrix.columns.3.xyz
    }
}
