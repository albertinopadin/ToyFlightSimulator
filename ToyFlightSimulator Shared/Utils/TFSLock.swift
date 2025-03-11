//
//  TFSLock.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/10/25.
//

import Foundation

/// Using this seems to cause a crash:
/// *** Terminating app due to uncaught exception 'NSInvalidArgumentException', reason: '-[__NSTaggedDate countByEnumeratingWithState:objects:count:]: unrecognized selector sent to instance 0x8000000000000000'
/// 
final class TFSLock {
    private static let semaphore = DispatchSemaphore(value: 1)
    
    public static func lock(_ block: () -> ()) {
        _ = semaphore.wait(timeout: .distantFuture)
        block()
        semaphore.signal()
    }
}
