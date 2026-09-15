//
//  TouchdownReporter.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/6/26.
//

import Foundation

/// Print-only flight-test telemetry: gear events as they come, airframe
/// contacts classified. Runs inside the physics step's callbacks on the
/// UpdateThread, so it must stay print-only. The player aircraft's
/// replacement for ContactDebugLogger, which stays for general contact cases.
final class TouchdownReporter {
    private let bodyLabel: String
    private let scrapeLogInterval: Double
    private var lastScrapeLog: [String: Double] = [:]
    private var lastImpactLog: [ObjectIdentifier: Double] = [:]
    
    init(bodyLabel: String, scrapeLogInterval: Double = 1.0) {
        self.bodyLabel = bodyLabel
        self.scrapeLogInterval = scrapeLogInterval
    }
    
    func report(_ event: LandingGearEvent) {
        switch event {
            case .touchdown(let sinkRate, let compressions):
                let comps = compressions.map { String(format: "%.3f", $0) }.joined(separator: ", ")
                print("[Touchdown] \(bodyLabel) sink \(String(format: "%.2f", sinkRate)) m/s, compressions [\(comps)] m")
            case .liftoff:
                print("[Liftoff] \(bodyLabel)")
            case .gearOverload(let strutName, let force, let bottomedOut):
                print("[GearOverload] \(bodyLabel).\(strutName) at \(String(format: "%.0f", force)) N"
                      + (bottomedOut ? ", bottomed out" : ""))
        }
    }
    
    /// Scrapes are throttled per collider name (a sliding fuselage re-contacts
    /// every step); impacts print once per frame per other body, keyed on
    /// GameTime.TotalGameTime, which a frame's substeps share. That is a
    /// policy, not a proof: a level belly slap is two cap contacts in one
    /// substep and one crash, and a tumbling airframe that strikes the same
    /// body with a second collider inside the same frame also prints once —
    /// one line for one event, which is the right amount of console.
    /// `preImpactRelativeVelocity` is the aircraft's step-start velocity at
    /// the contact point minus the other body's there: a rotating wing
    /// strikes at ω × r while the origin is still, and a ball thrown at a
    /// parked jet closes at its own speed.
    func reportAirframeContact(_ contact: Contact, preImpactRelativeVelocity: float3, isGearDown: Bool, against other: RigidBody) {
        let speed = AirframeContactClassifier.normalSpeed(contactNormal: contact.normal, preImpactVelocity: preImpactRelativeVelocity)
        let classification = AirframeContactClassifier.classification(forNormalSpeed: speed)
        let name = contact.colliderNameA ?? "aircraft body"
        let now = GameTime.TotalGameTime
        
        if classification == .scrape {
            if let last = lastScrapeLog[name], now - last < scrapeLogInterval { return }
            lastScrapeLog[name] = now
        } else {
            let key = ObjectIdentifier(other)
            if lastImpactLog[key] == now { return }
            lastImpactLog[key] = now
        }
        
        let otherLabel = other.gameObject?.getName() ?? "static geometry"
        let label = classification == .impact ? "CRASH" : "Scrape"
        print("[\(label)] \(bodyLabel).\(name) hit \(otherLabel) at "
                      + String(format: "%.2f m/s", speed)
                      + " (gear \(isGearDown ? "down" : "up"))")
    }
}
