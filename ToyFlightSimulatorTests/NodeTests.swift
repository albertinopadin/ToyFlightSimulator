//
//  NodeTests.swift
//  ToyFlightSimulatorTests
//
//  Created by Albertino Padin on 8/3/23.
//

import XCTest
@testable import ToyFlightSimulator

final class NodeTests: XCTestCase {
    func testSuccessfulInit() {
        let nodeName = "TestNode"
        let node = Node(name: nodeName)
        XCTAssertEqual(node.getName(), nodeName)
        XCTAssertNotNil(node.getID())
    }
    
    func testAddRemoveChild() {
        let node = Node(name: "TestNode")
        XCTAssertEqual(node.children.count, 0)
        let child = Node(name: "ChildNode")
        node.addChild(child)
        XCTAssertEqual(node.children.count, 1)
        let childFromArray = node.children.first(where: { $0.getID() == child.getID() })
        XCTAssertNotNil(childFromArray)
        node.removeChild(child)
        XCTAssertEqual(node.children.count, 0)
    }
    
    func testRemoveAllChildren() {
        let node = Node(name: "TestNode")
        let child1 = Node(name: "Child1")
        let child2 = Node(name: "Child2")
        let child3 = Node(name: "Child3")
        
        node.addChild(child1)
        node.addChild(child2)
        node.addChild(child3)
        
        XCTAssertEqual(node.children.count, 3)
        XCTAssertEqual(child1.parent?.getID(), node.getID())
        XCTAssertEqual(child2.parent?.getID(), node.getID())
        XCTAssertEqual(child3.parent?.getID(), node.getID())
        
        node.removeAllChildren()
        
        XCTAssertEqual(node.children.count, 0)
        XCTAssertNil(child1.parent)
        XCTAssertNil(child2.parent)
        XCTAssertNil(child3.parent)
    }
    
    func testPositionSettersAndGetters() {
        let node = Node(name: "TestNode")
        
        // Test initial position
        XCTAssertEqual(node.getPosition(), float3(0, 0, 0))
        
        // Test setPosition with float3
        let newPosition = float3(1, 2, 3)
        node.setPosition(newPosition)
        XCTAssertEqual(node.getPosition(), newPosition)
        XCTAssertEqual(node.getPositionX(), 1)
        XCTAssertEqual(node.getPositionY(), 2)
        XCTAssertEqual(node.getPositionZ(), 3)
        
        // Test setPosition with individual components
        node.setPosition(4, 5, 6)
        XCTAssertEqual(node.getPosition(), float3(4, 5, 6))
        
        // Test individual component setters
        node.setPositionX(7)
        XCTAssertEqual(node.getPosition(), float3(7, 5, 6))
        
        node.setPositionY(8)
        XCTAssertEqual(node.getPosition(), float3(7, 8, 6))
        
        node.setPositionZ(9)
        XCTAssertEqual(node.getPosition(), float3(7, 8, 9))
    }
    
    func testMoveMethods() {
        let node = Node(name: "TestNode")
        
        // Test move with individual components
        node.move(1, 2, 3)
        XCTAssertEqual(node.getPosition(), float3(1, 2, 3))
        
        // Test move with float3
        node.move(float3(2, 3, 4))
        XCTAssertEqual(node.getPosition(), float3(3, 5, 7))
        
        // Test individual axis movement
        node.moveX(2)
        XCTAssertEqual(node.getPosition(), float3(5, 5, 7))
        
        node.moveY(3)
        XCTAssertEqual(node.getPosition(), float3(5, 8, 7))
        
        node.moveZ(4)
        XCTAssertEqual(node.getPosition(), float3(5, 8, 11))
    }
    
    func testScaleSettersAndGetters() {
        let node = Node(name: "TestNode")
        
        // Test initial scale
        XCTAssertEqual(node.getScale(), float3(1, 1, 1))
        
        // Test setScale with float3
        let newScale = float3(2, 3, 4)
        node.setScale(newScale)
        XCTAssertEqual(node.getScale(), newScale)
        XCTAssertEqual(node.getScaleX(), 2)
        XCTAssertEqual(node.getScaleY(), 3)
        XCTAssertEqual(node.getScaleZ(), 4)
        
        // Test setScale with individual components
        node.setScale(5, 6, 7)
        XCTAssertEqual(node.getScale(), float3(5, 6, 7))
        
        // Test uniform scale
        node.setScale(8)
        XCTAssertEqual(node.getScale(), float3(8, 8, 8))
        
        // Test individual component setters
        node.setScaleX(9)
        XCTAssertEqual(node.getScale(), float3(9, 8, 8))
        
        node.setScaleY(10)
        XCTAssertEqual(node.getScale(), float3(9, 10, 8))
        
        node.setScaleZ(11)
        XCTAssertEqual(node.getScale(), float3(9, 10, 11))
    }
    
