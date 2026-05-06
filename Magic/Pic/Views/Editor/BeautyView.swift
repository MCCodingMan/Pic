import SwiftUI
import GPUImage
import Metal
import Vision
import CoreGraphics

/// 美颜工具项（与 EditorMode 同风格）
private enum BeautyTool: String, CaseIterable, Identifiable {
    case smoothing = "磨皮"
    case whitening = "美白"
    case brighten  = "亮肤"
    case slimming  = "瘦脸"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .smoothing: return "circle.dotted"
        case .whitening: return "sun.max"
        case .brighten:  return "sparkles"
        case .slimming:  return "face.smiling"
        }
    }
}

/// 美颜独立页面，从首页入口进入
struct BeautyView: View {
    let inputImage: UIImage
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    // 内置美颜参数
    @State private var skinSmoothing: Double = 0.0
    @State private var skinWhitening: Double = 0.0
    @State private var skinWhiteningYUV: Double = 0.0
    @State private var faceSlimming: Double = 0.0

    @State private var isProcessing = false
    // AsyncStream 驱动的预览更新（与 EditorViewModel 同模式）
    @State private var updateContinuation: AsyncStream<BeautyParams>.Continuation?
    @State private var updateTask: Task<Void, Never>?
    @State private var isSaving = false
    @State private var showSaveSuccess = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var faceContext: FaceContext = .empty
    private var faceDetected: Bool { !faceContext.isEmpty }

    // —— 内置美颜预览优化：降采样 + 长生命周期管线 + 缓存 mask —— //
    /// 降采样后的预览底图（短边 ≤ 1080），所有滑杆预览都基于此图运算
    @State private var previewBaseImage: UIImage?
    /// 已对当前 slimming 值缓存的瘦脸预览图（与 cachedSlimValue 配套）
    @State private var cachedSlimmedPreview: UIImage?
    /// cachedSlimmedPreview 对应的 slimming 值，用于失效判断
    @State private var cachedSlimValue: Double = -1
    /// 长生命周期的内置美颜管线（懒加载，仅在 slimming 变化或首次时重建）
    @State private var builtinPipeline: BeautyPreviewPipeline?
    /// 缓存的人物分割 mask 纹理（与 previewBaseImage 同尺寸，仅生成一次）
    /// 语义：白=人物/黑=背景，所有美颜 shader 都乘以它 → 背景完全不受影响
    @State private var previewMaskTexture: MTLTexture?
    /// 是否检测到人物（用于 UI 提示）
    @State private var personDetected: Bool = true

    /// 当前选中的美颜工具（nil = 显示工具坞）
    @State private var selectedTool: BeautyTool?

    var body: some View {
        ZStack {
            // 1. 背景
            DS.ColorToken.surfaceAlt(scheme)
                .ignoresSafeArea()

            // 2. 画布层
            canvasLayer

            // 3. UI Overlay
            VStack(spacing: 0) {
                topBar
                    .zIndex(2)

                // 状态提示（人物/人脸未检测到）
                if !personDetected || !faceDetected {
                    statusBanner
                        .padding(.top, 8)
                        .transition(.opacity)
                }

                Spacer()

                bottomControls
                    .zIndex(1)
            }
            .edgesIgnoringSafeArea(.bottom)
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            preparePreviewBaseImage()
            detectFaces()
            setupUpdateStream()
        }
        .onDisappear {
            updateTask?.cancel()
            updateContinuation?.finish()
        }
        .alert("保存成功", isPresented: $showSaveSuccess) {
            Button("确定") { dismiss() }
        }
        .alert("保存失败", isPresented: $showSaveError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
    }

    // MARK: - 画布层

    private var canvasLayer: some View {
        GeometryReader { _ in
            ZStack {
                MetalTexturePreview(
                    pipeline: builtinPipeline,
                    fallbackImage: previewBaseImage ?? inputImage
                )
                .id(ObjectIdentifier(builtinPipeline ?? BeautyPreviewPipeline()))
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            .dsShadow(.level2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 12)
            .padding(.top, 56)
            .padding(.bottom, 240)
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack(spacing: 10) {
            // 关闭
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

            // 中间标题胶囊
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.ColorToken.brandPrimary(scheme))
                Text("美颜")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.ColorToken.textPrimary(scheme))
                if hasAnyEffect {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            skinSmoothing = 0
                            skinWhitening = 0
                            skinWhiteningYUV = 0
                            faceSlimming = 0
                        }
                        schedulePreview()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12))
                            .foregroundColor(DS.ColorToken.textSecondary(scheme))
                            .padding(.leading, 4)
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background(DS.ColorToken.surface(scheme))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(DS.ColorToken.outline(scheme), lineWidth: 0.5)
            )
            .dsShadow(.level2)

