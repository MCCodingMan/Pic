import Foundation

nonisolated struct Adjustments: Codable, Equatable, Hashable {
    // Light
    var exposure: Double = 0.0    // -2.0 to 2.0 EV
    var contrast: Double = 1.0    // 0.5 to 1.5
    var brightness: Double = 0.0  // -0.5 to 0.5
    var highlights: Double = 0.0  // -1.0 to 1.0 (negative = darken, positive = brighten)
    var shadows: Double = 0.0     // -1.0 to 1.0 (negative = darken, positive = brighten)
    
    // Color
    var saturation: Double = 1.0  // 0.0 to 2.0
    var warmth: Double = 0.0      // -1.0 (cool) to 1.0 (warm)
    var tint: Double = 0.0        // -1.0 (green) to 1.0 (magenta)
    
    // Detail
    var sharpen: Double = 0.0     // -1.0 to 2.0 (negative = blur/soften)
    var clarity: Double = 0.0     // -1.0 to 1.0 (negative = soften, positive = structure)
    
    // Effects
    var vignette: Double = 0.0    // 0.0 to 1.0
    var grain: Double = 0.0       // 0.0 to 1.0
    
    // HSL
    var hsl: [HSLChannel: HSLShift] = [:]
    
    // Curves
    var curve: Curve = .identity
    
    static let identity = Adjustments()

    /// 是否所有参数都为默认值
    nonisolated var isDefault: Bool {
        self == .identity
    }
}

enum AdjustmentType: String, CaseIterable, Identifiable {
    case exposure = "曝光"
    case contrast = "对比度"
    case brightness = "亮度"
    case saturation = "饱和度"
    case highlights = "高光"
    case shadows = "阴影"
    case sharpen = "锐化"
    case clarity = "清晰度"
    case vignette = "暗角"
    case grain = "颗粒"
    case warmth = "色温"
    case tint = "色调"
    
    var id: String { rawValue }
    
    var range: ClosedRange<Double> {
        switch self {
        case .exposure: return -2.0...2.0
        case .contrast: return 0.5...1.5
        case .brightness: return -0.5...0.5
        case .saturation: return 0.0...2.0
        case .highlights: return -1.0...1.0
        case .shadows: return -1.0...1.0
        case .sharpen: return -1.0...2.0
        case .clarity: return -1.0...1.0
        case .vignette: return 0.0...1.0
        case .grain: return 0.0...1.0
        case .warmth: return -1.0...1.0
        case .tint: return -1.0...1.0
        }
    }
    
    var defaultValue: Double {
        switch self {
        case .contrast, .saturation: return 1.0
        default: return 0.0
        }
    }

    var icon: String {
        switch self {
        case .exposure:   return "sun.max"
        case .contrast:   return "circle.lefthalf.filled"
        case .brightness: return "sun.min"
        case .highlights: return "sun.and.horizon"
        case .shadows:    return "moon"
        case .saturation: return "drop.fill"
        case .warmth:     return "thermometer.medium"
        case .tint:       return "paintpalette"
        case .sharpen:    return "triangle"
        case .clarity:    return "sparkles"
        case .vignette:   return "circle.dashed"
        case .grain:      return "aqi.medium"
        }
    }

    func getValue(from adjustments: Adjustments) -> Double {
        switch self {
        case .exposure:   return adjustments.exposure
        case .contrast:   return adjustments.contrast
        case .brightness: return adjustments.brightness
        case .highlights: return adjustments.highlights
        case .shadows:    return adjustments.shadows
        case .saturation: return adjustments.saturation
        case .warmth:     return adjustments.warmth
        case .tint:       return adjustments.tint
        case .sharpen:    return adjustments.sharpen
        case .clarity:    return adjustments.clarity
        case .vignette:   return adjustments.vignette
        case .grain:      return adjustments.grain
        }
    }

    func setValue(_ adjustments: inout Adjustments, _ value: Double) {
        switch self {
        case .exposure:   adjustments.exposure = value
        case .contrast:   adjustments.contrast = value
        case .brightness: adjustments.brightness = value
        case .highlights: adjustments.highlights = value
        case .shadows:    adjustments.shadows = value
        case .saturation: adjustments.saturation = value
        case .warmth:     adjustments.warmth = value
        case .tint:       adjustments.tint = value
        case .sharpen:    adjustments.sharpen = value
        case .clarity:    adjustments.clarity = value
        case .vignette:   adjustments.vignette = value
        case .grain:      adjustments.grain = value
        }
    }

    func isModified(in adjustments: Adjustments) -> Bool {
        abs(getValue(from: adjustments) - defaultValue) > 0.001
    }
}
