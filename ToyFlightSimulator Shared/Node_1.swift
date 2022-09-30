//
//  Node.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/25/22.
//

//import MetalKit
//
//
//public final class Node {
//    var mesh: MTKMesh?
////    var texture: MTLTexture?
//    public var color = SIMD4<Float>(1, 1, 1, 1)
//    public var transform: simd_float4x4 = matrix_identity_float4x4
//    weak var parentNode: Node?
//    private(set) var childNodes = [Node]()
//    
//    init() { }
//    
//    init(mesh: MTKMesh) {
//        self.mesh = mesh
//    }
//    
//    init(position: SIMD3<Float>, color: SIMD4<Float>, alpha: Float) {
//        self.transform = float4x4(translate: SIMD3<Float>(position.x, position.y, position.z))
//        self.color = color
//        self.alpha = alpha
//    }
//    
//    @inlinable
//    var alpha: Float {
//        get {
//            return color.w
//        }
//        
//        set {
//            color.w = newValue
//        }
//    }
//    
//    var position: SIMD3<Float> {
//        return worldTransform.columns.3.xyz
//    }
//    
//    var worldTransform: simd_float4x4 {
//        if let parent = parentNode {
//            return parent.worldTransform * transform
//        } else {
//            return transform
//        }
//    }
//    
//    func addChildNode(_ node: Node) {
//        childNodes.append(node)
//        node.parentNode = self
//    }
//    
//    func removeFromParent() {
//        parentNode?.removeChildNode(self)
//    }
//    
//    private func removeChildNode(_ node: Node) {
//        childNodes.removeAll { $0 === node }
//    }
//}
