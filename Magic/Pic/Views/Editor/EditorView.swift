import SwiftUI
import UIKit
import PhotosUI

// MARK: - Editor Mode Enum
enum EditorMode: String, CaseIterable, Identifiable {
    case adjust = "调节"
    case hsl = "HSL"
    case curves = "曲线"
    case masks = "蒙版"
    case filter = "滤镜"
    case sticker = "贴纸"
    case text = "文字"
    case doodle = "涂鸦"

    var id: String { rawValue }
}

struct EditorView: View {
    // MARK: - State
    @State private var viewModel: EditorViewModel
    @State private var selectedAdjustment: AdjustmentType?
    @State private var currentMode: EditorMode = .adjust
    @State private var modeTransitionEdge: Edge = .leading
    @State private var isShowingOriginal = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var showHistory = false // Placeholder for History view
    @State private var showCropView = false
    
    // Text Editor State
    @State private var isShowingTextEditor = false
    @State private var textEditorContent = ""
    @State private var textEditorColor: Color = .black
    @State private var textEditorFont = "System"
    @State private var isEditingSticker = false
    
    // Doodle State
    @State private var selectedColor: Color = .red
    @State private var isEraser = false
    @State private var lineWidth: CGFloat = 5.0
    @State private var currentPoints: [CGPoint] = []
    @State private var brushLocation: CGPoint? // Track brush position for cursor
    
    // Sticker State
    @State private var selectedStickerID: UUID?
    @State private var selectedPhotoItem: PhotosPickerItem?
    
    // Global Gesture State
    @State private var currentScale: CGFloat = 1.0
    @State private var currentRotation: Angle = .zero
    @State private var dragOffset: CGSize = .zero
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var scheme
    
    // Animation Namespace
    @Namespace private var animation
    
    init(project: PhotoProject, image: UIImage, initialMode: EditorMode = .adjust) {
        let vm = EditorViewModel(project: project)
        vm.loadAsset(from: image)
        _viewModel = State(initialValue: vm)
        _currentMode = State(initialValue: initialMode)
    }
    
