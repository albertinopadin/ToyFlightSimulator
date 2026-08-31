//
//  ContactDebugLogger.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/31/26.
//

/// Debug-only contact reporter: prints which named collider touched what, at
/// most once per interval per collider name. Installed into RigidBody.onContact
/// (fires on the UpdateThread during the physics step — GameTime is owned by
/// the same thread, so reading it here is safe), so keep it print-only.
final class ContactDebugLogger {
    private let bodyLabel: String
    private let interval: Double
    private var lastLogTime: [String: Double] = [:]
    
    init(bodyLabel: String, interval: Double = 1.0) {
        self.bodyLabel = bodyLabel
        self.interval = interval
    }
    
    func log(_ contact: Contact, against other: RigidBody) {
        let name = contact.colliderNameA ?? "body"
        let now = GameTime.TotalGameTime
        if let last = lastLogTime[name], now - last < interval { return }
        lastLogTime[name] = now
        let otherLabel = other.gameObject?.getName() ?? "static geometry"
        print("[Contact] \(bodyLabel).\(name) touched \(otherLabel)" + String(format: " (depth %.3f m)", contact.depth))
    }
}
