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
    /// every step); impacts always print.
    func reportAirframeContact(_ contact: Contact, preImpactVelocity: float3, isGearDown: Bool, against other: RigidBody) {
        let speed = AirframeContactClassifier.normalSpeed(contactNormal: contact.normal, preImpactVelocity: preImpactVelocity)
        let classification = AirframeContactClassifier.classification(forNormalSpeed: speed)
        let name = contact.colliderNameA ?? "aircraft body"
        
        if classification == .scrape {
            let now = GameTime.TotalGameTime
            if let last = lastScrapeLog[name], now - last < scrapeLogInterval { return }
            lastScrapeLog[name] = now
        }
        
        let otherLabel = other.gameObject?.getName() ?? "static geometry"
        let label = classification == .impact ? "CRASH" : "Scrape"
        print("[\(label)] \(bodyLabel).\(name) hit \(otherLabel) at "
                      + String(format: "%.2f m/s", speed)
                      + " (gear \(isGearDown ? "down" : "up"))")
    }
}
