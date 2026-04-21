//
//  TFSCacheTests.swift
//  ToyFlightSimulatorTests
//

import Testing
@testable import ToyFlightSimulator

@Suite("TFSCache", .tags(.utils))
struct TFSCacheTests {

    @Test("Newly-created cache is empty")
    func initiallyEmpty() {
        let cache = TFSCache<String, Int>()
        #expect(cache.count == 0)
        #expect(cache.value(forKey: "absent") == nil)
    }

    @Test("insert then value retrieves the same value")
    func insertRetrieve() {
        let cache = TFSCache<String, Int>()
        cache.insert(42, forKey: "answer")
        #expect(cache.value(forKey: "answer") == 42)
    }

    @Test("Subscript setter inserts, getter retrieves, nil removes")
    func subscriptFlow() {
        let cache = TFSCache<String, Int>()
        cache["a"] = 1
        cache["b"] = 2
        #expect(cache["a"] == 1)
        #expect(cache["b"] == 2)
        cache["a"] = nil
        #expect(cache["a"] == nil)
    }

    @Test("removeValue makes key inaccessible via value(forKey:)")
    func removeValueWorks() {
        let cache = TFSCache<String, Int>()
        cache.insert(1, forKey: "x")
        cache.removeValue(forKey: "x")
        #expect(cache.value(forKey: "x") == nil)
    }

    @Test("Concurrent inserts do not crash and all values land",
          .tags(.concurrency),
          .timeLimit(.minutes(1)))
    func concurrentInserts() async {
        let cache = TFSCache<Int, Int>()
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<1_000 {
                group.addTask { cache.insert(i * 2, forKey: i) }
            }
        }
        for i in 0..<1_000 {
            #expect(cache.value(forKey: i) == i * 2)
        }
    }
}
