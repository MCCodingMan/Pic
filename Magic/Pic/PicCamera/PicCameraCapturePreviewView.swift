import SwiftUI
import UIKit

struct PicCameraCapturePreviewView: View {
    @Environment(\.colorScheme) private var scheme

    let image: UIImage
    let onContinue: () -> Void
    let onOpenAlbum: () -> Void
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onContinue) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.onBrand)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.black.opacity(0.48)))
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: onDone) {
                Text("完成")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.onBrand)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(Capsule().fill(.black.opacity(0.48)))
            }
            .buttonStyle(.plain)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(action: onContinue) {
                Label("继续拍", systemImage: "camera.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DS.ColorToken.onBrand)
            .background(Capsule().fill(.black.opacity(0.52)))

            Button(action: onOpenAlbum) {
                Label("打开相册", systemImage: "photo.on.rectangle")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DS.ColorToken.textPrimary(scheme))
            .background(Capsule().fill(DS.ColorToken.surface(scheme).opacity(0.9)))
        }
    }
}
