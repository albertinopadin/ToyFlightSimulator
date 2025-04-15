//
//  TFSCache.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/3/24.
//

import Foundation
import os

// Much of the code from: https://www.swiftbysundell.com/articles/caching-in-swift/
final class TFSCache<Key: Hashable, Value>: @unchecked Sendable {
    private let cacheLock = OSAllocatedUnfairLock()
    private let subscriptLock = OSAllocatedUnfairLock()
    
    final class WrappedKey: NSObject {
        let key: Key
        
        init(_ key: Key) { self.key = key }

        override var hash: Int { return key.hashValue }

        override func isEqual(_ object: Any?) -> Bool {
            guard let value = object as? WrappedKey else {
                return false
            }

            return value.key == key
        }
    }

    final class Entry {
        let value: Value

        init(value: Value) {
            self.value = value
        }
    }

    private let wrapped = NSCache<WrappedKey, Entry>()
    private var _count = 0
    public var count: Int {
        get { withLock(cacheLock) { return _count } }
    }

    func insert(_ value: Value, forKey key: Key) {
        withLock(cacheLock) {
            let entry = Entry(value: value)
            wrapped.setObject(entry, forKey: WrappedKey(key))
        }
    }

    func value(forKey key: Key) -> Value? {
        withLock(cacheLock) {
            let entry = wrapped.object(forKey: WrappedKey(key))
            return entry?.value
        }
    }

    func removeValue(forKey key: Key) {
        withLock(cacheLock) {
            wrapped.removeObject(forKey: WrappedKey(key))
        }
    }

    subscript(key: Key) -> Value? {
        get { withLock(subscriptLock) { value(forKey: key) } }

        set {
            withLock(subscriptLock) {
                guard let value = newValue else {
                    if let _ = value(forKey: key) {
                        removeValue(forKey: key)
                        _count -= 1
                    }
                    
                    return
                }
                
                insert(value, forKey: key)
                _count += 1
            }
        }
    }
}
