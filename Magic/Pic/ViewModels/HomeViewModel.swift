import Foundation
import Photos
import SwiftUI
import UIKit
import Observation

@Observable
class HomeViewModel {
    var recentProjects: [PhotoProject] = []
    var recommendedPhotos: [PHAsset] = []
    var permissionStatus: PHAuthorizationStatus = .notDetermined
    
    private let imageManager = PHCachingImageManager()
    
    init() {
        checkPermission()
        loadProjects()
    }
    
    func onAppear() {
        loadProjects()
        if permissionStatus == .authorized || permissionStatus == .limited {
            loadRecommendedPhotos()
        }
    }
    
    func loadProjects() {
        // Load from PersistenceService
        let projects = PersistenceService.shared.load()
        // Sort by most recently updated
        self.recentProjects = projects.sorted(by: { $0.updatedAt > $1.updatedAt })
    }
    
    func renameProject(_ project: PhotoProject, to newTitle: String) {
        if let index = recentProjects.firstIndex(where: { $0.id == project.id }) {
            var updatedProject = project
            updatedProject.title = newTitle
            updatedProject.updatedAt = Date()
            recentProjects[index] = updatedProject
            
            // Save to persistence
            PersistenceService.shared.save(projects: recentProjects)
        }
    }
    
    func deleteProject(_ project: PhotoProject) {
        if let index = recentProjects.firstIndex(where: { $0.id == project.id }) {
            recentProjects.remove(at: index)
            PersistenceService.shared.save(projects: recentProjects)
        }
    }
    
    func checkPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        self.permissionStatus = status
        
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
                DispatchQueue.main.async {
                    self?.permissionStatus = newStatus
                    if newStatus == .authorized || newStatus == .limited {
                        self?.loadRecommendedPhotos()
                    }
                }
            }
        } else if status == .authorized || status == .limited {
            loadRecommendedPhotos()
        }
    }
    
    func loadRecommendedPhotos() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.fetchLimit = 10

            let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            var assets: [PHAsset] = []
            fetchResult.enumerateObjects { asset, _, _ in
                assets.append(asset)
            }

            DispatchQueue.main.async {
                self?.recommendedPhotos = assets
            }
        }
    }
    
    func loadFullImage(for project: PhotoProject) async -> UIImage? {
        guard let assetID = project.originalAssetID else {
            print("LoadFullImage: assetID is nil")
            return nil
        }
        
        // Check permission
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status != .authorized && status != .limited {
             print("LoadFullImage: No permission")
             return nil
        }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = assets.firstObject else {
            print("LoadFullImage: Asset not found for ID: \(assetID)")
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            
            // Ensure continuation is only resumed once
            var hasResumed = false
            
            PHImageManager.default().requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFit, options: options) { image, info in
                guard !hasResumed else { return }
                
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                
                // If we got an image and it's not a degraded version (or if it's the only one we'll get)
                if let image = image, !isDegraded {
                    hasResumed = true
                    continuation.resume(returning: image)
                } else if image == nil {
                    // Error case
                    hasResumed = true
                    print("LoadFullImage: Failed to load image info: \(String(describing: info))")
                    continuation.resume(returning: nil)
                }
                // If it's degraded, we wait for the next callback (high quality)
            }
        }
    }
}
