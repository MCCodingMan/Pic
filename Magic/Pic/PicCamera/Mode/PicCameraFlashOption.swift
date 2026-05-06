//
//  PicCameraFlashOption.swift
//  Magic
//
//  Created by CoderWan on 2026/5/8.
//

import Foundation
internal import AVFoundation

enum PicCameraFlashOption: String, CaseIterable, Identifiable {
    case off = "关闭"
    case auto = "自动"
    case on = "开启"

    var id: String { rawValue }

    init(mode: AVCaptureDevice.FlashMode) {
        switch mode {
        case .off:
            self = .off
        case .auto:
            self = .auto
        case .on:
            self = .on
        @unknown default:
            self = .off
        }
    }

    var flashMode: AVCaptureDevice.FlashMode {
        switch self {
        case .off:
            return .off
        case .auto:
            return .auto
        case .on:
            return .on
        }
    }
}
