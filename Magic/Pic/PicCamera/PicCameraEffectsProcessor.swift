import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Metal

enum PicCameraEffectsProcessor {
    nonisolated private static let ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        }
        return CIContext()
    }()
    nonisolated private static let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
    nonisolated private static func originalFilter() -> FilterModel {
        FilterModel(id: "original", name: "原图", category: "基础", colorMatrix: nil, adjustments: nil)
    }

    nonisolated static func makePreviewImage(
        pixelBuffer: CVPixelBuffer,
        beautyParams: BeautyParams,
        faceContext: FaceContext,
        adjustments: Adjustments,
        filter: FilterModel
    ) -> CIImage {
        let activeFilter = filter.id == "auto" ? originalFilter() : filter
        let needsRealtimePipeline = !beautyParams.isIdentity || !adjustments.isDefault || activeFilter.id != "original"
        if needsRealtimePipeline,
           let texture = ImagePipeline.shared.processCameraFrame(
            pixelBuffer: pixelBuffer,
            params: beautyParams,
            faceContext: faceContext,
            adjustments: adjustments,
            filter: activeFilter
           ),
           let processed = CIImage(
            mtlTexture: texture,
            options: [.colorSpace: rgbColorSpace]
           ) {
            return processed.oriented(.right)
        } else {
            let baseImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
            let adjustedImage = apply(adjustments: adjustments, to: baseImage)
            return apply(filter: activeFilter, to: adjustedImage)
        }
    }

    nonisolated static func processCapturedImage(
        _ image: UIImage,
        beautyParams: BeautyParams,
        faceContext: FaceContext,
        adjustments: Adjustments,
        filter: FilterModel
    ) -> CIImage? {
        let activeFilter = filter.id == "auto" ? originalFilter() : filter
        var outputImage = image

        if !beautyParams.isIdentity {
            outputImage = ImagePipeline.shared.processBeauty(
                image: outputImage,
                params: beautyParams,
                faceContext: faceContext
            )
        }

        guard let ciImage = CIImage(image: outputImage) else {
            return nil
        }

        var edits = EditState()
        edits.adjustments = adjustments
        edits.filter = activeFilter
        return ImagePipeline.shared.processEditor(ciImage, edits: edits)
    }

    nonisolated static func apply(filter: FilterModel, to image: CIImage) -> CIImage {
        guard filter.id != "original" else { return image }

        var outputImage = image

        if let matrix = filter.colorMatrix,
           matrix.count == 20 {
            let values = matrix.map { CGFloat($0) }
            outputImage = outputImage.applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputRVector": CIVector(values: Array(values[0...3]), count: 4),
                    "inputGVector": CIVector(values: Array(values[4...7]), count: 4),
                    "inputBVector": CIVector(values: Array(values[8...11]), count: 4),
                    "inputAVector": CIVector(values: Array(values[12...15]), count: 4),
                    "inputBiasVector": CIVector(values: Array(values[16...19]), count: 4)
                ]
            )
        }

        if let adjustments = filter.adjustments {
            outputImage = apply(adjustments: adjustments, to: outputImage)
        }

        return outputImage
    }

    nonisolated static func apply(adjustments: Adjustments, to image: CIImage) -> CIImage {
        var outputImage = image

        if abs(adjustments.exposure) > 0.001 {
            outputImage = outputImage.applyingFilter(
                "CIExposureAdjust",
                parameters: [kCIInputEVKey: adjustments.exposure]
            )
        }

        if abs(adjustments.contrast - 1.0) > 0.001 ||
            abs(adjustments.brightness) > 0.001 ||
            abs(adjustments.saturation - 1.0) > 0.001 {
            outputImage = outputImage.applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputContrastKey: adjustments.contrast,
                    kCIInputBrightnessKey: adjustments.brightness,
                    kCIInputSaturationKey: adjustments.saturation
                ]
            )
        }

        if abs(adjustments.highlights) > 0.001 || abs(adjustments.shadows) > 0.001 {
            outputImage = outputImage.applyingFilter(
                "CIHighlightShadowAdjust",
                parameters: [
                    "inputHighlightAmount": min(max(1.0 + adjustments.highlights, 0.0), 2.0),
                    "inputShadowAmount": min(max(adjustments.shadows, -1.0), 1.0)
                ]
            )
        }

        if abs(adjustments.warmth) > 0.001 || abs(adjustments.tint) > 0.001 {
            let neutral = CIVector(x: 6500, y: 0)
            let target = CIVector(
                x: 6500 + adjustments.warmth * 2200,
                y: adjustments.tint * 180
            )
            outputImage = outputImage.applyingFilter(
                "CITemperatureAndTint",
                parameters: [
                    "inputNeutral": neutral,
                    "inputTargetNeutral": target
                ]
            )
        }

        if adjustments.sharpen > 0.001 {
            outputImage = outputImage.applyingFilter(
                "CISharpenLuminance",
                parameters: [kCIInputSharpnessKey: adjustments.sharpen]
            )
        } else if adjustments.sharpen < -0.001 {
            let originalExtent = outputImage.extent
            outputImage = outputImage
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: abs(adjustments.sharpen) * 2.5])
                .cropped(to: originalExtent)
        }

        if adjustments.clarity > 0.001 {
            outputImage = outputImage.applyingFilter(
                "CIUnsharpMask",
                parameters: [
                    kCIInputRadiusKey: 2.0,
                    kCIInputIntensityKey: adjustments.clarity * 1.2
                ]
            )
        } else if adjustments.clarity < -0.001 {
            let originalExtent = outputImage.extent
            outputImage = outputImage
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: abs(adjustments.clarity) * 1.8])
                .cropped(to: originalExtent)
        }

        if adjustments.vignette > 0.001 {
            outputImage = outputImage.applyingFilter(
                "CIVignette",
                parameters: [
                    kCIInputIntensityKey: adjustments.vignette * 1.2,
                    kCIInputRadiusKey: max(outputImage.extent.width, outputImage.extent.height) * 0.55
                ]
            )
        }

        return outputImage
    }
}
