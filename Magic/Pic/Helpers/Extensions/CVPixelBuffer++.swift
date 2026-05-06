//
//  CVPixelBuffer++.swift
//  Magic
//
//  Created by CoderWan on 2026/4/23.
//

import CoreImage
import CoreVideo

extension CVPixelBuffer {
    nonisolated var ciImage: CIImage {
        CIImage(cvPixelBuffer: self)
    }
}
