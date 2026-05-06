import Foundation

nonisolated enum HSLChannel: String, CaseIterable, Codable, Identifiable {
    case red = "Red"
    case orange = "Orange"
    case yellow = "Yellow"
    case green = "Green"
    case cyan = "Cyan"
    case blue = "Blue"
    case purple = "Purple"
    case magenta = "Magenta"
    
    var id: String { rawValue }
    
    // Center hue in normalized 0...1 range (must match shader hslKernel positions)
    var centerHue: Float {
        switch self {
        case .red: return 0.0        // 0°
        case .orange: return 0.0833  // 30°
        case .yellow: return 0.1667  // 60°
        case .green: return 0.3333   // 120°
        case .cyan: return 0.5       // 180°
        case .blue: return 0.6667    // 240°
        case .purple: return 0.75    // 270°
        case .magenta: return 0.8333 // 300°
        }
    }
    
    // Color representation for UI
    var uiColor: String {
        switch self {
        case .red: return "#FF3B30"
        case .orange: return "#FF9500"
        case .yellow: return "#FFCC00"
        case .green: return "#4CD964"
        case .cyan: return "#5AC8FA"
        case .blue: return "#007AFF"
        case .purple: return "#5856D6"
        case .magenta: return "#FF2D55"
        }
    }
}

nonisolated struct HSLShift: Codable, Equatable, Hashable {
    var hue: Double = 0.0        // -1.0 to 1.0 (Shift)
    var saturation: Double = 0.0 // -1.0 to 1.0 (Add/Subtract)
    var lightness: Double = 0.0  // -1.0 to 1.0 (Add/Subtract)
    
    static let identity = HSLShift()
}
