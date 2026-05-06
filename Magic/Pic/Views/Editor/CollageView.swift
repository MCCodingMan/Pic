import SwiftUI
import UIKit
import PhotosUI

// MARK: - Models

struct CollageImageState: Equatable {
    var scale: CGFloat = 1.0
    var rotation: Angle = .zero
    var offset: CGSize = .zero
    var cornerRadius: CGFloat = 0
    var shape: ImageShape = .rectangle
    var isMirrored: Bool = false
    
    // 3D Flip Rotation
    var rotation3D: Rotation3DState = .zero
    
    struct Rotation3DState: Equatable {
        var x: Double = 0
        var y: Double = 0
        var z: Double = 0
        
        static let zero = Rotation3DState()
    }
    
    enum ImageShape: String, CaseIterable, Identifiable {
        case rectangle = "方形"
        case circle = "圆形"
        var id: String { rawValue }
    }
}

struct CollageView: View {
    let images: [UIImage]
    @State private var selectedLayout: CollageLayout = .template
    @State private var selectedTemplate: CollageTemplate?
    @State private var globalRotationAngle: Double = 0
    @State private var isProcessing = false
    @State private var showSaveSuccess = false
    
    // Background Image State
    @State private var backgroundImage: UIImage?
    @State private var showBackgroundImage: Bool = true
    @State private var backgroundSelection: PhotosPickerItem?
    
    // Individual Image State
    @State private var imageStates: [Int: CollageImageState] = [:]
    @State private var selectedImageIndex: Int? = nil
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var scheme
    
