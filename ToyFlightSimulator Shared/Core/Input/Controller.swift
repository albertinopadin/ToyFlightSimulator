//
//  Controller.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/29/23.
//

import GameController


enum ControllerState {
    case LeftStickX
    case LeftStickY
    
    case RightStickX
    case RightStickY
}

class Controller {
    var gameController: GCController?
    var present: Bool = false
    
    private var observers = [Any]()
    
    let controllerStateMapping: [ControllerState: (GCExtendedGamepad) -> Float] = [
        .LeftStickX: { $0.leftThumbstick.xAxis.value },
        .LeftStickY: { $0.leftThumbstick.yAxis.value },
        .RightStickX: { $0.rightThumbstick.xAxis.value },
        .RightStickY: { $0.rightThumbstick.yAxis.value }
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
        guard let gamepad = gameController?.extendedGamepad else { return 0.0 }
        guard let stateFn = controllerStateMapping[state] else { return 0.0 }
        return stateFn(gamepad)
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
        print("Controller Connected!")
        gameController = controller
        present = true
    }

    private func controllerDidDisconnect(_ controller: GCController) {
        print("Controller Disconnected!")
        gameController = nil
        present = false
    }
}
