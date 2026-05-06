import SwiftUI
import PhotosUI
import UIKit
internal import AVFoundation

struct HomeView: View {
    @State private var viewModel = HomeViewModel()
    @Environment(\.colorScheme) var scheme
    
    @State private var selectedProjectToEdit: PhotoProject?
    @State private var loadedImageForEdit: UIImage?
    @State private var isEditorActive = false
    
    // Feature Handling
    @State private var showPhotoPicker = false
    @State private var showMultiPhotoPicker = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var collageImages: [UIImage] = []
    @State private var isCollageActive = false
    @State private var selectedFeatureMode: EditorMode = .adjust

    // Beauty
    @State private var showBeautyPicker = false
    @State private var beautyPickerItem: PhotosPickerItem?
    @State private var isBeautyActive = false
    @State private var beautyImage: UIImage?

    // Camera
    @State private var isPicCameraActive = false
    @State private var showCameraPermissionAlert = false

    // New Feature States
    @State private var showSettings = false
    @State private var showNotifications = false
    @State private var projectToRename: PhotoProject?
    @State private var newProjectTitle = ""
    @State private var showRenameAlert = false
    

    // Loading State
    @State private var isProcessingProject = false
    @State private var showLoadError = false
    
    var body: some View {
        ZStack {
            // Background Gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    scheme == .dark ? Color(hex: "0f172a") : Color(hex: "f0f9ff"),
                    scheme == .dark ? Color(hex: "1e293b") : Color(hex: "e0f2fe")
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Top Bar
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pic")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(DS.ColorToken.brandPrimary(scheme))
                        Text("让修图更简单")
                            .font(.caption)
                            .foregroundColor(DS.ColorToken.textSecondary(scheme))
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            showNotifications = true
                        }) {
                            Image(systemName: "bell.badge")
                                .font(.system(size: 20))
                                .foregroundColor(DS.ColorToken.textPrimary(scheme))
                                .frame(width: 40, height: 40)
                                .background(DS.ColorToken.surfaceAlt(scheme).opacity(0.8))
                                .clipShape(Circle())
                        }
                        
