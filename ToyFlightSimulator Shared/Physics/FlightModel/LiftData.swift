//
//  LiftData.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/17/26.
//

public struct LiftData {
    public let liftForceVector: float3
    public let liftVelocityVector: float3
    public let liftVelocitySquared: Float
    public let liftCoefficient: Float

    public init(liftForceVector: float3,
                liftVelocityVector: float3,
                liftVelocitySquared: Float,
                liftCoefficient: Float) {
        self.liftForceVector = liftForceVector
        self.liftVelocityVector = liftVelocityVector
        self.liftVelocitySquared = liftVelocitySquared
        self.liftCoefficient = liftCoefficient
    }
}
