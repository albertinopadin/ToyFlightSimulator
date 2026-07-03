//
//  LazyLibrary.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 7/3/26.
//

import os

/// A `Library` whose values are built on demand. Subclasses register a factory per
/// key in `makeLibrary()`; the factory runs once, on the first request for that key,
/// and the built value is cached for the process lifetime. Cache access is
/// serialized by a single lock, so a value is never built twice and lookups are
/// safe from any thread.
class LazyLibrary<Key: Hashable, Value>: Library<Key, Value>, @unchecked Sendable {
    // Factories describe *how* to build each value; they are not invoked until
    // that key is first requested (lazy load).
    private var _factories: [Key: () -> Value] = [:]
    private var _cache: [Key: Value] = [:]
    private let _lock = OSAllocatedUnfairLock()

    /// Registers the factory that builds the value for `key`. Call from
    /// `makeLibrary()` during init — before the library is visible to other
    /// threads — so registration itself needs no synchronization.
    func register(_ key: Key, _ factory: @escaping () -> Value) {
        _factories[key] = factory
    }

    /// Injects an already-built value (e.g. a runtime render target), replacing
    /// any cached one for `key`.
    func setResolved(_ key: Key, _ value: Value) {
        withLock(_lock) { _cache[key] = value }
    }

    /// Returns the value for `key`, building and caching it via its registered
    /// factory on first access. Returns nil when no factory is registered.
    /// The factory runs while the library lock is held: factories may use other
    /// libraries/caches (distinct locks) but must never re-enter the same library,
    /// and first access to a heavy asset should happen off the render thread
    /// (see the SceneManager.SetScene warm-up).
    func resolve(_ key: Key) -> Value? {
        withLock(_lock) {
            if let cached = _cache[key] { return cached }
            guard let factory = _factories[key] else { return nil }
            let value = factory()
            _cache[key] = value
            return value
        }
    }

    override subscript(_ type: Key) -> Value? {
        resolve(type)
    }
}
