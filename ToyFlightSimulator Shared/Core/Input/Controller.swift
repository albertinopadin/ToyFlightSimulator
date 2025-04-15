//
//  Controller.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/29/23.
//

import GameController
import os

enum ControllerState: CaseIterable {
    case LeftStickX
    case LeftStickY
    
    case RightStickX
    case RightStickY
    
    case RightTrigger
    case LeftTrigger
    
    case LeftBumper
    case RightBumper
}

final class Controller: @unchecked Sendable {
    let gameControllerLock = OSAllocatedUnfairLock()
    var gameController: GCController?
    var present: Bool = false
    
    private var observers = [Any]()
    
    let controllerStateMapping: [ControllerState: (GCExtendedGamepad) -> Float] = [
        .LeftStickX: { $0.leftThumbstick.xAxis.value },
        .LeftStickY: { $0.leftThumbstick.yAxis.value },
        .RightStickX: { $0.rightThumbstick.xAxis.value },
        .RightStickY: { $0.rightThumbstick.yAxis.value },
        .RightTrigger: { $0.rightTrigger.value },
        .LeftTrigger: { $0.leftTrigger.value },
        .LeftBumper: { $0.leftShoulder.value },
        .RightBumper: { $0.rightShoulder.value }
    ]

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    init() {
        registerControllerObservers()
    }
    
    func getState(_ state: ControllerState) -> Float {
        return withLock(gameControllerLock) {
            guard let gamepad = gameController?.extendedGamepad else { return 0.0 }
            guard let stateFn = controllerStateMapping[state] else { return 0.0 }
            return stateFn(gamepad)
        }
    }
    
    private func registerControllerObservers() {
        let connectionObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.GCControllerDidConnect,
            object: nil,
            queue: nil)
        { [weak self] notification in
            if let controller = notification.object as? GCController {
                self?.controllerDidConnect(controller)
            }
        }

        let disconnectionObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.GCControllerDidDisconnect,
            object: nil,
            queue: nil)
        { [weak self] notification in
            if let controller = notification.object as? GCController {
                self?.controllerDidDisconnect(controller)
            }
        }

        observers = [connectionObserver, disconnectionObserver]
    }

    private func controllerDidConnect(_ controller: GCController) {
        withLock(gameControllerLock) {
            print("Controller Connected!")
            gameController = controller
            present = true
        }
    }

    private func controllerDidDisconnect(_ controller: GCController) {
        withLock(gameControllerLock) {
            print("Controller Disconnected!")
            gameController = nil
            present = false
        }
    }
}
