import GPUImage
import Metal

// MARK: - 自定义 GPUImage3 Operation（从 App metallib 加载 shader）

/// GPUImage3 的 BasicOperation 从 Bundle.module 加载 shader，找不到 app 自定义 shader。
/// 此类实现 ImageProcessingOperation，从 app default metallib 加载 fragment 函数，
/// 但复用 GPUImage3 的顶点函数和渲染管线。
nonisolated class AppShaderOperation: ImageProcessingOperation {
    let maximumInputs: UInt
    let targets = TargetContainer()
    let sources = SourceContainer()

    var uniformSettings: ShaderUniformSettings
    /// 额外的 fragment 纹理（不通过 GPUImage 输入，直接绑定到指定 index）
    var extraFragmentTextures: [Int: MTLTexture] = [:]
    private let renderPipelineState: MTLRenderPipelineState
    private var inputTextures = [UInt: Texture]()
    private let textureInputSemaphore = DispatchSemaphore(value: 1)

    init(fragmentFunctionName: String, numberOfInputs: UInt = 1) {
        self.maximumInputs = numberOfInputs

        let device = sharedMetalRenderingDevice.device
        guard let appLibrary = device.makeDefaultLibrary() else {
            fatalError("无法加载 app default metallib")
        }

        let vertexName = defaultVertexFunctionNameForInputs(numberOfInputs)
        guard let vertexFunction = sharedMetalRenderingDevice.shaderLibrary.makeFunction(name: vertexName) else {
            fatalError("找不到顶点函数 \(vertexName)")
        }
        guard let fragmentFunction = appLibrary.makeFunction(name: fragmentFunctionName) else {
            fatalError("找不到片段函数 \(fragmentFunctionName)")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.rasterSampleCount = 1
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction

        let pipelineResult: (MTLRenderPipelineState, MTLRenderPipelineReflection?)
        do {
            pipelineResult = try device.makeRenderPipelineState(
                descriptor: descriptor, options: [.bufferTypeInfo, .bindingInfo])
        } catch {
            fatalError("无法创建渲染管线: \(error)")
        }
        renderPipelineState = pipelineResult.0
        let reflection = pipelineResult.1

        var lookupTable: [String: (Int, MTLStructMember)] = [:]
        var bufferSize = 0
        if let fragmentBindings = reflection?.fragmentBindings {
            for binding in fragmentBindings {
                if let bufferBinding = binding as? MTLBufferBinding,
                   let members = bufferBinding.bufferStructType?.members.enumerated() {
                    bufferSize = bufferBinding.bufferDataSize
                    for (index, uniform) in members {
                        lookupTable[uniform.name] = (index, uniform)
                    }
                }
            }
        }
        uniformSettings = ShaderUniformSettings(uniformLookupTable: lookupTable, bufferSize: bufferSize)
    }

    func transmitPreviousImage(to target: ImageConsumer, atIndex: UInt) {}

    func newTextureAvailable(_ texture: Texture, fromSourceIndex: UInt) {
        let _ = textureInputSemaphore.wait(timeout: .distantFuture)
        defer { textureInputSemaphore.signal() }

        inputTextures[fromSourceIndex] = texture

        guard UInt(inputTextures.count) >= maximumInputs else { return }

        let first = inputTextures[0]!
        let outputWidth = first.texture.width
        let outputHeight = first.texture.height

        guard let commandBuffer = sharedMetalRenderingDevice.commandQueue.makeCommandBuffer() else { return }
        let outputTexture = Texture(device: sharedMetalRenderingDevice.device, orientation: .portrait,
                                    width: outputWidth, height: outputHeight, timingStyle: first.timingStyle)

        // 手动渲染 quad（renderQuad 是 internal，无法从外部调用）
        let vertices: [Float] = [-1, 1, 1, 1, -1, -1, 1, -1]
        let vertexBuffer = sharedMetalRenderingDevice.device.makeBuffer(
            bytes: vertices, length: vertices.count * MemoryLayout<Float>.size, options: [])!

        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = outputTexture.texture
        renderPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        renderPass.colorAttachments[0].storeAction = .store
        renderPass.colorAttachments[0].loadAction = .clear

        if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) {
            renderEncoder.setFrontFacing(.counterClockwise)
            renderEncoder.setRenderPipelineState(renderPipelineState)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

            // 标准纹理坐标
            let texCoords: [Float] = [0, 0, 1, 0, 0, 1, 1, 1]
            for textureIndex in 0..<inputTextures.count {
                guard let tex = inputTextures[UInt(textureIndex)] else { continue }
                let tcBuffer = sharedMetalRenderingDevice.device.makeBuffer(
                    bytes: texCoords, length: texCoords.count * MemoryLayout<Float>.size, options: [])!
                renderEncoder.setVertexBuffer(tcBuffer, offset: 0, index: 1 + textureIndex)
                renderEncoder.setFragmentTexture(tex.texture, index: textureIndex)
            }
            // 绑定额外纹理（如人脸遮罩）
            for (idx, tex) in extraFragmentTextures {
                renderEncoder.setFragmentTexture(tex, index: idx)
            }
            uniformSettings.restoreShaderSettings(renderEncoder: renderEncoder)
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            renderEncoder.endEncoding()
        }
        commandBuffer.commit()

        inputTextures.removeAll()

        textureInputSemaphore.signal()
        updateTargetsWithTexture(outputTexture)
        let _ = textureInputSemaphore.wait(timeout: .distantFuture)
    }
}

