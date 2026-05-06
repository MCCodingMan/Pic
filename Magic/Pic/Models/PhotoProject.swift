import Foundation

struct PhotoProject: Codable, Identifiable, Equatable {
    var id: UUID
    var originalAssetID: String? // For PhotoKit assets
    var originalImageURL: URL? // For Files/Camera imports
    var title: String // Project Name
    var createdAt: Date
    var updatedAt: Date
    var currentEditState: EditState
    var thumbnailData: Data? // Low-res preview for list view

    enum CodingKeys: String, CodingKey {
        case id, originalAssetID, originalImageURL, title, createdAt, updatedAt, currentEditState, thumbnailData
    }
    
    init(assetID: String? = nil, imageURL: URL? = nil, title: String = "未命名作品") {
        self.id = UUID()
        self.originalAssetID = assetID
        self.originalImageURL = imageURL
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.currentEditState = EditState()
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        originalAssetID = try container.decodeIfPresent(String.self, forKey: .originalAssetID)
        originalImageURL = try container.decodeIfPresent(URL.self, forKey: .originalImageURL)
        // Provide default value if title is missing
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "未命名作品"
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        currentEditState = try container.decodeIfPresent(EditState.self, forKey: .currentEditState) ?? EditState()
        thumbnailData = try container.decodeIfPresent(Data.self, forKey: .thumbnailData)
    }
}
