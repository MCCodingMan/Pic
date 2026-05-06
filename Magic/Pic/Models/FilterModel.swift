import Foundation

// Deterministic random number generator for reproducible filter parameters
nonisolated struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

nonisolated struct FilterModel: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let category: String

    // Color Matrix (4x4 matrix + bias vector)
    // R, G, B, A vectors (each 4 components) + Bias vector (4 components)
    // Flattened array of 20 floats: R(4), G(4), B(4), A(4), Bias(4)
    let colorMatrix: [Double]?

    // Additional adjustments (Preset values)
    var adjustments: Adjustments?

    // Intensity (0.0 - 1.0), default 1.0
    var intensity: Double = 1.0

    static let original = FilterModel(id: "original", name: "原图", category: "基础", colorMatrix: nil, adjustments: nil)
    static let auto = FilterModel(id: "auto", name: "自动", category: "基础", colorMatrix: nil, adjustments: nil)

    // MARK: - Generators
    static func generateFilters() -> [FilterModel] {
        var filters: [FilterModel] = [original, auto]

        filters.append(contentsOf: generateSceneryFilters())
        filters.append(contentsOf: generatePortraitFilters())

        return filters
    }

    // MARK: - Filter Names

    private static let sceneryNames: [String] = [
        "晨曦初露", "山间清风", "暮色苍茫", "深海幽蓝", "极光幻境", "雨后初晴", "森林秘语", "沙漠孤烟", "雪域高原", "海岛假日",
        "秋日私语", "夏日如歌", "春风十里", "冬日暖阳", "星空璀璨", "云端漫步", "湖光山色", "田园牧歌", "城市微光", "午夜霓虹",
        "迷雾森林", "蔚蓝海岸", "金色麦田", "紫色晚霞", "青苔古石", "落日余晖", "碧海蓝天", "翠林竹影", "幽谷清泉", "断桥残雪",
        "烟雨江南", "大漠风沙", "长河落日", "孤帆远影", "寒江独钓", "枫林尽染", "白雪皑皑", "绿草如茵", "繁花似锦", "枯藤老树",
        "小桥流水", "古道西风", "断肠天涯", "海市蜃楼", "镜花水月", "风花雪月", "苍山洱海", "纳木错蓝", "茶卡盐湖", "稻城亚丁",
        "九寨沟蓝", "张家界奇", "黄山云海", "泰山日出", "华山论剑", "衡山烟云", "恒山悬空", "嵩山少林", "西湖美景", "漓江渔火",
        "鼓浪屿波", "三亚椰风", "丽江古城", "凤凰沱江", "乌镇水乡", "西塘夜色", "周庄梦蝶", "同里时光", "南浔旧梦", "宏村画里",
        "婺源油菜", "罗平花海", "普者黑荷", "元阳梯田", "龙脊金秋", "阿尔山秋", "喀纳斯湖", "赛里木蓝", "青海湖黄", "茶园清新",
        "竹海听涛", "松林听风", "荷塘月色", "梅花三弄", "兰花幽谷", "菊花台前", "竹林深处", "松涛阵阵", "柏林禅意", "柳絮纷飞",
        "杨柳依依", "桃红柳绿", "樱花漫舞", "杏花微雨", "梨花带雨", "海棠依旧", "牡丹争艳", "芍药含情", "茉莉清香", "云深不知"
    ]

    private static let portraitNames: [String] = [
        "初恋粉", "奶油肌", "冷白皮", "复古红", "港风韵", "日杂感", "清透蓝", "质感灰", "胶片绿", "电影感",
        "森系绿", "甜美杏", "元气橘", "高冷紫", "纯欲风", "温柔粉", "优雅金", "神秘黑", "梦幻紫", "清新绿",
        "阳光橙", "月光白", "星光蓝", "极光紫", "薄荷绿", "樱花粉", "蜜桃红", "珊瑚橙", "玫瑰金", "香槟金",
        "珍珠白", "象牙白", "小麦色", "古铜色", "健康肤", "通透感", "水光肌", "哑光面", "丝绒感", "磨砂感",
        "柔雾感", "空气感", "呼吸感", "少女感", "少年感", "成熟风", "知性美", "优雅风", "文艺范", "摇滚风",
        "朋克风", "嘻哈风", "街头风", "运动风", "休闲风", "度假风", "职场风", "晚宴风", "派对风", "约会妆",
        "日常妆", "伪素颜", "裸妆感", "宿醉妆", "晒伤妆", "雀斑妆", "混血感", "异域风", "国潮风", "汉服风",
        "和风物语", "法式浪漫", "英伦格调", "美式复古", "韩系潮流", "日系清新", "泰式浓颜", "ins风", "网红感", "高级脸",
        "厌世脸", "娃娃脸", "御姐范", "萝莉风", "女王范", "公主梦", "仙女气", "女神范", "男神范", "鲜肉感",
        "大叔控", "暖男风", "高冷范", "霸道风", "治愈系", "盐系", "甜系", "纯真年代", "光阴故事", "流金岁月"
    ]

    // Helper to create matrix filter
    private static func matrixFilter(
        name: String,
        category: String,
        r: (Double, Double, Double) = (1,0,0),
        g: (Double, Double, Double) = (0,1,0),
        b: (Double, Double, Double) = (0,0,1),
        bias: (Double, Double, Double) = (0,0,0),
        adjustments: Adjustments? = nil
    ) -> FilterModel {

        let matrix: [Double] = [
            r.0, r.1, r.2, 0,
            g.0, g.1, g.2, 0,
            b.0, b.1, b.2, 0,
            0,   0,   0,   1,
            bias.0, bias.1, bias.2, 0
        ]

        return FilterModel(id: UUID().uuidString, name: name, category: category, colorMatrix: matrix, adjustments: adjustments)
    }

    // MARK: - Scenery Filters (风景) - All GPUImage3/Metal based
    private static func generateSceneryFilters() -> [FilterModel] {
        var filters: [FilterModel] = []
        let cat = "风景"

        // Preset scenery filters with color matrix + adjustments
        filters.append(matrixFilter(name: "清晰增强", category: cat,
                                  adjustments: Adjustments(contrast: 1.1, saturation: 1.1, sharpen: 0.5, clarity: 0.3)))

        filters.append(matrixFilter(name: "去雾通透", category: cat,
                                  r: (1.0, 0.0, 0.0), g: (0.0, 1.0, 0.0), b: (0.0, 0.0, 0.95),
                                  adjustments: Adjustments(contrast: 1.15, saturation: 1.1, clarity: 0.4)))

        filters.append(matrixFilter(name: "远景去雾", category: cat,
                                    adjustments: Adjustments(contrast: 1.2, sharpen: 0.4, clarity: 0.6)))

        filters.append(matrixFilter(name: "空气感", category: cat,
                                  adjustments: Adjustments(contrast: 0.9, brightness: 0.1, clarity: -0.1)))

        filters.append(matrixFilter(name: "HDR风光", category: cat,
                                    adjustments: Adjustments(contrast: 1.1, highlights: -0.6, shadows: 0.6, saturation: 1.2, clarity: 0.3)))

        filters.append(matrixFilter(name: "高光压制", category: cat,
                                  adjustments: Adjustments(highlights: -0.8)))

        filters.append(matrixFilter(name: "阴影提亮", category: cat,
                                  adjustments: Adjustments(shadows: 0.8)))

        filters.append(matrixFilter(name: "明暗平衡", category: cat,
                                  adjustments: Adjustments(highlights: -0.4, shadows: 0.4)))

        filters.append(matrixFilter(name: "局部对比", category: cat,
                                  adjustments: Adjustments(clarity: 0.8)))

        filters.append(matrixFilter(name: "整体对比", category: cat,
                                  adjustments: Adjustments(contrast: 1.3)))

        filters.append(matrixFilter(name: "曲线S增强", category: cat,
                                  adjustments: Adjustments(contrast: 1.25, saturation: 1.1)))

        filters.append(matrixFilter(name: "自然饱和", category: cat,
                                  adjustments: Adjustments(saturation: 1.3)))

        filters.append(matrixFilter(name: "低饱和胶片", category: cat,
                                  r: (0.9, 0.05, 0.05), g: (0.05, 0.9, 0.05), b: (0.05, 0.05, 0.9),
                                  adjustments: Adjustments(contrast: 1.1, saturation: 0.7)))

        filters.append(matrixFilter(name: "色彩增强", category: cat,
                                  adjustments: Adjustments(contrast: 1.1, saturation: 1.4)))

        filters.append(matrixFilter(name: "秋日暖阳", category: cat,
                                  r: (1.1, 0.0, 0.0), g: (0.0, 1.05, 0.0), b: (0.0, 0.0, 0.9),
                                  adjustments: Adjustments(saturation: 1.1, warmth: 0.3)))

        filters.append(matrixFilter(name: "日落金橙", category: cat,
                                  r: (1.2, 0.0, 0.0), g: (0.0, 1.0, 0.0), b: (0.0, 0.0, 0.8),
                                  bias: (0.05, 0.02, 0.0),
                                  adjustments: Adjustments(warmth: 0.5)))

        filters.append(matrixFilter(name: "冷峻青蓝", category: cat,
                                  r: (0.9, 0.0, 0.0), g: (0.0, 1.0, 0.0), b: (0.0, 0.0, 1.2),
                                  adjustments: Adjustments(contrast: 1.1, warmth: -0.4)))

        filters.append(matrixFilter(name: "青橙电影", category: cat,
                                  r: (1.2, 0.0, 0.0), g: (0.0, 0.9, 0.1), b: (0.0, 0.2, 0.8),
                                  adjustments: Adjustments(contrast: 1.15, saturation: 1.1)))

        filters.append(matrixFilter(name: "森系清冷", category: cat,
                                  r: (0.95, 0.0, 0.0), g: (0.0, 1.05, 0.0), b: (0.0, 0.0, 1.1),
                                  adjustments: Adjustments(exposure: 0.1, saturation: 0.9, warmth: -0.2)))

        filters.append(matrixFilter(name: "草地增绿", category: cat,
                                  r: (1.0, 0.0, 0.0), g: (0.0, 1.15, 0.0), b: (0.0, 0.0, 1.0),
                                  adjustments: Adjustments(saturation: 1.1)))

        filters.append(matrixFilter(name: "蓝天增强", category: cat,
                                  r: (1.0, 0.0, 0.0), g: (0.0, 1.0, 0.0), b: (0.0, 0.0, 1.15),
                                  adjustments: Adjustments(saturation: 1.1)))

        filters.append(matrixFilter(name: "天空加深", category: cat,
                                  r: (0.9, 0.0, 0.0), g: (0.0, 0.9, 0.0), b: (0.0, 0.0, 1.1),
                                  bias: (-0.05, -0.05, 0.0)))

        filters.append(matrixFilter(name: "云层细节", category: cat,
                                  adjustments: Adjustments(highlights: -0.3, clarity: 0.7)))

        filters.append(matrixFilter(name: "水面通透", category: cat,
                                  r: (0.95, 0.0, 0.0), g: (0.0, 1.0, 0.0), b: (0.0, 0.0, 1.1),
                                  adjustments: Adjustments(contrast: 1.1, clarity: 0.5)))

        filters.append(matrixFilter(name: "水面长曝光", category: cat,
                                  adjustments: Adjustments(contrast: 1.1, sharpen: -0.5)))

        filters.append(matrixFilter(name: "夜景降噪", category: cat,
                                  adjustments: Adjustments(sharpen: -0.3)))

        filters.append(matrixFilter(name: "暗部降噪", category: cat,
                                  adjustments: Adjustments(shadows: 0.2, sharpen: -0.2)))

        filters.append(matrixFilter(name: "锐化细节", category: cat,
                                  adjustments: Adjustments(sharpen: 1.0)))

        filters.append(matrixFilter(name: "纹理增强", category: cat,
                                  adjustments: Adjustments(sharpen: 0.5, clarity: 0.5)))

        filters.append(matrixFilter(name: "微结构", category: cat,
                                  adjustments: Adjustments(clarity: 0.9)))

        filters.append(matrixFilter(name: "暗角轻微", category: cat,
                                  adjustments: Adjustments(vignette: 0.3)))

        filters.append(matrixFilter(name: "移轴风景", category: cat,
                                  adjustments: Adjustments(saturation: 1.3, vignette: 0.7)))

        filters.append(matrixFilter(name: "径向光束", category: cat,
                                  adjustments: Adjustments(brightness: 0.1, highlights: 0.2)))

        filters.append(matrixFilter(name: "阳光穿透", category: cat,
                                  adjustments: Adjustments(brightness: 0.1, warmth: 0.4, clarity: -0.2)))

        filters.append(matrixFilter(name: "星芒效果", category: cat,
                                  adjustments: Adjustments(highlights: 0.3, sharpen: 1.5)))

        filters.append(matrixFilter(name: "阴天提亮", category: cat,
                                  adjustments: Adjustments(exposure: 0.3, saturation: 1.1, warmth: 0.1)))

        filters.append(matrixFilter(name: "雾天柔化", category: cat,
                                  adjustments: Adjustments(brightness: 0.1, clarity: -0.3)))

        filters.append(matrixFilter(name: "雨后清透", category: cat,
                                  r: (0.95, 0.0, 0.0), g: (0.0, 1.0, 0.0), b: (0.0, 0.0, 1.05),
                                  adjustments: Adjustments(contrast: 1.1, clarity: 0.4)))

        filters.append(matrixFilter(name: "雪景去蓝", category: cat,
                                  r: (1.0, 0.0, 0.0), g: (0.0, 1.0, 0.0), b: (0.0, 0.0, 0.9),
                                  adjustments: Adjustments(exposure: 0.2)))

        filters.append(matrixFilter(name: "极简黑白", category: cat,
                                  r: (0.2126, 0.7152, 0.0722), g: (0.2126, 0.7152, 0.0722), b: (0.2126, 0.7152, 0.0722),
                                  adjustments: Adjustments(contrast: 1.2)))

        filters.append(matrixFilter(name: "高反差黑白", category: cat,
                                  r: (0.2126, 0.7152, 0.0722), g: (0.2126, 0.7152, 0.0722), b: (0.2126, 0.7152, 0.0722),
                                  adjustments: Adjustments(contrast: 1.5, highlights: 0.2)))

        filters.append(matrixFilter(name: "复古胶片", category: cat,
                                  r: (1.1, 0.0, 0.0), g: (0.0, 1.0, 0.0), b: (0.0, 0.0, 0.9),
                                  bias: (0.05, 0.0, 0.0),
                                  adjustments: Adjustments(contrast: 1.1, grain: 0.3)))

        filters.append(matrixFilter(name: "颗粒胶片", category: cat,
                                  adjustments: Adjustments(contrast: 1.1, grain: 0.5)))

        filters.append(matrixFilter(name: "淡雅日系", category: cat,
                                  r: (1.0, 0.0, 0.0), g: (0.0, 1.0, 0.0), b: (0.0, 0.0, 1.05),
                                  adjustments: Adjustments(exposure: 0.2, contrast: 0.9, saturation: 0.8)))

        filters.append(matrixFilter(name: "港风风光", category: cat,
                                  adjustments: Adjustments(contrast: 1.2, saturation: 1.2, warmth: 0.1, grain: 0.2)))

        filters.append(matrixFilter(name: "紫调梦幻", category: cat,
                                  r: (1.0, 0.0, 0.0), g: (0.0, 0.9, 0.0), b: (0.0, 0.0, 1.1),
                                  bias: (0.05, 0.0, 0.05),
                                  adjustments: Adjustments(tint: 0.3)))

        filters.append(matrixFilter(name: "蓝调夜景", category: cat,
                                  r: (0.8, 0.0, 0.0), g: (0.0, 0.9, 0.0), b: (0.0, 0.0, 1.3),
                                  adjustments: Adjustments(exposure: -0.1, contrast: 1.2)))

        // 100 seeded scenery filters
        var rng = SeededRandomNumberGenerator(seed: 42)
        for i in 0..<100 {
            let exposure = Double.random(in: -0.2...0.3, using: &rng)
            let contrast = Double.random(in: 0.9...1.3, using: &rng)
            let saturation = Double.random(in: 0.8...1.5, using: &rng)
            let warmth = Double.random(in: -0.3...0.4, using: &rng)
            let tint = Double.random(in: -0.2...0.2, using: &rng)
            let clarity = Double.random(in: 0.0...0.6, using: &rng)
            let sharpen = Double.random(in: 0.0...0.8, using: &rng)
            let highlights = Double.random(in: -0.8...0.0, using: &rng)
            let shadows = Double.random(in: 0.0...0.6, using: &rng)
            let vignette = Double.random(in: 0.0...0.5, using: &rng)

            let adj = Adjustments(
                exposure: exposure,
                contrast: contrast,
                highlights: highlights,
                shadows: shadows,
                saturation: saturation,
                warmth: warmth,
                tint: tint,
                sharpen: sharpen,
                clarity: clarity,
                vignette: vignette
            )

            let nameIndex = i % sceneryNames.count
            let name = sceneryNames[nameIndex]

            filters.append(matrixFilter(
                name: name,
                category: cat,
                adjustments: adj
            ))
        }

        return filters
    }

    // MARK: - Portrait Filters (人物) - All GPUImage3/Metal based
    private static func generatePortraitFilters() -> [FilterModel] {
        var filters: [FilterModel] = []
        let cat = "人物"

        // Preset portrait filters
        filters.append(matrixFilter(name: "自然美颜", category: cat,
                                  adjustments: Adjustments(contrast: 0.95, brightness: 0.05, sharpen: 0.1, clarity: -0.1)))

        filters.append(matrixFilter(name: "磨皮柔肤", category: cat,
                                  adjustments: Adjustments(sharpen: -0.1, clarity: -0.4)))

        filters.append(matrixFilter(name: "高级磨皮", category: cat,
                                  adjustments: Adjustments(sharpen: 0.2, clarity: -0.2)))

        filters.append(matrixFilter(name: "肤色提亮", category: cat,
                                  adjustments: Adjustments(brightness: 0.1, highlights: -0.1)))

        filters.append(matrixFilter(name: "肤色均匀", category: cat,
                                  adjustments: Adjustments(clarity: -0.2)))

        filters.append(matrixFilter(name: "去黄提气色", category: cat,
                                  r: (1.05, 0.0, 0.0), g: (0.0, 1.02, 0.0), b: (0.0, 0.0, 1.05),
                                  adjustments: Adjustments(warmth: -0.1, tint: 0.1)))

        filters.append(matrixFilter(name: "冷白皮", category: cat,
                                  r: (1.0, 0.0, 0.0), g: (0.0, 1.0, 0.0), b: (0.0, 0.0, 1.05),
                                  adjustments: Adjustments(brightness: 0.1, saturation: 0.85, warmth: -0.15)))

        filters.append(matrixFilter(name: "暖杏肤色", category: cat,
                                  r: (1.05, 0.0, 0.0), g: (0.0, 1.02, 0.0), b: (0.0, 0.0, 0.95),
                                  adjustments: Adjustments(warmth: 0.2)))

        filters.append(matrixFilter(name: "蜜桃粉", category: cat,
                                  r: (1.05, 0.0, 0.0), g: (0.0, 0.95, 0.0), b: (0.0, 0.0, 1.0),
                                  adjustments: Adjustments(brightness: 0.05, tint: 0.1)))

        filters.append(matrixFilter(name: "腮红增强", category: cat,
                                  adjustments: Adjustments(tint: 0.2)))

        filters.append(matrixFilter(name: "口红增强", category: cat,
                                  adjustments: Adjustments(saturation: 1.15, tint: 0.2)))

        filters.append(matrixFilter(name: "牙齿美白", category: cat,
                                  adjustments: Adjustments(brightness: 0.1, warmth: -0.1)))

        filters.append(matrixFilter(name: "眼白提亮", category: cat,
                                  adjustments: Adjustments(brightness: 0.1, highlights: -0.15, warmth: -0.05)))

        filters.append(matrixFilter(name: "去黑眼圈", category: cat,
                                  adjustments: Adjustments(brightness: 0.1, shadows: 0.1)))

        filters.append(matrixFilter(name: "去法令纹", category: cat,
                                  adjustments: Adjustments(shadows: 0.1, clarity: -0.2)))

        filters.append(matrixFilter(name: "祛痘祛斑", category: cat,
                                  adjustments: Adjustments(clarity: -0.3)))

        filters.append(matrixFilter(name: "控油去油光", category: cat,
                                  adjustments: Adjustments(highlights: -0.5)))

        filters.append(matrixFilter(name: "面部立体", category: cat,
                                  adjustments: Adjustments(contrast: 1.1, highlights: 0.1, shadows: -0.1)))

        filters.append(matrixFilter(name: "鼻梁高光", category: cat,
                                  adjustments: Adjustments(highlights: 0.2)))

        filters.append(matrixFilter(name: "下颌线增强", category: cat,
                                  adjustments: Adjustments(contrast: 1.1, shadows: -0.1)))

        filters.append(matrixFilter(name: "瘦脸", category: cat,
                                  adjustments: Adjustments(vignette: 0.3)))

        filters.append(matrixFilter(name: "小脸", category: cat,
                                  adjustments: Adjustments(vignette: 0.2)))

        filters.append(matrixFilter(name: "瘦下巴", category: cat,
                                  adjustments: Adjustments(vignette: 0.25)))

        filters.append(matrixFilter(name: "大眼", category: cat,
                                  adjustments: Adjustments(brightness: 0.05, sharpen: 0.2)))

        filters.append(matrixFilter(name: "眼睛锐化", category: cat,
                                  adjustments: Adjustments(sharpen: 0.4)))

        filters.append(matrixFilter(name: "眼神光", category: cat,
                                  adjustments: Adjustments(brightness: 0.05, sharpen: 0.4)))

        filters.append(matrixFilter(name: "睫毛增强", category: cat,
                                  adjustments: Adjustments(contrast: 1.1, sharpen: 0.5)))

        filters.append(matrixFilter(name: "眉毛增强", category: cat,
                                  adjustments: Adjustments(shadows: -0.1, sharpen: 0.4)))

        filters.append(matrixFilter(name: "发丝细节", category: cat,
                                  adjustments: Adjustments(sharpen: 0.6)))

        filters.append(matrixFilter(name: "头发柔顺", category: cat,
                                  adjustments: Adjustments(sharpen: 0.2, clarity: -0.2)))

        filters.append(matrixFilter(name: "发色增强", category: cat,
                                  adjustments: Adjustments(saturation: 1.2)))

        filters.append(matrixFilter(name: "背景虚化", category: cat,
                                  adjustments: Adjustments(sharpen: -0.2, vignette: 0.5)))

        filters.append(matrixFilter(name: "浅景深", category: cat,
                                  adjustments: Adjustments(vignette: 0.6)))

        filters.append(matrixFilter(name: "柔光人像", category: cat,
                                  adjustments: Adjustments(exposure: 0.1, clarity: -0.5)))

        filters.append(matrixFilter(name: "电影人像", category: cat,
                                  r: (1.1, 0.0, 0.0), g: (0.0, 1.0, 0.0), b: (0.0, 0.0, 0.9),
                                  adjustments: Adjustments(contrast: 1.1, saturation: 0.9)))

        filters.append(matrixFilter(name: "复古人像", category: cat,
                                  r: (1.0, 0.0, 0.0), g: (0.0, 1.0, 0.0), b: (0.0, 0.0, 0.8),
                                  bias: (0.05, 0.05, 0.0),
                                  adjustments: Adjustments(contrast: 1.05, grain: 0.3)))

        filters.append(matrixFilter(name: "日系清透", category: cat,
                                  adjustments: Adjustments(exposure: 0.15, contrast: 0.9, saturation: 0.85)))

        filters.append(matrixFilter(name: "韩系通透", category: cat,
                                  adjustments: Adjustments(exposure: 0.1, contrast: 1.0, brightness: 0.05, saturation: 0.95)))

        filters.append(matrixFilter(name: "港风复古", category: cat,
                                  adjustments: Adjustments(contrast: 1.15, saturation: 1.1, warmth: 0.1, grain: 0.2)))

        filters.append(matrixFilter(name: "黑白人像", category: cat,
                                  r: (0.2126, 0.7152, 0.0722), g: (0.2126, 0.7152, 0.0722), b: (0.2126, 0.7152, 0.0722),
                                  adjustments: Adjustments(contrast: 1.2, sharpen: 0.3)))

        filters.append(matrixFilter(name: "高反差黑白", category: cat,
                                  r: (0.2126, 0.7152, 0.0722), g: (0.2126, 0.7152, 0.0722), b: (0.2126, 0.7152, 0.0722),
                                  adjustments: Adjustments(contrast: 1.4)))

        filters.append(matrixFilter(name: "高级灰", category: cat,
                                  adjustments: Adjustments(contrast: 0.9, saturation: 0.4)))

        filters.append(matrixFilter(name: "暖调人像", category: cat,
                                  adjustments: Adjustments(warmth: 0.3)))

        filters.append(matrixFilter(name: "冷调人像", category: cat,
                                  adjustments: Adjustments(warmth: -0.3)))

        filters.append(matrixFilter(name: "肤色保护", category: cat,
                                  r: (1.03, 0.0, 0.0), g: (0.0, 1.01, 0.0), b: (0.0, 0.0, 0.97),
                                  adjustments: Adjustments(saturation: 0.95, warmth: 0.1)))

        filters.append(matrixFilter(name: "防过曝", category: cat,
                                  adjustments: Adjustments(highlights: -0.6)))

        filters.append(matrixFilter(name: "暗部提亮", category: cat,
                                  adjustments: Adjustments(shadows: 0.4)))

        filters.append(matrixFilter(name: "降噪", category: cat,
                                  adjustments: Adjustments(sharpen: -0.2)))

        filters.append(matrixFilter(name: "锐化", category: cat,
                                  adjustments: Adjustments(sharpen: 0.5)))

        filters.append(matrixFilter(name: "暗角聚焦", category: cat,
                                  adjustments: Adjustments(vignette: 0.4)))

        filters.append(matrixFilter(name: "局部提亮", category: cat,
                                  adjustments: Adjustments(brightness: 0.1)))

        filters.append(matrixFilter(name: "局部柔化", category: cat,
                                  adjustments: Adjustments(clarity: -0.3)))

        filters.append(matrixFilter(name: "光晕漏光", category: cat,
                                  adjustments: Adjustments(brightness: 0.1, warmth: 0.2)))

        filters.append(matrixFilter(name: "闪光灯直打", category: cat,
                                  adjustments: Adjustments(contrast: 1.3, brightness: 0.1, vignette: 0.2)))

        // 100 seeded portrait filters
        var rng = SeededRandomNumberGenerator(seed: 137)
        for i in 0..<100 {
            let exposure = Double.random(in: -0.1...0.3, using: &rng)
            let contrast = Double.random(in: 0.8...1.1, using: &rng)
            let brightness = Double.random(in: 0.0...0.2, using: &rng)
            let saturation = Double.random(in: 0.7...1.2, using: &rng)
            let warmth = Double.random(in: -0.4...0.4, using: &rng)
            let tint = Double.random(in: -0.2...0.2, using: &rng)
            let clarity = Double.random(in: -0.5...0.1, using: &rng)
            let sharpen = Double.random(in: 0.0...0.4, using: &rng)
            let highlights = Double.random(in: -0.5...0.0, using: &rng)
            let shadows = Double.random(in: 0.0...0.4, using: &rng)
            let vignette = Double.random(in: 0.0...0.3, using: &rng)

            let adj = Adjustments(
                exposure: exposure,
                contrast: contrast,
                brightness: brightness,
                highlights: highlights,
                shadows: shadows,
                saturation: saturation,
                warmth: warmth,
                tint: tint,
                sharpen: sharpen,
                clarity: clarity,
                vignette: vignette
            )

            let nameIndex = i % portraitNames.count
            let name = portraitNames[nameIndex]

            filters.append(matrixFilter(
                name: name,
                category: cat,
                adjustments: adj
            ))
        }

        return filters
    }
}