// MARK: - 磨皮滤镜工厂

nonisolated enum SkinSmoothingFactory {
    static func makeBilateralFilter(distanceNormalizationFactor: Float = 8.0) -> AppShaderOperation {
        let op = AppShaderOperation(fragmentFunctionName: "bilateralFragment", numberOfInputs: 1)
        op.uniformSettings["distanceNormalizationFactor"] = distanceNormalizationFactor
        return op
    }

    /// 可分离 Bilateral 横向 1D pass
    static func makeBilateralH(distanceNormalizationFactor: Float = 8.0) -> AppShaderOperation {
        let op = AppShaderOperation(fragmentFunctionName: "bilateralHFragment", numberOfInputs: 1)
        op.uniformSettings["distanceNormalizationFactor"] = distanceNormalizationFactor
        return op
    }

    /// 可分离 Bilateral 纵向 1D pass
    static func makeBilateralV(distanceNormalizationFactor: Float = 8.0) -> AppShaderOperation {
        let op = AppShaderOperation(fragmentFunctionName: "bilateralVFragment", numberOfInputs: 1)
        op.uniformSettings["distanceNormalizationFactor"] = distanceNormalizationFactor
        return op
    }

    /// combine 需要 2 个 GPUImage 输入（blurred + original），mask 通过额外纹理绑定。
    /// personMask 语义：人物分割 mask（白=人物/黑=背景），背景完全不磨皮。
    static func makeSkinSmoothCombine(intensity: Float = 0.5, personMask: MTLTexture?) -> AppShaderOperation {
        let op = AppShaderOperation(fragmentFunctionName: "skinSmoothCombineFragment", numberOfInputs: 2)
        op.uniformSettings["intensity"] = intensity
        op.extraFragmentTextures[2] = personMask ?? PersonSegmentationService.whiteFallbackTexture
        return op
    }

    /// 亮肤（YUV 方案）：单 pass 局部提亮 + 去黄偏粉 + 高频残差细节保护。
    /// 与 makeSkinWhiten（LUT 方案）互补，可串联使用。
    static func makeSkinWhitenYUV(strength: Float, personMask: MTLTexture?) -> AppShaderOperation {
        let op = AppShaderOperation(fragmentFunctionName: "skinWhitenYUVFragment", numberOfInputs: 1)
        op.uniformSettings["yuvStrength"] = strength
        op.extraFragmentTextures[1] = personMask ?? PersonSegmentationService.whiteFallbackTexture
        return op
    }

    /// 美白：肤色 Mask + 3D LUT + 高光保护，单 Pass。
    /// LUT 在 App 启动时一次性生成并缓存，强度通过 shader 端 mix 控制。
    static func makeSkinWhiten(strength: Float, personMask: MTLTexture?) -> AppShaderOperation {
        let op = AppShaderOperation(fragmentFunctionName: "skinWhitenLUTFragment", numberOfInputs: 1)
        op.uniformSettings["whitenStrength"] = strength
        if let lut = WhiteningLUTGenerator.sharedLUT {
            op.extraFragmentTextures[1] = lut
        }
        op.extraFragmentTextures[2] = personMask ?? PersonSegmentationService.whiteFallbackTexture
        return op
    }
}