            // 保存
            Button(action: { saveImage() }) {
                if isSaving {
                    ProgressView().tint(DS.ColorToken.onBrand)
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
            .disabled(isSaving || !hasAnyEffect)
            .opacity(hasAnyEffect ? 1 : 0.5)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    /// 状态提示条（未检测到人物/人脸）
    private var statusBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
            Text(!personDetected
                 ? "未检测到人物，效果将应用于全图"
                 : "未检测到人脸（瘦脸不可用）")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(DS.ColorToken.surface(scheme))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.orange.opacity(0.4), lineWidth: 0.5))
        .dsShadow(.level1)
    }

    /// 是否有任何效果参数 > 0
    private var hasAnyEffect: Bool {
        skinSmoothing > 0.001 || skinWhitening > 0.001 || skinWhiteningYUV > 0.001 || faceSlimming > 0.001
    }

    // MARK: - 底部控制

    private var bottomControls: some View {
        VStack(spacing: 0) {
            // 顶部拖动条
            Capsule()
                .fill(DS.ColorToken.outline(scheme))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 6)

            ZStack {
                if let tool = selectedTool {
                    toolSlider(for: tool)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    toolDock
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .frame(minHeight: 140)

            Color.clear.frame(height: 20)
        }
        .background(
            DS.ColorToken.surface(scheme)
                .clipShape(RoundedCorner(radius: DS.Radius.lg, corners: [.topLeft, .topRight]))
        )
        .dsShadow(.level2)
    }

    /// 工具坞（4 个圆形图标）
    private var toolDock: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                ForEach(BeautyTool.allCases) { tool in
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedTool = tool
                        }
                    }) {
                        VStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(DS.ColorToken.surfaceAlt(scheme))
                                    .frame(width: 56, height: 56)
                                    .overlay(
                                        Circle()
                                            .stroke(isModified(tool)
                                                    ? DS.ColorToken.brandPrimary(scheme)
                                                    : DS.ColorToken.outline(scheme),
                                                    lineWidth: isModified(tool) ? 2 : 1)
                                    )

                                Image(systemName: tool.icon)
                                    .font(.system(size: 22))
                                    .foregroundColor(isModified(tool)
                                                     ? DS.ColorToken.brandPrimary(scheme)
                                                     : DS.ColorToken.textPrimary(scheme))
                            }

                            Text(tool.rawValue)
                                .font(.system(size: 12))
                                .foregroundColor(isModified(tool)
                                                 ? DS.ColorToken.brandPrimary(scheme)
                                                 : DS.ColorToken.textSecondary(scheme))
                        }
                    }
                    .disabled(tool == .slimming && !faceDetected)
                    .opacity((tool == .slimming && !faceDetected) ? 0.4 : 1)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
    }

    /// 单工具滑杆面板
    private func toolSlider(for tool: BeautyTool) -> some View {
        VStack(spacing: 16) {
            // Header: 返回 + 标题 + 重置
            HStack {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTool = nil
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

                Button(action: { setValue(0, for: tool) }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14))
                        .foregroundColor(DS.ColorToken.textSecondary(scheme))
                }
                .opacity(isModified(tool) ? 1 : 0)
            }
            .padding(.horizontal, 24)
            .overlay {
                Text(tool.rawValue)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DS.ColorToken.textPrimary(scheme))
            }

            // 数值 + 滑杆
            VStack(spacing: 8) {
                Text("\(Int(getValue(for: tool) * 100))")
                    .font(.system(size: 28, weight: .light, design: .rounded))
                    .foregroundColor(DS.ColorToken.textPrimary(scheme))

                PillSlider(
                    value: Binding(
                        get: { getValue(for: tool) },
                        set: { setValue($0, for: tool) }
                    ),
                    range: 0.0...1.0
                )
            }
            .padding(.horizontal, 32)
        }
        .padding(.bottom, 8)
    }

    // MARK: - 工具数值桥接

    private func getValue(for tool: BeautyTool) -> Double {
        switch tool {
        case .smoothing: return skinSmoothing
        case .whitening: return skinWhitening
        case .brighten:  return skinWhiteningYUV
        case .slimming:  return faceSlimming
        }
    }

    private func setValue(_ newValue: Double, for tool: BeautyTool) {
        switch tool {
        case .smoothing: skinSmoothing = newValue
        case .whitening: skinWhitening = newValue
        case .brighten:  skinWhiteningYUV = newValue
        case .slimming:  faceSlimming = newValue
        }
        schedulePreview()
    }

    private func isModified(_ tool: BeautyTool) -> Bool {
        getValue(for: tool) > 0.001
    }

    /// 构建 AsyncStream 预览管线（与 EditorViewModel 同模式）
    private func setupUpdateStream() {
        var continuation: AsyncStream<BeautyParams>.Continuation!
        let stream = AsyncStream<BeautyParams>(bufferingPolicy: .bufferingNewest(1)) { cont in
            continuation = cont
        }
        self.updateContinuation = continuation

        let image = inputImage
        updateTask = Task.detached(priority: .userInitiated) {
            for await params in stream {
                let hasSmoothing = params.smoothing > 0.001
                let hasWhitening = params.whitening > 0.001
                let hasWhiteningYUV = params.whiteningYUV > 0.001
                let hasSlimming = params.slimming > 0.001
                guard hasSmoothing || hasWhitening || hasWhiteningYUV || hasSlimming else {
                    await MainActor.run { isProcessing = false }
                    continue
                }

                    // 等待预览底图就绪（首帧）
                    var base = await previewBaseImage
                    if base == nil {
                        let original = image
                        let down = ImageDownsampler.downsample(original, maxDimension: 1080)
                        await MainActor.run {
                            if previewBaseImage == nil { previewBaseImage = down }
                            tryGeneratePreviewMaskTexture()
                        }
                        base = down
                    }
                    guard let baseImage = base else { continue }

                    let ctx = await faceContext
                    let landmarks = ctx.observations
                    let detected = !ctx.isEmpty
                    let effectiveSlim = detected ? params.slimming : 0

                    // 1) 计算"瘦脸应用后"的源图（仅当 slim 值变化时重算）
                    let cachedValue = await cachedSlimValue
                    var sourceImage: UIImage = baseImage
                    if effectiveSlim > 0.001 {
                        if abs(cachedValue - effectiveSlim) < 0.001,
                           let cached = await cachedSlimmedPreview {
                            sourceImage = cached
                        } else {
                            let slimmed = applyFaceSlimming(to: baseImage,
                                                            strength: Float(effectiveSlim),
                                                            landmarks: landmarks)
                            await MainActor.run {
                                cachedSlimmedPreview = slimmed
                                cachedSlimValue = effectiveSlim
                            }
                            sourceImage = slimmed
                        }
                    } else if cachedValue >= 0 {
                        await MainActor.run {
                            cachedSlimmedPreview = nil
                            cachedSlimValue = -1
                        }
                    }

                    // 2) 取/建长生命周期管线，仅在 source 身份变化时重建
                    let mask = await previewMaskTexture
                    let pipeline = await MainActor.run { () -> BeautyPreviewPipeline in
                        if let p = builtinPipeline {
                            p.maskTexture = mask
                            return p
                        }
                        let p = BeautyPreviewPipeline()
                        p.maskTexture = mask
                        builtinPipeline = p
                        return p
                    }
                    pipeline.ensureSource(uiImage: sourceImage)

                    // 4) tick：只更新 uniforms + 触发一次 GPU 处理；R7 输出走 MTLTexture，
                    //    无 GPU→CPU 回读，由 MTKView 直显
                    let sigma = Float(6.0 + params.smoothing * 14.0)
                    pipeline.process(
                        sigma: sigma,
                        smoothIntensity: Float(params.smoothing),
                        whitenStrength: Float(params.whitening),
                        whitenYUVStrength: Float(params.whiteningYUV)
                    )
                await MainActor.run { isProcessing = false }
            }
        }
    }

    /// yield 当前参数到 stream（自动丢弃中间帧，只保留最新）
    private func schedulePreview() {
        isProcessing = true
        updateContinuation?.yield(BeautyParams(
            smoothing: skinSmoothing, whitening: skinWhitening, whiteningYUV: skinWhiteningYUV, slimming: faceSlimming
        ))
    }

    // MARK: - 人脸检测（含关键点）

    private func detectFaces() {
        let image = inputImage
        Task {
            let ctx = await FaceDetectionService.detectInPhoto(image)
            await MainActor.run {
                faceContext = ctx
                tryGeneratePreviewMaskTexture()
            }
        }
    }

    /// 在 onAppear 时一次性把原图降采样到短边 ≤ 1080 的预览底图。
    /// 这是优化的关键：所有滑杆预览都基于这张小图，处理速度提升 ~8 倍。
    private func preparePreviewBaseImage() {
        guard previewBaseImage == nil else { return }
        let original = inputImage
        Task.detached(priority: .userInitiated) {
            let downsampled = ImageDownsampler.downsample(original, maxDimension: 1080)
            await MainActor.run {
                previewBaseImage = downsampled
                tryGeneratePreviewMaskTexture()
            }
        }
    }

    /// 当 previewBaseImage 就绪后，调用 Vision 生成整个人物 mask 并缓存。
    /// 后续滑杆 tick 直接复用，不再重跑分割。
    private func tryGeneratePreviewMaskTexture() {
        guard previewMaskTexture == nil,
              let base = previewBaseImage else { return }

        Task.detached(priority: .userInitiated) {
            // 预览阶段用 .balanced 足够（短边 ≤ 1080），保存时再用 .accurate 重跑
            let tex = PersonSegmentationService.generateMaskTexture(for: base, quality: .balanced)
            await MainActor.run {
                previewMaskTexture = tex
                builtinPipeline?.maskTexture = tex
                personDetected = (tex != nil)
            }
        }
    }

    // MARK: - 处理

    private func saveImage() {
        saveBuiltinImage()
    }

    private func saveBuiltinImage() {
        isSaving = true
        let params = BeautyParams(
            smoothing: skinSmoothing,
            whitening: skinWhitening,
            whiteningYUV: skinWhiteningYUV,
            slimming: faceSlimming
        )
        let image = inputImage
        let ctx = faceContext
        Task.detached(priority: .userInitiated) {
            let result = ImagePipeline.shared.processBeauty(image: image, params: params, faceContext: ctx)
            do {
                try await PhotoLibraryService.shared.saveImage(result)
                await MainActor.run { isSaving = false; showSaveSuccess = true }
            } catch {
                await MainActor.run { isSaving = false; saveErrorMessage = error.localizedDescription; showSaveError = true }
            }
        }
    }

}


