import SwiftUI

struct CollageTemplateItem: Identifiable, Equatable {
    let id = UUID()
    let rect: CGRect // Normalized (0...1)
    let rotation: Double // Degrees
    let zIndex: Int
    
    static func create(x: Double, y: Double, w: Double, h: Double, r: Double = 0, z: Int = 0) -> CollageTemplateItem {
        CollageTemplateItem(rect: CGRect(x: x, y: y, width: w, height: h), rotation: r, zIndex: z)
    }
}

struct CollageTemplate: Identifiable, Equatable {
    let id: String
    let name: String
    let imageCount: Int
    let items: [CollageTemplateItem]
    
    var iconName: String {
        switch imageCount {
        case 2: return "rectangle.split.2x1"
        case 3: return "rectangle.split.3x1"
        case 4: return "square.grid.2x2"
        case 9: return "square.grid.3x3"
        default: return "square.grid.3x2"
        }
    }
}

class TemplateRepository {
    static let shared = TemplateRepository()
    
    private init() {}
    
    func getTemplates(for count: Int) -> [CollageTemplate] {
        allTemplates.filter { $0.imageCount == count }
    }
    
    // Expanded templates to ~20 per category
    private let allTemplates: [CollageTemplate] = [
        // MARK: - 2 Images (20 Styles)
        CollageTemplate(id: "2_1", name: "左右均分", imageCount: 2, items: [
            .create(x: 0, y: 0, w: 0.5, h: 1), .create(x: 0.5, y: 0, w: 0.5, h: 1)
        ]),
        CollageTemplate(id: "2_2", name: "上下均分", imageCount: 2, items: [
            .create(x: 0, y: 0, w: 1, h: 0.5), .create(x: 0, y: 0.5, w: 1, h: 0.5)
        ]),
        CollageTemplate(id: "2_3", name: "左窄右宽", imageCount: 2, items: [
            .create(x: 0, y: 0, w: 0.33, h: 1), .create(x: 0.33, y: 0, w: 0.67, h: 1)
        ]),
        CollageTemplate(id: "2_4", name: "左宽右窄", imageCount: 2, items: [
            .create(x: 0, y: 0, w: 0.67, h: 1), .create(x: 0.67, y: 0, w: 0.33, h: 1)
        ]),
        CollageTemplate(id: "2_5", name: "上窄下宽", imageCount: 2, items: [
            .create(x: 0, y: 0, w: 1, h: 0.33), .create(x: 0, y: 0.33, w: 1, h: 0.67)
        ]),
        CollageTemplate(id: "2_6", name: "上宽下窄", imageCount: 2, items: [
            .create(x: 0, y: 0, w: 1, h: 0.67), .create(x: 0, y: 0.67, w: 1, h: 0.33)
        ]),
        CollageTemplate(id: "2_7", name: "斜切布局", imageCount: 2, items: [ // Simulated via overlap/rotation
            .create(x: 0, y: 0, w: 0.7, h: 1, z: 0), .create(x: 0.4, y: 0.2, w: 0.6, h: 0.6, r: 15, z: 1)
        ]),
        CollageTemplate(id: "2_8", name: "画中画(右下)", imageCount: 2, items: [
            .create(x: 0, y: 0, w: 1, h: 1), .create(x: 0.6, y: 0.6, w: 0.35, h: 0.35, z: 1)
        ]),
        CollageTemplate(id: "2_9", name: "画中画(中心)", imageCount: 2, items: [
            .create(x: 0, y: 0, w: 1, h: 1), .create(x: 0.25, y: 0.25, w: 0.5, h: 0.5, z: 1)
        ]),
        CollageTemplate(id: "2_10", name: "拍立得(散落)", imageCount: 2, items: [
            .create(x: 0.1, y: 0.1, w: 0.5, h: 0.5, r: -10, z: 1), .create(x: 0.4, y: 0.4, w: 0.5, h: 0.5, r: 10, z: 2)
        ]),
        CollageTemplate(id: "2_11", name: "拍立得(叠放)", imageCount: 2, items: [
            .create(x: 0.15, y: 0.1, w: 0.7, h: 0.7, r: -5, z: 1), .create(x: 0.15, y: 0.2, w: 0.7, h: 0.7, r: 5, z: 2)
        ]),
        CollageTemplate(id: "2_12", name: "对角分布", imageCount: 2, items: [
            .create(x: 0, y: 0, w: 0.6, h: 0.6), .create(x: 0.4, y: 0.4, w: 0.6, h: 0.6)
        ]),
        CollageTemplate(id: "2_13", name: "垂直边框", imageCount: 2, items: [
            .create(x: 0.1, y: 0.05, w: 0.8, h: 0.4, z: 1), .create(x: 0.1, y: 0.55, w: 0.8, h: 0.4, z: 1)
        ]),
        CollageTemplate(id: "2_14", name: "水平边框", imageCount: 2, items: [
            .create(x: 0.05, y: 0.1, w: 0.4, h: 0.8, z: 1), .create(x: 0.55, y: 0.1, w: 0.4, h: 0.8, z: 1)
        ]),
        CollageTemplate(id: "2_15", name: "上下错位", imageCount: 2, items: [
            .create(x: 0, y: 0, w: 0.6, h: 0.5), .create(x: 0.4, y: 0.5, w: 0.6, h: 0.5)
        ]),
        CollageTemplate(id: "2_16", name: "左右错位", imageCount: 2, items: [
            .create(x: 0, y: 0, w: 0.5, h: 0.6), .create(x: 0.5, y: 0.4, w: 0.5, h: 0.6)
        ]),
        CollageTemplate(id: "2_17", name: "大图小图", imageCount: 2, items: [
            .create(x: 0, y: 0, w: 0.7, h: 0.7, z: 0), .create(x: 0.7, y: 0.7, w: 0.3, h: 0.3, z: 1)
        ]),
        CollageTemplate(id: "2_18", name: "中心对称", imageCount: 2, items: [
            .create(x: 0.2, y: 0.1, w: 0.6, h: 0.4), .create(x: 0.2, y: 0.5, w: 0.6, h: 0.4)
        ]),
        CollageTemplate(id: "2_19", name: "双旋转", imageCount: 2, items: [
            .create(x: 0.1, y: 0.1, w: 0.5, h: 0.8, r: -5), .create(x: 0.5, y: 0.1, w: 0.5, h: 0.8, r: 5)
        ]),
        CollageTemplate(id: "2_20", name: "自由叠加", imageCount: 2, items: [
            .create(x: 0.1, y: 0.1, w: 0.6, h: 0.6, z: 0), .create(x: 0.3, y: 0.3, w: 0.6, h: 0.6, z: 1)
        ]),

        // MARK: - 3 Images (20 Styles)
        CollageTemplate(id: "3_1", name: "三列均分", imageCount: 3, items: [
            .create(x: 0, y: 0, w: 0.333, h: 1), .create(x: 0.333, y: 0, w: 0.333, h: 1), .create(x: 0.666, y: 0, w: 0.334, h: 1)
        ]),
        CollageTemplate(id: "3_2", name: "三行均分", imageCount: 3, items: [
            .create(x: 0, y: 0, w: 1, h: 0.333), .create(x: 0, y: 0.333, w: 1, h: 0.333), .create(x: 0, y: 0.666, w: 1, h: 0.334)
        ]),
        CollageTemplate(id: "3_3", name: "左一右二", imageCount: 3, items: [
            .create(x: 0, y: 0, w: 0.5, h: 1), .create(x: 0.5, y: 0, w: 0.5, h: 0.5), .create(x: 0.5, y: 0.5, w: 0.5, h: 0.5)
        ]),
        CollageTemplate(id: "3_4", name: "右一左二", imageCount: 3, items: [
            .create(x: 0.5, y: 0, w: 0.5, h: 1), .create(x: 0, y: 0, w: 0.5, h: 0.5), .create(x: 0, y: 0.5, w: 0.5, h: 0.5)
        ]),
        CollageTemplate(id: "3_5", name: "上一下二", imageCount: 3, items: [
            .create(x: 0, y: 0, w: 1, h: 0.5), .create(x: 0, y: 0.5, w: 0.5, h: 0.5), .create(x: 0.5, y: 0.5, w: 0.5, h: 0.5)
        ]),
        CollageTemplate(id: "3_6", name: "下一上二", imageCount: 3, items: [
            .create(x: 0, y: 0.5, w: 1, h: 0.5), .create(x: 0, y: 0, w: 0.5, h: 0.5), .create(x: 0.5, y: 0, w: 0.5, h: 0.5)
        ]),
        CollageTemplate(id: "3_7", name: "T型布局", imageCount: 3, items: [
            .create(x: 0, y: 0, w: 1, h: 0.6), .create(x: 0, y: 0.6, w: 0.5, h: 0.4), .create(x: 0.5, y: 0.6, w: 0.5, h: 0.4)
        ]),
        CollageTemplate(id: "3_8", name: "逆T型", imageCount: 3, items: [
            .create(x: 0, y: 0.4, w: 1, h: 0.6), .create(x: 0, y: 0, w: 0.5, h: 0.4), .create(x: 0.5, y: 0, w: 0.5, h: 0.4)
        ]),
        CollageTemplate(id: "3_9", name: "左大右小", imageCount: 3, items: [
            .create(x: 0, y: 0, w: 0.66, h: 1), .create(x: 0.66, y: 0, w: 0.34, h: 0.5), .create(x: 0.66, y: 0.5, w: 0.34, h: 0.5)
        ]),
        CollageTemplate(id: "3_10", name: "右大左小", imageCount: 3, items: [
            .create(x: 0.34, y: 0, w: 0.66, h: 1), .create(x: 0, y: 0, w: 0.34, h: 0.5), .create(x: 0, y: 0.5, w: 0.34, h: 0.5)
        ]),
        CollageTemplate(id: "3_11", name: "阶梯分布", imageCount: 3, items: [
            .create(x: 0, y: 0, w: 0.5, h: 0.5), .create(x: 0.5, y: 0.25, w: 0.5, h: 0.5), .create(x: 0, y: 0.5, w: 0.5, h: 0.5)
        ]),
        CollageTemplate(id: "3_12", name: "中心环绕", imageCount: 3, items: [
            .create(x: 0.25, y: 0.25, w: 0.5, h: 0.5, z: 2), .create(x: 0, y: 0, w: 0.4, h: 0.4, z: 0), .create(x: 0.6, y: 0.6, w: 0.4, h: 0.4, z: 1)
        ]),
        CollageTemplate(id: "3_13", name: "散落重叠", imageCount: 3, items: [
            .create(x: 0.1, y: 0.1, w: 0.5, h: 0.5, r: -10, z: 0), .create(x: 0.4, y: 0.4, w: 0.5, h: 0.5, r: 10, z: 1), .create(x: 0.2, y: 0.6, w: 0.5, h: 0.3, z: 2)
        ]),
        CollageTemplate(id: "3_14", name: "横向拼接", imageCount: 3, items: [
            .create(x: 0, y: 0.1, w: 0.33, h: 0.8), .create(x: 0.33, y: 0.1, w: 0.33, h: 0.8), .create(x: 0.66, y: 0.1, w: 0.33, h: 0.8)
        ]),
        CollageTemplate(id: "3_15", name: "纵向拼接", imageCount: 3, items: [
            .create(x: 0.1, y: 0, w: 0.8, h: 0.33), .create(x: 0.1, y: 0.33, w: 0.8, h: 0.33), .create(x: 0.1, y: 0.66, w: 0.8, h: 0.33)
        ]),
        CollageTemplate(id: "3_16", name: "画中画双", imageCount: 3, items: [
            .create(x: 0, y: 0, w: 1, h: 1, z: 0), .create(x: 0.1, y: 0.1, w: 0.3, h: 0.3, z: 1), .create(x: 0.6, y: 0.6, w: 0.3, h: 0.3, z: 2)
        ]),
        CollageTemplate(id: "3_17", name: "品字布局", imageCount: 3, items: [
            .create(x: 0.25, y: 0, w: 0.5, h: 0.5), .create(x: 0, y: 0.5, w: 0.5, h: 0.5), .create(x: 0.5, y: 0.5, w: 0.5, h: 0.5)
        ]),
        CollageTemplate(id: "3_18", name: "倒品字", imageCount: 3, items: [
            .create(x: 0, y: 0, w: 0.5, h: 0.5), .create(x: 0.5, y: 0, w: 0.5, h: 0.5), .create(x: 0.25, y: 0.5, w: 0.5, h: 0.5)
        ]),
        CollageTemplate(id: "3_19", name: "斜向排列", imageCount: 3, items: [
            .create(x: 0, y: 0, w: 0.4, h: 0.4), .create(x: 0.3, y: 0.3, w: 0.4, h: 0.4), .create(x: 0.6, y: 0.6, w: 0.4, h: 0.4)
        ]),
        CollageTemplate(id: "3_20", name: "随意堆叠", imageCount: 3, items: [
            .create(x: 0.05, y: 0.05, w: 0.5, h: 0.5, r: -5, z: 0), .create(x: 0.45, y: 0.1, w: 0.5, h: 0.5, r: 5, z: 1), .create(x: 0.25, y: 0.5, w: 0.5, h: 0.4, z: 2)
        ]),

        // MARK: - 4 Images (20 Styles)
        CollageTemplate(id: "4_1", name: "田字格", imageCount: 4, items: [
            .create(x: 0, y: 0, w: 0.5, h: 0.5), .create(x: 0.5, y: 0, w: 0.5, h: 0.5),
            .create(x: 0, y: 0.5, w: 0.5, h: 0.5), .create(x: 0.5, y: 0.5, w: 0.5, h: 0.5)
        ]),
        CollageTemplate(id: "4_2", name: "四行均分", imageCount: 4, items: [
            .create(x: 0, y: 0, w: 1, h: 0.25), .create(x: 0, y: 0.25, w: 1, h: 0.25),
            .create(x: 0, y: 0.5, w: 1, h: 0.25), .create(x: 0, y: 0.75, w: 1, h: 0.25)
        ]),
        CollageTemplate(id: "4_3", name: "四列均分", imageCount: 4, items: [
            .create(x: 0, y: 0, w: 0.25, h: 1), .create(x: 0.25, y: 0, w: 0.25, h: 1),
            .create(x: 0.5, y: 0, w: 0.25, h: 1), .create(x: 0.75, y: 0, w: 0.25, h: 1)
        ]),
        CollageTemplate(id: "4_4", name: "左一右三", imageCount: 4, items: [
            .create(x: 0, y: 0, w: 0.5, h: 1), .create(x: 0.5, y: 0, w: 0.5, h: 0.33),
            .create(x: 0.5, y: 0.33, w: 0.5, h: 0.33), .create(x: 0.5, y: 0.66, w: 0.5, h: 0.34)
        ]),
        CollageTemplate(id: "4_5", name: "右一左三", imageCount: 4, items: [
            .create(x: 0.5, y: 0, w: 0.5, h: 1), .create(x: 0, y: 0, w: 0.5, h: 0.33),
            .create(x: 0, y: 0.33, w: 0.5, h: 0.33), .create(x: 0, y: 0.66, w: 0.5, h: 0.34)
        ]),
        CollageTemplate(id: "4_6", name: "上一下三", imageCount: 4, items: [
            .create(x: 0, y: 0, w: 1, h: 0.5), .create(x: 0, y: 0.5, w: 0.33, h: 0.5),
            .create(x: 0.33, y: 0.5, w: 0.33, h: 0.5), .create(x: 0.66, y: 0.5, w: 0.34, h: 0.5)
        ]),
        CollageTemplate(id: "4_7", name: "下一上三", imageCount: 4, items: [
            .create(x: 0, y: 0.5, w: 1, h: 0.5), .create(x: 0, y: 0, w: 0.33, h: 0.5),
            .create(x: 0.33, y: 0, w: 0.33, h: 0.5), .create(x: 0.66, y: 0, w: 0.34, h: 0.5)
        ]),
        CollageTemplate(id: "4_8", name: "中心环绕", imageCount: 4, items: [
            .create(x: 0.2, y: 0.2, w: 0.6, h: 0.6, z: 3), .create(x: 0, y: 0, w: 0.3, h: 0.3, z: 0),
            .create(x: 0.7, y: 0, w: 0.3, h: 0.3, z: 1), .create(x: 0.35, y: 0.8, w: 0.3, h: 0.2, z: 2)
        ]),
        CollageTemplate(id: "4_9", name: "菱形布局", imageCount: 4, items: [
            .create(x: 0.25, y: 0, w: 0.5, h: 0.5), .create(x: 0, y: 0.25, w: 0.5, h: 0.5),
            .create(x: 0.5, y: 0.25, w: 0.5, h: 0.5), .create(x: 0.25, y: 0.5, w: 0.5, h: 0.5)
        ]),
        CollageTemplate(id: "4_10", name: "交错排列", imageCount: 4, items: [
            .create(x: 0, y: 0, w: 0.6, h: 0.4), .create(x: 0.4, y: 0.2, w: 0.6, h: 0.4),
            .create(x: 0, y: 0.4, w: 0.6, h: 0.4), .create(x: 0.4, y: 0.6, w: 0.6, h: 0.4)
        ]),
        CollageTemplate(id: "4_11", name: "大图带三小", imageCount: 4, items: [
            .create(x: 0, y: 0, w: 0.75, h: 0.75), .create(x: 0.75, y: 0, w: 0.25, h: 0.25),
            .create(x: 0.75, y: 0.25, w: 0.25, h: 0.25), .create(x: 0.75, y: 0.5, w: 0.25, h: 0.25)
        ]),
        CollageTemplate(id: "4_12", name: "四角对峙", imageCount: 4, items: [
            .create(x: 0, y: 0, w: 0.45, h: 0.45), .create(x: 0.55, y: 0, w: 0.45, h: 0.45),
            .create(x: 0, y: 0.55, w: 0.45, h: 0.45), .create(x: 0.55, y: 0.55, w: 0.45, h: 0.45)
        ]),
        CollageTemplate(id: "4_13", name: "垂直长条", imageCount: 4, items: [
            .create(x: 0.05, y: 0, w: 0.2, h: 1), .create(x: 0.3, y: 0, w: 0.2, h: 1),
            .create(x: 0.55, y: 0, w: 0.2, h: 1), .create(x: 0.8, y: 0, w: 0.2, h: 1)
        ]),
        CollageTemplate(id: "4_14", name: "水平长条", imageCount: 4, items: [
            .create(x: 0, y: 0.05, w: 1, h: 0.2), .create(x: 0, y: 0.3, w: 1, h: 0.2),
            .create(x: 0, y: 0.55, w: 1, h: 0.2), .create(x: 0, y: 0.8, w: 1, h: 0.2)
        ]),
        CollageTemplate(id: "4_15", name: "风车布局", imageCount: 4, items: [
            .create(x: 0, y: 0, w: 0.6, h: 0.4), .create(x: 0.6, y: 0, w: 0.4, h: 0.6),
            .create(x: 0.4, y: 0.4, w: 0.6, h: 0.4), .create(x: 0, y: 0.6, w: 0.4, h: 0.6)
        ]),
        CollageTemplate(id: "4_16", name: "画中画四", imageCount: 4, items: [
            .create(x: 0, y: 0, w: 1, h: 1, z: 0), .create(x: 0.1, y: 0.1, w: 0.25, h: 0.25, z: 1),
            .create(x: 0.65, y: 0.1, w: 0.25, h: 0.25, z: 2), .create(x: 0.35, y: 0.65, w: 0.3, h: 0.3, z: 3)
        ]),
        CollageTemplate(id: "4_17", name: "对称分布", imageCount: 4, items: [
            .create(x: 0.1, y: 0.1, w: 0.35, h: 0.35), .create(x: 0.55, y: 0.1, w: 0.35, h: 0.35),
            .create(x: 0.1, y: 0.55, w: 0.35, h: 0.35), .create(x: 0.55, y: 0.55, w: 0.35, h: 0.35)
        ]),
        CollageTemplate(id: "4_18", name: "中心重叠", imageCount: 4, items: [
            .create(x: 0, y: 0, w: 0.55, h: 0.55, z: 0), .create(x: 0.45, y: 0, w: 0.55, h: 0.55, z: 1),
            .create(x: 0, y: 0.45, w: 0.55, h: 0.55, z: 2), .create(x: 0.45, y: 0.45, w: 0.55, h: 0.55, z: 3)
        ]),
        CollageTemplate(id: "4_19", name: "散落拍立得", imageCount: 4, items: [
            .create(x: 0.05, y: 0.05, w: 0.45, h: 0.45, r: -5, z: 0), .create(x: 0.5, y: 0.05, w: 0.45, h: 0.45, r: 5, z: 1),
            .create(x: 0.05, y: 0.5, w: 0.45, h: 0.45, r: 5, z: 2), .create(x: 0.5, y: 0.5, w: 0.45, h: 0.45, r: -5, z: 3)
        ]),
        CollageTemplate(id: "4_20", name: "阶梯四图", imageCount: 4, items: [
            .create(x: 0, y: 0, w: 0.4, h: 0.4), .create(x: 0.2, y: 0.2, w: 0.4, h: 0.4, z: 1),
            .create(x: 0.4, y: 0.4, w: 0.4, h: 0.4, z: 2), .create(x: 0.6, y: 0.6, w: 0.4, h: 0.4, z: 3)
        ]),

        // MARK: - 5 Images (20 Styles)
        CollageTemplate(id: "5_1", name: "五格中心", imageCount: 5, items: [
            .create(x: 0.25, y: 0.25, w: 0.5, h: 0.5, z: 4),
            .create(x: 0, y: 0, w: 0.25, h: 0.25), .create(x: 0.75, y: 0, w: 0.25, h: 0.25),
            .create(x: 0, y: 0.75, w: 0.25, h: 0.25), .create(x: 0.75, y: 0.75, w: 0.25, h: 0.25)
        ]),
        CollageTemplate(id: "5_2", name: "左一右四", imageCount: 5, items: [
            .create(x: 0, y: 0, w: 0.5, h: 1), .create(x: 0.5, y: 0, w: 0.5, h: 0.25),
            .create(x: 0.5, y: 0.25, w: 0.5, h: 0.25), .create(x: 0.5, y: 0.5, w: 0.5, h: 0.25),
            .create(x: 0.5, y: 0.75, w: 0.5, h: 0.25)
        ]),
        CollageTemplate(id: "5_3", name: "右一左四", imageCount: 5, items: [
            .create(x: 0.5, y: 0, w: 0.5, h: 1), .create(x: 0, y: 0, w: 0.5, h: 0.25),
            .create(x: 0, y: 0.25, w: 0.5, h: 0.25), .create(x: 0, y: 0.5, w: 0.5, h: 0.25),
            .create(x: 0, y: 0.75, w: 0.5, h: 0.25)
        ]),
        CollageTemplate(id: "5_4", name: "上一下四", imageCount: 5, items: [
            .create(x: 0, y: 0, w: 1, h: 0.5), .create(x: 0, y: 0.5, w: 0.25, h: 0.5),
            .create(x: 0.25, y: 0.5, w: 0.25, h: 0.5), .create(x: 0.5, y: 0.5, w: 0.25, h: 0.5),
            .create(x: 0.75, y: 0.5, w: 0.25, h: 0.5)
        ]),
        CollageTemplate(id: "5_5", name: "下一上四", imageCount: 5, items: [
            .create(x: 0, y: 0.5, w: 1, h: 0.5), .create(x: 0, y: 0, w: 0.25, h: 0.5),
            .create(x: 0.25, y: 0, w: 0.25, h: 0.5), .create(x: 0.5, y: 0, w: 0.25, h: 0.5),
            .create(x: 0.75, y: 0, w: 0.25, h: 0.5)
        ]),
        CollageTemplate(id: "5_6", name: "H型布局", imageCount: 5, items: [
            .create(x: 0, y: 0, w: 0.33, h: 1), .create(x: 0.67, y: 0, w: 0.33, h: 1),
            .create(x: 0.33, y: 0, w: 0.34, h: 0.33), .create(x: 0.33, y: 0.33, w: 0.34, h: 0.34),
            .create(x: 0.33, y: 0.67, w: 0.34, h: 0.33)
        ]),
        CollageTemplate(id: "5_7", name: "五图拼接", imageCount: 5, items: [
            .create(x: 0, y: 0, w: 0.5, h: 0.6), .create(x: 0.5, y: 0, w: 0.5, h: 0.6),
            .create(x: 0, y: 0.6, w: 0.33, h: 0.4), .create(x: 0.33, y: 0.6, w: 0.34, h: 0.4),
            .create(x: 0.67, y: 0.6, w: 0.33, h: 0.4)
        ]),
        CollageTemplate(id: "5_8", name: "倒五图拼接", imageCount: 5, items: [
            .create(x: 0, y: 0.4, w: 0.5, h: 0.6), .create(x: 0.5, y: 0.4, w: 0.5, h: 0.6),
            .create(x: 0, y: 0, w: 0.33, h: 0.4), .create(x: 0.33, y: 0, w: 0.34, h: 0.4),
            .create(x: 0.67, y: 0, w: 0.33, h: 0.4)
        ]),
        CollageTemplate(id: "5_9", name: "左二右三", imageCount: 5, items: [
            .create(x: 0, y: 0, w: 0.4, h: 0.5), .create(x: 0, y: 0.5, w: 0.4, h: 0.5),
            .create(x: 0.4, y: 0, w: 0.6, h: 0.33), .create(x: 0.4, y: 0.33, w: 0.6, h: 0.33),
            .create(x: 0.4, y: 0.66, w: 0.6, h: 0.34)
        ]),
        CollageTemplate(id: "5_10", name: "左三右二", imageCount: 5, items: [
            .create(x: 0.6, y: 0, w: 0.4, h: 0.5), .create(x: 0.6, y: 0.5, w: 0.4, h: 0.5),
            .create(x: 0, y: 0, w: 0.6, h: 0.33), .create(x: 0, y: 0.33, w: 0.6, h: 0.33),
            .create(x: 0, y: 0.66, w: 0.6, h: 0.34)
        ]),
        CollageTemplate(id: "5_11", name: "中心十字", imageCount: 5, items: [
            .create(x: 0.33, y: 0, w: 0.34, h: 0.33), .create(x: 0, y: 0.33, w: 0.33, h: 0.34),
            .create(x: 0.33, y: 0.33, w: 0.34, h: 0.34), .create(x: 0.67, y: 0.33, w: 0.33, h: 0.34),
            .create(x: 0.33, y: 0.67, w: 0.34, h: 0.33)
        ]),
        CollageTemplate(id: "5_12", name: "五行均分", imageCount: 5, items: [
            .create(x: 0, y: 0, w: 1, h: 0.2), .create(x: 0, y: 0.2, w: 1, h: 0.2),
            .create(x: 0, y: 0.4, w: 1, h: 0.2), .create(x: 0, y: 0.6, w: 1, h: 0.2),
            .create(x: 0, y: 0.8, w: 1, h: 0.2)
        ]),
        CollageTemplate(id: "5_13", name: "五列均分", imageCount: 5, items: [
            .create(x: 0, y: 0, w: 0.2, h: 1), .create(x: 0.2, y: 0, w: 0.2, h: 1),
            .create(x: 0.4, y: 0, w: 0.2, h: 1), .create(x: 0.6, y: 0, w: 0.2, h: 1),
            .create(x: 0.8, y: 0, w: 0.2, h: 1)
        ]),
        CollageTemplate(id: "5_14", name: "螺旋五图", imageCount: 5, items: [
            .create(x: 0, y: 0, w: 0.5, h: 0.5), .create(x: 0.5, y: 0, w: 0.5, h: 0.5),
            .create(x: 0.5, y: 0.5, w: 0.5, h: 0.25), .create(x: 0.5, y: 0.75, w: 0.5, h: 0.25),
            .create(x: 0, y: 0.5, w: 0.5, h: 0.5)
        ]),
        CollageTemplate(id: "5_15", name: "画中画五", imageCount: 5, items: [
            .create(x: 0, y: 0, w: 1, h: 1, z: 0), .create(x: 0.1, y: 0.1, w: 0.2, h: 0.2, z: 1),
            .create(x: 0.7, y: 0.1, w: 0.2, h: 0.2, z: 2), .create(x: 0.1, y: 0.7, w: 0.2, h: 0.2, z: 3),
            .create(x: 0.7, y: 0.7, w: 0.2, h: 0.2, z: 4)
        ]),
        CollageTemplate(id: "5_16", name: "不规则五", imageCount: 5, items: [
            .create(x: 0, y: 0, w: 0.4, h: 0.4), .create(x: 0.4, y: 0, w: 0.6, h: 0.6),
            .create(x: 0, y: 0.4, w: 0.4, h: 0.6), .create(x: 0.4, y: 0.6, w: 0.3, h: 0.4),
            .create(x: 0.7, y: 0.6, w: 0.3, h: 0.4)
        ]),
        CollageTemplate(id: "5_17", name: "交错五图", imageCount: 5, items: [
            .create(x: 0, y: 0, w: 0.5, h: 0.4), .create(x: 0.5, y: 0, w: 0.5, h: 0.4),
            .create(x: 0, y: 0.4, w: 0.33, h: 0.6), .create(x: 0.33, y: 0.4, w: 0.34, h: 0.6),
            .create(x: 0.67, y: 0.4, w: 0.33, h: 0.6)
        ]),
        CollageTemplate(id: "5_18", name: "散落五张", imageCount: 5, items: [
            .create(x: 0.1, y: 0.1, w: 0.4, h: 0.4, r: -5, z: 0), .create(x: 0.5, y: 0.1, w: 0.4, h: 0.4, r: 5, z: 1),
            .create(x: 0.1, y: 0.5, w: 0.4, h: 0.4, r: 5, z: 2), .create(x: 0.5, y: 0.5, w: 0.4, h: 0.4, r: -5, z: 3),
            .create(x: 0.3, y: 0.3, w: 0.4, h: 0.4, r: 0, z: 4)
        ]),
        CollageTemplate(id: "5_19", name: "中心带四边", imageCount: 5, items: [
            .create(x: 0.2, y: 0.2, w: 0.6, h: 0.6, z: 4),
            .create(x: 0, y: 0, w: 1, h: 0.2, z: 0), .create(x: 0, y: 0.8, w: 1, h: 0.2, z: 1),
            .create(x: 0, y: 0.2, w: 0.2, h: 0.6, z: 2), .create(x: 0.8, y: 0.2, w: 0.2, h: 0.6, z: 3)
        ]),
        CollageTemplate(id: "5_20", name: "阶梯五图", imageCount: 5, items: [
            .create(x: 0, y: 0, w: 0.3, h: 0.3), .create(x: 0.2, y: 0.2, w: 0.3, h: 0.3, z: 1),
            .create(x: 0.4, y: 0.4, w: 0.3, h: 0.3, z: 2), .create(x: 0.6, y: 0.6, w: 0.3, h: 0.3, z: 3),
            .create(x: 0.7, y: 0.7, w: 0.3, h: 0.3, z: 4)
        ]),

        // MARK: - 6 Images (20 Styles)
        CollageTemplate(id: "6_1", name: "2x3网格", imageCount: 6, items: [
            .create(x: 0, y: 0, w: 0.5, h: 0.333), .create(x: 0.5, y: 0, w: 0.5, h: 0.333),
            .create(x: 0, y: 0.333, w: 0.5, h: 0.333), .create(x: 0.5, y: 0.333, w: 0.5, h: 0.333),
            .create(x: 0, y: 0.666, w: 0.5, h: 0.334), .create(x: 0.5, y: 0.666, w: 0.5, h: 0.334)
        ]),
        CollageTemplate(id: "6_2", name: "3x2网格", imageCount: 6, items: [
            .create(x: 0, y: 0, w: 0.333, h: 0.5), .create(x: 0.333, y: 0, w: 0.333, h: 0.5), .create(x: 0.666, y: 0, w: 0.334, h: 0.5),
            .create(x: 0, y: 0.5, w: 0.333, h: 0.5), .create(x: 0.333, y: 0.5, w: 0.333, h: 0.5), .create(x: 0.666, y: 0.5, w: 0.334, h: 0.5)
        ]),
        CollageTemplate(id: "6_3", name: "左一右五", imageCount: 6, items: [
            .create(x: 0, y: 0, w: 0.5, h: 1),
            .create(x: 0.5, y: 0, w: 0.5, h: 0.2), .create(x: 0.5, y: 0.2, w: 0.5, h: 0.2),
            .create(x: 0.5, y: 0.4, w: 0.5, h: 0.2), .create(x: 0.5, y: 0.6, w: 0.5, h: 0.2),
            .create(x: 0.5, y: 0.8, w: 0.5, h: 0.2)
        ]),
        CollageTemplate(id: "6_4", name: "右一左五", imageCount: 6, items: [
            .create(x: 0.5, y: 0, w: 0.5, h: 1),
            .create(x: 0, y: 0, w: 0.5, h: 0.2), .create(x: 0, y: 0.2, w: 0.5, h: 0.2),
            .create(x: 0, y: 0.4, w: 0.5, h: 0.2), .create(x: 0, y: 0.6, w: 0.5, h: 0.2),
            .create(x: 0, y: 0.8, w: 0.5, h: 0.2)
        ]),
        CollageTemplate(id: "6_5", name: "上一下五", imageCount: 6, items: [
            .create(x: 0, y: 0, w: 1, h: 0.5),
            .create(x: 0, y: 0.5, w: 0.2, h: 0.5), .create(x: 0.2, y: 0.5, w: 0.2, h: 0.5),
            .create(x: 0.4, y: 0.5, w: 0.2, h: 0.5), .create(x: 0.6, y: 0.5, w: 0.2, h: 0.5),
            .create(x: 0.8, y: 0.5, w: 0.2, h: 0.5)
        ]),
        CollageTemplate(id: "6_6", name: "下一上五", imageCount: 6, items: [
            .create(x: 0, y: 0.5, w: 1, h: 0.5),
            .create(x: 0, y: 0, w: 0.2, h: 0.5), .create(x: 0.2, y: 0, w: 0.2, h: 0.5),
            .create(x: 0.4, y: 0, w: 0.2, h: 0.5), .create(x: 0.6, y: 0, w: 0.2, h: 0.5),
            .create(x: 0.8, y: 0, w: 0.2, h: 0.5)
        ]),
        CollageTemplate(id: "6_7", name: "大图围小图", imageCount: 6, items: [
            .create(x: 0, y: 0, w: 0.66, h: 0.66),
            .create(x: 0.66, y: 0, w: 0.34, h: 0.33), .create(x: 0.66, y: 0.33, w: 0.34, h: 0.33),
            .create(x: 0.66, y: 0.66, w: 0.34, h: 0.34), .create(x: 0.33, y: 0.66, w: 0.33, h: 0.34),
            .create(x: 0, y: 0.66, w: 0.33, h: 0.34)
        ]),
        CollageTemplate(id: "6_8", name: "六图拼接(2+4)", imageCount: 6, items: [
            .create(x: 0, y: 0, w: 0.5, h: 0.5), .create(x: 0.5, y: 0, w: 0.5, h: 0.5),
            .create(x: 0, y: 0.5, w: 0.25, h: 0.5), .create(x: 0.25, y: 0.5, w: 0.25, h: 0.5),
            .create(x: 0.5, y: 0.5, w: 0.25, h: 0.5), .create(x: 0.75, y: 0.5, w: 0.25, h: 0.5)
        ]),
        CollageTemplate(id: "6_9", name: "六图拼接(4+2)", imageCount: 6, items: [
            .create(x: 0, y: 0, w: 0.25, h: 0.5), .create(x: 0.25, y: 0, w: 0.25, h: 0.5),
            .create(x: 0.5, y: 0, w: 0.25, h: 0.5), .create(x: 0.75, y: 0, w: 0.25, h: 0.5),
            .create(x: 0, y: 0.5, w: 0.5, h: 0.5), .create(x: 0.5, y: 0.5, w: 0.5, h: 0.5)
        ]),
        CollageTemplate(id: "6_10", name: "中心四图", imageCount: 6, items: [
            .create(x: 0, y: 0, w: 1, h: 0.33),
            .create(x: 0, y: 0.33, w: 0.25, h: 0.34), .create(x: 0.25, y: 0.33, w: 0.25, h: 0.34),
            .create(x: 0.5, y: 0.33, w: 0.25, h: 0.34), .create(x: 0.75, y: 0.33, w: 0.25, h: 0.34),
            .create(x: 0, y: 0.67, w: 1, h: 0.33)
        ]),
        CollageTemplate(id: "6_11", name: "左两列", imageCount: 6, items: [
            .create(x: 0, y: 0, w: 0.5, h: 0.33), .create(x: 0.5, y: 0, w: 0.5, h: 0.33),
            .create(x: 0, y: 0.33, w: 0.5, h: 0.33), .create(x: 0.5, y: 0.33, w: 0.5, h: 0.33),
            .create(x: 0, y: 0.66, w: 0.5, h: 0.34), .create(x: 0.5, y: 0.66, w: 0.5, h: 0.34)
        ]),
        CollageTemplate(id: "6_12", name: "不规则六", imageCount: 6, items: [
            .create(x: 0, y: 0, w: 0.5, h: 0.4), .create(x: 0.5, y: 0, w: 0.5, h: 0.6),
            .create(x: 0, y: 0.4, w: 0.5, h: 0.3), .create(x: 0.5, y: 0.6, w: 0.5, h: 0.4),
            .create(x: 0, y: 0.7, w: 0.25, h: 0.3), .create(x: 0.25, y: 0.7, w: 0.25, h: 0.3)
        ]),
        CollageTemplate(id: "6_13", name: "六列均分", imageCount: 6, items: [
            .create(x: 0, y: 0, w: 0.166, h: 1), .create(x: 0.166, y: 0, w: 0.166, h: 1),
            .create(x: 0.332, y: 0, w: 0.166, h: 1), .create(x: 0.498, y: 0, w: 0.166, h: 1),
            .create(x: 0.664, y: 0, w: 0.166, h: 1), .create(x: 0.83, y: 0, w: 0.17, h: 1)
        ]),
        CollageTemplate(id: "6_14", name: "六行均分", imageCount: 6, items: [
            .create(x: 0, y: 0, w: 1, h: 0.166), .create(x: 0, y: 0.166, w: 1, h: 0.166),
            .create(x: 0, y: 0.332, w: 1, h: 0.166), .create(x: 0, y: 0.498, w: 1, h: 0.166),
            .create(x: 0, y: 0.664, w: 1, h: 0.166), .create(x: 0, y: 0.83, w: 1, h: 0.17)
        ]),
        CollageTemplate(id: "6_15", name: "随机散落", imageCount: 6, items: [
            .create(x: 0.05, y: 0.05, w: 0.4, h: 0.4, r: -5, z: 0), .create(x: 0.55, y: 0.05, w: 0.4, h: 0.4, r: 5, z: 1),
            .create(x: 0.05, y: 0.35, w: 0.4, h: 0.4, r: 5, z: 2), .create(x: 0.55, y: 0.35, w: 0.4, h: 0.4, r: -5, z: 3),
            .create(x: 0.05, y: 0.65, w: 0.4, h: 0.3, r: -5, z: 4), .create(x: 0.55, y: 0.65, w: 0.4, h: 0.3, r: 5, z: 5)
        ]),
        CollageTemplate(id: "6_16", name: "中心堆叠", imageCount: 6, items: [
            .create(x: 0.1, y: 0.1, w: 0.4, h: 0.4, z: 0), .create(x: 0.5, y: 0.1, w: 0.4, h: 0.4, z: 1),
            .create(x: 0.1, y: 0.5, w: 0.4, h: 0.4, z: 2), .create(x: 0.5, y: 0.5, w: 0.4, h: 0.4, z: 3),
            .create(x: 0.3, y: 0.3, w: 0.4, h: 0.4, z: 4), .create(x: 0.3, y: 0.3, w: 0.4, h: 0.4, r: 45, z: 5)
        ]),
        CollageTemplate(id: "6_17", name: "画中画六", imageCount: 6, items: [
            .create(x: 0, y: 0, w: 1, h: 1, z: 0),
            .create(x: 0.1, y: 0.1, w: 0.2, h: 0.2, z: 1), .create(x: 0.7, y: 0.1, w: 0.2, h: 0.2, z: 2),
            .create(x: 0.1, y: 0.7, w: 0.2, h: 0.2, z: 3), .create(x: 0.7, y: 0.7, w: 0.2, h: 0.2, z: 4),
            .create(x: 0.4, y: 0.4, w: 0.2, h: 0.2, z: 5)
        ]),
        CollageTemplate(id: "6_18", name: "对称阶梯", imageCount: 6, items: [
            .create(x: 0, y: 0, w: 0.33, h: 0.33), .create(x: 0.67, y: 0, w: 0.33, h: 0.33),
            .create(x: 0.16, y: 0.33, w: 0.33, h: 0.33), .create(x: 0.51, y: 0.33, w: 0.33, h: 0.33),
            .create(x: 0, y: 0.66, w: 0.33, h: 0.34), .create(x: 0.67, y: 0.66, w: 0.33, h: 0.34)
        ]),
        CollageTemplate(id: "6_19", name: "三角排列", imageCount: 6, items: [
            .create(x: 0.33, y: 0, w: 0.34, h: 0.33),
            .create(x: 0.16, y: 0.33, w: 0.34, h: 0.33), .create(x: 0.5, y: 0.33, w: 0.34, h: 0.33),
            .create(x: 0, y: 0.66, w: 0.33, h: 0.34), .create(x: 0.33, y: 0.66, w: 0.34, h: 0.34), .create(x: 0.67, y: 0.66, w: 0.33, h: 0.34)
        ]),
        CollageTemplate(id: "6_20", name: "六边形模拟", imageCount: 6, items: [
            .create(x: 0.25, y: 0, w: 0.5, h: 0.33),
            .create(x: 0, y: 0.33, w: 0.5, h: 0.33), .create(x: 0.5, y: 0.33, w: 0.5, h: 0.33),
            .create(x: 0, y: 0.66, w: 0.5, h: 0.34), .create(x: 0.5, y: 0.66, w: 0.5, h: 0.34),
            .create(x: 0.25, y: 0.66, w: 0.5, h: 0.34) // Overlaps bottom center
        ]),

        // MARK: - 9 Images (20 Styles)
        CollageTemplate(id: "9_1", name: "九宫格", imageCount: 9, items: [
            .create(x: 0, y: 0, w: 0.333, h: 0.333), .create(x: 0.333, y: 0, w: 0.333, h: 0.333), .create(x: 0.666, y: 0, w: 0.334, h: 0.333),
            .create(x: 0, y: 0.333, w: 0.333, h: 0.333), .create(x: 0.333, y: 0.333, w: 0.333, h: 0.333), .create(x: 0.666, y: 0.333, w: 0.334, h: 0.333),
            .create(x: 0, y: 0.666, w: 0.333, h: 0.334), .create(x: 0.333, y: 0.666, w: 0.333, h: 0.334), .create(x: 0.666, y: 0.666, w: 0.334, h: 0.334)
        ]),
        CollageTemplate(id: "9_2", name: "中心突出", imageCount: 9, items: [
            .create(x: 0.333, y: 0.333, w: 0.333, h: 0.333, z: 8), // Center on top
            .create(x: 0, y: 0, w: 0.333, h: 0.333), .create(x: 0.333, y: 0, w: 0.333, h: 0.333), .create(x: 0.666, y: 0, w: 0.334, h: 0.333),
            .create(x: 0, y: 0.333, w: 0.333, h: 0.333), .create(x: 0.666, y: 0.333, w: 0.334, h: 0.333),
            .create(x: 0, y: 0.666, w: 0.333, h: 0.334), .create(x: 0.333, y: 0.666, w: 0.333, h: 0.334), .create(x: 0.666, y: 0.666, w: 0.334, h: 0.334)
        ]),
        CollageTemplate(id: "9_3", name: "大图居中", imageCount: 9, items: [
            .create(x: 0.33, y: 0.33, w: 0.34, h: 0.34, z: 8), // Center
            .create(x: 0, y: 0, w: 0.33, h: 0.33), .create(x: 0.33, y: 0, w: 0.34, h: 0.33), .create(x: 0.67, y: 0, w: 0.33, h: 0.33),
            .create(x: 0, y: 0.33, w: 0.33, h: 0.34), .create(x: 0.67, y: 0.33, w: 0.33, h: 0.34),
            .create(x: 0, y: 0.67, w: 0.33, h: 0.33), .create(x: 0.33, y: 0.67, w: 0.34, h: 0.33), .create(x: 0.67, y: 0.67, w: 0.33, h: 0.33)
        ]),
        CollageTemplate(id: "9_4", name: "3x3变体", imageCount: 9, items: [
            .create(x: 0, y: 0, w: 0.5, h: 0.33), .create(x: 0.5, y: 0, w: 0.5, h: 0.33),
            .create(x: 0, y: 0.33, w: 0.25, h: 0.33), .create(x: 0.25, y: 0.33, w: 0.25, h: 0.33), .create(x: 0.5, y: 0.33, w: 0.25, h: 0.33), .create(x: 0.75, y: 0.33, w: 0.25, h: 0.33),
            .create(x: 0, y: 0.66, w: 0.33, h: 0.34), .create(x: 0.33, y: 0.66, w: 0.33, h: 0.34), .create(x: 0.66, y: 0.66, w: 0.34, h: 0.34)
        ]),
        CollageTemplate(id: "9_5", name: "横向条纹", imageCount: 9, items: [
            .create(x: 0, y: 0, w: 1, h: 0.11), .create(x: 0, y: 0.11, w: 1, h: 0.11), .create(x: 0, y: 0.22, w: 1, h: 0.11),
            .create(x: 0, y: 0.33, w: 1, h: 0.11), .create(x: 0, y: 0.44, w: 1, h: 0.11), .create(x: 0, y: 0.55, w: 1, h: 0.11),
            .create(x: 0, y: 0.66, w: 1, h: 0.11), .create(x: 0, y: 0.77, w: 1, h: 0.11), .create(x: 0, y: 0.88, w: 1, h: 0.12)
        ]),
        CollageTemplate(id: "9_6", name: "纵向条纹", imageCount: 9, items: [
            .create(x: 0, y: 0, w: 0.11, h: 1), .create(x: 0.11, y: 0, w: 0.11, h: 1), .create(x: 0.22, y: 0, w: 0.11, h: 1),
            .create(x: 0.33, y: 0, w: 0.11, h: 1), .create(x: 0.44, y: 0, w: 0.11, h: 1), .create(x: 0.55, y: 0, w: 0.11, h: 1),
            .create(x: 0.66, y: 0, w: 0.11, h: 1), .create(x: 0.77, y: 0, w: 0.11, h: 1), .create(x: 0.88, y: 0, w: 0.12, h: 1)
        ]),
        CollageTemplate(id: "9_7", name: "四周环绕", imageCount: 9, items: [
            .create(x: 0.2, y: 0.2, w: 0.6, h: 0.6, z: 8),
            .create(x: 0, y: 0, w: 0.2, h: 0.2), .create(x: 0.4, y: 0, w: 0.2, h: 0.2), .create(x: 0.8, y: 0, w: 0.2, h: 0.2),
            .create(x: 0, y: 0.4, w: 0.2, h: 0.2), .create(x: 0.8, y: 0.4, w: 0.2, h: 0.2),
            .create(x: 0, y: 0.8, w: 0.2, h: 0.2), .create(x: 0.4, y: 0.8, w: 0.2, h: 0.2), .create(x: 0.8, y: 0.8, w: 0.2, h: 0.2)
        ]),
        CollageTemplate(id: "9_8", name: "散落九张", imageCount: 9, items: [
            .create(x: 0, y: 0, w: 0.33, h: 0.33, r: -5), .create(x: 0.33, y: 0, w: 0.33, h: 0.33, r: 5), .create(x: 0.66, y: 0, w: 0.33, h: 0.33, r: -5),
            .create(x: 0, y: 0.33, w: 0.33, h: 0.33, r: 5), .create(x: 0.33, y: 0.33, w: 0.33, h: 0.33, r: 0), .create(x: 0.66, y: 0.33, w: 0.33, h: 0.33, r: -5),
            .create(x: 0, y: 0.66, w: 0.33, h: 0.33, r: -5), .create(x: 0.33, y: 0.66, w: 0.33, h: 0.33, r: 5), .create(x: 0.66, y: 0.66, w: 0.33, h: 0.33, r: 5)
        ]),
        CollageTemplate(id: "9_9", name: "九宫菱形", imageCount: 9, items: [
            .create(x: 0.33, y: 0, w: 0.33, h: 0.33),
            .create(x: 0.16, y: 0.16, w: 0.33, h: 0.33), .create(x: 0.5, y: 0.16, w: 0.33, h: 0.33),
            .create(x: 0, y: 0.33, w: 0.33, h: 0.33), .create(x: 0.33, y: 0.33, w: 0.33, h: 0.33), .create(x: 0.66, y: 0.33, w: 0.33, h: 0.33),
            .create(x: 0.16, y: 0.5, w: 0.33, h: 0.33), .create(x: 0.5, y: 0.5, w: 0.33, h: 0.33),
            .create(x: 0.33, y: 0.66, w: 0.33, h: 0.33)
        ]),
        CollageTemplate(id: "9_10", name: "不规则九", imageCount: 9, items: [
            .create(x: 0, y: 0, w: 0.5, h: 0.5), .create(x: 0.5, y: 0, w: 0.5, h: 0.25),
            .create(x: 0.5, y: 0.25, w: 0.25, h: 0.25), .create(x: 0.75, y: 0.25, w: 0.25, h: 0.25),
            .create(x: 0, y: 0.5, w: 0.25, h: 0.25), .create(x: 0.25, y: 0.5, w: 0.25, h: 0.25),
            .create(x: 0.5, y: 0.5, w: 0.5, h: 0.25), .create(x: 0, y: 0.75, w: 0.5, h: 0.25), .create(x: 0.5, y: 0.75, w: 0.5, h: 0.25)
        ]),
        CollageTemplate(id: "9_11", name: "4大5小", imageCount: 9, items: [
            .create(x: 0, y: 0, w: 0.5, h: 0.5), .create(x: 0.5, y: 0, w: 0.5, h: 0.5),
            .create(x: 0, y: 0.5, w: 0.5, h: 0.5), .create(x: 0.5, y: 0.5, w: 0.5, h: 0.5),
            .create(x: 0.4, y: 0.4, w: 0.2, h: 0.2, z: 5), .create(x: 0.2, y: 0.2, w: 0.15, h: 0.15, z: 6),
            .create(x: 0.65, y: 0.2, w: 0.15, h: 0.15, z: 7), .create(x: 0.2, y: 0.65, w: 0.15, h: 0.15, z: 8),
            .create(x: 0.65, y: 0.65, w: 0.15, h: 0.15, z: 9)
        ]),
        CollageTemplate(id: "9_12", name: "画中画九", imageCount: 9, items: [
            .create(x: 0, y: 0, w: 1, h: 1, z: 0),
            .create(x: 0.1, y: 0.1, w: 0.2, h: 0.2, z: 1), .create(x: 0.4, y: 0.1, w: 0.2, h: 0.2, z: 2), .create(x: 0.7, y: 0.1, w: 0.2, h: 0.2, z: 3),
            .create(x: 0.1, y: 0.4, w: 0.2, h: 0.2, z: 4), .create(x: 0.7, y: 0.4, w: 0.2, h: 0.2, z: 5),
            .create(x: 0.1, y: 0.7, w: 0.2, h: 0.2, z: 6), .create(x: 0.4, y: 0.7, w: 0.2, h: 0.2, z: 7), .create(x: 0.7, y: 0.7, w: 0.2, h: 0.2, z: 8)
        ]),
        CollageTemplate(id: "9_13", name: "交错网格", imageCount: 9, items: [
            .create(x: 0, y: 0, w: 0.33, h: 0.33), .create(x: 0.33, y: 0.1, w: 0.33, h: 0.33), .create(x: 0.66, y: 0, w: 0.33, h: 0.33),
            .create(x: 0, y: 0.33, w: 0.33, h: 0.33), .create(x: 0.33, y: 0.43, w: 0.33, h: 0.33), .create(x: 0.66, y: 0.33, w: 0.33, h: 0.33),
            .create(x: 0, y: 0.66, w: 0.33, h: 0.33), .create(x: 0.33, y: 0.76, w: 0.33, h: 0.33), .create(x: 0.66, y: 0.66, w: 0.33, h: 0.33)
        ]),
        CollageTemplate(id: "9_14", name: "左大右八", imageCount: 9, items: [
            .create(x: 0, y: 0, w: 0.5, h: 1),
            .create(x: 0.5, y: 0, w: 0.25, h: 0.25), .create(x: 0.75, y: 0, w: 0.25, h: 0.25),
            .create(x: 0.5, y: 0.25, w: 0.25, h: 0.25), .create(x: 0.75, y: 0.25, w: 0.25, h: 0.25),
            .create(x: 0.5, y: 0.5, w: 0.25, h: 0.25), .create(x: 0.75, y: 0.5, w: 0.25, h: 0.25),
            .create(x: 0.5, y: 0.75, w: 0.25, h: 0.25), .create(x: 0.75, y: 0.75, w: 0.25, h: 0.25)
        ]),
        CollageTemplate(id: "9_15", name: "上大下八", imageCount: 9, items: [
            .create(x: 0, y: 0, w: 1, h: 0.5),
            .create(x: 0, y: 0.5, w: 0.25, h: 0.25), .create(x: 0.25, y: 0.5, w: 0.25, h: 0.25), .create(x: 0.5, y: 0.5, w: 0.25, h: 0.25), .create(x: 0.75, y: 0.5, w: 0.25, h: 0.25),
            .create(x: 0, y: 0.75, w: 0.25, h: 0.25), .create(x: 0.25, y: 0.75, w: 0.25, h: 0.25), .create(x: 0.5, y: 0.75, w: 0.25, h: 0.25), .create(x: 0.75, y: 0.75, w: 0.25, h: 0.25)
        ]),
        CollageTemplate(id: "9_16", name: "阶梯九", imageCount: 9, items: [
            .create(x: 0, y: 0, w: 0.33, h: 0.33), .create(x: 0.1, y: 0.1, w: 0.33, h: 0.33, z: 1), .create(x: 0.2, y: 0.2, w: 0.33, h: 0.33, z: 2),
            .create(x: 0.3, y: 0.3, w: 0.33, h: 0.33, z: 3), .create(x: 0.4, y: 0.4, w: 0.33, h: 0.33, z: 4), .create(x: 0.5, y: 0.5, w: 0.33, h: 0.33, z: 5),
            .create(x: 0.6, y: 0.6, w: 0.33, h: 0.33, z: 6), .create(x: 0.7, y: 0.7, w: 0.33, h: 0.33, z: 7), .create(x: 0.6, y: 0, w: 0.33, h: 0.33, z: 8)
        ]),
        CollageTemplate(id: "9_17", name: "T型九", imageCount: 9, items: [
            .create(x: 0, y: 0, w: 1, h: 0.4),
            .create(x: 0, y: 0.4, w: 0.25, h: 0.3), .create(x: 0.25, y: 0.4, w: 0.25, h: 0.3), .create(x: 0.5, y: 0.4, w: 0.25, h: 0.3), .create(x: 0.75, y: 0.4, w: 0.25, h: 0.3),
            .create(x: 0, y: 0.7, w: 0.25, h: 0.3), .create(x: 0.25, y: 0.7, w: 0.25, h: 0.3), .create(x: 0.5, y: 0.7, w: 0.25, h: 0.3), .create(x: 0.75, y: 0.7, w: 0.25, h: 0.3)
        ]),
        CollageTemplate(id: "9_18", name: "十字网格", imageCount: 9, items: [
            .create(x: 0.33, y: 0, w: 0.34, h: 1, z: 0), .create(x: 0, y: 0.33, w: 1, h: 0.34, z: 1),
            .create(x: 0, y: 0, w: 0.33, h: 0.33), .create(x: 0.67, y: 0, w: 0.33, h: 0.33),
            .create(x: 0, y: 0.67, w: 0.33, h: 0.33), .create(x: 0.67, y: 0.67, w: 0.33, h: 0.33),
            .create(x: 0.35, y: 0.35, w: 0.3, h: 0.3, z: 2), .create(x: 0.1, y: 0.4, w: 0.2, h: 0.2, z: 3), .create(x: 0.7, y: 0.4, w: 0.2, h: 0.2, z: 4)
        ]),
        CollageTemplate(id: "9_19", name: "圆环九", imageCount: 9, items: [
            .create(x: 0.35, y: 0.35, w: 0.3, h: 0.3, z: 8),
            .create(x: 0.1, y: 0.1, w: 0.25, h: 0.25), .create(x: 0.375, y: 0.05, w: 0.25, h: 0.25), .create(x: 0.65, y: 0.1, w: 0.25, h: 0.25),
            .create(x: 0.7, y: 0.375, w: 0.25, h: 0.25), .create(x: 0.65, y: 0.65, w: 0.25, h: 0.25),
            .create(x: 0.375, y: 0.7, w: 0.25, h: 0.25), .create(x: 0.1, y: 0.65, w: 0.25, h: 0.25), .create(x: 0.05, y: 0.375, w: 0.25, h: 0.25)
        ]),
        CollageTemplate(id: "9_20", name: "混合散落", imageCount: 9, items: [
            .create(x: 0.05, y: 0.05, w: 0.3, h: 0.3, r: -5), .create(x: 0.35, y: 0.05, w: 0.3, h: 0.3, r: 5), .create(x: 0.65, y: 0.05, w: 0.3, h: 0.3, r: -5),
            .create(x: 0.05, y: 0.35, w: 0.3, h: 0.3, r: 5), .create(x: 0.35, y: 0.35, w: 0.3, h: 0.3, r: 0), .create(x: 0.65, y: 0.35, w: 0.3, h: 0.3, r: 5),
            .create(x: 0.05, y: 0.65, w: 0.3, h: 0.3, r: -5), .create(x: 0.35, y: 0.65, w: 0.3, h: 0.3, r: 5), .create(x: 0.65, y: 0.65, w: 0.3, h: 0.3, r: -5)
        ])
    ]
}
