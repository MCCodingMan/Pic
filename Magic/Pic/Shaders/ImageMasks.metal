//
//  ImageMasks.metal
//  Split from Shaders.ci.metal
//  Contains: gradient, radial, blend, portrait, mask refine kernels
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Linear Gradient

struct GradientParams {
    float2 startPoint;
    float2 endPoint;
    float4 color0;
    float4 color1;
};

kernel void linearGradientKernel(texture2d<float, access::write> outTexture [[texture(0)]],
                                 constant GradientParams &params [[buffer(0)]],
                                 uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }

    float2 size = float2(outTexture.get_width(), outTexture.get_height());
    float2 uv = (float2(gid) + 0.5) / size;
    float2 start = params.startPoint;
    float2 end = params.endPoint;
    float2 ba = end - start;
    float2 pa = uv - start;
    float denom = dot(ba, ba);
    float t = (denom > 1.0e-10) ? dot(pa, ba) / denom : 0.0;
    t = clamp(t, 0.0, 1.0);
    float4 color = mix(params.color0, params.color1, t);
    outTexture.write(color, gid);
}

// MARK: - Radial Gradient

struct RadialGradientParams {
    float2 center;
    float radius0;
    float radius1;
    float4 color0;
    float4 color1;
};

kernel void radialGradientKernel(texture2d<float, access::write> outTexture [[texture(0)]],
                                 constant RadialGradientParams &params [[buffer(0)]],
                                 uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }

    float2 size = float2(outTexture.get_width(), outTexture.get_height());
    float2 uv = (float2(gid) + 0.5) / size;
    float aspect = size.x / size.y;
    float2 uvCorrected = uv;
    uvCorrected.x *= aspect;
    float2 centerCorrected = params.center;
    centerCorrected.x *= aspect;
    float distCorrected = distance(uvCorrected, centerCorrected);
    float range = params.radius1 - params.radius0;
    float t = (range > 1.0e-6) ? (distCorrected - params.radius0) / range : 1.0;
    t = clamp(t, 0.0, 1.0);
    float4 color = mix(params.color0, params.color1, t);
    outTexture.write(color, gid);
}

// MARK: - Portrait Blur

kernel void portraitBlurKernel(texture2d<float, access::read> originalTexture [[texture(0)]],
                               texture2d<float, access::read> blurredTexture [[texture(1)]],
                               texture2d<float, access::read> maskTexture [[texture(2)]],
                               texture2d<float, access::write> outTexture [[texture(3)]],
                               uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }

    float4 original = originalTexture.read(gid);
    float4 blurred = blurredTexture.read(gid);
    float maskValue = maskTexture.read(gid).r;
    float alpha = smoothstep(0.05, 0.95, maskValue);
    float4 result = mix(blurred, original, alpha);
    outTexture.write(result, gid);
}

// MARK: - Mask Refine

kernel void maskRefineKernel(texture2d<float, access::read> inMask [[texture(0)]],
                             texture2d<float, access::write> outMask [[texture(1)]],
                             constant float &radius [[buffer(0)]],
                             uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= outMask.get_width() || gid.y >= outMask.get_height()) {
        return;
    }

    uint w = inMask.get_width();
    uint h = inMask.get_height();
    int r = int(radius);

    float maxVal = 0.0;
    float sum = 0.0;
    float weightSum = 0.0;

    for (int dy = -r; dy <= r; dy++) {
        for (int dx = -r; dx <= r; dx++) {
            uint2 pos = uint2(
                clamp(int(gid.x) + dx, 0, int(w) - 1),
                clamp(int(gid.y) + dy, 0, int(h) - 1)
            );
            float val = inMask.read(pos).r;
            float dist = length(float2(float(dx), float(dy)));
            float weight = max(0.0, 1.0 - dist / (float(r) + 1.0));

            maxVal = max(maxVal, val);
            sum += val * weight;
            weightSum += weight;
        }
    }

    float avgVal = (weightSum > 0.0) ? sum / weightSum : 0.0;
    float result = mix(avgVal, maxVal, 0.3);
    outMask.write(float4(result, result, result, 1.0), gid);
}

// MARK: - Blend with Mask

kernel void blendWithMaskKernel(texture2d<float, access::read> inputTexture [[texture(0)]],
                                texture2d<float, access::read> backgroundTexture [[texture(1)]],
                                texture2d<float, access::read> maskTexture [[texture(2)]],
                                texture2d<float, access::write> outTexture [[texture(3)]],
                                uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }

    float4 fore = inputTexture.read(gid);
    float4 back = backgroundTexture.read(gid);
    float4 mask = maskTexture.read(gid);
    float alpha = mask.r;
    float4 result = mix(back, fore, alpha);
    outTexture.write(result, gid);
}