// MARK: - 美颜处理管线（瘦脸 → 磨皮 → 美白）

/// 高质量美颜处理（BeautyView 保存路径 + 美颜相机拍照路径共用）
nonisolated func applyBeautyPipeline(to image: UIImage, smoothing: Double, whitening: Double, whiteningYUV: Double,
                                     slimming: Double, landmarks: [VNFaceObservation]) -> UIImage {
    var current = image

    // 1) 瘦脸（MLS Rigid 形变，compute kernel）
    if slimming > 0.001 && !landmarks.isEmpty {
        current = applyFaceSlimming(to: current, strength: Float(slimming), landmarks: landmarks)
    }

    let hasSmoothing = smoothing > 0.001
    let hasWhitening = whitening > 0.001
    let hasWhiteningYUV = whiteningYUV > 0.001
    guard hasSmoothing || hasWhitening || hasWhiteningYUV else { return current }

    // 人物分割 mask（保存阶段用 .accurate；GPUImage PictureInput 走 topLeft，
    // 必须与之对齐，否则 mask Y 方向镜像）
    let personMask = PersonSegmentationService.generateMaskTexture(
        for: current, quality: .accurate, origin: .topLeft)

    // 2) 仅磨皮
    if hasSmoothing && !hasWhitening {
        let sigma = Float(6.0 + smoothing * 14.0)
        let bilateral = SkinSmoothingFactory.makeBilateralFilter(distanceNormalizationFactor: sigma)
        let combine = SkinSmoothingFactory.makeSkinSmoothCombine(intensity: Float(smoothing), personMask: personMask)
        current = current.filterWithPipeline { input, output in
            input --> bilateral
            bilateral --> combine
            input --> combine
            combine --> output
        }
    }
    // 3) 仅美白
    else if !hasSmoothing && hasWhitening {
        let whiten = SkinSmoothingFactory.makeSkinWhiten(strength: Float(whitening), personMask: personMask)
        current = current.filterWithPipeline { input, output in
            input --> whiten
            whiten --> output
        }
    }
    // 4) 磨皮 + 美白
    else if hasSmoothing && hasWhitening {
        let sigma = Float(6.0 + smoothing * 14.0)
        let bilateral = SkinSmoothingFactory.makeBilateralFilter(distanceNormalizationFactor: sigma)
        let combine = SkinSmoothingFactory.makeSkinSmoothCombine(intensity: Float(smoothing), personMask: personMask)
        let whiten = SkinSmoothingFactory.makeSkinWhiten(strength: Float(whitening), personMask: personMask)
        current = current.filterWithPipeline { input, output in
            input --> bilateral
            bilateral --> combine
            input --> combine
            combine --> whiten
            whiten --> output
        }
    }

    // 5) 亮肤（YUV 单 pass）
    if hasWhiteningYUV {
        let whitenYUV = SkinSmoothingFactory.makeSkinWhitenYUV(strength: Float(whiteningYUV), personMask: personMask)
        current = current.filterWithPipeline { input, output in
            input --> whitenYUV
            whitenYUV --> output
        }
    }

    return current
}

