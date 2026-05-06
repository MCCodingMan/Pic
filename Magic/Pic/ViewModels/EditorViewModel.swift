import SwiftUI
import CoreImage
import Combine
import UIKit

@Observable
class EditorViewModel {
    var project: PhotoProject
    var editState: EditState {
        didSet {
            // Auto-save logic could go here
            project.currentEditState = editState
        }
    }

    var originalImage: CIImage?
    var originalUIImage: UIImage? // For comparison and fallback
    var previewImage: UIImage?
    var isProcessing: Bool = false

    // Performance: Downsampled image for preview
    private var downsampledOriginalImage: CIImage?
    private var updateTask: Task<Void, Never>?
    private var updateContinuation: AsyncStream<EditState>.Continuation?

    // History
    private(set) var undoStack: [EditState] = []
    private(set) var redoStack: [EditState] = []

    var canUndo: Bool {
        return !undoStack.isEmpty
    }

    var canRedo: Bool {
        return !redoStack.isEmpty
    }

    init(project: PhotoProject) {
        self.project = project
        self.editState = project.currentEditState
        setupUpdateStream()
        loadFilters()
    }

    deinit {
        updateContinuation?.finish()
        updateTask?.cancel()
    }

    func autoEnhance() {
        guard let original = downsampledOriginalImage ?? originalImage else { return }

        isProcessing = true
        Task {
            let recommended = ImageProcessingService.shared.analyzeAutoEnhance(for: original)

            await MainActor.run {
                commitEdit("自动增强")
                editState.adjustments = recommended
                scheduleUpdate()
                isProcessing = false
            }
        }
    }

    func loadAsset(from image: UIImage) {
        guard let ciImage = CIImage(image: image) else { return }
        self.originalImage = ciImage
        self.originalUIImage = image

        // Create downsampled image for preview
        self.downsampledOriginalImage = ImageDownsampler.downsample(ciImage, maxDimension: 1200)

        // Initial update
        scheduleUpdate()
    }

    func updateAdjustment<V>(_ keyPath: WritableKeyPath<Adjustments, V>, value: V) {
        // Update state directly for immediate UI feedback (if bound to state)
        if draftMask != nil {
            // 更新草稿蒙版
            draftMask!.adjustments[keyPath: keyPath] = value
        } else if let id = selectedMaskID, let index = editState.masks.firstIndex(where: { $0.id == id }) {
            var mask = editState.masks[index]
            var adjustments = mask.adjustments
            adjustments[keyPath: keyPath] = value
            mask.adjustments = adjustments
            editState.masks[index] = mask
        } else {
            var newAdjustments = editState.adjustments
            newAdjustments[keyPath: keyPath] = value
            editState.adjustments = newAdjustments
        }

        scheduleUpdate()
    }

    func undo() {
        guard !undoStack.isEmpty else { return }

        let currentState = editState
        let previousState = undoStack.removeLast()

        redoStack.append(currentState)
        editState = previousState
        scheduleUpdate()
    }

    func redo() {
        guard !redoStack.isEmpty else { return }

        let currentState = editState
        let nextState = redoStack.removeLast()

        undoStack.append(currentState)
        editState = nextState
        scheduleUpdate()
    }

    func jumpToHistory(at index: Int) {
        guard index >= 0 && index < undoStack.count else { return }

        // Save current state to redo stack if needed, or just clear redo?
        // Standard behavior: jumping to history usually clears redo stack or creates a new branch
        // Here we'll treat it as undoing multiple steps

        let targetState = undoStack[index]

        // Push states after index to redo stack (in reverse order)
        let statesToRedo = undoStack.suffix(from: index + 1) + [editState]
        redoStack.append(contentsOf: statesToRedo.reversed())

        // Keep states up to index in undo stack
        undoStack = Array(undoStack.prefix(upTo: index))

        editState = targetState
        scheduleUpdate()
    }

    private let maxUndoCount = 50

    func commitEdit(_ description: String = "编辑") {
        var stateToSave = editState
        stateToSave.description = description
        undoStack.append(stateToSave)
        if undoStack.count > maxUndoCount {
            undoStack.removeFirst(undoStack.count - maxUndoCount)
        }
        redoStack.removeAll()
    }

    func reset() {
        commitEdit("重置")
        // Reset to original
        var newState = EditState()
        newState.id = editState.id // Keep same ID? Or new?
        editState = newState
        scheduleUpdate()
    }

    func scheduleUpdate() {
        updateContinuation?.yield(editState)
    }

