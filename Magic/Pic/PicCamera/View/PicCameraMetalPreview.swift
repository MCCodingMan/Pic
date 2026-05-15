import SwiftUI
import MetalKit

struct PicCameraMetalPreview: UIViewRepresentable {
    let renderer: PicCameraRenderer
    let service: PicCameraService
    let isPaused: Bool

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.device)
        view.isOpaque = true
        view.enableSetNeedsDisplay = false
        view.isPaused = isPaused
        view.preferredFramesPerSecond = 60
        view.autoResizeDrawable = true
        renderer.configure(for: view)
        view.delegate = renderer
        Task { @MainActor in
            service.attachPreviewLayer(view.layer)
        }
        view.alpha = 0
        UIView.animate(withDuration: 0.5, delay: 0.5, options: .curveEaseInOut) {
            view.alpha = 1
        }
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        uiView.isPaused = isPaused
    }
}