// MARK: - 瘦脸（MLS Rigid Warp）

/// 控制点结构，与 Metal 端 WarpControlPoint 布局一致
nonisolated private struct FaceWarpPoint {
    var src: SIMD2<Float> // 输出空间（瘦脸后位置，像素坐标）
    var dst: SIMD2<Float> // 输入空间（原始位置，像素坐标）
}

/// 缓存 MLS warp compute pipeline
nonisolated private let warpPipelineState: MTLComputePipelineState? = {
    let device = sharedMetalRenderingDevice.device
    guard let library = device.makeDefaultLibrary(),
          let function = library.makeFunction(name: "mlsRigidWarpKernel")
    else { return nil }
    return try? device.makeComputePipelineState(function: function)
}()

/// 从 Vision landmarks 生成瘦脸控制点
nonisolated private func generateSlimControlPoints(landmarks: [VNFaceObservation], imageSize: CGSize, strength: Float) -> [FaceWarpPoint] {
    var points: [FaceWarpPoint] = []
    let w = Float(imageSize.width)
    let h = Float(imageSize.height)

    for face in landmarks {
        let box = face.boundingBox
        guard let contour = face.landmarks?.faceContour else { continue }

        // 脸部中心 x（像素坐标）
        let faceCenterX = Float(box.midX) * w
        let faceCenterY = Float(box.midY) * h

        let contourPoints = contour.normalizedPoints
        let count = contourPoints.count

        // 下颌轮廓点 → 向中心收缩
        for (i, pt) in contourPoints.enumerated() {
            // Vision 归一化坐标（相对于 boundingBox）→ 像素坐标
            let px = (Float(box.origin.x) + Float(pt.x) * Float(box.width)) * w
            // Vision y 轴从底部开始，转为从顶部开始
            let py = (1.0 - (Float(box.origin.y) + Float(pt.y) * Float(box.height))) * h

            let original = SIMD2<Float>(px, py)

            // 只收缩下半部分颌骨区域（跳过额头附近的点）
            // faceContour 通常从右耳到左耳沿下颌线排列
            // 中间的点是下巴，两侧是腮帮
            let progress = Float(i) / Float(max(count - 1, 1))
            // 两侧收缩强度大，下巴(中间)收缩小
            let lateralFactor = 1.0 - abs(progress - 0.5) * 2.0 // 0→1→0
            let slimFactor = strength * (1.0 - lateralFactor * 0.6) * 0.12

            let slimmedX = px + (faceCenterX - px) * slimFactor
            let slimmedY = py + (faceCenterY - py) * slimFactor * 0.15
            let slimmed = SIMD2<Float>(slimmedX, slimmedY)

            points.append(FaceWarpPoint(src: slimmed, dst: original))
        }

        // 添加锚点（眼睛、鼻尖）— 不移动，稳定形变
        if let leftEye = face.landmarks?.leftEye {
            let pts = leftEye.normalizedPoints
            if let center = pts.first {
                let px = (Float(box.origin.x) + Float(center.x) * Float(box.width)) * w
                let py = (1.0 - (Float(box.origin.y) + Float(center.y) * Float(box.height))) * h
                let p = SIMD2<Float>(px, py)
                points.append(FaceWarpPoint(src: p, dst: p))
            }
        }
        if let rightEye = face.landmarks?.rightEye {
            let pts = rightEye.normalizedPoints
            if let center = pts.first {
                let px = (Float(box.origin.x) + Float(center.x) * Float(box.width)) * w
                let py = (1.0 - (Float(box.origin.y) + Float(center.y) * Float(box.height))) * h
                let p = SIMD2<Float>(px, py)
                points.append(FaceWarpPoint(src: p, dst: p))
            }
        }
        if let nose = face.landmarks?.noseCrest {
            let pts = nose.normalizedPoints
            if let tip = pts.last {
                let px = (Float(box.origin.x) + Float(tip.x) * Float(box.width)) * w
                let py = (1.0 - (Float(box.origin.y) + Float(tip.y) * Float(box.height))) * h
                let p = SIMD2<Float>(px, py)
                points.append(FaceWarpPoint(src: p, dst: p))
            }
        }
    }

    return points
}