    // Layout types
    enum CollageLayout: String, CaseIterable, Identifiable {
        case template = "模版"
        case vertical = "长图"
        case freestyle = "自由"
        
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .template: return "square.grid.2x2"
            case .vertical: return "rectangle.grid.1x2"
            case .freestyle: return "photo.stack"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Bar
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .foregroundColor(DS.ColorToken.textPrimary(scheme))
                        .padding()
                }
                Spacer()
                Text("拼图")
                    .font(.headline)
                    .foregroundColor(DS.ColorToken.textPrimary(scheme))
                Spacer()
                Button(action: saveCollage) {
                    if isProcessing {
                        ProgressView()
                    } else {
                        Text("保存")
                            .fontWeight(.bold)
                            .foregroundColor(DS.ColorToken.brandPrimary(scheme))
                    }
                }
                .disabled(isProcessing)
                .padding()
            }
            .background(DS.ColorToken.surface(scheme))
            
            // Canvas Area
            GeometryReader { geometry in
                ZStack {
                    Color(hex: "f1f5f9").ignoresSafeArea() // App Background
                        .onTapGesture {
                            withAnimation {
                                selectedImageIndex = nil
                            }
                        }
                    
                    // The Collage Content
                    collageContent
                        .frame(width: max(geometry.size.width - 40, 1), height: max(geometry.size.height - 40, 1))
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            }
            
            // Bottom Toolbar
            VStack(spacing: 12) {
                // Image Specific Controls (Visible when image selected)
                if let index = selectedImageIndex, let _ = imageStates[index] {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 16) {
                            // Shape Selector
                            HStack {
                                Picker("形状", selection: Binding(
                                    get: { imageStates[index]?.shape ?? .rectangle },
                                    set: { imageStates[index]?.shape = $0 }
                                )) {
                                    ForEach(CollageImageState.ImageShape.allCases) { shape in
                                        Text(shape.rawValue).tag(shape)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 120)
                                
                                Spacer()
                                
                                Toggle("镜像", isOn: Binding(
                                    get: { imageStates[index]?.isMirrored ?? false },
                                    set: { imageStates[index]?.isMirrored = $0 }
                                ))
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: DS.ColorToken.brandPrimary(scheme)))
                                
                                Text("镜像")
                                    .font(.caption)
                                    .foregroundColor(DS.ColorToken.textSecondary(scheme))
                            }
                            .padding(.horizontal)
                            
                            // Controls based on Shape
                            if imageStates[index]?.shape == .rectangle {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("圆角 \(Int(imageStates[index]?.cornerRadius ?? 0))")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                    PillSlider(value: Binding(
                                        get: { Double(imageStates[index]?.cornerRadius ?? 0) },
                                        set: { imageStates[index]?.cornerRadius = CGFloat($0) }
                                    ), range: 0...100, trackHeight: 26, thumbSize: 18)
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("半径 \(String(format: "%.1f", imageStates[index]?.scale ?? 1.0))")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                    PillSlider(value: Binding(
                                        get: { Double(imageStates[index]?.scale ?? 1.0) },
                                        set: { imageStates[index]?.scale = CGFloat($0) }
                                    ), range: 0.2...3.0, trackHeight: 26, thumbSize: 18)
                                }
                            }

                            // 2D Rotation
                            VStack(alignment: .leading, spacing: 2) {
                                Text("旋转 \(Int(imageStates[index]?.rotation.degrees ?? 0))°")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                PillSlider(value: Binding(
                                    get: { imageStates[index]?.rotation.degrees ?? 0 },
                                    set: { imageStates[index]?.rotation = .degrees($0) }
                                ), range: -180...180, trackHeight: 26, thumbSize: 18)
                            }

                            Divider()

                            // 3D Rotation Controls
                            Group {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("X轴翻转 \(Int(imageStates[index]?.rotation3D.x ?? 0))°")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                    PillSlider(value: Binding(
                                        get: { imageStates[index]?.rotation3D.x ?? 0 },
                                        set: { imageStates[index]?.rotation3D.x = $0 }
                                    ), range: -180...180, tintColor: .blue, trackHeight: 26, thumbSize: 18)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Y轴翻转 \(Int(imageStates[index]?.rotation3D.y ?? 0))°")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                    PillSlider(value: Binding(
                                        get: { imageStates[index]?.rotation3D.y ?? 0 },
                                        set: { imageStates[index]?.rotation3D.y = $0 }
                                    ), range: -180...180, tintColor: .green, trackHeight: 26, thumbSize: 18)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Z轴翻转 \(Int(imageStates[index]?.rotation3D.z ?? 0))°")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                    PillSlider(value: Binding(
                                        get: { imageStates[index]?.rotation3D.z ?? 0 },
                                        set: { imageStates[index]?.rotation3D.z = $0 }
                                    ), range: -180...180, tintColor: .orange, trackHeight: 26, thumbSize: 18)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    // Global/Background Controls
                    HStack {
                        Toggle("显示底图", isOn: $showBackgroundImage)
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: DS.ColorToken.brandPrimary(scheme)))
                        
                        Text("底图")
                            .font(.caption)
                            .foregroundColor(DS.ColorToken.textSecondary(scheme))
                        
                        Spacer()
                        
                        PhotosPicker(selection: $backgroundSelection, matching: .images) {
                            HStack {
                                Image(systemName: "photo")
                                Text("选择背景")
                            }
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(DS.ColorToken.surfaceAlt(scheme))
                            .cornerRadius(16)
                        }
                        .onChange(of: backgroundSelection) {_, newItem in
                            Task {
                                if let data = try? await newItem?.loadTransferable(type: Data.self),
                                   let uiImage = UIImage(data: data) {
                                    backgroundImage = uiImage
                                    showBackgroundImage = true
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                Divider()
                
                // Template Selector (Only if Template mode)
                if selectedLayout == .template {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            let templates = TemplateRepository.shared.getTemplates(for: images.count)
                            ForEach(templates) { template in
                                Button(action: {
                                    withAnimation {
                                        selectedTemplate = template
                                        resetImageStates()
                                    }
                                }) {
                                    VStack {
                                        Image(systemName: template.iconName)
                                            .font(.title2)
                                        Text(template.name)
                                            .font(.caption2)
                                    }
                                    .frame(width: 70, height: 70)
                                    .background(selectedTemplate?.id == template.id ? DS.ColorToken.brandPrimary(scheme).opacity(0.1) : DS.ColorToken.surfaceAlt(scheme))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedTemplate?.id == template.id ? DS.ColorToken.brandPrimary(scheme) : Color.clear, lineWidth: 2)
                                    )
                                }
                                .foregroundColor(DS.ColorToken.textPrimary(scheme))
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 80)
                }
                
                // Layout Mode Selector
                HStack(spacing: 30) {
                    ForEach(CollageLayout.allCases) { layout in
                        Button(action: {
                            withAnimation {
                                selectedLayout = layout
                                selectedImageIndex = nil
                            }
                        }) {
                            VStack(spacing: 8) {
                                Image(systemName: layout.icon)
                                    .font(.system(size: 24))
                                Text(layout.rawValue)
                                    .font(.caption)
                            }
                            .foregroundColor(selectedLayout == layout ? DS.ColorToken.brandPrimary(scheme) : .gray)
                        }
                    }
                }
            }
            .padding(.vertical, 10)
            .background(DS.ColorToken.surface(scheme))
        }
        .navigationBarHidden(true)
        .alert("保存成功", isPresented: $showSaveSuccess) {
            Button("确定") { dismiss() }
        }
        .onAppear {
            initializeStates()
            // Select first template by default
            if let first = TemplateRepository.shared.getTemplates(for: images.count).first {
                selectedTemplate = first
            }
        }
    }
    
    private func initializeStates() {
        for i in 0..<images.count {
            if imageStates[i] == nil {
                imageStates[i] = CollageImageState()
            }
        }
    }
    
    private func resetImageStates() {
        // Optional: Keep corner radius but reset transform? 
    }
    
    // Extracted content for reuse in rendering
    var collageContent: some View {
        ZStack {
            // Background
            if showBackgroundImage, let bg = backgroundImage {
                Image(uiImage: bg)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else {
                Color.white
            }
            
            Group {
                switch selectedLayout {
                case .template:
                    if let tmpl = selectedTemplate {
                        TemplateLayout(
                            template: tmpl,
                            images: images,
                            imageStates: $imageStates,
                            selectedImageIndex: $selectedImageIndex
                        )
                    } else {
                        GridLayout(images: images)
                    }
                case .vertical:
                    VerticalLayout(images: images)
                case .freestyle:
                    FreestyleLayout(images: images)
                }
            }
            .padding(10)
            .rotationEffect(.degrees(globalRotationAngle))
        }
    }
    
    @MainActor
    private func saveCollage() {
        isProcessing = true
        
        // Temporarily clear selection to remove selection borders during render
        let previousSelection = selectedImageIndex
        selectedImageIndex = nil
        
        // Render at high resolution
        let renderer = ImageRenderer(content: 
            collageContent
                .frame(width: 1080, height: 1440) // Standard poster size
        )
        renderer.scale = 2.0
        
        if let image = renderer.uiImage {
            saveToAlbum(image)
        } else {
            isProcessing = false
        }
        
        // Restore selection
        selectedImageIndex = previousSelection
    }
    
    private func saveToAlbum(_ image: UIImage) {
        Task {
            do {
                try await PhotoLibraryService.shared.saveImage(image)
                await MainActor.run {
                    isProcessing = false
                    showSaveSuccess = true
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                }
            }
        }
    }
}

