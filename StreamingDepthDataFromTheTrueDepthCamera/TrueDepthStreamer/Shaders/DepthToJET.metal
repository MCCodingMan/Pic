///*
//See the LICENSE.txt file for this sample’s licensing information.
//
//Abstract:
//Metal compute shader that translates depth values to JET RGB values.
//*/
//
//#include <metal_stdlib>
//using namespace metal;
//
//struct BGRAPixel {
//    uchar b;
//    uchar g;
//    uchar r;
//    uchar a;
//};
//
//struct JETParams {
//    int histogramSize;
//    int binningFactor;
//};
//
//// Compute kernel
//kernel void depthToJET(texture2d<float, access::read>  inputTexture      [[ texture(0) ]],
//                       texture2d<float, access::write> outputTexture     [[ texture(1) ]],
//                       constant JETParams& params [[ buffer(0) ]],
//                       constant float* histogram        [[ buffer(1) ]],
//                       constant BGRAPixel *colorTable [[ buffer(2) ]],
//                       uint2 gid [[ thread_position_in_grid ]])
//{
//    // Ensure we don't read or write outside of the texture
//    if ((gid.x >= inputTexture.get_width()) || (gid.y >= inputTexture.get_height())) {
//        return;
//    }
//    
//    // depthDataType is kCVPixelFormatType_DepthFloat16
//    float depth = inputTexture.read(gid).x;
//    
//    ushort histIndex = (ushort)(depth * params.binningFactor);
//    
//    // make sure the value is part of the histogram
//    if (histIndex >= params.histogramSize) {
//        return;
//    }
//    
//    float colorIndex = histogram[histIndex];
//    
//    BGRAPixel outputColor = colorTable[(int)colorIndex];
//    
//    outputTexture.write(float4(outputColor.r / 255.0, outputColor.g / 255.0, outputColor.b / 255.0, 1.0), gid);
//}
#include <metal_stdlib>
using namespace metal;

struct JETParams {
    int histogramSize;
    int binningFactor;
};

// Compute kernel - 深度图转灰度图
kernel void depthToJET(texture2d<float, access::read>  inputTexture  [[ texture(0) ]],
                       texture2d<float, access::write> outputTexture [[ texture(1) ]],
                       constant JETParams& params                    [[ buffer(0) ]],
                       constant float* histogram                     [[ buffer(1) ]],
                       uint2 gid [[ thread_position_in_grid ]])
{
    // Ensure we don't read or write outside of the texture
    if ((gid.x >= inputTexture.get_width()) || (gid.y >= inputTexture.get_height())) {
        return;
    }
    
    float depth = inputTexture.read(gid).x;
    
    ushort histIndex = (ushort)(depth * params.binningFactor);
    
    // make sure the value is part of the histogram
    if (histIndex >= params.histogramSize) {
        return;
    }
    
    // ✅ 用直方图均衡化后的值作为灰度（已归一化到 0~1）
    float gray = histogram[histIndex] / 255.0;
    
    outputTexture.write(float4(gray, gray, gray, 1.0), gid);
}
