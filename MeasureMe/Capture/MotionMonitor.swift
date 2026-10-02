import CoreMotion
import Foundation

/// Reports phone tilt and shake from Core Motion. Device motion needs no permission prompt.
/// https://developer.apple.com/documentation/coremotion/cmmotionmanager
final class MotionMonitor: @unchecked Sendable {
    struct Snapshot {
        /// Forward/back tilt from upright portrait, degrees. Positive = top of phone leaning towards the subject.
        var pitchDegrees: Double
        /// Sideways tilt, degrees.
        var rollDegrees: Double
        /// Rotation rate magnitude, rad/s.
        var rotationRate: Double
    }

    private let manager = CMMotionManager()
    private let queue = OperationQueue()
    private let lock = NSLock()
    private var latest: Snapshot?

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let m = motion else { return }
            let g = m.gravity
            // Upright portrait: gravity ≈ (0, -1, 0). z points out of the screen.
            let pitch = atan2(g.z, -g.y) * 180 / .pi
            let roll = atan2(g.x, -g.y) * 180 / .pi
            let r = m.rotationRate
            let rate = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
            self.lock.lock()
            self.latest = Snapshot(pitchDegrees: pitch, rollDegrees: roll, rotationRate: rate)
            self.lock.unlock()
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    func snapshot() -> Snapshot? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }
}
