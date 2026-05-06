import SwiftUI
import UIKit

struct ZoomableCanvas<Content: View>: View {
    let image: UIImage
    let originalImage: UIImage?
    let isShowingOriginal: Bool
    let content: Content
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    init(image: UIImage, originalImage: UIImage? = nil, isShowingOriginal: Bool = false, @ViewBuilder content: () -> Content = { EmptyView() }) {
        self.image = image
        self.originalImage = originalImage
        self.isShowingOriginal = isShowingOriginal
        self.content = content()
    }
    
    var displayImage: UIImage {
        if isShowingOriginal, let original = originalImage {
            return original
        }
        return image
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.clear
                
                ZStack {
                    // 1. Original Image (Bottom)
                    if let original = originalImage {
                        Image(uiImage: original)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                    
                    // 2. Edited Preview Image (Top)
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .opacity(isShowingOriginal ? 0 : 1) // Smooth fade transition
                }
                .overlay(content)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let delta = value / lastScale
                            lastScale = value
                            scale *= delta
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                            withAnimation {
                                if scale < 1.0 {
                                    scale = 1.0
                                    offset = .zero
                                }
                            }
                        }
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                            withAnimation {
                                if scale <= 1.0 {
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    TapGesture(count: 2)
                        .onEnded {
                            withAnimation {
                                if scale > 1.0 {
                                    scale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 2.0
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            }
                        }
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
    }
}
