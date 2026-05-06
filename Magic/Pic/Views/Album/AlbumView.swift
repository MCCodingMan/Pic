import SwiftUI
import Photos
import UIKit

struct AlbumView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var scheme
    
    @State private var viewModel = AlbumViewModel()
    @Namespace private var previewNamespace
    
    // Callback for when an image is selected
    var onSelect: ((UIImage) -> Void)?
    
    // Grid Layout: 3 columns
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        ZStack {
            // Background
            DS.ColorToken.surface(scheme)
                .ignoresSafeArea()
            
            if viewModel.authorizationStatus == .authorized || viewModel.authorizationStatus == .limited {
                albumGridView
            } else if viewModel.authorizationStatus == .denied || viewModel.authorizationStatus == .restricted {
                permissionDeniedView
            } else {
                // Loading or waiting for permission
                ProgressView()
            }

        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Menu {
                    ForEach(viewModel.albums) { album in
                        Button(action: {
                            viewModel.selectAlbum(album)
                        }) {
                            HStack {
                                Text(album.title)
                                if viewModel.selectedAlbum?.id == album.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.selectedAlbum?.title ?? "相册")
                            .font(.headline)
                            .foregroundColor(DS.ColorToken.textPrimary(scheme))
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(DS.ColorToken.textSecondary(scheme))
                    }
                }
            }
        }
        .onAppear {
            if viewModel.authorizationStatus == .notDetermined {
                viewModel.requestPermission()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
    }
    
    // MARK: - Grid View
    private var albumGridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                // Use fetchResult count directly to avoid loading all assets into memory array
                ForEach(0..<viewModel.assets.count, id: \.self) { index in
                    let asset = viewModel.assets[index]
                    NavigationLink {
                        AlbumPhotoPreviewView(
                            viewModel: viewModel,
                            initialIndex: index,
                            namespace: previewNamespace,
                            onSelect: onSelect.map { select in
                                { image in
                                    select(image)
                                    dismiss()
                                }
                            }
                        )
                    } label: {
                        PhotoThumbnailView(asset: asset)
                            .aspectRatio(1, contentMode: .fill)
                            .clipped()
                            .matchedTransitionSource(id: asset.localIdentifier, in: previewNamespace)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
        }
    }
    
    // MARK: - Permission Denied View
    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 50))
                .foregroundColor(DS.ColorToken.textSecondary(scheme))
            
            Text("需要相册权限")
                .font(.headline)
                .foregroundColor(DS.ColorToken.textPrimary(scheme))
            
            Text("请在设置中允许访问您的相册以选择照片")
                .font(.subheadline)
                .foregroundColor(DS.ColorToken.textSecondary(scheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }) {
                Text("去设置")
                    .font(.headline)
                    .foregroundColor(DS.ColorToken.onBrand)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 12)
                    .background(DS.ColorToken.brandPrimary(scheme))
                    .cornerRadius(8)
            }
        }
    }
    
}

private struct AlbumPhotoPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    let viewModel: AlbumViewModel
    @State private var selectedIndex: Int
    let namespace: Namespace.ID
    let onSelect: ((UIImage) -> Void)?

    @State private var selectedImage: UIImage?
    @State private var isCurrentPageZoomed = false
    @State private var isThumbnailStripDragging = false

    init(
        viewModel: AlbumViewModel,
        initialIndex: Int,
        namespace: Namespace.ID,
        onSelect: ((UIImage) -> Void)?
    ) {
        self.viewModel = viewModel
        self._selectedIndex = State(initialValue: initialIndex)
        self.namespace = namespace
        self.onSelect = onSelect
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            TabView(selection: $selectedIndex) {
                ForEach(0..<viewModel.assets.count, id: \.self) { index in
                    AlbumZoomableAssetPage(
                        asset: viewModel.assets[index],
                        imageManager: viewModel.imageManager,
                        isCurrent: selectedIndex == index,
                        selectedIndex: $selectedIndex,
                        pageCount: viewModel.assets.count,
                        namespace: namespace,
                        isCurrentPageZoomed: $isCurrentPageZoomed
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .scrollDisabled(isCurrentPageZoomed || isThumbnailStripDragging)
            .ignoresSafeArea()

            topBar
            thumbnailStrip
        }
        .navigationTransition(.zoom(sourceID: currentSourceID, in: namespace))
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: selectedIndex) { _, _ in
            isCurrentPageZoomed = false
        }
        .task(id: selectedIndex) {
            guard viewModel.assets.count > 0 else { return }
            selectedImage = await loadImage(for: viewModel.assets[clampedSelectedIndex])
        }
    }

    private var clampedSelectedIndex: Int {
        min(max(selectedIndex, 0), max(viewModel.assets.count - 1, 0))
    }

    private var currentSourceID: String {
        guard viewModel.assets.count > 0 else { return "" }
        return viewModel.assets[clampedSelectedIndex].localIdentifier
    }

    private var topBar: some View {
        VStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(.black.opacity(0.45)))
                }
                .buttonStyle(.plain)

                Spacer()

                if let onSelect {
                    Button {
                        if let selectedImage {
                            onSelect(selectedImage)
                        }
                    } label: {
                        Text("选择")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 38)
                            .background(Capsule().fill(DS.ColorToken.brandPrimary(scheme)))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedImage == nil)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            Spacer()
        }
    }

    private var thumbnailStrip: some View {
        VStack {
            Spacer()

            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 0) {
                            ForEach(0..<viewModel.assets.count, id: \.self) { index in
                                let isSelected = selectedIndex == index
                                Button {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                        selectedIndex = index
                                    }
                                } label: {
                                    PhotoThumbnailView(asset: viewModel.assets[index])
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(isSelected ? Color.white : Color.white.opacity(0.16), lineWidth: isSelected ? 2 : 1)
                                        }
                                        .scaleEffect(isSelected ? 1.1 : 1)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, isSelected ? 20 : 8)
                                .id(index)
                            }
                        }
                        .safeAreaPadding(.horizontal, max((geometry.size.width - 56) / 2, 0))
                        .padding(.vertical, 12)
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { _ in
                                isThumbnailStripDragging = true
                            }
                            .onEnded { _ in
                                isThumbnailStripDragging = false
                            }
                    )
                    .onAppear {
                        proxy.scrollTo(selectedIndex, anchor: .center)
                    }
                    .onChange(of: selectedIndex) { _, newValue in
                        withAnimation(.easeInOut(duration: 0.22)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            }
            .frame(height: 92)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            )
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func loadImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            var didResume = false
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .none
            options.isNetworkAccessAllowed = true

            viewModel.imageManager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: image)
            }
        }
    }
}

