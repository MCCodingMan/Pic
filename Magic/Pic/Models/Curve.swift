import Foundation
import CoreGraphics

nonisolated struct Curve: Codable, Equatable, Hashable {
    // We use 5 control points for CIToneCurve
    // Default: (0,0), (0.25, 0.25), (0.5, 0.5), (0.75, 0.75), (1, 1)
    var points: [CGPoint]
    
    func hash(into hasher: inout Hasher) {
        for point in points {
            hasher.combine(point.x)
            hasher.combine(point.y)
        }
    }
    
    static let identity = Curve(points: [
        CGPoint(x: 0.0, y: 0.0),
        CGPoint(x: 0.25, y: 0.25),
        CGPoint(x: 0.5, y: 0.5),
        CGPoint(x: 0.75, y: 0.75),
        CGPoint(x: 1.0, y: 1.0)
    ])
}
