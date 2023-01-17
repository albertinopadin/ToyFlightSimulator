//
//  HeadsUpDisplay.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/16/23.
//

import MetalKit

class HeadsUpDisplay: GameObject {
    private var _horizonLine: Line
    private var _greenSphere: Sphere
    init() {
        _horizonLine = Line(startPoint: float3(-10, 0, 0),
                            endPoint: float3(10, 0, 0),
                            color: GREEN_COLOR)
        _horizonLine.setScale(10)
        
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
    
//    override func doRender(_ renderCommandEncoder: MTLRenderCommandEncoder) {
//        _greenSphere.doRender(renderCommandEncoder)
//        super.doRender(renderCommandEncoder)
//    }

//    override func render(renderCommandEncoder: MTLRenderCommandEncoder, renderPipelineStateType: RenderPipelineStateType) {
//        _greenSphere.render(renderCommandEncoder: renderCommandEncoder, renderPipelineStateType: renderPipelineStateType)
//        super.render(renderCommandEncoder: renderCommandEncoder, renderPipelineStateType: renderPipelineStateType)
//    }
}
