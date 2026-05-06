@preconcurrency internal import AVFoundation
import UIKit
import CoreVideo
import CoreMedia
import QuartzCore


final class PicCameraService: NSObject, @unchecked Sendable {
    nonisolated private struct CapturePayload {
        var photo: AVCapturePhoto?
        var liveMovieURL: URL?
    }

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "pic.camera.session")
    private let videoQueue = DispatchQueue(label: "pic.camera.video", qos: .userInteractive)
    nonisolated(unsafe) private let photoOutput = AVCapturePhotoOutput()
    nonisolated(unsafe) private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated(unsafe) private let depthOutput = AVCaptureDepthDataOutput()
    nonisolated(unsafe) private let metadataOutput = AVCaptureMetadataOutput()
    nonisolated(unsafe) private var syncDataOutput: AVCaptureDataOutputSynchronizer?
    private let metadataHandler = PicCameraFaceMetadataHandler()

    private var currentInput: AVCaptureDeviceInput?
    private var currentMode: PicCameraMode = .photo
    private var isSessionConfigured = false
    private var flashModeStorage: AVCaptureDevice.FlashMode = .off
    private var isLivePhotoEnabled = false
    private var captureRotationAngle: CGFloat = -90
    private weak var previewLayer: CALayer?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    nonisolated(unsafe) private var capturePayloads: [Int64: CapturePayload] = [:]

    nonisolated(unsafe) weak var frameConsumer: PicCameraFrameConsumer?
    nonisolated(unsafe) var onPhotoCapture: ((AVCapturePhoto) -> Void)?
    nonisolated(unsafe) var onLivePhotoCapture: ((AVCapturePhoto, URL) -> Void)?
    nonisolated(unsafe) var onCaptureError: ((Error?) -> Void)?
    nonisolated(unsafe) var onFaceRects: (([CGRect]) -> Void)?

    override init() {
        super.init()
        metadataHandler.onFaces = { [weak self] rects in
            self?.onFaceRects?(rects)
        }
    }

    deinit {
        onPhotoCapture = nil
        onLivePhotoCapture = nil
        onCaptureError = nil
        onFaceRects = nil
        frameConsumer = nil
        metadataHandler.onFaces = nil
        capturePayloads.removeAll()
        syncDataOutput?.setDelegate(nil, queue: videoQueue)
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        metadataOutput.setMetadataObjectsDelegate(nil, queue: videoQueue)
        if session.isRunning {
            session.stopRunning()
        }
    }

    func authorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    func requestAccessIfNeeded() async -> AVAuthorizationStatus {
        let status = authorizationStatus()
        if status != .notDetermined { return status }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .authorized : .denied
    }

    func configureSessionIfNeeded(mode: PicCameraMode) async -> Bool {
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            sessionQueue.async {
                if self.isSessionConfigured {
                    continuation.resume(returning: true)
                    return
                }
                let result = self.configureSession(mode: mode)
                self.isSessionConfigured = result
                continuation.resume(returning: result)
            }
        }
    }

    func startSession() async {
        sessionQueue.async {
            self.session.startRunning()
        }
    }

    func stopSession() {
        sessionQueue.async {
            self.session.stopRunning()
        }
    }

    @MainActor
    func attachPreviewLayer(_ layer: CALayer) {
        previewLayer = layer
    }

    func switchMode(to mode: PicCameraMode) async -> Bool {
        let targetMode = mode
        let preferredPosition = currentCameraPosition()
        guard let device = preferredDevice(for: targetMode, position: preferredPosition)
            ?? preferredDevice(for: targetMode, position: .back)
            ?? preferredDevice(for: targetMode, position: .front) else {
            return false
        }

        let success = await withCheckedContinuation { (continuation: CheckedContinuation<(Bool), Never>) in
            sessionQueue.async {
                self.session.beginConfiguration()
                defer {
                    self.session.commitConfiguration()
                }

                let previousInput = self.currentInput
                let shouldReuseCurrentInput = previousInput?.device.uniqueID == device.uniqueID
                var newInput: AVCaptureDeviceInput?

                if !shouldReuseCurrentInput, let previousInput {
                    self.session.removeInput(previousInput)
                }

                if !shouldReuseCurrentInput {
                    guard let input = try? AVCaptureDeviceInput(device: device),
                          self.session.canAddInput(input) else {
                        if let previousInput, self.session.canAddInput(previousInput) {
                            self.session.addInput(previousInput)
                        }
                        continuation.resume(returning: false)
                        return
                    }
                    newInput = input
                }

                guard self.applyDepthConfiguration(to: device) else {
                    if !shouldReuseCurrentInput,
                       let previousInput,
                       self.session.canAddInput(previousInput) {
                        self.session.addInput(previousInput)
                    }
                    continuation.resume(returning: false)
                    return
                }

                if let newInput {
                    self.session.addInput(newInput)
                    self.currentInput = newInput
                }
                self.currentMode = targetMode
                if self.session.outputs.contains(self.depthOutput) {
                    self.session.removeOutput(self.depthOutput)
                }
                let shouldEnableDepth = targetMode == .portrait &&
                    self.supportsDepthStream(on: device) &&
                    self.supportsDepthPhotoCapture(on: device) &&
                    self.session.canAddOutput(self.depthOutput)
                if shouldEnableDepth {
                    self.session.addOutput(self.depthOutput)
                    self.configureDepthOutputForStability()
                }
                self.applyMirroringToActiveConnections()
                if self.photoOutput.isDepthDataDeliverySupported {
                    self.photoOutput.isDepthDataDeliveryEnabled = shouldEnableDepth
                }
                if self.photoOutput.isLivePhotoCaptureSupported {
                    self.photoOutput.isLivePhotoCaptureEnabled = self.isLivePhotoEnabled
                }
                self.configureFrameDelivery(enableDepth: shouldEnableDepth)
                self.applyDeviceConfiguration(to: device)
                continuation.resume(returning: true)
                
            }
        }
        return success
    }

    func currentCameraPosition() -> AVCaptureDevice.Position {
        currentInput?.device.position ?? .back
    }

    func switchCameraPosition() async -> Bool {
        let targetPosition: AVCaptureDevice.Position = currentCameraPosition() == .front ? .back : .front
        guard let device = preferredDevice(for: currentMode, position: targetPosition) else {
            return false
        }

        let success = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            sessionQueue.async {
                self.session.beginConfiguration()
                defer {
                    self.session.commitConfiguration()
                }

                let previousInput = self.currentInput
                if let previousInput {
                    self.session.removeInput(previousInput)
                }

                guard let input = try? AVCaptureDeviceInput(device: device),
                      self.session.canAddInput(input) else {
                    if let previousInput, self.session.canAddInput(previousInput) {
                        self.session.addInput(previousInput)
                    }
                    continuation.resume(returning: false)
                    return
                }

                guard self.applyDepthConfiguration(to: device) else {
                    if let previousInput, self.session.canAddInput(previousInput) {
                        self.session.addInput(previousInput)
                    }
                    continuation.resume(returning: false)
                    return
                }

                self.session.addInput(input)
                self.currentInput = input

                if self.session.outputs.contains(self.depthOutput) {
                    self.session.removeOutput(self.depthOutput)
                }
                let shouldEnableDepth = self.currentMode == .portrait &&
                    self.supportsDepthStream(on: device) &&
                    self.supportsDepthPhotoCapture(on: device) &&
                    self.session.canAddOutput(self.depthOutput)
                if shouldEnableDepth {
                    self.session.addOutput(self.depthOutput)
                    self.configureDepthOutputForStability()
                }
                self.applyMirroringToActiveConnections()
                if self.photoOutput.isDepthDataDeliverySupported {
                    self.photoOutput.isDepthDataDeliveryEnabled = shouldEnableDepth
                }
                if self.photoOutput.isLivePhotoCaptureSupported {
                    self.photoOutput.isLivePhotoCaptureEnabled = self.isLivePhotoEnabled
                }

                self.configureFrameDelivery(enableDepth: shouldEnableDepth)

                self.applyDeviceConfiguration(to: device)
                continuation.resume(returning: true)
            }
        }
        return success
    }

    func capturePhoto() {
        sessionQueue.async {
            let codec: AVVideoCodecType = self.photoOutput.availablePhotoCodecTypes.contains(.hevc) ? .hevc : .jpeg
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: codec])
            if self.supportsFlash() {
                settings.flashMode = self.flashModeStorage
            }
            settings.photoQualityPrioritization = .balanced
            if self.photoOutput.isDepthDataDeliverySupported {
                settings.isDepthDataDeliveryEnabled = self.currentMode == .portrait
            }
            
            if self.photoOutput.isLivePhotoCaptureSupported,
               self.photoOutput.isLivePhotoCaptureEnabled,
               self.isLivePhotoEnabled {
                settings.livePhotoMovieFileURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mov")
            }

            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func supportsFlash() -> Bool {
        currentInput?.device.hasFlash == true
    }

    func supportsLivePhoto() -> Bool {
        photoOutput.isLivePhotoCaptureSupported
    }

    func supportsPortraitDepthCapture() -> Bool {
        return photoOutput.isDepthDataDeliverySupported
    }

    func currentFlashMode() -> AVCaptureDevice.FlashMode {
        flashModeStorage
    }

    func currentLivePhotoEnabled() -> Bool {
        isLivePhotoEnabled
    }

    func setFlashMode(_ mode: AVCaptureDevice.FlashMode) {
        flashModeStorage = mode
    }

    func setLivePhotoEnabled(_ enabled: Bool) {
        isLivePhotoEnabled = enabled
        sessionQueue.async {
            if self.photoOutput.isLivePhotoCaptureSupported {
                self.photoOutput.isLivePhotoCaptureEnabled = enabled
            }
        }
    }

    func focus(at normalizedPoint: CGPoint) async {
        let clampedPoint = CGPoint(
            x: min(max(normalizedPoint.x, 0), 1),
            y: min(max(normalizedPoint.y, 0), 1)
        )

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                defer { continuation.resume() }
                guard let device = self.currentInput?.device else { return }

                do {
                    try device.lockForConfiguration()

                    if device.isFocusPointOfInterestSupported {
                        device.focusPointOfInterest = clampedPoint
                        if device.isFocusModeSupported(.continuousAutoFocus) {
                            device.focusMode = .continuousAutoFocus
                        } else if device.isFocusModeSupported(.autoFocus) {
                            device.focusMode = .autoFocus
                        }
                    }

                    if device.isExposurePointOfInterestSupported {
                        device.exposurePointOfInterest = clampedPoint
                        if device.isExposureModeSupported(.continuousAutoExposure) {
                            device.exposureMode = .continuousAutoExposure
                        } else if device.isExposureModeSupported(.autoExpose) {
                            device.exposureMode = .autoExpose
                        }
                    }

                    device.isSubjectAreaChangeMonitoringEnabled = true
                    device.unlockForConfiguration()
                } catch {}
            }
        }
    }

    func currentZoomFactor() async -> CGFloat {
        await withCheckedContinuation { (continuation: CheckedContinuation<CGFloat, Never>) in
            sessionQueue.async {
                let factor = self.currentInput?.device.videoZoomFactor ?? 1
                continuation.resume(returning: factor)
            }
        }
    }

    func currentDisplayVideoZoomFactorMultiplier() async -> CGFloat {
        await withCheckedContinuation { (continuation: CheckedContinuation<CGFloat, Never>) in
            sessionQueue.async {
                let multiplier = self.currentInput?.device.displayVideoZoomFactorMultiplier ?? 1
                continuation.resume(returning: multiplier)
            }
        }
    }

    func setZoomFactor(_ requestedFactor: CGFloat, preferredRange: ClosedRange<CGFloat>) async -> CGFloat {
        await withCheckedContinuation { (continuation: CheckedContinuation<CGFloat, Never>) in
            sessionQueue.async {
                guard let device = self.currentInput?.device else {
                    continuation.resume(returning: 1)
                    return
                }

                let lowerBound = max(preferredRange.lowerBound, device.minAvailableVideoZoomFactor)
                let upperBound = min(preferredRange.upperBound, device.maxAvailableVideoZoomFactor)
                let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors
                    .map { CGFloat(truncating: $0) }
                    .sorted()
                let stableUpperBound: CGFloat
                if let firstSwitch = switchOvers.first(where: { $0 > lowerBound + 0.05 }) {
                    stableUpperBound = max(lowerBound, firstSwitch - 0.01)
                } else {
                    stableUpperBound = upperBound
                }
                let validatedUpperBound = max(min(upperBound, stableUpperBound), lowerBound)
                let clamped = min(max(requestedFactor, lowerBound), validatedUpperBound)

                do {
                    try device.lockForConfiguration()
                    device.videoZoomFactor = clamped
                    device.unlockForConfiguration()
                    continuation.resume(returning: device.videoZoomFactor)
                } catch {
                    continuation.resume(returning: device.videoZoomFactor)
                }
            }
        }
    }

    private func configureSession(mode: PicCameraMode) -> Bool {
        session.beginConfiguration()
        defer {
            session.commitConfiguration()
        }

        session.sessionPreset = .photo

        let preferredPosition = currentInput?.device.position ?? .back
        guard let device = preferredDevice(for: mode, position: preferredPosition)
            ?? preferredDevice(for: mode, position: .back)
            ?? preferredDevice(for: mode, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return false
        }

        guard applyDepthConfiguration(to: device) else {
            return false
        }

        session.addInput(input)
        currentInput = input

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        guard session.canAddOutput(videoOutput),
              session.canAddOutput(photoOutput),
              session.canAddOutput(metadataOutput) else {
            return false
        }

        session.addOutput(videoOutput)
        session.addOutput(photoOutput)
        session.addOutput(metadataOutput)
        applyMirroringToActiveConnections()

        let shouldEnableDepth = mode == .portrait &&
            supportsDepthStream(on: device) &&
            supportsDepthPhotoCapture(on: device) &&
            session.canAddOutput(depthOutput)
        if shouldEnableDepth {
            session.addOutput(depthOutput)
            configureDepthOutputForStability()
            applyMirroringToActiveConnections()
        }

        photoOutput.maxPhotoQualityPrioritization = .balanced
        if photoOutput.isDepthDataDeliverySupported {
            photoOutput.isDepthDataDeliveryEnabled = shouldEnableDepth
        }
        if photoOutput.isLivePhotoCaptureSupported {
            photoOutput.isLivePhotoCaptureEnabled = isLivePhotoEnabled
        }

        if metadataOutput.availableMetadataObjectTypes.contains(.face) {
            metadataOutput.metadataObjectTypes = [.face]
        }
        metadataOutput.setMetadataObjectsDelegate(metadataHandler, queue: videoQueue)

        configureFrameDelivery(enableDepth: shouldEnableDepth)

        currentMode = mode
        applyDeviceConfiguration(to: device)
        return true
    }
    
    private func adjustMirroringIfSupported(_ connection: AVCaptureConnection?) {
        guard let connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = currentCameraPosition() == .front
    }

    private func applyMirroringToActiveConnections() {
        adjustMirroringIfSupported(videoOutput.connection(with: .video))
        adjustMirroringIfSupported(photoOutput.connection(with: .video))
        adjustMirroringIfSupported(metadataOutput.connection(with: .video))
        adjustMirroringIfSupported(depthOutput.connection(with: .depthData))
    }

    private func supportsDepthStream(on device: AVCaptureDevice) -> Bool {
        !device.activeFormat.supportedDepthDataFormats.isEmpty
    }

    private func supportsDepthPhotoCapture(on device: AVCaptureDevice) -> Bool {
        guard supportsDepthStream(on: device) else { return false }
        if photoOutput.isDepthDataDeliverySupported {
            return true
        }
        return preferredDepthFormat(for: device) != nil
    }

    private func configureFrameDelivery(enableDepth: Bool) {
        syncDataOutput?.setDelegate(nil, queue: nil)
        syncDataOutput = nil

        if enableDepth, depthOutput.connection(with: .depthData) != nil {
            videoOutput.setSampleBufferDelegate(nil, queue: nil)
            syncDataOutput = AVCaptureDataOutputSynchronizer(dataOutputs: [videoOutput, depthOutput])
            syncDataOutput?.setDelegate(self, queue: videoQueue)
        } else {
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        }
    }

    private func preferredDevice(for mode: PicCameraMode, position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: mode.deviceTypes(for: position),
            mediaType: .video,
            position: position
        )
        if let device = discovery.devices.first {
            return device
        }

        let fallbackDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInTrueDepthCamera],
            mediaType: .video,
            position: position
        )
        return fallbackDiscovery.devices.first
    }

    private func applyDepthConfiguration(to device: AVCaptureDevice) -> Bool {
        do {
            try device.lockForConfiguration()
            if let depthFormat = preferredDepthFormat(for: device) {
                device.activeDepthDataFormat = depthFormat
            }
            device.unlockForConfiguration()
            return true
        } catch {
            return false
        }
    }

    private func preferredDepthFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let depthFormats = device.activeFormat.supportedDepthDataFormats
        guard !depthFormats.isEmpty else { return nil }

        let float16Formats = depthFormats.filter {
            CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_DepthFloat16
        }
        let candidates = float16Formats.isEmpty ? depthFormats : float16Formats

        return candidates.max { lhs, rhs in
            let lhsDimensions = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
            let rhsDimensions = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
            return Int(lhsDimensions.width) * Int(lhsDimensions.height) < Int(rhsDimensions.width) * Int(rhsDimensions.height)
        }
    }

    private func configureDepthOutputForStability() {
        depthOutput.isFilteringEnabled = true
        depthOutput.alwaysDiscardsLateDepthData = true
    }

    private func applyDeviceConfiguration(to device: AVCaptureDevice) {
        applyMirroringToActiveConnections()

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = 1
            if let depthFormat = preferredDepthFormat(for: device) {
                device.activeDepthDataFormat = depthFormat
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            device.unlockForConfiguration()
        } catch {}
    }

    private func applyFrameRateConfiguration(to device: AVCaptureDevice) {
        let ranges = device.activeFormat.videoSupportedFrameRateRanges
        let preferredFPS: Double = ranges.contains { $0.minFrameRate <= 60 && $0.maxFrameRate >= 60 } ? 60 : 30
        let duration = CMTime(value: 1, timescale: CMTimeScale(preferredFPS))
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
    }
}

