//
//  F35Animator.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/11/26.
//

// TODO: Explore doing this with components instead of inheritance

final class F35Animator: AircraftAnimator {
    override func didUpdateGearStateMachine() {
        guard let model = model else { return }
        updateSkeletonPoses(skeletons: model.skeletons)
    }
}