// MARK: - Interactive Layouts

struct TemplateLayout: View {
    let template: CollageTemplate
    let images: [UIImage]
    @Binding var imageStates: [Int: CollageImageState]
    @Binding var selectedImageIndex: Int?
    
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            
            ZStack {
                ForEach(Array(template.items.enumerated()), id: \.element.id) { index, item in
                    if index < images.count {
                        DraggableImage(
                            image: images[index],
                            rect: item.rect,
                            rotation: item.rotation,
                            zIndex: item.zIndex,
                            containerSize: CGSize(width: w, height: h),
                            isSelected: selectedImageIndex == index,
                            state: Binding(
                                get: { imageStates[index] ?? CollageImageState() },
                                set: { imageStates[index] = $0 }
                            ),
                            onSelect: {
                                selectedImageIndex = index
                            }
                        )
                    }
                }
            }
        }
    }
}

struct DraggableImage: View {
    let image: UIImage
    let rect: CGRect
    let rotation: Double
    let zIndex: Int
    let containerSize: CGSize
    let isSelected: Bool
    @Binding var state: CollageImageState
    let onSelect: () -> Void
    
    // Temporary states for gestures
    @GestureState private var gestureZoom: CGFloat = 1.0
    @GestureState private var gestureRotation: Angle = .zero
    @GestureState private var gesturePan: CGSize = .zero
    
