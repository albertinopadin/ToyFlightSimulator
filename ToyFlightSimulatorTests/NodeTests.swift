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
}
