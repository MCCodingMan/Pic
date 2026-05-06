#include <metal_stdlib>
using namespace metal;

// 实时美颜统一 compute kernel：
// 单 pass 完成 磨皮(廉价 bilateral) + 亮肤(YUV) + 美白(skin-mask brightness lift)
//
// 用于美颜相机的实时预览（CVPixelBuffer 帧），替代之前的 CIFilter 路径，
// 全部走 Metal compute，与编辑器侧的 compute kernel 调用范式统一。
//
// 输入：
//   inTex     : BGRA 相机帧
//   outTex    : 写出 BGRA
//   params    : 美颜强度 + 人脸圆数量
//   faces     : 最多 4 个人脸圆 (中心 uv + 半径 uv)，由 CPU 端从 FaceContext 计算

struct RealtimeBeautyParams {
    float smoothing;     // 0..1
    float whitening;     // 0..1
    float whiteningYUV;  // 0..1
    int   faceCount;     // 0..4
};

struct FaceCircle {
    float2 center;       // 归一化 UV (0..1)
    float  radius;       // 归一化半径
    float  _pad;
};

struct RealtimeCameraAdjustmentParams {
    float exposure;
    float contrast;
    float brightness;
    float saturation;
    float highlights;
    float shadows;
    float temperature;
    float tint;
    float vignette;
    float sharpen;
    float clarity;
    float grain;
};

struct RealtimeColorMatrixParams {
    float4 rVector;
    float4 gVector;
    float4 bVector;
    float4 aVector;
    float4 biasVector;
};

static inline float realtimeLuminance(float3 color) {
    return dot(color, float3(0.2126, 0.7152, 0.0722));
}

static inline float4 realtimeApplyCameraFilter(float4 source,
                                               float3 baseColor,
                                               float2 uv,
                                               float2 px,
                                               uint2 gid,
                                               texture2d<float, access::sample> inTex,
                                               sampler s,
                                               constant RealtimeCameraAdjustmentParams &adjParams,
                                               constant RealtimeColorMatrixParams &matrixParams,
                                               float intensity) {
    float3 color = baseColor;
    float detailAmount = max(adjParams.sharpen * 0.16 + adjParams.clarity * 0.10, 0.0);
    float softenAmount = max(-adjParams.sharpen * 0.22 - adjParams.clarity * 0.12, 0.0);

    if (detailAmount > 0.0001 || softenAmount > 0.0001) {
        float3 left = inTex.sample(s, uv + float2(-px.x, 0.0)).rgb;
        float3 right = inTex.sample(s, uv + float2(px.x, 0.0)).rgb;
        float3 up = inTex.sample(s, uv + float2(0.0, -px.y)).rgb;
        float3 down = inTex.sample(s, uv + float2(0.0, px.y)).rgb;
        float3 crossBlur = (left + right + up + down) * 0.25;
        if (detailAmount > 0.0001) {
            color += (color - crossBlur) * detailAmount;
        }
        if (softenAmount > 0.0001) {
            color = mix(color, crossBlur, clamp(softenAmount, 0.0, 0.75));
        }
    }

    if (adjParams.exposure != 0.0) {
        color *= pow(2.0, adjParams.exposure);
    }
    color = (color - 0.5) * adjParams.contrast + 0.5 + adjParams.brightness;

    float luma = realtimeLuminance(color);
    color = mix(float3(luma), color, adjParams.saturation);

    if (adjParams.highlights != 0.0 || adjParams.shadows != 0.0) {
        float lum = realtimeLuminance(color);
        float shadowFactor = 1.0 - lum;
        float highlightFactor = lum;
        if (adjParams.shadows != 0.0) {
            color *= (1.0 + adjParams.shadows * shadowFactor * 0.3);
        }
        if (adjParams.highlights != 0.0) {
            color *= (1.0 + adjParams.highlights * highlightFactor * 0.3);
        }
    }

    if (adjParams.temperature != 0.0 || adjParams.tint != 0.0) {
        float3 scale = float3(1.0);
        scale.r *= (1.0 + adjParams.temperature * 0.1);
        scale.b *= (1.0 - adjParams.temperature * 0.1);
        scale.g *= (1.0 - adjParams.tint * 0.1);
        scale.r *= (1.0 + adjParams.tint * 0.05);
        scale.b *= (1.0 + adjParams.tint * 0.05);
        color *= scale;
    }

    float4 adjustedColor = float4(clamp(color, 0.0, 1.0), source.a);
    float r = dot(adjustedColor, matrixParams.rVector);
    float g = dot(adjustedColor, matrixParams.gVector);
    float b = dot(adjustedColor, matrixParams.bVector);
    float a = dot(adjustedColor, matrixParams.aVector);
    float4 result = mix(adjustedColor, clamp(float4(r, g, b, a) + matrixParams.biasVector, 0.0, 1.0), intensity);

    if (adjParams.vignette > 0.0001) {
        float dist = distance(uv, float2(0.5, 0.5));
        float v = smoothstep(0.34, 0.78, dist) * adjParams.vignette * 0.72;
        result.rgb *= (1.0 - v);
    }

    if (adjParams.grain > 0.0001) {
        float noise = fract(sin(dot(float2(gid), float2(12.9898, 78.233))) * 43758.5453);
        result.rgb = clamp(result.rgb + (noise - 0.5) * adjParams.grain * 0.16, 0.0, 1.0);
    }

    return float4(clamp(result.rgb, 0.0, 1.0), result.a);
}

