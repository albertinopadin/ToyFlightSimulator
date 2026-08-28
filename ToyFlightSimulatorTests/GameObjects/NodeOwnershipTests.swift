//
//  NodeOwnershipTests.swift
//  ToyFlightSimulatorTests
//
//  Step 0.3b: parents own children (strong `children` array), children point
//  back weakly. Before the weak flip, every detached ≥2-node subtree was a
//  retain cycle — aircraft swaps and scene resets leaked the old aircraft
//  island. Plain Nodes only: the cycle mechanics don't need GameObjects
//  (which would need Metal).
//

import Testing
@testable import ToyFlightSimulator

@Suite("Node ownership (weak parent)", .tags(.gameObjects))
struct NodeOwnershipTests {

    @Test("detached parent+child island deallocates when the last external ref drops")
    func detachedIslandDeallocates() {
        weak var weakParent: Node?
        weak var weakChild: Node?

        // Build inside a function scope so every strong local is provably
        // gone on return (debug builds may extend a `let` to scope end,
        // which a bare do-block doesn't reliably terminate).
        func buildIsland() {
            let parent = Node(name: "island_parent")
            let child = Node(name: "island_child")
            parent.addChild(child)
            weakParent = parent
            weakChild = child
        }
        buildIsland()

        // With a strong back-reference this is the red test: the pair keeps
        // itself alive forever.
        #expect(weakParent == nil, "parent leaked — parent↔child retain cycle")
        #expect(weakChild == nil, "child leaked — parent↔child retain cycle")
    }

    @Test("3-deep chain detached from a living root deallocates as an island")
    func detachedChainDeallocates() {
        let root = Node(name: "root")
        weak var weakTop: Node?
        weak var weakMid: Node?
        weak var weakLeaf: Node?

        func buildAndDetach() {
            let top = Node(name: "top")
            let mid = Node(name: "mid")
            let leaf = Node(name: "leaf")
            top.addChild(mid)
            mid.addChild(leaf)
            root.addChild(top)
            weakTop = top
            weakMid = mid
            weakLeaf = leaf

            // Same shape as SceneManager.RemoveObject on an aircraft swap:
            // the root drops its strong ref to the subtree's head.
            root.removeChild(top)
        }
        buildAndDetach()

        #expect(weakTop == nil && weakMid == nil && weakLeaf == nil,
                "detached chain leaked — internal parent links must be weak")
        #expect(root.children.isEmpty)
    }

    @Test("reparented child survives and points at the new parent")
    func reparentedChildSurvivesWithCorrectParent() {
        let first = Node(name: "first_parent")
        let second = Node(name: "second_parent")
        weak var weakChild: Node?

        func reparent() {
            let child = Node(name: "child")
            first.addChild(child)
            first.removeChild(child)
            second.addChild(child)
            weakChild = child
        }
        reparent()

        // second.children is the owning ref now — no premature dealloc.
        #expect(weakChild != nil, "child died during reparent — children array must own it")
        #expect(weakChild?.parent === second)
        #expect(first.children.isEmpty)
    }

    @Test("child.parent reads nil after the parent deallocates (weak zeroing, no crash)")
    func parentReadsNilAfterParentDeallocates() {
        // Explicit optional so the strong ref drops deterministically
        // (same pattern as RigidBodyTests.rigidBodyToleratesNilGameObject).
        var parent: Node? = Node(name: "dying_parent")
        let child = Node(name: "surviving_child")
        parent!.addChild(child)
        #expect(child.parent === parent)

        // Our local `child` ref keeps the child alive; releasing the parent
        // releases its children array. The child's weak parent must zero.
        parent = nil
        #expect(child.parent == nil)
    }
}
