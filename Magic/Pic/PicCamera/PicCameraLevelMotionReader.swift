import CoreMotion
import UIKit

@MainActor
final class PicCameraLevelMotionReader {
    private let motionManager = CMMotionManager()
    private var orientation: UIDeviceOrientation = .portrait

    func updateOrientation(_ orientation: UIDeviceOrientation) {
        self.orientation = orientation
    }

    func start(onChange: @escaping (Double) -> Void) {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.stopDeviceMotionUpdates()
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self else { return }
            guard let motion else { return }
            let gravity = motion.gravity
            let angle: Double

            switch self.orientation {
            case .landscapeLeft:
                angle = atan2(-gravity.y, -gravity.x)
            case .landscapeRight:
                angle = atan2(gravity.y, gravity.x)
            case .portraitUpsideDown:
                angle = atan2(-gravity.x, gravity.y)
            default:
                angle = atan2(gravity.x, -gravity.y)
            }

            onChange(angle)
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }

    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
}
