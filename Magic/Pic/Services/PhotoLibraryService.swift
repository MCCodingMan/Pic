import Photos
import UIKit
import ImageIO
import UniformTypeIdentifiers

class PhotoLibraryService {
    static let shared = PhotoLibraryService()
    
    func checkPermission() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return newStatus == .authorized || newStatus == .limited
        default:
            return false
        }
    }
    
    func saveImage(_ image: UIImage) async throws {
        let hasPermission = await checkPermission()
        guard hasPermission else {
            throw NSError(domain: "Pic", code: 1, userInfo: [NSLocalizedDescriptionKey: "Photo library access denied"])
        }

        guard let encoded = encodeHEIFOrJPEG(from: image, metadataSourceData: nil) else {
            throw NSError(domain: "Pic", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create image data"])
        }

        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(encoded.fileExtension)
        try encoded.data.write(to: imageURL)

        defer {
            try? FileManager.default.removeItem(at: imageURL)
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: imageURL, options: nil)
        }
    }

    /// 保存实况照片（静态图 + 视频）到相册
    func saveLivePhoto(_ image: UIImage, movieURL: URL) async throws {
        guard let encoded = encodeHEIFOrJPEG(from: image, metadataSourceData: nil) else {
            throw NSError(domain: "Pic", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create image data"])
        }
        try await saveLivePhoto(imageData: encoded.data, imageFileExtension: encoded.fileExtension, movieURL: movieURL)
    }

    /// 保存实况照片（静态图 + 视频）到相册，并尽量保留源图中的 Live Photo 配对元数据
    func saveLivePhoto(stillImage: UIImage, sourcePhotoData: Data, movieURL: URL) async throws {
        let encoded = encodeHEIFOrJPEG(from: stillImage, metadataSourceData: sourcePhotoData)
        let imageData = encoded?.data ?? sourcePhotoData
        let fileExtension = encoded?.fileExtension ?? preferredImageFileExtension(for: sourcePhotoData, fallback: "heic")
        try await saveLivePhoto(imageData: imageData, imageFileExtension: fileExtension, movieURL: movieURL)
    }

    private func saveLivePhoto(imageData: Data, imageFileExtension: String, movieURL: URL) async throws {
        let hasPermission = await checkPermission()
        guard hasPermission else {
            throw NSError(domain: "Pic", code: 1, userInfo: [NSLocalizedDescriptionKey: "Photo library access denied"])
        }

        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(imageFileExtension)
        try imageData.write(to: imageURL)

        defer {
            try? FileManager.default.removeItem(at: imageURL)
            try? FileManager.default.removeItem(at: movieURL)
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: imageURL, options: nil)
            let videoOptions = PHAssetResourceCreationOptions()
            videoOptions.shouldMoveFile = true
            request.addResource(with: .pairedVideo, fileURL: movieURL, options: videoOptions)
        }
    }

    private struct EncodedImage {
        let data: Data
        let fileExtension: String
    }

    private func encodeHEIFOrJPEG(from image: UIImage, metadataSourceData: Data?) -> EncodedImage? {
        if let heifData = encodeImageData(from: image, type: .heic, metadataSourceData: metadataSourceData) {
            return EncodedImage(data: heifData, fileExtension: "heic")
        }
        if let jpegData = encodeImageData(from: image, type: .jpeg, metadataSourceData: metadataSourceData) {
            return EncodedImage(data: jpegData, fileExtension: "jpg")
        }
        return nil
    }

    private func encodeImageData(from image: UIImage, type: UTType, metadataSourceData: Data?) -> Data? {
        guard let cgImage = normalizedCGImage(from: image) else { return nil }

        var metadata: [CFString: Any] = [:]
        if let metadataSourceData,
           let source = CGImageSourceCreateWithData(metadataSourceData as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            metadata = properties
        }
        metadata[kCGImagePropertyOrientation] = CGImagePropertyOrientation.up.rawValue

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            type.identifier as CFString,
            1,
            nil
        ) else { return nil }

        CGImageDestinationAddImage(destination, cgImage, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private func normalizedCGImage(from image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cgImage = image.cgImage {
            return cgImage
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = !imageHasAlpha(image)
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let normalizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return normalizedImage.cgImage
    }

    private func imageHasAlpha(_ image: UIImage) -> Bool {
        guard let alphaInfo = image.cgImage?.alphaInfo else { return false }
        return alphaInfo == .first
            || alphaInfo == .last
            || alphaInfo == .premultipliedFirst
            || alphaInfo == .premultipliedLast
    }

    private func preferredImageFileExtension(for data: Data, fallback: String) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else {
            return fallback
        }
        return UTType(type as String)?.preferredFilenameExtension ?? fallback
    }
}