    func testScaleMethods() {
        let node = Node(name: "TestNode")
        
        // Test scale with individual components
        node.scale(1, 2, 3)
        XCTAssertEqual(node.getScale(), float3(2, 3, 4))
        
        // Test individual axis scaling
        node.scaleX(2)
        XCTAssertEqual(node.getScale(), float3(4, 3, 4))
        
        node.scaleY(3)
        XCTAssertEqual(node.getScale(), float3(4, 6, 4))
        
        node.scaleZ(4)
        XCTAssertEqual(node.getScale(), float3(4, 6, 8))
    }
    
    func testRotationMethods() {
        let node = Node(name: "TestNode")
        
        // Set a known rotation and test the rotation matrix is updated
        let initialRotationMatrix = node.rotationMatrix
        XCTAssertEqual(initialRotationMatrix, matrix_identity_float4x4)
        
        // Test basic rotation
        let angle: Float = .pi / 2
        node.setRotation(angle: angle, axis: float3(1, 0, 0))
        
        // Verify rotation matrix is no longer identity
        XCTAssertNotEqual(node.rotationMatrix, matrix_identity_float4x4)
        
        // Test rotation decomposition
        let rotX = node.getRotationX()
        XCTAssertEqual(rotX, angle, accuracy: 0.001)
    }
    
    func testParentChildRelationship() {
        let parent = Node(name: "Parent")
        let child = Node(name: "Child")
        
        // Test parent-child relationship
        parent.addChild(child)
        XCTAssertEqual(child.parent?.getID(), parent.getID())
        
        // Test that child inherits parent's model matrix
        parent.setPosition(1, 2, 3)
        parent.update()
        
        // Child's parentModelMatrix should be equal to parent's modelMatrix
        let childParentMatrix = child.parentModelMatrix
        let parentModelMatrix = parent.modelMatrix
        
        // Compare matrices
        for i in 0..<4 {
            for j in 0..<4 {
                XCTAssertEqual(childParentMatrix[i][j], parentModelMatrix[i][j], accuracy: 0.001)
            }
        }
    }
    
    func testDirectionVectors() {
        let node = Node(name: "TestNode")
        
        // Test initial direction vectors
        XCTAssertEqual(node.getFwdVector(), float3(0, 0, -1))
        XCTAssertEqual(node.getUpVector(), float3(0, 1, 0))
        XCTAssertEqual(node.getRightVector(), float3(1, 0, 0))
        
        // Rotate the node and test that direction vectors change
        node.setRotation(angle: .pi/2, axis: float3(0, 1, 0))
        
        // After 90-degree Y rotation, forward should point to +X, right should point to +Z
        let fwd = node.getFwdVector()
        let right = node.getRightVector()
        
        XCTAssertEqual(fwd.x, -1, accuracy: 0.001)
        XCTAssertEqual(fwd.z, 0, accuracy: 0.001)
        
        XCTAssertEqual(right.x, 0, accuracy: 0.001)
        XCTAssertEqual(right.z, -1, accuracy: 0.001)
    }
    
    func testMoveAlongVector() {
        let node = Node(name: "TestNode")
        
        // Test moving along a specific vector
        let moveVector = float3(1, 1, 1)
        let distance: Float = 5.0
        
        node.moveAlongVector(moveVector, distance: distance)
        
        // The normalized vector * distance should equal the node's position
        let expectedPosition = normalize(moveVector) * distance
        
        XCTAssertEqual(node.getPosition().x, expectedPosition.x, accuracy: 0.001)
        XCTAssertEqual(node.getPosition().y, expectedPosition.y, accuracy: 0.001)
        XCTAssertEqual(node.getPosition().z, expectedPosition.z, accuracy: 0.001)
    }
    
    func testModelMatrixUpdates() {
        let node = Node(name: "TestNode")
        
        // Initial model matrix should be identity
        let initialModelMatrix = node.modelMatrix
        for i in 0..<4 {
            for j in 0..<4 {
                if i == j {
                    XCTAssertEqual(initialModelMatrix[i][j], 1.0)
                } else {
                    XCTAssertEqual(initialModelMatrix[i][j], 0.0)
                }
            }
        }
        
        // Change position and verify model matrix updates
        node.setPosition(1, 2, 3)
        let positionMatrix = node.modelMatrix
        
        // Translation should be in the last column
        XCTAssertEqual(positionMatrix[3][0], 1.0)
        XCTAssertEqual(positionMatrix[3][1], 2.0)
        XCTAssertEqual(positionMatrix[3][2], 3.0)
    }
}