    private func setupUpdateStream() {
        // Use AsyncStream(bufferingPolicy:) initializer which is safer and cleaner
        var continuation: AsyncStream<EditState>.Continuation!
        let stream = AsyncStream<EditState>(bufferingPolicy: .bufferingNewest(1)) { cont in
            continuation = cont
        }

        self.updateContinuation = continuation

        updateTask = Task { [weak self] in
            for await state in stream {
                guard let self = self else { break }

                await self.updatePreview(with: state)
            }
        }
    }

    private func updatePreview(with state: EditState) async {
        guard let inputImage = downsampledOriginalImage ?? originalImage else { return }

        let newPreview = await ImageProcessingService.shared.generatePreview(for: inputImage, edits: state, targetSize: .zero)

        if !Task.isCancelled {
            await MainActor.run {
                if let newPreview {
                    self.previewImage = newPreview
                }
                self.isProcessing = false
            }
        }
    }

    // Geometry
    func setAspectRatio(_ ratio: AspectRatio) {
        guard let original = originalImage else { return }

        commitEdit("调整比例")

        // Update state
        var newState = editState
        newState.aspectRatio = ratio

        // Reset crop if original
        if ratio == .original {
            newState.cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            editState = newState
            scheduleUpdate()
            return
        }

        guard let targetRatio = ratio.ratio else { return }

        // Calculate crop rect to fit target ratio centered
        let extent = original.extent
        let imageRatio = extent.width / extent.height

        var newCropRect = CGRect(x: 0, y: 0, width: 1, height: 1)

        if imageRatio > targetRatio {
            // Image is wider than target -> Crop width
            let relativeWidth = targetRatio / imageRatio
            let originX = (1.0 - relativeWidth) / 2.0
            newCropRect = CGRect(x: originX, y: 0, width: relativeWidth, height: 1.0)
        } else {
            // Image is taller than target -> Crop height
            let relativeHeight = imageRatio / targetRatio
            let originY = (1.0 - relativeHeight) / 2.0
            newCropRect = CGRect(x: 0, y: originY, width: 1.0, height: relativeHeight)
        }

        newState.cropRect = newCropRect
        editState = newState
        scheduleUpdate()
    }

    func rotate() {
        commitEdit("旋转")
        // Rotate 90 degrees clockwise
        // editState.rotation is in radians
        let newRotation = editState.rotation - (.pi / 2.0)
        editState.rotation = newRotation
        scheduleUpdate()
    }

    func flipHorizontal() {
        commitEdit("水平翻转")
        editState.flipHorizontal.toggle()
        scheduleUpdate()
    }

    func flipVertical() {
        commitEdit("垂直翻转")
        editState.flipVertical.toggle()
        scheduleUpdate()
    }

    /// 应用裁剪后的图片，替换原图并重置裁剪状态
    func applyCroppedImage(_ croppedImage: UIImage) {
        commitEdit("裁剪")
        // 用裁剪后的图片替换原图
        loadAsset(from: croppedImage)
        // 重置裁剪相关状态
        editState.cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        editState.rotation = 0
        editState.flipHorizontal = false
        editState.flipVertical = false
        editState.aspectRatio = .original
        scheduleUpdate()
    }

    // HSL
    func updateHSL(channel: HSLChannel, shift: HSLShift) {
        if draftMask != nil {
            // 更新草稿蒙版 HSL
            if shift == .identity {
                draftMask!.adjustments.hsl.removeValue(forKey: channel)
            } else {
                draftMask!.adjustments.hsl[channel] = shift
            }
        } else if let id = selectedMaskID, let index = editState.masks.firstIndex(where: { $0.id == id }) {
            // Update mask HSL
            var mask = editState.masks[index]
            if shift == .identity {
                mask.adjustments.hsl.removeValue(forKey: channel)
            } else {
                mask.adjustments.hsl[channel] = shift
            }
            editState.masks[index] = mask
        } else {
            // Global HSL
            if shift == .identity {
                editState.adjustments.hsl.removeValue(forKey: channel)
            } else {
                editState.adjustments.hsl[channel] = shift
            }
        }

        scheduleUpdate()
    }

    // Filters
    // Categorized filters
    private(set) var availableFilters: [String: [FilterModel]] = [:]

    // Ordered categories for display
    let filterCategories = ["基础", "风景", "人物"]

    func setFilter(_ filter: FilterModel) {
        if filter.id == FilterModel.auto.id {
            applyAutoEnhance()
            return
        }
        if editState.filter != filter {
            commitEdit("滤镜: \(filter.name)")
            editState.filter = filter
            scheduleUpdate()
        }
    }

