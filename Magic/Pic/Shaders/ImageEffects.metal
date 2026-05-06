//
//  ImageEffects.metal
//  Split from Shaders.ci.metal
//  Contains: sharpen, vignette, grain, curve kernels
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Sharpen

kernel void sharpenKernel(texture2d<float, access::read> inTexture [[texture(0)]],
                          texture2d<float, access::write> outTexture [[texture(1)]],
                          constant float &intensity [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }

    float4 center = inTexture.read(gid);
    uint w = inTexture.get_width();
    uint h = inTexture.get_height();
    float4 top    = inTexture.read(uint2(gid.x, gid.y > 0 ? gid.y - 1 : 0));
    float4 bottom = inTexture.read(uint2(gid.x, min(gid.y + 1, h - 1)));
    float4 left   = inTexture.read(uint2(gid.x > 0 ? gid.x - 1 : 0, gid.y));
    float4 right  = inTexture.read(uint2(min(gid.x + 1, w - 1), gid.y));

    float3 sharpened = center.rgb * 5.0 - (top.rgb + bottom.rgb + left.rgb + right.rgb);
    float3 result = mix(center.rgb, sharpened, intensity * 0.2);
    outTexture.write(float4(clamp(result, 0.0, 1.0), center.a), gid);
}

// MARK: - Vignette

struct VignetteParams {
    float intensity;
    float radius;
};

kernel void vignetteKernel(texture2d<float, access::read> inTexture [[texture(0)]],
                           texture2d<float, access::write> outTexture [[texture(1)]],
                           constant VignetteParams &params [[buffer(0)]],
                           uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }

    float4 color = inTexture.read(gid);
    float2 size = float2(outTexture.get_width(), outTexture.get_height());
    float2 uv = (float2(gid) + 0.5) / size;
    float2 center = float2(0.5, 0.5);
    float aspect = size.x / size.y;
    float2 uvCorrected = float2((uv.x - center.x) * aspect, uv.y - center.y);
    float dist = length(uvCorrected);
    float darken = smoothstep(params.radius * 0.5, 1.0, dist);
    color.rgb *= (1.0 - darken * params.intensity);
    outTexture.write(color, gid);
}

// MARK: - Grain

kernel void grainKernel(texture2d<float, access::read> inTexture [[texture(0)]],
                        texture2d<float, access::write> outTexture [[texture(1)]],
                        constant float &intensity [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }

    float4 color = inTexture.read(gid);
    float2 uv = float2(gid);
    float noise = fract(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453);
    float3 result = color.rgb + (noise - 0.5) * intensity;
    outTexture.write(float4(clamp(result, 0.0, 1.0), color.a), gid);
}

// MARK: - Curves (LUT)

kernel void curveKernel(texture2d<float, access::read> inTexture [[texture(0)]],
                        texture2d<float, access::write> outTexture [[texture(1)]],
                        texture1d<float, access::sample> curveTexture [[texture(2)]],
                        uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }

    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);

    float4 color = inTexture.read(gid);
    float r = curveTexture.sample(s, (color.r * 255.0 + 0.5) / 256.0).r;
    float g = curveTexture.sample(s, (color.g * 255.0 + 0.5) / 256.0).r;
    float b = curveTexture.sample(s, (color.b * 255.0 + 0.5) / 256.0).r;
    outTexture.write(float4(r, g, b, color.a), gid);
}
