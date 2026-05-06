//
//  PicCameraMode.swift
//  Magic
//
//  Created by CoderWan on 2026/5/8.
//

internal import AVFoundation

enum PicCameraMode: String, CaseIterable, Identifiable {
    case photo
    case portrait

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo:
            return "拍照"
        case .portrait:
            return "人像"
        }
    }

    var iconName: String {
        switch self {
        case .photo:
            return "camera"
        case .portrait:
            return "person.crop.square"
        }
    }

    func deviceTypes(for position: AVCaptureDevice.Position) -> [AVCaptureDevice.DeviceType] {
        switch (self, position) {
        case (.photo, .back):
            return [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
        case (.photo, .front):
            return [.builtInWideAngleCamera, .builtInTrueDepthCamera]
        case (.portrait, .back):
            // Portrait should work on more devices, not only LiDAR-capable ones.
            return [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera, .builtInLiDARDepthCamera]
//            return [.builtInLiDARDepthCamera, .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
        case (.portrait, .front):
            return [.builtInTrueDepthCamera, .builtInWideAngleCamera]
        default:
            return [.builtInWideAngleCamera]
        }
    }
}
