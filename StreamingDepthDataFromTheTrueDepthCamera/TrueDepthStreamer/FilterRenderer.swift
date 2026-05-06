/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Filter renderer protocol.
*/

import CoreMedia

protocol FilterRenderer: AnyObject {
    
    var description: String { get }
    
    var isPrepared: Bool { get }
    
    // Prepare resources.
    // The outputRetainedBufferCountHint tells out of place renderers how many of
    // their output buffers will be held onto by the downstream pipeline at one time.
    // This can be used by the renderer to size and preallocate their pools.
    func prepare(with inputFormatDescription: CMFormatDescription, outputRetainedBufferCountHint: Int)
    
    // Release resources.
    func reset()
    
    // The format description of the output pixel buffers.
    var outputFormatDescription: CMFormatDescription? { get }
    
    // The format description of the input pixel buffers.
    var inputFormatDescription: CMFormatDescription? { get }
    
    // Render pixel buffer.
    func render(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer?
}

func allocateOutputBufferPool(with inputFormatDescription: CMFormatDescription,
                              outputRetainedBufferCountHint: Int) ->(
    outputBufferPool: CVPixelBufferPool?,
    outputColorSpace: CGColorSpace?,
    outputFormatDescription: CMFormatDescription?) {
        
        let inputMediaSubType = CMFormatDescriptionGetMediaSubType(inputFormatDescription)
        if inputMediaSubType != kCVPixelFormatType_32BGRA {
            assertionFailure("Invalid input pixel buffer type \(inputMediaSubType)")
            return (nil, nil, nil)
        }
        
        let inputDimensions = CMVideoFormatDescriptionGetDimensions(inputFormatDescription)
        var pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: UInt(inputMediaSubType),
            kCVPixelBufferWidthKey as String: Int(inputDimensions.width),
            kCVPixelBufferHeightKey as String: Int(inputDimensions.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        
        // Get pixel buffer attributes and color space from the input format description
        var cgColorSpace = CGColorSpaceCreateDeviceRGB()
        if let inputFormatDescriptionExtension = CMFormatDescriptionGetExtensions(inputFormatDescription) as Dictionary? {
            let colorPrimaries = inputFormatDescriptionExtension[kCVImageBufferColorPrimariesKey]
            
            if let colorPrimaries = colorPrimaries {
                var colorSpaceProperties: [String: AnyObject] = [kCVImageBufferColorPrimariesKey as String: colorPrimaries]
                
                if let yCbCrMatrix = inputFormatDescriptionExtension[kCVImageBufferYCbCrMatrixKey] {
                    colorSpaceProperties[kCVImageBufferYCbCrMatrixKey as String] = yCbCrMatrix
                }
                
                if let transferFunction = inputFormatDescriptionExtension[kCVImageBufferTransferFunctionKey] {
                    colorSpaceProperties[kCVImageBufferTransferFunctionKey as String] = transferFunction
                }
                
                pixelBufferAttributes[kCVBufferPropagatedAttachmentsKey as String] = colorSpaceProperties
            }
            
            if let cvColorspace = inputFormatDescriptionExtension[kCVImageBufferCGColorSpaceKey] {
                cgColorSpace = cvColorspace as! CGColorSpace
            } else if (colorPrimaries as? String) == (kCVImageBufferColorPrimaries_P3_D65 as String) {
                cgColorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
            }
        }
        
        // Create a pixel buffer pool with the same pixel attributes as the input format description
        let poolAttributes = [kCVPixelBufferPoolMinimumBufferCountKey as String: outputRetainedBufferCountHint]
        var cvPixelBufferPool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttributes as NSDictionary?, pixelBufferAttributes as NSDictionary?, &cvPixelBufferPool)
        guard let pixelBufferPool = cvPixelBufferPool else {
            assertionFailure("Allocation failure: Could not allocate pixel buffer pool")
            return (nil, nil, nil)
        }
        
        preallocateBuffers(pool: pixelBufferPool, allocationThreshold: outputRetainedBufferCountHint)
        
        // Get output format description
        var pixelBuffer: CVPixelBuffer?
        var outputFormatDescription: CMFormatDescription?
        let auxAttributes = [kCVPixelBufferPoolAllocationThresholdKey as String: outputRetainedBufferCountHint] as NSDictionary
        CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pixelBufferPool, auxAttributes, &pixelBuffer)
        if pixelBuffer != nil {
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                         imageBuffer: pixelBuffer!,
                                                         formatDescriptionOut: &outputFormatDescription)
        }
        pixelBuffer = nil
        
        return (pixelBufferPool, cgColorSpace, outputFormatDescription)
}

private func preallocateBuffers(pool: CVPixelBufferPool, allocationThreshold: Int) {
    var pixelBuffers = [CVPixelBuffer]()
    var error: CVReturn = kCVReturnSuccess
    let auxAttributes = [kCVPixelBufferPoolAllocationThresholdKey as String: allocationThreshold] as NSDictionary
    var pixelBuffer: CVPixelBuffer?
    while error == kCVReturnSuccess {
        error = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, auxAttributes, &pixelBuffer)
        if let pixelBuffer = pixelBuffer {
            pixelBuffers.append(pixelBuffer)
        }
        pixelBuffer = nil
    }
    pixelBuffers.removeAll()
}

/*
 
调用seedance2.0执行一个完整的生成视频和查询视频生成情况的结果
ARK_API_KEY: 5eb86b3b-e470-4f17-b05a-a9bbfac287e9
1、创建视频的接口
curl https://ark.cn-beijing.volces.com/api/v3/contents/generations/tasks \
-H "Content-Type: application/json" \
-H "Authorization: Bearer 5eb86b3b-e470-4f17-b05a-a9bbfac287e9" \
-d '{
    "model": "doubao-seedance-2-0-260128",
    "content": [
        {
            "type": "text",
            "text": "镜头从黑暗中缓慢推进，一束光照亮桌上的咖啡杯，热气缓缓升起，画面温暖治愈，最后定格在咖啡表面轻轻荡漾的涟漪，氛围安静、电影感、柔和光影"
        }
    ],
    "generate_audio": true,
    "ratio": "16:9",
    "duration": 4,
    "watermark": false
}'
2、轮训查询生成结果的请求
//将 {任务ID} 替换为创建视频生成任务时获得的任务ID
curl -X GET https://ark.cn-beijing.volces.com/api/v3/contents/generations/tasks/cgt-20260410114600-bxxbd \
-H "Content-Type: application/json"\
-H "Authorization: Bearer 5eb86b3b-e470-4f17-b05a-a9bbfac287e9"

第2步查询生成结果请求需要轮训查询状态，知道成功为止

你需要将这个流程记录到一个md文档中，并且，需要详细的记录请求的参数（json格式），返回参数（json格式），轮训时，每一次轮训的结果都需要记录进去

 */
