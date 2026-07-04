//
//  SceneManagerUnregisterTests.swift
//  ToyFlightSimulatorTests
//
//  Created by Albertino Padin on 6/16/26.
//

import Testing
@testable import ToyFlightSimulator

/// `SceneManager.Unregister` walks `subtreeNodes(of:)` and removes each node
/// from the collection it was registered into. The traversal is the part that
/// regressed before (`RemoveObject` removed only the top node), and it's pure
/// scene-graph logic, so it's tested here directly with bare `Node`s — no
/// Metal / asset loading required.
@Suite("SceneManager subtree traversal", .tags(.scenes))
struct SceneManagerUnregisterTests {

    private func ids(_ nodes: [Node]) -> Set<String> {
        Set(nodes.map { $0.getID() })
    }

    @Test("A leaf node yields only itself")
    func leafYieldsSelf() {
        let leaf = Node(name: "Leaf")
        let result = SceneManager.subtreeNodes(of: leaf)
        #expect(result.count == 1)
        #expect(result.first?.getID() == leaf.getID())
    }

    @Test("Direct children are all included")
    func directChildrenIncluded() {
        let parent = Node(name: "Parent")
        let childA = Node(name: "ChildA")
        let childB = Node(name: "ChildB")
        parent.addChild(childA)
        parent.addChild(childB)

        let result = SceneManager.subtreeNodes(of: parent)

        #expect(result.count == 3)
        #expect(ids(result) == ids([parent, childA, childB]))
    }

    @Test("Grandchildren (and deeper) are included — the RemoveObject regression guard")
    func deepDescendantsIncluded() {
        // Mirrors an aircraft whose control surfaces are children and whose
        // sub-parts could nest deeper. Before the fix, removal stopped at the
        // top node and orphaned everything below it.
        let root = Node(name: "Root")
        let childA = Node(name: "ChildA")
        let childB = Node(name: "ChildB")
        let grandA1 = Node(name: "GrandA1")
        let grandA2 = Node(name: "GrandA2")
        let greatA1 = Node(name: "GreatA1")

        root.addChild(childA)
        root.addChild(childB)
        childA.addChild(grandA1)
        childA.addChild(grandA2)
        grandA2.addChild(greatA1)

        let result = SceneManager.subtreeNodes(of: root)

        #expect(result.count == 6)
        #expect(ids(result) == ids([root, childA, childB, grandA1, grandA2, greatA1]))
    }

    @Test("The root node comes first (pre-order)")
    func rootIsFirst() {
        let root = Node(name: "Root")
        root.addChild(Node(name: "Child"))
        let result = SceneManager.subtreeNodes(of: root)
        #expect(result.first?.getID() == root.getID())
    }

    @Test("Unregister on a plain-Node tree is a no-op (Nodes carry no registration marker)")
    func unregisterPlainNodeTree() {
        let root = Node(name: "Root")
        let child = Node(name: "Child")
        root.addChild(child)

        // Plain Nodes aren't GameObjects, so they carry no registeredObjectType
        // and unregisterSingle must skip them without touching any collection.
        // (GameObject round-trips need Metal, so they're covered by the
        // app-hosted suite; this guards the early-return path.)
        SceneManager.Unregister(root)

        // Unregister only affects SceneManager collections — the parent/child
        // links of the subtree itself are untouched.
        #expect(SceneManager.subtreeNodes(of: root).count == 2)
        #expect(child.parent?.getID() == root.getID())
    }

    @Test("A node registered flat under several composite parents is counted once per instance")
    func eachInstanceCountedOnce() {
        // Two sibling subtrees, each with its own children — the traversal must
        // return every distinct instance exactly once.
        let root = Node(name: "Root")
        let wing = Node(name: "Wing")
        let aileron = Node(name: "Aileron")
        let tail = Node(name: "Tail")
        let rudder = Node(name: "Rudder")

        root.addChild(wing)
        wing.addChild(aileron)
        root.addChild(tail)
        tail.addChild(rudder)

        let result = SceneManager.subtreeNodes(of: root)

        #expect(result.count == 5)
        #expect(ids(result).count == 5)   // no duplicates
    }
}