extension PicCameraService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        
        guard error == nil else {
            return
        }

        let captureID = photo.resolvedSettings.uniqueID
        var payload = capturePayloads[captureID] ?? CapturePayload()
        payload.photo = photo
        capturePayloads[captureID] = payload
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL,
                                 duration: CMTime,
                                 photoDisplayTime: CMTime,
                                 resolvedSettings: AVCaptureResolvedPhotoSettings,
                                 error: Error?) {
        guard error == nil else {
            try? FileManager.default.removeItem(at: outputFileURL)
            return
        }
        let captureID = resolvedSettings.uniqueID
        var payload = capturePayloads[captureID] ?? CapturePayload()
        payload.liveMovieURL = outputFileURL
        capturePayloads[captureID] = payload
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                                 error: Error?) {
        let captureID = resolvedSettings.uniqueID
        let payload = capturePayloads.removeValue(forKey: captureID)

        if let error {
            if let liveMovieURL = payload?.liveMovieURL {
                try? FileManager.default.removeItem(at: liveMovieURL)
            }
            _ = error
            onCaptureError?(error)
            return
        }

        guard let payload else {
            onCaptureError?(nil)
            return
        }
        if let photo = payload.photo {
            if let liveMovieURL = payload.liveMovieURL {
                onLivePhotoCapture?(photo, liveMovieURL)
            } else {
                onPhotoCapture?(photo)
            }
        } else {
            onCaptureError?(nil)
        }
    }

}

