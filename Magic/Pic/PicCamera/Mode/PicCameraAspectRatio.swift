//
//  PicCameraAspectRatio.swift
//  Magic
//
//  Created by CoderWan on 2026/5/8.
//

import Foundation

enum PicCameraAspectRatio: String, CaseIterable, Identifiable {
    case ratio1x1 = "1:1"
    case ratio3x4 = "3:4"
    case ratio9x16 = "9:16"

    var id: String { rawValue }

    var portraitAspect: CGFloat {
        switch self {
        case .ratio1x1: return 1.0
        case .ratio3x4: return 3.0 / 4.0
        case .ratio9x16: return 9.0 / 16.0
        }
    }

    func displayName(isLandscape: Bool) -> String {
        guard isLandscape else { return rawValue }
        switch self {
        case .ratio1x1:
            return "1:1"
        case .ratio3x4:
            return "4:3"
        case .ratio9x16:
            return "16:9"
        }
    }

    func iconName(isLandscape: Bool) -> String {
        switch self {
        case .ratio1x1:
            return "square"
        case .ratio3x4:
            return isLandscape ? "rectangle.ratio.4.to.3" : "rectangle.ratio.3.to.4"
        case .ratio9x16:
            return isLandscape ? "rectangle.ratio.16.to.9" : "rectangle.ratio.9.to.16"
        }
    }
}
