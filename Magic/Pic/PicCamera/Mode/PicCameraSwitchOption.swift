//
//  PicCameraSwitchOption.swift
//  Magic
//
//  Created by CoderWan on 2026/5/8.
//

import Foundation

enum PicCameraSwitchOption: String, CaseIterable, Identifiable {
    case off = "关"
    case on = "开"

    var id: String { rawValue }

    var isEnabled: Bool {
        self == .on
    }

    init(_ isEnabled: Bool) {
        self = isEnabled ? .on : .off
    }
}
