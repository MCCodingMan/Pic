import Foundation

enum AspectRatio: String, CaseIterable, Identifiable, Codable {
    case original = "原图"
    case square = "1:1"
    case fourToThree = "4:3"
    case threeToFour = "3:4"
    case sixteenToNine = "16:9"
    case nineToSixteen = "9:16"
    
    var id: String { rawValue }
    
    var ratio: Double? {
        switch self {
        case .original: return nil
        case .square: return 1.0
        case .fourToThree: return 4.0 / 3.0
        case .threeToFour: return 3.0 / 4.0
        case .sixteenToNine: return 16.0 / 9.0
        case .nineToSixteen: return 9.0 / 16.0
        }
    }
}
