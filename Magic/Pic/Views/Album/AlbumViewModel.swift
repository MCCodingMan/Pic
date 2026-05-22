import SwiftUI
import Photos
import Observation

struct AlbumModel: Identifiable, Hashable {
    let id: String
    let title: String
    let count: Int
    let collection: PHAssetCollection?
}

private final class AlbumPhotoLibraryObserver: NSObject, PHPhotoLibraryChangeObserver {
    var onChange: (() -> Void)?

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        onChange?()
    }
}

@Observable
class AlbumViewModel {
    var assets: PHFetchResult<PHAsset> = PHFetchResult()
    var albums: [AlbumModel] = []
    var selectedAlbum: AlbumModel?
    var authorizationStatus: PHAuthorizationStatus = .notDetermined
    
    let imageManager = PHCachingImageManager()

    @ObservationIgnored private let libraryObserver = AlbumPhotoLibraryObserver()
    @ObservationIgnored private var isObservingPhotoLibrary = false
    
    init() {
        libraryObserver.onChange = { [weak self] in
            Task { @MainActor in
                self?.reloadAfterPhotoLibraryChange()
            }
        }
        checkPermission()
    }

    deinit {
        if isObservingPhotoLibrary {
            PHPhotoLibrary.shared().unregisterChangeObserver(libraryObserver)
        }
    }
    
    func checkPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorized || status == .limited {
                self.startObservingPhotoLibrary()
                self.fetchAlbums()
            }
        }
    }
    
    func requestPermission() {
        Task { @MainActor in
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            authorizationStatus = status
            if status == .authorized || status == .limited {
                startObservingPhotoLibrary()
                fetchAlbums()
            }
        }
    }
    
    func fetchAlbums(preserveSelection: Bool = false) {
        let selectedAlbumID = preserveSelection ? selectedAlbum?.id : nil
        var newAlbums: [AlbumModel] = []
        
        // 1. Recents (Smart Album)
        let smartAlbums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumUserLibrary, options: nil)
        if let recents = smartAlbums.firstObject {
             let fetchOptions = PHFetchOptions()
             fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
             let count = PHAsset.fetchAssets(in: recents, options: fetchOptions).count
             newAlbums.append(AlbumModel(id: recents.localIdentifier, title: "最近项目", count: count, collection: recents))
        }
        
        // 2. Favorites
        let favorites = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumFavorites, options: nil)
        if let fav = favorites.firstObject {
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
            let count = PHAsset.fetchAssets(in: fav, options: fetchOptions).count
            if count > 0 {
                newAlbums.append(AlbumModel(id: fav.localIdentifier, title: "个人收藏", count: count, collection: fav))
            }
        }
        
        // 3. User Collections
        let userCollections = PHCollectionList.fetchTopLevelUserCollections(with: nil)
        userCollections.enumerateObjects { collection, _, _ in
            if let assetCollection = collection as? PHAssetCollection {
                let fetchOptions = PHFetchOptions()
                fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
                let count = PHAsset.fetchAssets(in: assetCollection, options: fetchOptions).count
                if count > 0 {
                    newAlbums.append(AlbumModel(id: assetCollection.localIdentifier, title: assetCollection.localizedTitle ?? "未命名", count: count, collection: assetCollection))
                }
            }
        }
        
        Task { @MainActor in
            self.albums = newAlbums
            if let selectedAlbumID, let album = newAlbums.first(where: { $0.id == selectedAlbumID }) {
                self.selectedAlbum = album
            } else {
                self.selectedAlbum = newAlbums.first
            }
            self.fetchAssets()
        }
    }
    
    func selectAlbum(_ album: AlbumModel) {
        self.selectedAlbum = album
        self.fetchAssets()
    }
    
    func fetchAssets() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)

        if let collection = selectedAlbum?.collection {
            let result = PHAsset.fetchAssets(in: collection, options: options)
            Task { @MainActor in
                self.assets = result
            }
        } else {
             // Fallback
             let result = PHAsset.fetchAssets(with: .image, options: options)
             Task { @MainActor in
                 self.assets = result
             }
        }
    }
    
    // MARK: - Caching
    func startCaching(assets: [PHAsset], targetSize: CGSize) {
        imageManager.startCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: nil)
    }
    
    func stopCaching(assets: [PHAsset], targetSize: CGSize) {
        imageManager.stopCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: nil)
    }
    
    func stopCachingAll() {
        imageManager.stopCachingImagesForAllAssets()
    }

    private func startObservingPhotoLibrary() {
        guard !isObservingPhotoLibrary else { return }
        PHPhotoLibrary.shared().register(libraryObserver)
        isObservingPhotoLibrary = true
    }

    @MainActor
    private func reloadAfterPhotoLibraryChange() {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else { return }
        stopCachingAll()
        fetchAlbums(preserveSelection: true)
    }
}
