import SwiftUI
import UIKit

struct StickerView: View {
    let sticker: Sticker
    let parentSize: CGSize
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        contentView
            .overlay(
                Group {
                    if isSelected {
                        Rectangle()
                            .stroke(Color.blue, lineWidth: 2)
                    }
                }
                .allowsHitTesting(false)
            )
            .scaleEffect(sticker.scale)
            .rotationEffect(.radians(sticker.rotation))
            .rotation3DEffect(.radians(sticker.rotationX), axis: (x: 1, y: 0, z: 0))
            .rotation3DEffect(.radians(sticker.rotationY), axis: (x: 0, y: 1, z: 0))
            .position(
                x: sticker.position.x * parentSize.width,
                y: sticker.position.y * parentSize.height
            )
            .onTapGesture {
                onSelect()
            }
    }
    
    @ViewBuilder
    private var contentView: some View {
        if let data = sticker.imageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
        } else {
            // Text Sticker
            Text(sticker.content)
                .font(.custom(sticker.fontName == "System" ? ".AppleSystemUIFont" : sticker.fontName, size: 100))
                .foregroundColor(sticker.textColor.uiColor)
                .frame(minWidth: 100, minHeight: 100)
                .minimumScaleFactor(0.1)
                // Add background if needed
                .padding(4)
                .background(sticker.backgroundColor?.uiColor ?? .clear)
                .cornerRadius(8)
        }
    }
}