extension PicCameraService: AVCaptureDataOutputSynchronizerDelegate {
    nonisolated func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                                            didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        guard let synchronizedVideoData = synchronizedDataCollection.synchronizedData(for: videoOutput) as? AVCaptureSynchronizedSampleBufferData,
              !synchronizedVideoData.sampleBufferWasDropped,
              let pixelBuffer = CMSampleBufferGetImageBuffer(synchronizedVideoData.sampleBuffer) else {
            return
        }
        let depthData: AVDepthData?
        if let synchronizedDepthData = synchronizedDataCollection.synchronizedData(for: depthOutput) as? AVCaptureSynchronizedDepthData,
           !synchronizedDepthData.depthDataWasDropped {
            depthData = synchronizedDepthData.depthData
        } else {
            depthData = nil
        }
        frameConsumer?.consume(pixelBuffer: pixelBuffer, depthData: depthData)
    }
}

extension PicCameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameConsumer?.consume(pixelBuffer: pixelBuffer, depthData: nil)
    }
}

private final class PicCameraFaceMetadataHandler: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    var onFaces: (([CGRect]) -> Void)?
    private var lastEmitTime: CFTimeInterval = 0
    private var lastRects: [CGRect] = []

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        let rects = metadataObjects.compactMap { object -> CGRect? in
            guard object.type == .face else { return nil }
            return object.bounds
        }
        let now = CACurrentMediaTime()
        guard rects != lastRects || now - lastEmitTime >= 1.0 / 15.0 else { return }
        lastEmitTime = now
        lastRects = rects
        onFaces?(rects)
    }
}