    var body: some View {
        let w = containerSize.width
        let h = containerSize.height
        let frameW = rect.width * w
        let frameH = rect.height * h
        
        let isCircle = state.shape == .circle
        let baseW = isCircle ? min(frameW, frameH) : frameW
        let baseH = isCircle ? min(frameW, frameH) : frameH
        
        // Use a container ZStack to group Image and Selection Border together
        // Apply 3D rotation to the whole group so border follows image
        ZStack {
            // 1. Image Content with Clipping
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: baseW, height: baseH)
                .clipped()
                .clipShape(
                    RoundedRectangle(cornerRadius: isCircle ? baseW/2 : state.cornerRadius)
                )
            
            // 2. Selection Border (On top, inside the 3D transform group)
            if isSelected {
                if isCircle {
                    Circle()
                        .stroke(Color.blue, lineWidth: 3)
                } else {
                    RoundedRectangle(cornerRadius: state.cornerRadius)
                        .stroke(Color.blue, lineWidth: 3)
                }
            }
        }
        .frame(width: baseW, height: baseH)
        // Apply Mirror (Horizontal Flip) - Before 3D rotation
        .scaleEffect(x: state.isMirrored ? -1 : 1, y: 1)
        // Apply 3D Flip/Rotation to the Container (Image + Border)
        .rotation3DEffect(.degrees(state.rotation3D.x), axis: (x: 1, y: 0, z: 0))
        .rotation3DEffect(.degrees(state.rotation3D.y), axis: (x: 0, y: 1, z: 0))
        .rotation3DEffect(.degrees(state.rotation3D.z), axis: (x: 0, y: 0, z: 1))
        // Apply 2D Transforms (Scale/Rotate)
        .scaleEffect(state.scale * gestureZoom)
        .rotationEffect(state.rotation + gestureRotation)
        
        // Gestures & Position
        .contentShape(Rectangle()) // Ensure hit test works on the whole frame
        .gesture(
            TapGesture()
                .onEnded {
                    onSelect()
                }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .updating($gestureZoom) { value, state, _ in
                    state = value
                }
                .onEnded { value in
                    state.scale *= value
                }
        )
        .simultaneousGesture(
            RotationGesture()
                .updating($gestureRotation) { value, state, _ in
                    state = value
                }
                .onEnded { value in
                    state.rotation += value
                }
        )
        .simultaneousGesture(
            DragGesture()
                .updating($gesturePan) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    state.offset.width += value.translation.width
                    state.offset.height += value.translation.height
                    onSelect()
                }
        )
        // Apply Drag Offset
        .offset(x: state.offset.width + gesturePan.width, y: state.offset.height + gesturePan.height)
        // Template Item Initial Rotation & Position
        .rotationEffect(.degrees(rotation))
        .position(
            x: rect.minX * w + frameW / 2,
            y: rect.minY * h + frameH / 2
        )
        .zIndex(Double(zIndex) + (isSelected ? 100 : 0))
    }
}

struct GridLayout: View {
    let images: [UIImage]
    var body: some View {
        GeometryReader { geometry in
            let count = images.count
            let columnsCount = count <= 4 ? 2 : 3
            let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: columnsCount)
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(images.prefix(9), id: \.self) { img in
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: (geometry.size.width / CGFloat(columnsCount)) - 5)
                        .clipped()
                }
            }
        }
    }
}

struct VerticalLayout: View {
    let images: [UIImage]
    var body: some View {
        VStack(spacing: 0) {
            ForEach(images, id: \.self) { img in
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct FreestyleLayout: View {
    let images: [UIImage]
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<images.count, id: \.self) { index in
                    Image(uiImage: images[index])
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width * 0.6)
                        .border(Color.white, width: 8)
                        .shadow(radius: 5)
                        .rotationEffect(.degrees(Double(index) * 15 - 10))
                        .offset(x: CGFloat((index % 2 == 0 ? -1 : 1) * 30), y: CGFloat(index * 40))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