                        Button(action: {
                            showSettings = true
                        }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 20))
                                .foregroundColor(DS.ColorToken.textPrimary(scheme))
                                .frame(width: 40, height: 40)
                                .background(DS.ColorToken.surfaceAlt(scheme).opacity(0.8))
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 10)
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        // 功能区: 2 行 4 列, 修图占 2 格作为主推
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("功能", accent: .purple)

                            // col = (屏宽 - 左右 padding 32 - 3 个间距 24) / 4
                            let col = (SwiftApp.screenWidth - 56) / 4
                            let gap: CGFloat = 8

                            VStack(spacing: gap) {
                                // Row 1: 修图(2 格) + 裁剪 + 涂鸦
                                HStack(spacing: gap) {
                                    BentoTile(
                                        icon: "wand.and.stars",
                                        title: "修图",
                                        subtitle: "一键美化",
                                        colors: [Color(hex: "8b5cf6"), Color(hex: "a855f7")]
                                    ) {
                                        selectedFeatureMode = .filter
                                        showPhotoPicker = true
                                    }
                                    .frame(width: col * 2 + gap, height: col)

                                    BentoTile(
                                        icon: "crop",
                                        title: "裁剪",
                                        colors: [Color(hex: "3b82f6"), Color(hex: "06b6d4")]
                                    ) {
                                        selectedFeatureMode = .adjust
                                        showPhotoPicker = true
                                    }
                                    .frame(width: col, height: col)

                                    BentoTile(
                                        icon: "paintbrush.fill",
                                        title: "涂鸦",
                                        colors: [Color(hex: "f97316"), Color(hex: "ef4444")]
                                    ) {
                                        selectedFeatureMode = .doodle
                                        showPhotoPicker = true
                                    }
                                    .frame(width: col, height: col)
                                }

                                // Row 2: 相机 + 美颜 + 拼图
                                HStack(spacing: gap) {
                                    BentoTile(
                                        icon: "camera.fill",
                                        title: "相机",
                                        colors: [Color(hex: "0ea5e9"), Color(hex: "6366f1")]
                                    ) {
                                        Task { await handleCameraTap() }
                                    }
                                    .frame(width: col, height: col)

                                    BentoTile(
                                        icon: "sparkles",
                                        title: "美颜",
                                        colors: [Color(hex: "ec4899"), Color(hex: "f43f5e")]
                                    ) {
                                        showBeautyPicker = true
                                    }
                                    .frame(width: col, height: col)

                                    BentoTile(
                                        icon: "photo.on.rectangle.angled",
                                        title: "拼图",
                                        colors: [Color(hex: "10b981"), Color(hex: "14b8a6")]
                                    ) {
                                        showMultiPhotoPicker = true
                                    }
                                    .frame(width: col, height: col)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        
                        // 3. Edit History (Recent Projects)
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("最近编辑")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(DS.ColorToken.textPrimary(scheme))
                                Spacer()
                                Button("查看全部") {
                                    // See all action
                                }
                                .font(.caption)
                                .foregroundColor(DS.ColorToken.brandPrimary(scheme))
                            }
                            .padding(.horizontal)
                            
                            if viewModel.recentProjects.isEmpty {
                                HStack {
                                    Spacer()
                                    VStack(spacing: 8) {
                                        Image(systemName: "doc.text.image")
                                            .font(.largeTitle)
                                            .foregroundColor(.gray.opacity(0.5))
                                        Text("暂无历史记录")
                                            .foregroundColor(.gray)
                                    }
                                    .padding(.vertical, 20)
                                    Spacer()
                                }
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 16) {
                                        ForEach(viewModel.recentProjects) { project in
                                            ProjectCardView(project: project)
                                                .onTapGesture {
                                                    guard !isProcessingProject else { return }
                                                    isProcessingProject = true
                                                    
                                                    Task {
                                                        if let image = await viewModel.loadFullImage(for: project) {
                                                            await MainActor.run {
                                                                self.selectedProjectToEdit = project
                                                                self.loadedImageForEdit = image
                                                                self.isEditorActive = true
                                                                self.isProcessingProject = false
                                                            }
                                                        } else {
                                                            await MainActor.run {
                                                                self.isProcessingProject = false
                                                                self.showLoadError = true
                                                            }
                                                        }
                                                    }
                                                }
                                                .contextMenu {
                                                    Button {
                                                        self.projectToRename = project
                                                        self.newProjectTitle = project.title
                                                        self.showRenameAlert = true
                                                    } label: {
                                                        Label("重命名", systemImage: "pencil")
                                                    }
                                                    
                                                    Button(role: .destructive) {
                                                        withAnimation {
                                                            viewModel.deleteProject(project)
                                                        }
                                                    } label: {
                                                        Label("删除", systemImage: "trash")
                                                    }
                                                }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                        
                        // 5. Recommended Photos (New Photos)
                        VStack(alignment: .leading, spacing: 16) {
                            Text("为您推荐")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(DS.ColorToken.textPrimary(scheme))
                                .padding(.horizontal)
                            
                            if viewModel.recommendedPhotos.isEmpty {
                                if viewModel.permissionStatus == .denied {
                                    Text("需要相册权限以显示推荐图片")
                                        .foregroundColor(.gray)
                                        .padding(.horizontal)
                                } else {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                        Spacer()
                                    }
                                    .padding(.vertical, 20)
                                }
                            } else {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                    ForEach(viewModel.recommendedPhotos, id: \.localIdentifier) { asset in
                                        PhotoThumbnailView(asset: asset)
                                            .aspectRatio(1, contentMode: .fill)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                                            .onTapGesture {
                                                loadAssetAndEdit(asset)
                                            }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.bottom, 120) // Space for TabBar
                }
            }
            
            if isProcessingProject {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            Text("正在加载...")
                                .foregroundColor(.white)
                                .font(.headline)
                        }
                    )
                    .zIndex(100)
            }
        }
        .onAppear {
            viewModel.onAppear()
        }
        .photosPicker(isPresented: $showBeautyPicker, selection: $beautyPickerItem, matching: .images)
        .onChange(of: beautyPickerItem) { _, newItem in
            Task {
                if let item = newItem,
                   let data = try? await item.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    let fixed = fixOrientation(img: uiImage)
                    await MainActor.run {
                        beautyImage = fixed
                        isBeautyActive = true
                        beautyPickerItem = nil
                    }
                }
            }
        }
        .navigationDestination(isPresented: $isBeautyActive) {
            if let image = beautyImage {
                BeautyView(inputImage: image)
                    .navigationBarBackButtonHidden(true)
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedItem, matching: .images)
        .photosPicker(isPresented: $showMultiPhotoPicker, selection: $selectedItems, maxSelectionCount: 9, matching: .images)
        .onChange(of: selectedItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                var loadedImages: [UIImage] = []
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        loadedImages.append(fixOrientation(img: uiImage))
                    }
                }
                
                if !loadedImages.isEmpty {
                    await MainActor.run {
                        self.collageImages = loadedImages
                        self.isCollageActive = true
                        self.selectedItems = [] // Reset selection
                    }
                }
            }
        }
        .onChange(of: selectedItem) { _, newItem in
            Task {
                if let item = newItem,
                   let data = try? await item.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    
                    let fixedImage = fixOrientation(img: uiImage)
                    let project = PhotoProject(assetID: item.itemIdentifier)
                    
                    await MainActor.run {
                        self.selectedProjectToEdit = project
                        self.loadedImageForEdit = fixedImage
                        self.isEditorActive = true
                        self.selectedItem = nil
                    }
                }
            }
        }
        .navigationDestination(isPresented: $isEditorActive) {
            if let project = selectedProjectToEdit, let image = loadedImageForEdit {
                EditorView(project: project, image: image, initialMode: selectedFeatureMode)
                    .navigationBarBackButtonHidden(true)
            }
        }
        .navigationDestination(isPresented: $isCollageActive) {
            CollageView(images: collageImages)
                .navigationBarBackButtonHidden(true)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showNotifications) {
            NotificationView()
        }
        .alert("重命名作品", isPresented: $showRenameAlert) {
            TextField("输入新名称", text: $newProjectTitle)
            Button("取消", role: .cancel) { }
            Button("保存") {
                if let project = projectToRename {
                    viewModel.renameProject(project, to: newProjectTitle)
                }
            }
        }
        .alert("加载失败", isPresented: $showLoadError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("无法加载原始图片，可能原图已被删除或无权访问。")
        }
        .alert("需要相机权限", isPresented: $showCameraPermissionAlert) {
            Button("取消", role: .cancel) { }
            Button("去设置") { openSettings() }
        } message: {
            Text("请在系统设置中允许访问相机后再拍照。")
        }
        .fullScreenCover(isPresented: $isPicCameraActive) {
            PicCameraView()
        }
    }

    /// 编辑组右侧正方形小方块边长 — 基于屏幕宽度反推,保证两列正方形且与左侧大块齐高
    private func editTileSide(gap: CGFloat) -> CGFloat {
        let horizontalPadding: CGFloat = 32 // section .padding(.horizontal, 16) * 2
        let totalW = SwiftApp.screenWidth - horizontalPadding
        // 右侧 2x2 正方形宽度等于左侧大块的某个比例 — 这里直接固定右侧占总宽 0.56
        let rightW = (totalW - gap) * 0.56
        return (rightW - gap) / 2
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, accent: Color) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent)
                .frame(width: 3, height: 16)
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(DS.ColorToken.textPrimary(scheme))
            Spacer()
        }
    }

    private func handleCameraTap() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isPicCameraActive = true
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .video) {
                isPicCameraActive = true
            } else {
                showCameraPermissionAlert = true
            }
        default:
            showCameraPermissionAlert = true
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // Helper to fix image orientation (Copied from MainTabView to be self-contained)
    private func fixOrientation(img: UIImage) -> UIImage {
        if (img.imageOrientation == .up) {
            return img
        }

        UIGraphicsBeginImageContextWithOptions(img.size, false, img.scale)
        let rect = CGRect(x: 0, y: 0, width: img.size.width, height: img.size.height)
        img.draw(in: rect)

        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return normalizedImage ?? img
    }
    
    private func loadAssetAndEdit(_ asset: PHAsset) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        PHImageManager.default().requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFit, options: options) { image, _ in
            if let image = image {
                let fixedImage = fixOrientation(img: image)
                let project = PhotoProject(assetID: asset.localIdentifier)
                
                DispatchQueue.main.async {
                    self.selectedProjectToEdit = project
                    self.loadedImageForEdit = fixedImage
                    self.isEditorActive = true
                }
            }
        }
    }
}

// MARK: - Subviews

struct FeatureButton: View {
    let icon: String
    let title: String
    let color: Color
    var action: () -> Void = {}
    @Environment(\.colorScheme) var scheme
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.1))
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundColor(color)
                }
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(DS.ColorToken.textPrimary(scheme))
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct ProjectCardView: View {
    let project: PhotoProject
    @Environment(\.colorScheme) var scheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let data = project.thumbnailData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 140, height: 160)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 140, height: 160)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundColor(DS.ColorToken.textPrimary(scheme))
                
                Text(project.updatedAt, style: .date)
                    .font(.caption)
                    .foregroundColor(DS.ColorToken.textSecondary(scheme))
            }
            .padding(12)
        }
        .background(DS.ColorToken.surface(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .frame(width: 140)
    }
}

// MARK: - Bento Tile

struct BentoTile: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    let colors: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))

                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: icon)
                        .resizable()
                        .foregroundStyle(.white)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20)

                    Spacer(minLength: 6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: (colors.last ?? .black).opacity(0.28), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(BentoPressStyle())
    }
}

private struct BentoPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
