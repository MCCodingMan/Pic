//
//  PicCameraFrameConsumer.swift
//  Magic
//
//  Created by CoderWan on 2026/5/8.
//

internal import AVFoundation

protocol PicCameraFrameConsumer: AnyObject {
    nonisolated func consume(pixelBuffer: CVPixelBuffer, depthData: AVDepthData?)
}
