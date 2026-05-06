//
//  ImageAdjustments.metal
//  Split from Shaders.ci.metal
//  Contains: basic adjustments, HSL, color matrix, unified filter kernels
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Helper Functions

float3 rgb2hsv(float3 c) {
    float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = mix(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = mix(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-6;
    return float3(fract(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float3 hsv2rgb(float3 c) {
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

float luminance(float3 color) {
    return dot(color, float3(0.2126, 0.7152, 0.0722));
}

// MARK: - Parameters

struct AdjustmentParams {
    float exposure;
    float contrast;
    float brightness;
    float saturation;
    float highlights;
    float shadows;
    float temperature;
    float tint;
};

struct HSLParams {
    float hRed, sRed, lRed;
    float hOrange, sOrange, lOrange;
    float hYellow, sYellow, lYellow;
    float hGreen, sGreen, lGreen;
    float hCyan, sCyan, lCyan;
    float hBlue, sBlue, lBlue;
    float hPurple, sPurple, lPurple;
    float hMagenta, sMagenta, lMagenta;
};

struct ColorMatrixParams {
    float4 rVector;
    float4 gVector;
    float4 bVector;
    float4 aVector;
    float4 biasVector;
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

struct CameraDisplayParams {
    float scale;
    float2 offset;
};

// MARK: - Basic Adjustments

kernel void basicAdjustmentsKernel(texture2d<float, access::read> inTexture [[texture(0)]],
                                   texture2d<float, access::write> outTexture [[texture(1)]],
                                   constant AdjustmentParams &params [[buffer(0)]],
                                   uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }

    float4 inColor = inTexture.read(gid);
    float3 color = inColor.rgb;

    if (params.exposure != 0.0) {
        color *= pow(2.0, params.exposure);
    }

    color = (color - 0.5) * params.contrast + 0.5 + params.brightness;

    float luma = luminance(color);
    color = mix(float3(luma), color, params.saturation);

    if (params.highlights != 0.0 || params.shadows != 0.0) {
        float lum = luminance(color);
        float shadowFactor = 1.0 - lum;
        float highlightFactor = lum;
        if (params.shadows != 0.0) {
             color *= (1.0 + params.shadows * shadowFactor * 0.3);
        }
        if (params.highlights != 0.0) {
             color *= (1.0 + params.highlights * highlightFactor * 0.3);
        }
    }

    if (params.temperature != 0.0 || params.tint != 0.0) {
        float3 scale = float3(1.0);
        scale.r *= (1.0 + params.temperature * 0.1);
        scale.b *= (1.0 - params.temperature * 0.1);
        scale.g *= (1.0 - params.tint * 0.1);
        scale.r *= (1.0 + params.tint * 0.05);
        scale.b *= (1.0 + params.tint * 0.05);
        color *= scale;
    }

    outTexture.write(float4(clamp(color, 0.0, 1.0), inColor.a), gid);
}

// MARK: - HSL Adjustment

kernel void hslKernel(texture2d<float, access::read> inTexture [[texture(0)]],
                      texture2d<float, access::write> outTexture [[texture(1)]],
                      constant HSLParams &params [[buffer(0)]],
                      uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }

    float4 inColor = inTexture.read(gid);
    float3 color = inColor.rgb;
    float3 hsv = rgb2hsv(color);
    float hue = hsv.x;

    float dRed = min(abs(hue - 0.0), 1.0 - abs(hue - 0.0));
    float wRed = max(0.0, 1.0 - dRed * 8.0);
    float dOrange = min(abs(hue - 0.0833), 1.0 - abs(hue - 0.0833));
    float wOrange = max(0.0, 1.0 - dOrange * 8.0);
    float dYellow = min(abs(hue - 0.1667), 1.0 - abs(hue - 0.1667));
    float wYellow = max(0.0, 1.0 - dYellow * 8.0);
    float dGreen = min(abs(hue - 0.3333), 1.0 - abs(hue - 0.3333));
    float wGreen = max(0.0, 1.0 - dGreen * 8.0);
    float dCyan = min(abs(hue - 0.5), 1.0 - abs(hue - 0.5));
    float wCyan = max(0.0, 1.0 - dCyan * 8.0);
    float dBlue = min(abs(hue - 0.6667), 1.0 - abs(hue - 0.6667));
    float wBlue = max(0.0, 1.0 - dBlue * 8.0);
    float dPurple = min(abs(hue - 0.75), 1.0 - abs(hue - 0.75));
    float wPurple = max(0.0, 1.0 - dPurple * 8.0);
    float dMagenta = min(abs(hue - 0.8333), 1.0 - abs(hue - 0.8333));
    float wMagenta = max(0.0, 1.0 - dMagenta * 8.0);

    float shiftH = (params.hRed * wRed + params.hOrange * wOrange + params.hYellow * wYellow + params.hGreen * wGreen +
                    params.hCyan * wCyan + params.hBlue * wBlue + params.hPurple * wPurple + params.hMagenta * wMagenta);
    float shiftS = (params.sRed * wRed + params.sOrange * wOrange + params.sYellow * wYellow + params.sGreen * wGreen +
                    params.sCyan * wCyan + params.sBlue * wBlue + params.sPurple * wPurple + params.sMagenta * wMagenta);
    float shiftV = (params.lRed * wRed + params.lOrange * wOrange + params.lYellow * wYellow + params.lGreen * wGreen +
                    params.lCyan * wCyan + params.lBlue * wBlue + params.lPurple * wPurple + params.lMagenta * wMagenta);

    hsv.x = fract(hsv.x + shiftH);
    hsv.y = clamp(hsv.y * (1.0 + shiftS), 0.0, 1.0);
    hsv.z = clamp(hsv.z * (1.0 + shiftV), 0.0, 1.0);

    outTexture.write(float4(hsv2rgb(hsv), inColor.a), gid);
}

// MARK: - Color Matrix

kernel void colorMatrixKernel(texture2d<float, access::read> inTexture [[texture(0)]],
                              texture2d<float, access::write> outTexture [[texture(1)]],
                              constant ColorMatrixParams &params [[buffer(0)]],
                              constant float &intensity [[buffer(1)]],
                              uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }

    float4 c = inTexture.read(gid);
    float r = dot(c, params.rVector);
    float g = dot(c, params.gVector);
    float b = dot(c, params.bVector);
    float a = dot(c, params.aVector);
    float4 result = float4(r, g, b, a) + params.biasVector;
    result = mix(c, clamp(result, 0.0, 1.0), intensity);
    outTexture.write(result, gid);
}

// MARK: - Unified Filter (Adjustments + Color Matrix)

kernel void unifiedFilterKernel(texture2d<float, access::read> inTexture [[texture(0)]],
                                texture2d<float, access::write> outTexture [[texture(1)]],
                                constant AdjustmentParams &adjParams [[buffer(0)]],
                                constant ColorMatrixParams &matrixParams [[buffer(1)]],
                                constant float &intensity [[buffer(2)]],
                                uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }

    float4 inColor = inTexture.read(gid);
    float3 color = inColor.rgb;

    if (adjParams.exposure != 0.0) {
        color *= pow(2.0, adjParams.exposure);
    }
    color = (color - 0.5) * adjParams.contrast + 0.5 + adjParams.brightness;
    float luma = luminance(color);
    color = mix(float3(luma), color, adjParams.saturation);

    if (adjParams.highlights != 0.0 || adjParams.shadows != 0.0) {
        float lum = luminance(color);
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

    float4 adjustedColor = float4(clamp(color, 0.0, 1.0), inColor.a);

    float r = dot(adjustedColor, matrixParams.rVector);
    float g = dot(adjustedColor, matrixParams.gVector);
    float b = dot(adjustedColor, matrixParams.bVector);
    float a = dot(adjustedColor, matrixParams.aVector);
    float4 result = float4(r, g, b, a) + matrixParams.biasVector;
    result = mix(inColor, clamp(result, 0.0, 1.0), intensity);
    outTexture.write(result, gid);
}

kernel void realtimeCameraFilterKernel(texture2d<float, access::sample> inTexture [[texture(0)]],
                                       texture2d<float, access::write> outTexture [[texture(1)]],
                                       constant RealtimeCameraAdjustmentParams &adjParams [[buffer(0)]],
                                       constant ColorMatrixParams &matrixParams [[buffer(1)]],
                                       constant float &intensity [[buffer(2)]],
                                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }

    constexpr sampler s(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    float2 size = float2(outTexture.get_width(), outTexture.get_height());
    float2 uv = (float2(gid) + 0.5) / size;
    float2 px = 1.0 / size;

    float4 inColor = inTexture.sample(s, uv);
    float3 color = inColor.rgb;
    float detailAmount = max(adjParams.sharpen * 0.16 + adjParams.clarity * 0.10, 0.0);
    float softenAmount = max(-adjParams.sharpen * 0.22 - adjParams.clarity * 0.12, 0.0);

    if (detailAmount > 0.0001 || softenAmount > 0.0001) {
        float3 left = inTexture.sample(s, uv + float2(-px.x, 0.0)).rgb;
        float3 right = inTexture.sample(s, uv + float2(px.x, 0.0)).rgb;
        float3 up = inTexture.sample(s, uv + float2(0.0, -px.y)).rgb;
        float3 down = inTexture.sample(s, uv + float2(0.0, px.y)).rgb;
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

    float luma = luminance(color);
    color = mix(float3(luma), color, adjParams.saturation);

    if (adjParams.highlights != 0.0 || adjParams.shadows != 0.0) {
        float lum = luminance(color);
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

    float4 adjustedColor = float4(clamp(color, 0.0, 1.0), inColor.a);
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

    outTexture.write(float4(clamp(result.rgb, 0.0, 1.0), result.a), gid);
}

kernel void cameraDisplayKernel(texture2d<float, access::sample> inTexture [[texture(0)]],
                                texture2d<float, access::write> outTexture [[texture(1)]],
                                constant CameraDisplayParams &params [[buffer(0)]],
                                uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }

    constexpr sampler s(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    float2 dst = float2(gid) + 0.5;
    float2 src = (dst - params.offset) / max(params.scale, 1e-6);
    float2 srcSize = float2(inTexture.get_width(), inTexture.get_height());
    float2 uv = src / srcSize;
    float4 color = inTexture.sample(s, uv);
    outTexture.write(color, gid);
}
