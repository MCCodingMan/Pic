import Foundation
import CoreGraphics
import SwiftUI

struct EditState: Codable, Equatable, Identifiable {
    var id: UUID
    var adjustments: Adjustments
    var cropRect: CGRect // Normalized (0.0...1.0)
    var rotation: Double // In radians
    var flipHorizontal: Bool
    var flipVertical: Bool
    var aspectRatio: AspectRatio = .original
    var filter: FilterModel = .original
    var description: String = "初始状态"
    
    // Masks
    var masks: [MaskLayer] = []
    
    // Stickers
    var stickers: [Sticker] = []
    
    // Drawings
    var drawings: [DrawingStroke] = []

    // Beauty / 美颜
    var skinSmoothing: Double = 0.0 // 0.0 ~ 1.0

    init() {
        self.id = UUID()
        self.adjustments = Adjustments()
        self.cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        self.rotation = 0.0
        self.flipHorizontal = false
        self.flipVertical = false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        adjustments = try container.decodeIfPresent(Adjustments.self, forKey: .adjustments) ?? Adjustments()
        cropRect = try container.decodeIfPresent(CGRect.self, forKey: .cropRect) ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        rotation = try container.decodeIfPresent(Double.self, forKey: .rotation) ?? 0.0
        flipHorizontal = try container.decodeIfPresent(Bool.self, forKey: .flipHorizontal) ?? false
        flipVertical = try container.decodeIfPresent(Bool.self, forKey: .flipVertical) ?? false
        aspectRatio = try container.decodeIfPresent(AspectRatio.self, forKey: .aspectRatio) ?? .original
        filter = try container.decodeIfPresent(FilterModel.self, forKey: .filter) ?? .original
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? "初始状态"
        masks = try container.decodeIfPresent([MaskLayer].self, forKey: .masks) ?? []
        stickers = try container.decodeIfPresent([Sticker].self, forKey: .stickers) ?? []
        drawings = try container.decodeIfPresent([DrawingStroke].self, forKey: .drawings) ?? []
        skinSmoothing = try container.decodeIfPresent(Double.self, forKey: .skinSmoothing) ?? 0.0
    }
}

struct EditPreset: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var createdAt: Date
    var adjustments: Adjustments
    var filter: FilterModel

    init(name: String, adjustments: Adjustments, filter: FilterModel) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.adjustments = adjustments
        self.filter = filter
    }
}

// MARK: - Sticker Model
struct Sticker: Codable, Equatable, Identifiable {
    var id: UUID
    var content: String // Emoji or image name (if imageData is nil)
    var imageData: Data? // For photo stickers
    var position: CGPoint // Normalized (0...1) relative to image
    var scale: CGFloat
    var rotation: Double // Radians (Z-axis)
    var rotationX: Double // Radians (X-axis)
    var rotationY: Double // Radians (Y-axis)
    
    // Text Properties
    var textColor: CodableColor = .black
    var backgroundColor: CodableColor?
    var fontName: String = "System"
    
    init(content: String, imageData: Data? = nil, position: CGPoint = CGPoint(x: 0.5, y: 0.5), scale: CGFloat = 1.0, rotation: Double = 0.0, rotationX: Double = 0.0, rotationY: Double = 0.0, textColor: CodableColor = .black, backgroundColor: CodableColor? = nil, fontName: String = "System") {
        self.id = UUID()
        self.content = content
        self.imageData = imageData
        self.position = position
        self.scale = scale
        self.rotation = rotation
        self.rotationX = rotationX
        self.rotationY = rotationY
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.fontName = fontName
    }
}

// MARK: - Drawing Model
struct DrawingStroke: Codable, Equatable, Identifiable {
    var id: UUID
    var points: [CGPoint] // Normalized (0...1)
    var color: CodableColor
    var lineWidth: CGFloat
    var isEraser: Bool // If true, acts as eraser (or blur)
    
    init(points: [CGPoint] = [], color: CodableColor = .black, lineWidth: CGFloat = 5.0, isEraser: Bool = false) {
        self.id = UUID()
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.isEraser = isEraser
    }
}

struct CodableColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
    
    static let black = CodableColor(red: 0, green: 0, blue: 0, alpha: 1)
    static let white = CodableColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let red = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
    static let blue = CodableColor(red: 0, green: 0, blue: 1, alpha: 1)
    static let green = CodableColor(red: 0, green: 1, blue: 0, alpha: 1)
    static let yellow = CodableColor(red: 1, green: 1, blue: 0, alpha: 1)
    
    var uiColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
    
    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
    
    init(_ color: Color) {
        // Simple conversion, assuming sRGB
        // In real app, use UIColor/NSColor to extract components
        if let components = UIColor(color).cgColor.components {
            if components.count >= 3 {
                self.red = Double(components[0])
                self.green = Double(components[1])
                self.blue = Double(components[2])
                self.alpha = components.count >= 4 ? Double(components[3]) : 1.0
            } else if components.count >= 2 { // Grayscale
                self.red = Double(components[0])
                self.green = Double(components[0])
                self.blue = Double(components[0])
                self.alpha = Double(components[1])
            } else {
                self.red = 0
                self.green = 0
                self.blue = 0
                self.alpha = 1
            }
        } else {
            self.red = 0
            self.green = 0
            self.blue = 0
            self.alpha = 1
        }
    }
}