    /// 使用 Apple 内置自动调整分析当前图片
    private func applyAutoEnhance() {
        guard let image = originalImage else { return }
        let autoAdj = ImageProcessingService.shared.analyzeAutoEnhance(for: image)
        commitEdit("滤镜: 自动")
        editState.filter = .auto
        editState.adjustments = autoAdj
        scheduleUpdate()
    }

    private func loadFilters() {
        let all = FilterModel.generateFilters()
        self.availableFilters = Dictionary(grouping: all, by: { $0.category })
    }

    // Masks
    var selectedMaskID: UUID?
    /// 草稿蒙版：点击线性/径向后创建，尚未添加到 editState.masks
    var draftMask: MaskLayer?

    /// 是否正在编辑蒙版（包括草稿和已有的）
    var isEditingMask: Bool {
        draftMask != nil || selectedMaskID != nil
    }

    func addMask(type: MaskType) {
        // 不立即添加到 masks，而是创建草稿
        let newMask = MaskLayer(type: type)
        draftMask = newMask
        selectedMaskID = nil
    }

    /// 完成蒙版编辑（返回时调用）
    func finishMaskEditing() {
        if let draft = draftMask {
            if !draft.adjustments.isDefault {
                // 草稿有实际调整，提交到 masks
                commitEdit("添加蒙版")
                editState.masks.append(draft)
                scheduleUpdate()
            }
            draftMask = nil
        } else if let id = selectedMaskID {
            // 编辑已有蒙版，如果调整恢复为默认值则移除
            if let index = editState.masks.firstIndex(where: { $0.id == id }) {
                if editState.masks[index].adjustments.isDefault {
                    commitEdit("移除蒙版")
                    editState.masks.remove(at: index)
                    scheduleUpdate()
                }
            }
            selectedMaskID = nil
        }
    }

    func removeMask(id: UUID) {
        if let draftMask, draftMask.id == id {
            self.draftMask = nil
            return
        }
        if let index = editState.masks.firstIndex(where: { $0.id == id }) {
            commitEdit("移除蒙版")
            editState.masks.remove(at: index)
            if selectedMaskID == id {
                selectedMaskID = nil
            }
            scheduleUpdate()
        }
    }

    func updateMask(_ mask: MaskLayer) {
        if let index = editState.masks.firstIndex(where: { $0.id == mask.id }) {
            editState.masks[index] = mask
            scheduleUpdate()
        }
    }

    // MARK: - Stickers
    let stickerEmojis: [String] = [
        // Faces
        "😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "🥲", "☺️", "😊", "😇", "🙂", "🙃", "😉", "😌", "😍", "🥰", "😘", "😗",
        "😙", "😚", "😋", "😛", "😝", "😜", "🤪", "🤨", "🧐", "🤓", "😎", "🥸", "🤩", "🥳", "😏", "😒", "😞", "😔", "😟", "😕",
        "🙁", "☹️", "😣", "😖", "😫", "😩", "🥺", "😢", "😭", "😤", "😠", "😡", "🤬", "🤯", "😳", "🥵", "🥶", "😱", "😨", "😰",
        "😥", "😓", "🤗", "🤔", "🤭", "🤫", "🤥", "😶", "😐", "😑", "😬", "🙄", "😯", "😦", "😧", "😮", "😲", "🥱", "😴", "🤤",
        "😪", "😵", "🤐", "🥴", "🤢", "🤮", "🤧", "😷", "🤒", "🤕", "🤑", "🤠", "😈", "👿", "👹", "👺", "🤡", "💩", "👻", "💀",
        // Hands & Body
        "👋", "🤚", "🖐", "✋", "🖖", "👌", "🤌", "🤏", "✌️", "🤞", "🤟", "🤘", "🤙", "👈", "👉", "👆", "👇", "☝️", "👍", "👎",
        "✊", "👊", "🤛", "🤜", "👏", "🙌", "👐", "🤲", "🤝", "🙏", "✍️", "💅", "🤳", "💪", "🦾", "🦵", "🦿", "🦶", "👣", "👂",
        // Hearts & Symbols
        "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔", "❣️", "💕", "💞", "💓", "💗", "💖", "💘", "💝", "💟", "☮️",
        "✝️", "☪️", "🕉", "☸️", "✡️", "🔯", "🕎", "☯️", "☦️", "🛐", "⛎", "♈️", "♉️", "♊️", "♋️", "♌️", "♍️", "♎️", "♏️", "♐️",
        // Nature & Animals
        "🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐻‍❄️", "🐨", "🐯", "🦁", "🐮", "🐷", "🐽", "🐸", "🐵", "🙈", "🙉", "🙊",
        "🐒", "🐔", "🐧", "🐦", "🐤", "🐣", "🐥", "🦆", "🦅", "🦉", "🦇", "🐺", "🐗", "🐴", "🦄", "🐝", "🪱", "🐛", "🦋", "🐌",
        // Plants & Flowers
        "💐", "🌸", "💮", "🏵", "🌹", "🥀", "🌺", "🌻", "🌼", "🌷", "🌱", "🪴", "🌲", "🌳", "🌴", "🌵", "🌾", "🌿", "☘️", "🍀",
        // Food
        "🍏", "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐", "🍈", "🍒", "🍑", "🥭", "🍍", "🥥", "🥝", "🍅", "🍆", "🥑",
        // Objects & Activities
        "⚽️", "🏀", "🏈", "⚾️", "🥎", "🎾", "🏐", "🏉", "🥏", "🎱", "🪀", "🏓", "🏸", "🏒", "🏑", "🥍", "🏏", "🪃", "🥅", "⛳️",
        "🎨", "🎬", "🎤", "🎧", "🎼", "🎹", "🥁", "🎷", "🎺", "🎸", "🪕", "🎻", "🎲", "♟", "🎯", "🎳", "🎮", "🎰", "🧩", "🚗",
        // Weather & Space
        "☀️", "🌝", "🌚", "🌍", "🌎", "🌏", "🪐", "💫", "⭐️", "🌟", "✨", "⚡️", "☄️", "💥", "🔥", "🌪", "🌈", "☀️", "🌤", "⛅️",
        "🌥", "☁️", "🌦", "🌧", "⛈", "🌩", "🌨", "❄️", "☃️", "⛄️", "🌬", "💨", "💧", "💦", "☔️", "☂️", "🌊", "🌫", "🎃", "🎄"
    ]

