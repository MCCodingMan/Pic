import Foundation
import CoreGraphics

enum MaskType: String, Codable, Identifiable {
    case linear = "线性渐变"
    case radial = "径向渐变"
    // Future: Brush, AI Subject
    
    var id: String { rawValue }
}

struct MaskLayer: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var type: MaskType
    var isInverted: Bool = false
    
    // Geometry (Normalized 0...1)
    // For Linear: startPoint, endPoint
    // For Radial: center, radius (X/Y)
    var startPoint: CGPoint = CGPoint(x: 0.5, y: 0.2)
    var endPoint: CGPoint = CGPoint(x: 0.5, y: 0.8)
    
    // Adjustments for this mask
    var adjustments: Adjustments = Adjustments()
    
    static func == (lhs: MaskLayer, rhs: MaskLayer) -> Bool {
        return lhs.id == rhs.id &&
               lhs.type == rhs.type &&
               lhs.isInverted == rhs.isInverted &&
               lhs.startPoint == rhs.startPoint &&
               lhs.endPoint == rhs.endPoint &&
               lhs.adjustments == rhs.adjustments
    }
}
