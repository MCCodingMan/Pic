//
//  PicCameraToast.swift
//  Magic
//
//  Created by CoderWan on 2026/5/8.
//

import Foundation

struct PicCameraToast: Equatable {
    enum Kind: Equatable {
        case info
        case success
        case error
    }

    let message: String
    let systemImage: String
    let kind: Kind
}