    func addSticker(_ content: String) {
        commitEdit("添加贴纸")
        let sticker = Sticker(content: content)
        editState.stickers.append(sticker)
        scheduleUpdate()
    }

    func addImageSticker(_ image: UIImage) {
        commitEdit("添加图片贴纸")
        // Compress image to reasonable size
        let maxDimension: CGFloat = 500
        let size = image.size
        let scale = maxDimension / max(size.width, size.height)
        var finalImage = image

        if scale < 1.0 {
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            finalImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }

        if let data = finalImage.pngData() {
            let sticker = Sticker(content: "image", imageData: data)
            editState.stickers.append(sticker)
            scheduleUpdate()
        }
    }

    func addTextSticker(_ content: String, color: CodableColor, fontName: String) {
        commitEdit("添加文字")
        let sticker = Sticker(content: content, textColor: color, fontName: fontName)
        editState.stickers.append(sticker)
        scheduleUpdate()
    }

    func updateSticker(_ sticker: Sticker) {
        if let index = editState.stickers.firstIndex(where: { $0.id == sticker.id }) {
            editState.stickers[index] = sticker
            scheduleUpdate()
        }
    }

    func removeSticker(_ id: UUID) {
        commitEdit("删除贴纸")
        editState.stickers.removeAll { $0.id == id }
        scheduleUpdate()
    }

    // MARK: - Drawings
    func addDrawing(_ stroke: DrawingStroke) {
        commitEdit("涂鸦")
        editState.drawings.append(stroke)
        scheduleUpdate()
    }


    // Export
    func saveImage() async throws {
        guard let original = originalImage else { return }

        await MainActor.run { isProcessing = true }

        do {
            // Update thumbnail
            if let preview = previewImage {
                let thumbSize = CGSize(width: 300, height: 300)
                let renderer = UIGraphicsImageRenderer(size: thumbSize)
                let thumb = renderer.image { _ in
                    preview.draw(in: CGRect(origin: .zero, size: thumbSize))
                }
                project.thumbnailData = thumb.jpegData(compressionQuality: 0.7)
            }

            // Save Project to Persistence
            PersistenceService.shared.save(project: project)

            // Process on background thread to avoid blocking UI
            let edits = editState
            let uiImage: UIImage? = await Task.detached(priority: .userInitiated) {
                let processedCI = ImagePipeline.shared.processEditor(original, edits: edits)
                guard let cgImage = ImageProcessingService.shared.render(image: processedCI) else { return nil }
                return UIImage(cgImage: cgImage)
            }.value

            if let uiImage {
                try await PhotoLibraryService.shared.saveImage(uiImage)
            }

            await MainActor.run { isProcessing = false }
        } catch {
            await MainActor.run { isProcessing = false }
            throw error
        }
    }
}
