import Foundation

enum PicCameraHistoryPersistence {
    struct SavedState: Codable {
        var modeRawValue: String
        var cameraPositionRawValue: String
        var zoomFactor: Double
        var flashModeRawValue: String
        var isLivePhotoEnabled: Bool
        var isAutoFilterEnabled: Bool
        var isGridEnabled: Bool
        var isLevelEnabled: Bool
        var aspectRatioRawValue: String
        var skinSmoothing: Double
        var skinWhitening: Double
        var skinWhiteningYUV: Double
        var faceSlimming: Double
        var portraitAperture: Double
        var selectedFilterCategory: String
        var selectedFilterName: String
        var adjustments: Adjustments
    }

    private static let historyEnabledKey = "pic.camera.history.enabled"
    private static let stateKey = "pic.camera.history.state"
    private static let defaults = UserDefaults.standard

    static func historyEnabled() -> Bool {
        defaults.object(forKey: historyEnabledKey) as? Bool ?? false
    }

    static func setHistoryEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: historyEnabledKey)
    }

    static func loadState() -> SavedState? {
        guard let data = defaults.data(forKey: stateKey) else { return nil }
        return try? JSONDecoder().decode(SavedState.self, from: data)
    }

    static func saveState(_ state: SavedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: stateKey)
    }

    static func clearState() {
        defaults.removeObject(forKey: stateKey)
    }
}
