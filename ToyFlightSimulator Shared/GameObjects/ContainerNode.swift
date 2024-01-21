//
//  ContainerNode.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/21/24.
//

class ContainerNode: Node {
    private static let _defaultCameraPositionOffset = float3(0, 2, 4)
    
    public var camera: AttachedCamera?
    
    init(camera: AttachedCamera, cameraOffset: float3 = _defaultCameraPositionOffset) {
        self.camera = camera
        self.camera!.setPosition(cameraOffset)
        self.camera!.positionOffset = cameraOffset
        self.camera!.setRotationX(Float(-15).toRadians)
        super.init(name: "Container")
        addChild(self.camera!)
    }
    
    override func addChild(_ child: Node) {
        if let ac = child as? Aircraft {
            ac.containerNode = self
        }
        
        super.addChild(child)
    }
}
