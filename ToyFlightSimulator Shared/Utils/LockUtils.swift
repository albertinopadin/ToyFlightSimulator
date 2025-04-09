//
//  LockUtils.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/30/25.
//

import os

@inlinable
func withLock<Value>(_ lock: OSAllocatedUnfairLock<Void>, body: () -> Value) -> Value {
    lock.lock()
    defer {
        lock.unlock()
    }
    return body()
}