nonisolated private func applyFaceSlimming(to image: UIImage, strength: Float, landmarks: [VNFaceObservation]) -> UIImage {
    let device = sharedMetalRenderingDevice.device
    guard let pipelineState = warpPipelineState,
          let cgImage = image.cgImage
    else { return image }

    let width = cgImage.width
    let height = cgImage.height

    // 生成控制点
    var controlPoints = generateSlimControlPoints(landmarks: landmarks, imageSize: CGSize(width: width, height: height), strength: strength)
    guard !controlPoints.isEmpty else { return image }

    // 输入纹理（需要 sample 权限）
    let inDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    inDesc.usage = [.shaderRead]
    guard let inTexture = device.makeTexture(descriptor: inDesc) else { return image }

    let bytesPerRow = 4 * width
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: &pixels, width: width, height: height,
                              bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                              space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    else { return image }
    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    inTexture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: pixels, bytesPerRow: bytesPerRow)

    // 输出纹理
    let outDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    outDesc.usage = [.shaderWrite]
    guard let outTexture = device.makeTexture(descriptor: outDesc) else { return image }

    // 控制点 buffer
    let pointBuffer = device.makeBuffer(bytes: &controlPoints,
                                         length: MemoryLayout<FaceWarpPoint>.stride * controlPoints.count,
                                         options: .storageModeShared)!
    var pointCount = Int32(controlPoints.count)

    // Dispatch
    guard let commandBuffer = sharedMetalRenderingDevice.commandQueue.makeCommandBuffer(),
          let encoder = commandBuffer.makeComputeCommandEncoder()
    else { return image }

    encoder.setComputePipelineState(pipelineState)
    encoder.setTexture(inTexture, index: 0)
    encoder.setTexture(outTexture, index: 1)
    encoder.setBuffer(pointBuffer, offset: 0, index: 0)
    encoder.setBytes(&pointCount, length: MemoryLayout<Int32>.size, index: 1)

    let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
    let threadGroups = MTLSize(
        width: (width + 15) / 16,
        height: (height + 15) / 16,
        depth: 1
    )
    encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
    encoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    // 读回
    var outBytes = [UInt8](repeating: 0, count: width * height * 4)
    outTexture.getBytes(&outBytes, bytesPerRow: bytesPerRow,
                        from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

    guard let outCtx = CGContext(data: &outBytes, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
          let outCG = outCtx.makeImage()
    else { return image }

    return UIImage(cgImage: outCG, scale: image.scale, orientation: image.imageOrientation)
}

// MARK: - 长生命周期内置美颜管线
//
// 把 GPUImage3 的滤镜操作长期持有，避免每 tick 重建 MTLRenderPipelineState（含 shader 反射，
// 单次 10–30ms × 3 个 op = 主要卡顿来源）。同一份 source UIImage 也只上传一次到 GPU。
//
// 调用规约：
//   - ensureSource(image): 当源图身份变化（瘦脸值变更）时，重建 PictureInput 与连线；
//     源图相同则零开销复用。
//   - process(...): 每帧 tick 只更新 uniforms 然后同步触发一次 processImage。
//
// 该类被 BeautyView 通过 @State 持有，访问发生在 Task.detached 后台线程；GPUImage 的
// AppShaderOperation 内部有 textureInputSemaphore，PictureInput.processImage(synchronously:true)
// 同步执行，因此整体安全。
nonisolated final class BeautyPreviewPipeline: @unchecked Sendable {
    private let bilateralH: AppShaderOperation
    private let bilateralV: AppShaderOperation
    private let combineOp: AppShaderOperation
    private let whitenOp: AppShaderOperation
    private let whitenYUVOp: AppShaderOperation
    private let textureOutput: BeautyTextureOutput
    private var rawSource: RawTextureSource?
    private var sourceFingerprint: ObjectIdentifier?

    /// 人物分割 mask 纹理：同时绑定到 combine/LUT美白/亮肤 三个 op，
    /// 让背景区域在所有 pass 中都保持原样。nil 时回落到 1×1 白色纹理。
    var maskTexture: MTLTexture? {
        didSet {
            let t = maskTexture ?? PersonSegmentationService.whiteFallbackTexture
            combineOp.extraFragmentTextures[2]    = t
            whitenOp.extraFragmentTextures[2]     = t  // LUT 占用 slot 1，personMask 在 slot 2
            whitenYUVOp.extraFragmentTextures[1]  = t
        }
    }

    /// 最近一帧的输出 MTLTexture（供 MetalTextureView 直显）
    var latestTexture: MTLTexture? { textureOutput.latestTexture }

    /// 通知预览刷新的回调（在 GPUImage 线程触发）
    var onFrameReady: (() -> Void)? {
        get { textureOutput.onFrameReady }
        set { textureOutput.onFrameReady = newValue }
    }

    init() {
        bilateralH = AppShaderOperation(fragmentFunctionName: "bilateralHFragment", numberOfInputs: 1)
        bilateralV = AppShaderOperation(fragmentFunctionName: "bilateralVFragment", numberOfInputs: 1)
        combineOp = AppShaderOperation(fragmentFunctionName: "skinSmoothCombineFragment", numberOfInputs: 2)
        whitenOp = AppShaderOperation(fragmentFunctionName: "skinWhitenLUTFragment", numberOfInputs: 1)
        if let lut = WhiteningLUTGenerator.sharedLUT {
            whitenOp.extraFragmentTextures[1] = lut
        }
        whitenYUVOp = AppShaderOperation(fragmentFunctionName: "skinWhitenYUVFragment", numberOfInputs: 1)
        whitenYUVOp.uniformSettings["yuvStrength"] = Float(0)
        textureOutput = BeautyTextureOutput()

        // 初始绑定全白 personMask，首帧在分割完成前也能安全渲染
        let whiteMask = PersonSegmentationService.whiteFallbackTexture
        combineOp.extraFragmentTextures[2]   = whiteMask
        whitenOp.extraFragmentTextures[2]    = whiteMask
        whitenYUVOp.extraFragmentTextures[1] = whiteMask
    }

    /// R6: 直接以 UIImage 上传一次到 MTLTexture，跳过 GPUImage 的 PictureInput round-trip。
    /// 内部按 UIImage 身份缓存上传，相同图像 ≥ 第二次调用零开销。
    func ensureSource(uiImage: UIImage) {
        let key = ObjectIdentifier(uiImage)
        if key == sourceFingerprint, rawSource != nil { return }
        guard let cg = uiImage.cgImage else { return }
        let loader = MTKTextureLoader(device: sharedMetalRenderingDevice.device)
        guard let tex = try? loader.newTexture(cgImage: cg, options: [
            .SRGB: false,
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .origin: MTKTextureLoader.Origin.bottomLeft
        ]) else { return }

        teardown()
        let src = RawTextureSource(texture: tex)
        // input → H → V → combine → whiten → output
        //   input → combine（第二输入，作为 original）
        src --> bilateralH --> bilateralV --> combineOp --> whitenOp --> whitenYUVOp --> textureOutput
        src --> combineOp
        rawSource = src
        sourceFingerprint = key
    }

    private func teardown() {
        rawSource?.removeAllTargets()
        bilateralH.removeAllTargets()
        bilateralV.removeAllTargets()
        combineOp.removeAllTargets()
        whitenOp.removeAllTargets()
        whitenYUVOp.removeAllTargets()
        bilateralH.sources.removeAtIndex(0)
        bilateralV.sources.removeAtIndex(0)
        combineOp.sources.removeAtIndex(0)
        combineOp.sources.removeAtIndex(1)
        whitenOp.sources.removeAtIndex(0)
        whitenYUVOp.sources.removeAtIndex(0)
    }

    /// tick：仅更新 uniforms 并同步处理一帧；R7 路径下不再做 GPU→CPU 回读。
    func process(sigma: Float, smoothIntensity: Float, whitenStrength: Float, whitenYUVStrength: Float) {
        guard let src = rawSource else { return }
        bilateralH.uniformSettings["distanceNormalizationFactor"] = sigma
        bilateralV.uniformSettings["distanceNormalizationFactor"] = sigma
        combineOp.uniformSettings["intensity"] = smoothIntensity
        whitenOp.uniformSettings["whitenStrength"] = whitenStrength
        whitenYUVOp.uniformSettings["yuvStrength"] = whitenYUVStrength
        src.processImage()
    }
}

// MARK: - R6: 原始 MTLTexture 数据源（避免 UIImage round-trip）

nonisolated final class RawTextureSource: ImageSource, @unchecked Sendable {
    let targets = TargetContainer()
    private let wrappedTexture: Texture

    init(texture: MTLTexture) {
        self.wrappedTexture = Texture(orientation: .portrait, texture: texture)
    }

    func processImage() {
        updateTargetsWithTexture(wrappedTexture)
    }

    func transmitPreviousImage(to target: ImageConsumer, atIndex: UInt) {
        target.newTextureAvailable(wrappedTexture, fromSourceIndex: atIndex)
    }
}

// MARK: - R7: 仅捕获 MTLTexture 的 Output（不做 CGImage 回读）

nonisolated final class BeautyTextureOutput: ImageConsumer, @unchecked Sendable {
    let maximumInputs: UInt = 1
    let sources = SourceContainer()
    private(set) var latestTexture: MTLTexture?
    var onFrameReady: (() -> Void)?

    func newTextureAvailable(_ texture: Texture, fromSourceIndex: UInt) {
        latestTexture = texture.texture
        onFrameReady?()
    }
}

// MARK: - R7: MTKView 直显（跳过 UIImage 解码 & GPU→CPU 回读）

import MetalKit

struct MetalTexturePreview: UIViewRepresentable {
    let pipeline: BeautyPreviewPipeline?
    let fallbackImage: UIImage

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: sharedMetalRenderingDevice.device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.delegate = context.coordinator
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .black
        view.layer.isOpaque = true
        context.coordinator.view = view
        context.coordinator.pipeline = pipeline
        context.coordinator.fallbackImage = fallbackImage
        pipeline?.onFrameReady = { [weak view] in
            DispatchQueue.main.async { view?.setNeedsDisplay() }
        }
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.pipeline = pipeline
        context.coordinator.fallbackImage = fallbackImage
        pipeline?.onFrameReady = { [weak uiView] in
            DispatchQueue.main.async { uiView?.setNeedsDisplay() }
        }
        uiView.setNeedsDisplay()
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        weak var view: MTKView?
        var pipeline: BeautyPreviewPipeline?
        var fallbackImage: UIImage = UIImage()
        private var fallbackTexture: MTLTexture?
        private var fallbackKey: ObjectIdentifier?
        private lazy var ciContext = CIContext(mtlDevice: sharedMetalRenderingDevice.device)

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let cmdBuffer = sharedMetalRenderingDevice.commandQueue.makeCommandBuffer()
            else { return }

            let tex = pipeline?.latestTexture ?? loadFallbackTexture()
            guard let src = tex else {
                cmdBuffer.present(drawable)
                cmdBuffer.commit()
                return
            }

            // 用 CIImage 走 CIContext.render 做 letterbox 缩放到 drawable
            // 源 texture 已用 .bottomLeft origin 加载，与 CIImage 坐标系一致，无需额外翻转
            var ci = CIImage(mtlTexture: src, options: [.colorSpace: CGColorSpaceCreateDeviceRGB()])
                ?? CIImage.empty()

            let dstW = CGFloat(drawable.texture.width)
            let dstH = CGFloat(drawable.texture.height)
            let srcW = ci.extent.width
            let srcH = ci.extent.height
            let scale = min(dstW / srcW, dstH / srcH)
            let drawW = srcW * scale
            let drawH = srcH * scale
            let dx = (dstW - drawW) / 2
            let dy = (dstH - drawH) / 2
            ci = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale)
                .translatedBy(x: dx / scale, y: dy / scale))

            ciContext.render(ci,
                             to: drawable.texture,
                             commandBuffer: cmdBuffer,
                             bounds: CGRect(x: 0, y: 0, width: dstW, height: dstH),
                             colorSpace: CGColorSpaceCreateDeviceRGB())
            cmdBuffer.present(drawable)
            cmdBuffer.commit()
        }

        private func loadFallbackTexture() -> MTLTexture? {
            let key = ObjectIdentifier(fallbackImage)
            if key == fallbackKey, let t = fallbackTexture { return t }
            guard let cg = fallbackImage.cgImage else { return nil }
            let loader = MTKTextureLoader(device: sharedMetalRenderingDevice.device)
            let opts: [MTKTextureLoader.Option: Any] = [
                .SRGB: false,
                .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
                .origin: MTKTextureLoader.Origin.bottomLeft
            ]
            let t = try? loader.newTexture(cgImage: cg, options: opts)
            fallbackTexture = t
            fallbackKey = key
            return t
        }
    }
}
