import SwiftUI
import Photos
import UIKit

struct PhotoThumbnailView: View {
    private static let sharedImageManager = PHCachingImageManager()

    let asset: PHAsset
    private var imageManager: PHCachingImageManager { Self.sharedImageManager }
    
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                }
            }
            .onAppear {
                loadImage(targetSize: geometry.size)
            }
            .onDisappear {
                cancelImageRequest()
            }
        }
        .contentShape(.rect)
    }
    
    private func loadImage(targetSize: CGSize) {
        let scale = SwiftApp.screenScale
        let size = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        
        // Cancel previous request if reused
        cancelImageRequest()
        
        requestID = imageManager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { result, info in
            if let result = result {
                self.image = result
            }
        }
    }
    
    private func cancelImageRequest() {
        if let id = requestID {
            imageManager.cancelImageRequest(id)
            requestID = nil
        }
    }
}
