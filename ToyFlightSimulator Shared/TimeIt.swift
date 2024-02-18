//
//  TimeIt.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/25/22.
//

import Dispatch

@inlinable
@inline(__always)
public func timeit(body: ()->()) -> UInt64 {
    let start = DispatchTime.now().uptimeNanoseconds
    body()
    return DispatchTime.now().uptimeNanoseconds - start
}

@inlinable
@inline(__always)
public func timeit(body: @escaping () async -> ()) -> UInt64 {
    let start = DispatchTime.now().uptimeNanoseconds
    Task(priority: .userInitiated) {
        await body()
    }
    return DispatchTime.now().uptimeNanoseconds - start
}