kernel void realtimeBeautyKernel(
    texture2d<float, access::sample> inTex   [[texture(0)]],
    texture2d<float, access::write>  outTex  [[texture(1)]],
    constant RealtimeBeautyParams &params    [[buffer(0)]],
    constant FaceCircle *faces               [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;
    constexpr sampler s(mag_filter::linear, min_filter::linear, address::clamp_to_edge);

    float w = float(inTex.get_width());
    float h = float(inTex.get_height());
    float2 uv = (float2(gid) + 0.5) / float2(w, h);

    float4 src = inTex.sample(s, uv);
    float3 rgb = clamp(src.rgb, 0.0, 1.0);

    // ---- 1. 廉价 bilateral：仅磨皮开启时采样，避免美白/亮肤空跑 16 次 texture sample
    float tw = 1.0 / w;
    float th = 1.0 / h;
    float3 smoothed = rgb;
    if (params.smoothing > 0.001) {
        float faceMask = 0.0;
        int n = min(params.faceCount, 4);
        for (int i = 0; i < n; i++) {
            float2 d = uv - faces[i].center;
            float dist = length(d);
            float r = max(faces[i].radius, 1e-4);
            float m = 1.0 - smoothstep(r * 0.3, r, dist);
            faceMask = max(faceMask, m);
        }
        if (n == 0) faceMask = 0.5;

        float sigmaR = 0.18;
        float twoSigmaR2 = 2.0 * sigmaR * sigmaR;
        float3 sumC = rgb;
        float wsum = 1.0;
        for (int i = 1; i <= 4; i++) {
            float fi = float(i);
            float spatial = exp(-(fi * fi) / 8.0);
            float2 offs[4] = {
                float2( fi * tw, 0.0),
                float2(-fi * tw, 0.0),
                float2( 0.0,  fi * th),
                float2( 0.0, -fi * th)
            };
            for (int j = 0; j < 4; j++) {
                float3 c = inTex.sample(s, uv + offs[j]).rgb;
                float3 diff = c - rgb;
                float range = exp(-dot(diff, diff) / twoSigmaR2);
                float wt = spatial * range;
                sumC += c * wt;
                wsum += wt;
            }
        }
        float3 blurred = sumC / wsum;
        smoothed = mix(rgb, blurred, params.smoothing * faceMask);
    }

    // ---- 2. 肤色 mask（YCbCr 椭圆 + 亮度门限）
    float Y  = dot(smoothed, float3(0.299, 0.587, 0.114));
    float Cb = -0.168736 * smoothed.r - 0.331264 * smoothed.g + 0.5      * smoothed.b + 0.5;
    float Cr =  0.5      * smoothed.r - 0.418688 * smoothed.g - 0.081312 * smoothed.b + 0.5;
    float2 dcc = float2(Cb - 0.42, Cr - 0.59);
    float skinDist = length(dcc);
    float skinMask = 1.0 - smoothstep(0.08, 0.18, skinDist);
    skinMask *= smoothstep(0.20, 0.35, Y);
    skinMask *= 1.0 - smoothstep(0.86, 0.98, Y);

    // ---- 3. 亮肤 (YUV) ：抬亮度 + 微偏粉
    float yuvEff = params.whiteningYUV * skinMask;
    float Yw = clamp(Y + yuvEff * 0.12, 0.0, 1.0);
    float Cbw = Cb - yuvEff * 0.010;
    float Crw = Cr + yuvEff * 0.012;
    float cbv = Cbw - 0.5;
    float crv = Crw - 0.5;
    float3 yuvOut = float3(
        Yw + 1.402    * crv,
        Yw - 0.344136 * cbv - 0.714136 * crv,
        Yw + 1.772    * cbv
    );

    // ---- 4. 美白：肤色区轻微提亮
    float3 result = yuvOut + params.whitening * skinMask * 0.08;
    result = clamp(result, 0.0, 1.0);

    outTex.write(float4(result, src.a), gid);
}

kernel void realtimeBeautyFilterKernel(
    texture2d<float, access::sample> inTex [[texture(0)]],
    texture2d<float, access::write> outTex [[texture(1)]],
    constant RealtimeBeautyParams &params [[buffer(0)]],
    constant FaceCircle *faces [[buffer(1)]],
    constant RealtimeCameraAdjustmentParams &adjParams [[buffer(2)]],
    constant RealtimeColorMatrixParams &matrixParams [[buffer(3)]],
    constant float &intensity [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;
    constexpr sampler s(mag_filter::linear, min_filter::linear, address::clamp_to_edge);

    float w = float(inTex.get_width());
    float h = float(inTex.get_height());
    float2 uv = (float2(gid) + 0.5) / float2(w, h);
    float2 px = 1.0 / float2(w, h);

    float4 src = inTex.sample(s, uv);
    float3 rgb = clamp(src.rgb, 0.0, 1.0);

    float tw = 1.0 / w;
    float th = 1.0 / h;
    float3 smoothed = rgb;
    if (params.smoothing > 0.001) {
        float faceMask = 0.0;
        int n = min(params.faceCount, 4);
        for (int i = 0; i < n; i++) {
            float2 d = uv - faces[i].center;
            float dist = length(d);
            float r = max(faces[i].radius, 1e-4);
            float m = 1.0 - smoothstep(r * 0.3, r, dist);
            faceMask = max(faceMask, m);
        }
        if (n == 0) faceMask = 0.5;

        float sigmaR = 0.18;
        float twoSigmaR2 = 2.0 * sigmaR * sigmaR;
        float3 sumC = rgb;
        float wsum = 1.0;
        for (int i = 1; i <= 4; i++) {
            float fi = float(i);
            float spatial = exp(-(fi * fi) / 8.0);
            float2 offs[4] = {
                float2( fi * tw, 0.0),
                float2(-fi * tw, 0.0),
                float2( 0.0,  fi * th),
                float2( 0.0, -fi * th)
            };
            for (int j = 0; j < 4; j++) {
                float3 c = inTex.sample(s, uv + offs[j]).rgb;
                float3 diff = c - rgb;
                float range = exp(-dot(diff, diff) / twoSigmaR2);
                float wt = spatial * range;
                sumC += c * wt;
                wsum += wt;
            }
        }
        float3 blurred = sumC / wsum;
        smoothed = mix(rgb, blurred, params.smoothing * faceMask);
    }

    float Y = dot(smoothed, float3(0.299, 0.587, 0.114));
    float Cb = -0.168736 * smoothed.r - 0.331264 * smoothed.g + 0.5 * smoothed.b + 0.5;
    float Cr = 0.5 * smoothed.r - 0.418688 * smoothed.g - 0.081312 * smoothed.b + 0.5;
    float2 dcc = float2(Cb - 0.42, Cr - 0.59);
    float skinDist = length(dcc);
    float skinMask = 1.0 - smoothstep(0.08, 0.18, skinDist);
    skinMask *= smoothstep(0.20, 0.35, Y);
    skinMask *= 1.0 - smoothstep(0.86, 0.98, Y);

    float yuvEff = params.whiteningYUV * skinMask;
    float Yw = clamp(Y + yuvEff * 0.12, 0.0, 1.0);
    float Cbw = Cb - yuvEff * 0.010;
    float Crw = Cr + yuvEff * 0.012;
    float cbv = Cbw - 0.5;
    float crv = Crw - 0.5;
    float3 yuvOut = float3(
        Yw + 1.402 * crv,
        Yw - 0.344136 * cbv - 0.714136 * crv,
        Yw + 1.772 * cbv
    );

    float3 beautified = clamp(yuvOut + params.whitening * skinMask * 0.08, 0.0, 1.0);
    float4 filtered = realtimeApplyCameraFilter(src, beautified, uv, px, gid, inTex, s, adjParams, matrixParams, intensity);
    outTex.write(filtered, gid);
}