    // MARK: - Body
    var body: some View {
        ZStack {
            // 1. Background
            backgroundLayer
            
            // 2. Canvas Layer
            canvasLayer
            
            // 3. UI Overlay
            VStack(spacing: 0) {
                topBar
                    .zIndex(2)
                
                Spacer()
                
                bottomControls
                    .zIndex(1)
            }
            .edgesIgnoringSafeArea(.bottom)
        }
        .alert("Error", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
        .sheet(isPresented: $showHistory) {
            HistoryView(
                undoStack: viewModel.undoStack,
                currentState: viewModel.editState,
                redoStack: viewModel.redoStack,
                onJump: { index in
                    withAnimation {
                        viewModel.jumpToHistory(at: index)
                    }
                },
                onDismiss: {
                    showHistory = false
                }
            )
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showCropView) {
            if let uiImage = viewModel.originalUIImage {
                TailorView(image: uiImage) {
                    showCropView = false
                } croppedBlock: { image in
                    showCropView = false
                    viewModel.applyCroppedImage(image)
                } closeBlock: {
                    showCropView = false
                }
                .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $isShowingTextEditor) {
            TextEditorSheet(
                text: $textEditorContent,
                color: $textEditorColor,
                fontName: $textEditorFont,
                onCommit: {
                    if isEditingSticker, let id = selectedStickerID,
                       let index = viewModel.editState.stickers.firstIndex(where: { $0.id == id }) {
                        var sticker = viewModel.editState.stickers[index]
                        sticker.content = textEditorContent
                        sticker.textColor = CodableColor(textEditorColor)
                        sticker.fontName = textEditorFont
                        viewModel.updateSticker(sticker)
                    } else {
                        viewModel.addTextSticker(textEditorContent, color: CodableColor(textEditorColor), fontName: textEditorFont)
                    }
                    isShowingTextEditor = false
                    // Reset
                    textEditorContent = ""
                    isEditingSticker = false
                },
                onCancel: {
                    isShowingTextEditor = false
                    textEditorContent = ""
                    isEditingSticker = false
                }
            )
        }
    }
    
    // MARK: - Background
    private var backgroundLayer: some View {
        ZStack {
            DS.ColorToken.surfaceAlt(scheme)
                .ignoresSafeArea()
        }
    }
    
    // MARK: - Canvas
    private var canvasLayer: some View {
        GeometryReader { geometry in
            ZStack {
                if let preview = viewModel.previewImage {
                    ZoomableCanvas(
                        image: preview,
                        originalImage: viewModel.originalUIImage,
                        isShowingOriginal: isShowingOriginal
                    ) {
                        ZStack {
                            doodleLayer
                            stickerLayer
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                    .dsShadow(.level2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView()
                        .scaleEffect(1.2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 56)
            .padding(.bottom, 270)
        }
    }
    
    private var stickerLayer: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(viewModel.editState.stickers) { sticker in
                    let isSelected = selectedStickerID == sticker.id
                    StickerView(
                        sticker: sticker,
                        parentSize: geo.size,
                        isSelected: isSelected,
                        onSelect: {
                            selectedStickerID = sticker.id
                        }
                    )
                    // Apply transient transformations if selected
                    .scaleEffect(isSelected ? currentScale : 1.0)
                    .rotationEffect(isSelected ? currentRotation : .zero)
                    .offset(isSelected ? dragOffset : .zero)
                    .allowsHitTesting(currentMode == .sticker || currentMode == .text)
                }
                
                // Global Gesture Layer
                if (currentMode == .sticker || currentMode == .text) && selectedStickerID != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    dragOffset = value.translation
                                }
                                .onEnded { value in
                                    if let id = selectedStickerID,
                                       let index = viewModel.editState.stickers.firstIndex(where: { $0.id == id }) {
                                        var sticker = viewModel.editState.stickers[index]
                                        let newX = (sticker.position.x * geo.size.width + value.translation.width) / geo.size.width
                                        let newY = (sticker.position.y * geo.size.height + value.translation.height) / geo.size.height
                                        sticker.position = CGPoint(x: newX, y: newY)
                                        viewModel.updateSticker(sticker)
                                    }
                                    dragOffset = .zero
                                }
                        )
                        .simultaneousGesture(
                            MagnificationGesture()
                                .onChanged { scale in
                                    currentScale = scale
                                }
                                .onEnded { scale in
                                    if let id = selectedStickerID,
                                       let index = viewModel.editState.stickers.firstIndex(where: { $0.id == id }) {
                                        var sticker = viewModel.editState.stickers[index]
                                        sticker.scale *= scale
                                        viewModel.updateSticker(sticker)
                                    }
                                    currentScale = 1.0
                                }
                        )
                        .simultaneousGesture(
                            RotationGesture()
                                .onChanged { angle in
                                    currentRotation = angle
                                }
                                .onEnded { angle in
                                    if let id = selectedStickerID,
                                       let index = viewModel.editState.stickers.firstIndex(where: { $0.id == id }) {
                                        var sticker = viewModel.editState.stickers[index]
                                        sticker.rotation += angle.radians
                                        viewModel.updateSticker(sticker)
                                    }
                                    currentRotation = .zero
                                }
                        )
                }
            }
            .onTapGesture {
                selectedStickerID = nil
            }
            .allowsHitTesting(currentMode == .sticker || currentMode == .text)
        }
    }
    
    private var doodleLayer: some View {
        GeometryReader { geo in
            ZStack {
                // Existing Drawings
                Canvas { context, size in
                    for drawing in viewModel.editState.drawings {
                        var path = Path()
                        let points = drawing.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
                        if !points.isEmpty {
                            path.move(to: points[0])
                            for i in 1..<points.count {
                                path.addLine(to: points[i])
                            }
                        }
                        
                        let style = StrokeStyle(lineWidth: drawing.lineWidth, lineCap: .round, lineJoin: .round)
                        
                        if drawing.isEraser {
                            context.blendMode = .destinationOut
                            context.stroke(path, with: .color(.black), style: style)
                            context.blendMode = .normal
                        } else {
                            context.stroke(path, with: .color(drawing.color.uiColor), style: style)
                        }
                    }
                    
                    // Current Stroke
                    if !currentPoints.isEmpty {
                        var path = Path()
                        let points = currentPoints.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
                        if let first = points.first {
                            path.move(to: first)
                            for i in 1..<points.count {
                                path.addLine(to: points[i])
                            }
                        }
                        
                        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                        
                        if isEraser {
                            context.blendMode = .destinationOut
                            context.stroke(path, with: .color(.black), style: style)
                            context.blendMode = .normal
                        } else {
                            context.stroke(path, with: .color(selectedColor), style: style)
                        }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard currentMode == .doodle else { return }
                            let point = value.location
                            brushLocation = point
                            let normalized = CGPoint(x: point.x / geo.size.width, y: point.y / geo.size.height)
                            currentPoints.append(normalized)
                        }
                        .onEnded { _ in
                            brushLocation = nil
                            guard currentMode == .doodle else { return }
                            if !currentPoints.isEmpty {
                                let stroke = DrawingStroke(
                                    points: currentPoints,
                                    color: CodableColor(isEraser ? .white : selectedColor), // Eraser just paints white for now
                                    lineWidth: lineWidth,
                                    isEraser: isEraser
                                )
                                viewModel.addDrawing(stroke)
                                currentPoints = []
                            }
                        }
                )
                .allowsHitTesting(currentMode == .doodle) // Pass through if not drawing
                
                // Brush Cursor
                if currentMode == .doodle, let location = brushLocation {
                    Circle()
                        .stroke(Color.white, lineWidth: 1)
                        .background(Circle().fill(isEraser ? Color.white.opacity(0.5) : selectedColor.opacity(0.5)))
                        .frame(width: lineWidth, height: lineWidth)
                        .position(location)
                        .allowsHitTesting(false)
                        .shadow(color: .black.opacity(0.5), radius: 1)
                }
            }
        }
    }
    
    // MARK: - Top Bar
    private var topBar: some View {
        HStack(spacing: 10) {
            // Dismiss
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DS.ColorToken.textPrimary(scheme))
                    .frame(width: 36, height: 36)
                    .background(DS.ColorToken.surface(scheme))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(DS.ColorToken.outline(scheme), lineWidth: 0.5)
                    )
                    .dsShadow(.level2)
            }

