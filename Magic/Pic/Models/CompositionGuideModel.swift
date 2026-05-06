import Foundation

// MARK: - Composition Guide Models (解析 CompositionGuides.json)

/// 顶层结构
struct CompositionGuidesData: Codable {
    let categories: CompositionCategories
}

/// 分类：人物 / 风景
struct CompositionCategories: Codable {
    let people: CompositionSubCategory
    let landscape: CompositionSubCategory
}

/// 子分类：normal / depth
struct CompositionSubCategory: Codable {
    let normal: [CompositionScene]
    let depth: [CompositionScene]
}

/// 场景（如"街拍"、"海边"）
struct CompositionScene: Codable, Identifiable {
    let scene: String
    let description: String
    let ratios: [String: [CompositionOption]]

    var id: String { scene }
}

/// 单个构图方案
struct CompositionOption: Codable, Identifiable {
    let description: String
    let rects: [CompositionPoint]

    var id: String { description }
}

/// 坐标点（归一化 0~1）
struct CompositionPoint: Codable {
    let x: CGFloat
    let y: CGFloat
}

// MARK: - 分类枚举（用于面板切换）

enum CompositionCategory: String, CaseIterable, Identifiable {
    case people = "人物"
    case landscape = "风景"

    var id: String { rawValue }
}

// MARK: - 加载

extension CompositionGuidesData {
    /// 从 Bundle 加载并解析 JSON
    static func loadFromBundle() -> CompositionGuidesData? {
        guard let url = Bundle.main.url(forResource: "CompositionGuides", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let result = try? JSONDecoder().decode(CompositionGuidesData.self, from: data)
        else { return nil }
        return result
    }

    /// 根据分类获取可用场景列表
    func scenes(category: CompositionCategory) -> [CompositionScene] {
        let sub: CompositionSubCategory
        switch category {
        case .people:    sub = categories.people
        case .landscape: sub = categories.landscape
        }
        return sub.normal
    }
}

