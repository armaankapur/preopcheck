//
//  SteadinessMonitor.swift
//  PreOpCheck
//
//  Answers one question for the scanner: is the phone being held still?
//
//  Recognition runs about three times a second, so while the phone moves
//  the markers trail the picture and appear to jump. Reading the motion
//  sensors is far cheaper than analysing frames, so the scanner draws
//  nothing while the phone moves and draws as soon as it has been still for
//  `settleTime`. In the Simulator there are no sensors and the phone counts
//  as always still.
//
//  Motion data never leaves the device and nothing is recorded.
//

import CoreMotion
import Foundation

final class SteadinessMonitor {

    /// Below these the phone counts as still. Rotation in radians per
    /// second; acceleration in g, gravity removed. Tuned on a hand-held
    /// phone: slow re-aiming passes, a deliberate pan does not.
    private static let maxRotation = 0.25
    private static let maxAcceleration = 0.12
    /// How long the phone must be still before overlays appear.
    private static let settleTime: TimeInterval = 0.3

    private let motion = CMMotionManager()
    private var stillSince: Date?

    /// True once the phone has been still for `settleTime`. Read on main.
    private(set) var isSteady = true

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            self.update(with: data)
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        stillSince = nil
        isSteady = true
    }

    private func update(with data: CMDeviceMotion) {
        let r = data.rotationRate
        let a = data.userAcceleration
        let rotation = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
        let acceleration = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()

        if rotation > SteadinessMonitor.maxRotation || acceleration > SteadinessMonitor.maxAcceleration {
            stillSince = nil
            isSteady = false
            return
        }
        let since = stillSince ?? Date()
        stillSince = since
        isSteady = Date().timeIntervalSince(since) >= SteadinessMonitor.settleTime
    }
}