            // Action Group — scrollable to fit any screen width
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    // Auto Enhance
                    topBarButton(icon: "wand.and.stars") {
                        viewModel.autoEnhance()
                    }

                    // History
                    topBarButton(icon: "clock.arrow.circlepath", action: { showHistory.toggle() })

                    // Compare Toggle
                    topBarButton(icon: isShowingOriginal ? "square.split.2x1.fill" : "square.split.2x1", isActive: isShowingOriginal) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isShowingOriginal.toggle()
                        }
                    }

                    // Crop
                    topBarButton(icon: "crop") {
                        showCropView = true
                    }

                    Divider()
                        .frame(height: 18)
                        .background(DS.ColorToken.outline(scheme))

                    // Undo
                    topBarButton(icon: "arrow.uturn.backward", isDisabled: !viewModel.canUndo) {
                        withAnimation { viewModel.undo() }
                    }

                    // Redo
                    topBarButton(icon: "arrow.uturn.forward", isDisabled: !viewModel.canRedo) {
                        withAnimation { viewModel.redo() }
                    }

                    Divider()
                        .frame(height: 18)
                        .background(DS.ColorToken.outline(scheme))

                    // Reset
                    topBarButton(icon: "arrow.counterclockwise") {
                        withAnimation { viewModel.reset() }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
            }
            .background(DS.ColorToken.surface(scheme))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(DS.ColorToken.outline(scheme), lineWidth: 0.5)
            )
            .dsShadow(.level2)
            .frame(height: 40)

            // Save
            Button(action: {
                Task {
                    do {
                        try await viewModel.saveImage()
                        dismiss()
                    } catch {
                        saveErrorMessage = error.localizedDescription
                        showSaveError = true
                    }
                }
            }) {
                if viewModel.isProcessing {
                    ProgressView().tint(.white)
                } else {
                    Text("保存")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .frame(width: 56, height: 36)
            .foregroundColor(DS.ColorToken.onBrand)
            .background(DS.ColorToken.brandPrimary(scheme))
            .clipShape(Capsule())
            .dsShadow(.level2)
            .disabled(viewModel.isProcessing)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
    
    private func topBarButton(icon: String, isActive: Bool = false, isDisabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isActive ? DS.ColorToken.brandPrimary(scheme) : DS.ColorToken.textPrimary(scheme).opacity(isDisabled ? 0.3 : 0.8))
                .frame(width: 30, height: 30)
                .background(isActive ? DS.ColorToken.brandPrimary(scheme).opacity(0.1) : Color.clear)
                .clipShape(Circle())
        }
        .disabled(isDisabled)
    }
    
    // MARK: - Bottom Controls
    private var bottomControls: some View {
        VStack(spacing: 0) {
            // Handle / Separator
            Capsule()
                .fill(DS.ColorToken.outline(scheme))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 6)
            
            // 1. Active Tool Controls (Sliders, Sub-menus)
            ZStack {
                if let selected = selectedAdjustment {
                    // Specific Adjustment Slider
                    adjustmentSlider(for: selected)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    // Mode Specific Controls
                    Group {
                        switch currentMode {
                        case .adjust:
                            adjustmentsList
                        case .hsl:
                            hslControls
                        case .curves:
                            curvesControls
                        case .masks:
                            masksControls
                        case .filter:
                            filterSelector
                        case .sticker:
                            stickerControls
                        case .text:
                            textControls
                        case .doodle:
                            doodleControls
                        }
                    }
                    .id(currentMode)
                    .transition(.asymmetric(
                        insertion: .move(edge: modeTransitionEdge).combined(with: .opacity),
                        removal: .scale(scale: 0.8).combined(with: .opacity)
                    ))
                }
            }
            .frame(height: 180) // Fixed height for control area
            
            Divider()
                .background(DS.ColorToken.outline(scheme))
                .padding(.vertical, 6)
            
            // 2. Mode Selector Dock
            modeDock
                .padding(.bottom, 34) // Home indicator safe area
        }
        .background(
            DS.ColorToken.surface(scheme)
                .clipShape(RoundedCorner(radius: 32, corners: [.topLeft, .topRight]))
                .shadow(color: DS.Elevation.level4.parameters(for: scheme).color, radius: 30, y: -5)
                .overlay(
                    RoundedCorner(radius: 32, corners: [.topLeft, .topRight])
                        .stroke(DS.ColorToken.outline(scheme).opacity(0.5), lineWidth: 1)
                )
                .edgesIgnoringSafeArea(.bottom)
        )
    }
    
    // MARK: - Mode Dock
    private var modeDock: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(EditorMode.allCases) { mode in
                    Button(action: {
                        let allModes = EditorMode.allCases
                        let oldIndex = allModes.firstIndex(of: currentMode) ?? 0
                        let newIndex = allModes.firstIndex(of: mode) ?? 0
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            modeTransitionEdge = newIndex > oldIndex ? .trailing : .leading
                            currentMode = mode
                            selectedAdjustment = nil // Reset drill-down
                        }
                    }) {
                        VStack(spacing: 6) {
                            Image(systemName: modeIcon(for: mode))
                                .font(.system(size: 22))
                                .symbolRenderingMode(.hierarchical)
                            
                            Text(mode.rawValue)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(currentMode == mode ? DS.ColorToken.textPrimary(scheme) : DS.ColorToken.textSecondary(scheme))
                        .frame(width: 60)
                        .scaleEffect(currentMode == mode ? 1.1 : 1.0)
                        .overlay(
                            VStack {
                                Spacer()
                                if currentMode == mode {
                                    Capsule()
                                        .fill(DS.ColorToken.brandPrimary(scheme))
                                        .frame(width: 4, height: 4)
                                        .offset(y: 8)
                                        .matchedGeometryEffect(id: "ActiveDot", in: animation)
                                }
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }
    
    // MARK: - Adjustments (List & Slider)
    
    private var adjustmentsList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(AdjustmentType.allCases) { type in
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedAdjustment = type
                        }
                    }) {
                        VStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(DS.ColorToken.surfaceAlt(scheme))
                                    .frame(width: 56, height: 56)
                                    .overlay(
                                        Circle()
                                            .stroke(isModified(type) ? DS.ColorToken.brandPrimary(scheme) : DS.ColorToken.outline(scheme), lineWidth: isModified(type) ? 2 : 1)
                                    )
                                
                                Image(systemName: iconName(for: type))
                                    .font(.system(size: 24))
                                    .foregroundColor(isModified(type) ? DS.ColorToken.brandPrimary(scheme) : DS.ColorToken.textPrimary(scheme))
                            }
                            
                            Text(type.rawValue)
                                .font(.system(size: 12))
                                .foregroundColor(isModified(type) ? DS.ColorToken.brandPrimary(scheme) : DS.ColorToken.textSecondary(scheme))
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 4)
        }
    }

    private func adjustmentSlider(for type: AdjustmentType) -> some View {
        VStack(spacing: 16) {
            // Header with Back Button
            HStack {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedAdjustment = nil
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("返回")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DS.ColorToken.textSecondary(scheme))
                }
                
                Spacer()
                
                
                // Reset this parameter
                Button(action: {
                    setValue(type.defaultValue, for: type)
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14))
                        .foregroundColor(DS.ColorToken.textSecondary(scheme))
                }
                .opacity(isModified(type) ? 1 : 0)
            }
            .padding(.horizontal, 24)
            .overlay {
                Text(type.rawValue)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DS.ColorToken.textPrimary(scheme))
            }
            
            // Value Display & Slider
            VStack(spacing: 8) {
                Text("\(Int(getValue(for: type) * 100))")
                    .font(.system(size: 28, weight: .light, design: .rounded))
                    .foregroundColor(DS.ColorToken.textPrimary(scheme))
                
                PillSlider(
                    value: Binding(
                        get: { getValue(for: type) },
                        set: { setValue($0, for: type) }
                    ),
                    range: type.range,
                    onEditingChanged: { editing in
                        if editing {
                            viewModel.commitEdit("调整\(type.rawValue)")
                        }
                    }
                )
            }
            .padding(.horizontal, 32)
        }
    }
    
    // MARK: - HSL Controls
    @State private var selectedHSLChannel: HSLChannel = .red
    
    private var hslControls: some View {
        VStack(spacing: 16) {
            // Channel Dots
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(HSLChannel.allCases) { channel in
                        Button(action: {
                            withAnimation { selectedHSLChannel = channel }
                        }) {
                            Circle()
                                .fill(Color(hex: channel.uiColor))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .stroke(DS.ColorToken.textPrimary(scheme).opacity(0.8), lineWidth: selectedHSLChannel == channel ? 2 : 0)
                                        .padding(-4)
                                )
                                .dsShadow(.level1)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 6)
            }

            // Sliders
            VStack(spacing: 12) {
                hslCompactSlider(label: "色相", icon: "arrow.left.and.right.circle", keyPath: \.hue)
                hslCompactSlider(label: "饱和度", icon: "drop.fill", keyPath: \.saturation)
                hslCompactSlider(label: "明度", icon: "sun.max.fill", keyPath: \.lightness)
            }
            .padding(.horizontal, 24)
        }
    }
    
    private func hslCompactSlider(label: String, icon: String, keyPath: WritableKeyPath<HSLShift, Double>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(DS.ColorToken.textSecondary(scheme))
                .frame(width: 20)
            
            PillSlider(
                value: Binding(
                    get: {
                        let hsl: [HSLChannel: HSLShift]
                        if let id = viewModel.selectedMaskID,
                           let mask = viewModel.editState.masks.first(where: { $0.id == id }) {
                            hsl = mask.adjustments.hsl
                        } else {
                            hsl = viewModel.editState.adjustments.hsl
                        }
                        let shift = hsl[selectedHSLChannel] ?? .identity
                        return shift[keyPath: keyPath]
                    },
                    set: { newValue in
                        let currentHSL: [HSLChannel: HSLShift]
                        if let id = viewModel.selectedMaskID,
                           let mask = viewModel.editState.masks.first(where: { $0.id == id }) {
                            currentHSL = mask.adjustments.hsl
                        } else {
                            currentHSL = viewModel.editState.adjustments.hsl
                        }
                        var shift = currentHSL[selectedHSLChannel] ?? .identity
                        shift[keyPath: keyPath] = newValue
                        viewModel.updateHSL(channel: selectedHSLChannel, shift: shift)
                    }
                ),
                range: -1.0...1.0,
                tintColor: Color(hex: selectedHSLChannel.uiColor),
                trackHeight: 28,
                thumbSize: 20
            )
        }
        .frame(height: 28)
    }
    
    // MARK: - Filter Controls
    @State private var selectedFilterCategory: String = "基础"
    
    private var filterSelector: some View {
        VStack(spacing: 12) {
            // Categories
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.filterCategories, id: \.self) { category in
                        Button(action: { selectedFilterCategory = category }) {
                            Text(category)
                                .font(.system(size: 13, weight: selectedFilterCategory == category ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedFilterCategory == category ? DS.ColorToken.surfaceAlt(scheme) : Color.clear)
                                .foregroundColor(selectedFilterCategory == category ? DS.ColorToken.textPrimary(scheme) : DS.ColorToken.textSecondary(scheme))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(selectedFilterCategory == category ? DS.ColorToken.outline(scheme) : Color.clear, lineWidth: 1)
                                )
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            
            // Filter Items
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    let filters = viewModel.availableFilters[selectedFilterCategory] ?? []
                    if !filters.isEmpty {
                        ForEach(filters) { filter in
                            Button(action: {
                                viewModel.setFilter(filter)
                            }) {
                                VStack(spacing: 8) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(DS.ColorToken.surfaceAlt(scheme))
                                            .frame(width: 64, height: 64)
                                        
                                        Text(String(filter.name.prefix(1)))
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .foregroundColor(DS.ColorToken.textSecondary(scheme))
                                        
                                        if viewModel.editState.filter == filter {
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(DS.ColorToken.brandPrimary(scheme), lineWidth: 2)
                                                .frame(width: 64, height: 64)
                                        }
                                    }
                                    
                                    Text(filter.name)
                                        .font(.caption2)
                                        .foregroundColor(viewModel.editState.filter == filter ? DS.ColorToken.brandPrimary(scheme) : DS.ColorToken.textSecondary(scheme))
                                        .lineLimit(1)
                                        .frame(width: 64)
                                }
                            }
                        }
                    } else {
                        Text("无可用滤镜")
                            .font(.caption)
                            .foregroundColor(DS.ColorToken.textSecondary(scheme))
                            .frame(width: 200)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }
    

    
    // MARK: - Sticker & Doodle Controls
    private var stickerControls: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                if let selectedID = selectedStickerID, let index = viewModel.editState.stickers.firstIndex(where: { $0.id == selectedID }) {
                    // Selected Sticker Controls
                    let sticker = viewModel.editState.stickers[index]
                    
                    HStack {
                        Button(action: { selectedStickerID = nil }) {
                            Image(systemName: "chevron.left")
                            Text("返回")
                        }
                        Spacer()
                        Button(action: {
                            viewModel.removeSticker(selectedID)
                            selectedStickerID = nil
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.horizontal, 24)
                    .foregroundColor(DS.ColorToken.textPrimary(scheme))
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 20) {
                            // 3D Actions
                            Button(action: {
                                var newSticker = sticker
                                newSticker.rotationY += .pi
                                viewModel.updateSticker(newSticker)
                            }) {
                                VStack {
                                    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                                    Text("水平翻转")
                                        .font(.caption)
                                }
                            }
                            
                            Button(action: {
                                var newSticker = sticker
                                newSticker.rotationX += .pi
                                viewModel.updateSticker(newSticker)
                            }) {
                                VStack {
                                    Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down")
                                    Text("垂直翻转")
                                        .font(.caption)
                                }
                            }
                            
                            Button(action: {
                                var newSticker = sticker
                                newSticker.rotationX = 0
                                newSticker.rotationY = 0
                                newSticker.rotation = 0
                                viewModel.updateSticker(newSticker)
                            }) {
                                VStack {
                                    Image(systemName: "arrow.counterclockwise")
                                    Text("复位")
                                        .font(.caption)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    
                    // Fine-tune Sliders
                    VStack(spacing: 10) {
                        HStack {
                            Text("X轴")
                                .font(.caption)
                                .frame(width: 30)
                            PillSlider(value: Binding(
                                get: { sticker.rotationX },
                                set: { val in
                                    var newSticker = sticker
                                    newSticker.rotationX = val
                                    viewModel.updateSticker(newSticker)
                                }
                            ), range: -Double.pi...Double.pi, trackHeight: 26, thumbSize: 18)
                        }

                        HStack {
                            Text("Y轴")
                                .font(.caption)
                                .frame(width: 30)
                            PillSlider(value: Binding(
                                get: { sticker.rotationY },
                                set: { val in
                                    var newSticker = sticker
                                    newSticker.rotationY = val
                                    viewModel.updateSticker(newSticker)
                                }
                            ), range: -Double.pi...Double.pi, trackHeight: 26, thumbSize: 18)
                        }

                        HStack {
                            Text("Z轴")
                                .font(.caption)
                                .frame(width: 30)
                            PillSlider(value: Binding(
                                get: { sticker.rotation },
                                set: { val in
                                    var newSticker = sticker
                                    newSticker.rotation = val
                                    viewModel.updateSticker(newSticker)
                                }
                            ), range: -Double.pi...Double.pi, trackHeight: 26, thumbSize: 18)
                        }
                    }
                    .padding(.horizontal, 24)
                } else {
                    // Add Sticker List
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 50))], spacing: 16) {
                            // Photo Picker
                            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                VStack {
                                    Image(systemName: "photo")
                                        .font(.system(size: 24))
                                    Text("相册")
                                        .font(.caption)
                                }
                                .frame(width: 50, height: 50)
                                .background(DS.ColorToken.surfaceAlt(scheme))
                                .clipShape(Circle())
                                .foregroundColor(DS.ColorToken.textPrimary(scheme))
                            }
                            .onChange(of: selectedPhotoItem) { _, newItem in
                                if let newItem {
                                    Task {
                                        if let data = try? await newItem.loadTransferable(type: Data.self),
                                           let image = UIImage(data: data) {
                                            await MainActor.run {
                                                viewModel.addImageSticker(image)
                                                selectedPhotoItem = nil
                                            }
                                        }
                                    }
                                }
                            }
                            
                            ForEach(viewModel.stickerEmojis, id: \.self) { emoji in
                                Button(action: {
                                    viewModel.addSticker(emoji)
                                }) {
                                    Text(emoji)
                                        .font(.system(size: 32))
                                        .frame(width: 50, height: 50)
                                        .background(DS.ColorToken.surfaceAlt(scheme))
                                        .clipShape(Circle())
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 200) // Increase max height or allow flexible height
        .foregroundColor(DS.ColorToken.textPrimary(scheme))
    }
    
    // MARK: - Text Controls
    private var textControls: some View {
        VStack {
            if let selectedID = selectedStickerID,
               let index = viewModel.editState.stickers.firstIndex(where: { $0.id == selectedID }),
               viewModel.editState.stickers[index].imageData == nil { // Ensure it's text
               
                let sticker = viewModel.editState.stickers[index]
                
                // Edit Tools
                HStack(spacing: 30) {
                    // Edit Text
                    Button(action: {
                        textEditorContent = sticker.content
                        textEditorColor = sticker.textColor.uiColor
                        textEditorFont = sticker.fontName
                        isEditingSticker = true
                        isShowingTextEditor = true
                    }) {
                        VStack {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 28))
                            Text("编辑")
                                .font(.caption)
                        }
                    }
                    
                    // Delete
                    Button(action: {
                        viewModel.removeSticker(sticker.id)
                        selectedStickerID = nil
                    }) {
                        VStack {
                            Image(systemName: "trash.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.red)
                            Text("删除")
                                .font(.caption)
                        }
                    }
                }
                .padding(.horizontal, 24)

            } else {
                // Add Text Button
                Button(action: {
                    textEditorContent = ""
                    textEditorColor = .black
                    textEditorFont = "System"
                    isEditingSticker = false
                    isShowingTextEditor = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("添加文字")
                    }
                    .font(.headline)
                    .padding()
                    .background(DS.ColorToken.surfaceAlt(scheme))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical)
        .foregroundColor(DS.ColorToken.textPrimary(scheme))
    }
    
    private var doodleControls: some View {
        VStack(spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    Button(action: { isEraser = true }) {
                        Image(systemName: "eraser.fill")
                            .font(.system(size: 20))
                            .foregroundColor(isEraser ? DS.ColorToken.brandPrimary(scheme) : DS.ColorToken.textSecondary(scheme))
                            .frame(width: 40, height: 40)
                            .background(isEraser ? DS.ColorToken.brandPrimary(scheme).opacity(0.1) : DS.ColorToken.surfaceAlt(scheme))
                            .clipShape(Circle())
                            .overlay(
                                Circle().stroke(isEraser ? DS.ColorToken.brandPrimary(scheme) : Color.clear, lineWidth: 2)
                            )
                    }
                    
                    ForEach([Color.red, .orange, .yellow, .green, .blue, .purple, .pink, .white, .black], id: \.self) { color in
                        Button(action: {
                            selectedColor = color
                            isEraser = false
                        }) {
                            Circle()
                                .fill(color)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 2)
                                        .shadow(radius: 1)
                                )
                                .scaleEffect((!isEraser && selectedColor == color) ? 1.2 : 1.0)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            
            HStack(spacing: 12) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                PillSlider(value: Binding(
                    get: { Double(lineWidth) },
                    set: { lineWidth = CGFloat($0) }
                ), range: 2...20, trackHeight: 28, thumbSize: 20)
                Image(systemName: "circle.fill")
                    .font(.system(size: 14))
            }
            .padding(.horizontal, 32)
            .foregroundColor(DS.ColorToken.textSecondary(scheme))
        }
    }
    
    // MARK: - Curves Controls
    private var curvesControls: some View {
        CurvesToolView(
            curve: Binding(
                get: { viewModel.editState.adjustments.curve },
                set: {
                    viewModel.editState.adjustments.curve = $0
                    viewModel.scheduleUpdate()
                }
            ),
            isProcessing: $viewModel.isProcessing
        )
        .drawingGroup()
    }
    
    // MARK: - Masks Controls
    private var masksControls: some View {
        ZStack {
            if viewModel.isEditingMask {
                // Active Mask Edit Mode (draft or existing)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                viewModel.finishMaskEditing()
                            }
                        }) {
                            Image(systemName: "chevron.left")
                        }
                        Text("编辑蒙版")
                            .font(.headline)
                        Spacer()
                        if let id = viewModel.selectedMaskID {
                            // 已有蒙版才显示删除按钮
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    viewModel.removeMask(id: id)
                                }
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(DS.ColorToken.danger(scheme))
                            }
                        } else if viewModel.draftMask != nil {
                            // 草稿蒙版显示取消按钮
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    viewModel.draftMask = nil
                                }
                            }) {
                                Image(systemName: "xmark")
                                    .foregroundColor(DS.ColorToken.danger(scheme))
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .foregroundColor(DS.ColorToken.textPrimary(scheme))

                    // Reuse adjustment slider logic or simplified version
                    adjustmentsList
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))

            } else {
                VStack(alignment: .leading, spacing: 12) {
                    // Mask List
                    if viewModel.editState.masks.isEmpty {
                        HStack {
                            Spacer()
                            Text("添加蒙版以开始局部调整")
                                .font(.caption)
                                .foregroundColor(DS.ColorToken.textSecondary(scheme))
                            Spacer()
                        }
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(viewModel.editState.masks) { mask in
                                    Button(action: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            viewModel.selectedMaskID = mask.id
                                        }
                                    }) {
                                        VStack(spacing: 6) {
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(DS.ColorToken.surfaceAlt(scheme))
                                                .frame(width: 72, height: 52)
                                                .overlay(
                                                    Image(systemName: mask.type == .linear ? "square.split.diagonal.2x2" : "circle.circle")
                                                        .font(.system(size: 22))
                                                        .foregroundColor(DS.ColorToken.textPrimary(scheme))
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(DS.ColorToken.outline(scheme), lineWidth: 1)
                                                )
                                            Text(mask.type == .linear ? "线性" : "径向")
                                                .font(.caption2)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                    }

                    // Add Buttons
                    HStack(spacing: 16) {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                viewModel.addMask(type: .linear)
                            }
                        }) {
                            Label("线性", systemImage: "square.split.diagonal.2x2")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(DS.ColorToken.surfaceAlt(scheme))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(DS.ColorToken.outline(scheme), lineWidth: 1)
                                )
                        }
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                viewModel.addMask(type: .radial)
                            }
                        }) {
                            Label("径向", systemImage: "circle.circle")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(DS.ColorToken.surfaceAlt(scheme))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(DS.ColorToken.outline(scheme), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .foregroundColor(DS.ColorToken.textPrimary(scheme))
    }

    // MARK: - Helpers
    private func modeIcon(for mode: EditorMode) -> String {
        switch mode {
        case .adjust: return "slider.horizontal.3"
        case .hsl: return "paintpalette"
        case .curves: return "scribble.variable"
        case .masks: return "circle.dashed.inset.filled"
        case .filter: return "camera.filters"
        case .sticker: return "face.smiling"
        case .text: return "textformat"
        case .doodle: return "pencil.tip.crop.circle"
        }
    }
    
    private func iconName(for type: AdjustmentType) -> String {
        switch type {
        case .exposure: return "sun.max"
        case .contrast: return "circle.lefthalf.filled"
        case .brightness: return "sun.min"
        case .saturation: return "drop"
        case .highlights: return "rays"
        case .shadows: return "shadow"
        case .sharpen: return "triangle"
        case .clarity: return "camera.macro"
        case .vignette: return "circle.dashed"
        case .grain: return "aqi.medium"
        case .warmth: return "thermometer.sun"
        case .tint: return "drop.triangle"
        }
    }
    
    private func isModified(_ type: AdjustmentType) -> Bool {
        return abs(getValue(for: type) - type.defaultValue) > 0.001
    }
    
    private func getValue(for type: AdjustmentType) -> Double {
        // 优先从草稿蒙版读取
        if let draft = viewModel.draftMask {
            return type.getValue(from: draft.adjustments)
        }
        // 再从已选中蒙版读取
        if let id = viewModel.selectedMaskID,
           let mask = viewModel.editState.masks.first(where: { $0.id == id }) {
            return type.getValue(from: mask.adjustments)
        }

        switch type {
        case .exposure: return viewModel.editState.adjustments.exposure
        case .contrast: return viewModel.editState.adjustments.contrast
        case .brightness: return viewModel.editState.adjustments.brightness
        case .saturation: return viewModel.editState.adjustments.saturation
        case .highlights: return viewModel.editState.adjustments.highlights
        case .shadows: return viewModel.editState.adjustments.shadows
        case .sharpen: return viewModel.editState.adjustments.sharpen
        case .clarity: return viewModel.editState.adjustments.clarity
        case .vignette: return viewModel.editState.adjustments.vignette
        case .grain: return viewModel.editState.adjustments.grain
        case .warmth: return viewModel.editState.adjustments.warmth
        case .tint: return viewModel.editState.adjustments.tint
        }
    }
    
    private func setValue(_ value: Double, for type: AdjustmentType) {
        switch type {
        case .exposure: viewModel.updateAdjustment(\.exposure, value: value)
        case .contrast: viewModel.updateAdjustment(\.contrast, value: value)
        case .brightness: viewModel.updateAdjustment(\.brightness, value: value)
        case .saturation: viewModel.updateAdjustment(\.saturation, value: value)
        case .highlights: viewModel.updateAdjustment(\.highlights, value: value)
        case .shadows: viewModel.updateAdjustment(\.shadows, value: value)
        case .sharpen: viewModel.updateAdjustment(\.sharpen, value: value)
        case .clarity: viewModel.updateAdjustment(\.clarity, value: value)
        case .vignette: viewModel.updateAdjustment(\.vignette, value: value)
        case .grain: viewModel.updateAdjustment(\.grain, value: value)
        case .warmth: viewModel.updateAdjustment(\.warmth, value: value)
        case .tint: viewModel.updateAdjustment(\.tint, value: value)
        }
    }
}

// MARK: - Components

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

struct VisualEffectBlur: UIViewRepresentable {
    var blurStyle: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: blurStyle)
    }
}
