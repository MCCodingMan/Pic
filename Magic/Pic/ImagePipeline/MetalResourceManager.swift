import Metal
import CoreImage

/// 统一的 Metal 资源管理：device、command queue、default library 与 compute pipeline 缓存。
/// 替代 ImageProcessingService / RealtimeBeautyPipeline / 各处散落的 makeDefaultLibrary 调用。
nonisolated final class MetalResourceManager: @unchecked Sendable {
    static let shared = MetalResourceManager()

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let library: MTLLibrary?
    let ciContext: CIContext

    private var pipelineCache: [String: MTLComputePipelineState] = [:]
    private let cacheLock = NSLock()

    init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            fatalError("Metal not supported")
        }
        self.device = device
        self.commandQueue = queue
        self.ciContext = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])

        var lib: MTLLibrary?
        if let url = Bundle.main.url(forResource: "default", withExtension: "metallib") {
            lib = try? device.makeLibrary(URL: url)
        }
        if lib == nil {
            lib = try? device.makeDefaultLibrary(bundle: Bundle.main)
        }
        self.library = lib
    }

    /// 按名字获取 compute pipeline state（带缓存）
    func computePipeline(named name: String) -> MTLComputePipelineState? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = pipelineCache[name] { return cached }
        guard let library, let function = library.makeFunction(name: name) else {
            print("[MetalResourceManager] function \(name) not found")
            return nil
        }
        guard let state = try? device.makeComputePipelineState(function: function) else {
            print("[MetalResourceManager] failed to create pipeline for \(name)")
            return nil
        }
        pipelineCache[name] = state
        return state
    }
}