private struct AlbumZoomableAssetPage: View {
    let asset: PHAsset
    let imageManager: PHCachingImageManager
    let isCurrent: Bool
    @Binding var selectedIndex: Int
    let pageCount: Int
    let namespace: Namespace.ID
    @Binding var isCurrentPageZoomed: Bool

    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var pageSwitchArmed = true

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image {
                    zoomableImage(image, in: geometry.size)
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .task(id: asset.localIdentifier) {
            image = await loadImage()
        }
        .onChange(of: isCurrent) { _, newValue in
            if !newValue {
                resetZoom()
            }
        }
    }

    @ViewBuilder
    private func zoomableImage(_ image: UIImage, in size: CGSize) -> some View {
        let content = Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(magnifyGesture(in: size))
            .onTapGesture(count: 2) {
                toggleZoom(in: size)
            }

        if scale > 1.001 {
            content.simultaneousGesture(panGesture(in: size))
        } else {
            content
        }
    }

    private func magnifyGesture(in size: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let nextScale = min(max(lastScale * value, 1), 20)
                scale = nextScale
                updateCurrentZoomState()
                offset = clamped(offset, for: size, scale: nextScale)
            }
            .onEnded { _ in
                scale = min(max(scale, 1), 20)
                updateCurrentZoomState()
                offset = clamped(offset, for: size, scale: scale)
                lastScale = scale
                lastOffset = offset
            }
    }

    private func panGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard scale > 1.001 else { return }
                let proposed = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                offset = clamped(proposed, for: size, scale: scale)
                trySwitchPageIfNeeded(translation: value.translation, proposedOffset: proposed, size: size)
            }
            .onEnded { _ in
                pageSwitchArmed = true
                offset = clamped(offset, for: size, scale: scale)
                lastOffset = offset
            }
    }

    private func trySwitchPageIfNeeded(translation: CGSize, proposedOffset: CGSize, size: CGSize) {
        guard pageSwitchArmed, abs(translation.width) > abs(translation.height), abs(translation.width) > 72 else { return }
        let limit = horizontalLimit(for: size, scale: scale)

        if proposedOffset.width > limit + 42, selectedIndex > 0 {
            pageSwitchArmed = false
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedIndex -= 1
            }
        } else if proposedOffset.width < -limit - 42, selectedIndex < pageCount - 1 {
            pageSwitchArmed = false
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedIndex += 1
            }
        }
    }

    private func toggleZoom(in size: CGSize) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            if scale > 1.001 {
                resetZoom()
            } else {
                scale = 2.5
                lastScale = scale
                offset = .zero
                lastOffset = .zero
                updateCurrentZoomState()
            }
        }
    }

    private func resetZoom() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
        pageSwitchArmed = true
        updateCurrentZoomState()
    }

    private func updateCurrentZoomState() {
        guard isCurrent else { return }
        isCurrentPageZoomed = scale > 1.001
    }

    private func clamped(_ value: CGSize, for size: CGSize, scale: CGFloat) -> CGSize {
        let xLimit = horizontalLimit(for: size, scale: scale)
        let yLimit = max((size.height * scale - size.height) / 2, 0)
        return CGSize(
            width: min(max(value.width, -xLimit), xLimit),
            height: min(max(value.height, -yLimit), yLimit)
        )
    }

    private func horizontalLimit(for size: CGSize, scale: CGFloat) -> CGFloat {
        max((size.width * scale - size.width) / 2, 0)
    }

    private func loadImage() async -> UIImage? {
        await withCheckedContinuation { continuation in
            var didResume = false
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .none
            options.isNetworkAccessAllowed = true

            imageManager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: image)
            }
        }
    }
}
