#include <metal_stdlib>
using namespace metal;

// =====================================================================
// Guided Filter（灰度版）
//   q = a * I + b
//   a = cov(I, p) / (var(I) + eps)
//   b = mean(p) - a * mean(I)
//   I = guide（RGB 灰度，取 .r）
//   p = 原始 depth / CoC 场
// 作用：用 RGB 的边缘结构去约束糊糊的 depth，输出"贴边"的 mask
// =====================================================================
kernel void depthGuidedFilter(
    texture2d<float, access::sample> guide  [[texture(0)]],
    texture2d<float, access::sample> p_in   [[texture(1)]],
    texture2d<float, access::write>  q_out  [[texture(2)]],
    constant int   &radius                   [[buffer(0)]],
    constant float &eps                      [[buffer(1)]],
    uint2 gid                                [[thread_position_in_grid]]
) {
    uint W = q_out.get_width();
    uint H = q_out.get_height();
    if (gid.x >= W || gid.y >= H) return;

    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 size = float2(W, H);
    float2 uv0  = (float2(gid) + 0.5) / size;

    float mI = 0.0, mP = 0.0, cI = 0.0, cIP = 0.0;
    float n  = 0.0;

    for (int dy = -radius; dy <= radius; ++dy) {
        for (int dx = -radius; dx <= radius; ++dx) {
            float2 uv = uv0 + float2(dx, dy) / size;
            float I = guide.sample(s, uv).r;
            float p = p_in.sample(s, uv).r;
            mI  += I;
            mP  += p;
            cI  += I * I;
            cIP += I * p;
            n   += 1.0;
        }
    }

    mI  /= n;
    mP  /= n;
    cI  /= n;
    cIP /= n;

    float varI  = cI  - mI * mI;
    float covIp = cIP - mI * mP;

    float a = covIp / (varI + eps);
    float b = mP - a * mI;

    float I0 = guide.sample(s, uv0).r;
    float q  = clamp(a * I0 + b, 0.0, 1.0);
    q_out.write(float4(q, q, q, 1.0), gid);
}

// =====================================================================
// 变径散景（Bokeh）
//   - 每像素半径由 mask 决定：r = maxRadius * coc
//   - 六边形光圈：cos(6*angle) 约束采样圆 → 多边形
//   - 高光增强：亮像素权重 ∝ (brightness^2)，灯光会"炸开"
//   - 对焦区域（coc ≈ 0）直接保留原色，省开销
// =====================================================================
kernel void depthBokehBlur(
    texture2d<float, access::sample> color    [[texture(0)]],
    texture2d<float, access::sample> mask     [[texture(1)]],
    texture2d<float, access::write>  out_tex  [[texture(2)]],
    constant float &maxRadius                  [[buffer(0)]],
    uint2 gid                                  [[thread_position_in_grid]]
) {
    uint W = out_tex.get_width();
    uint H = out_tex.get_height();
    if (gid.x >= W || gid.y >= H) return;

    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 size = float2(W, H);
    float2 uv   = (float2(gid) + 0.5) / size;

    float  coc      = mask.sample(s, uv).r;
    float3 original = color.sample(s, uv).rgb;

    // 对焦区域直接输出原色
    if (coc < 0.02) {
        out_tex.write(float4(original, 1.0), gid);
        return;
    }

    float radius = max(1.0, maxRadius * coc);
    int   ir     = int(ceil(radius));

    float3 acc  = float3(0.0);
    float  wSum = 0.0;

    for (int dy = -ir; dy <= ir; ++dy) {
        for (int dx = -ir; dx <= ir; ++dx) {
            float2 off = float2(float(dx), float(dy));
            float  r   = length(off);
            if (r > radius) continue;

            // 六边形光圈约束
            float ang = atan2(off.y, off.x);
            float hex = cos(6.0 * ang);
            if (r > radius * (0.78 + 0.22 * hex)) continue;

            float2 suv = uv + off / size;
            float3 samp = color.sample(s, suv).rgb;

            // 高光增强：亮度越高权重越大
            float br = dot(samp, float3(0.299, 0.587, 0.114));
            float w  = 1.0 + br * br * 3.0;

            acc  += samp * w;
            wSum += w;
        }
    }

    float3 blurred = (wSum > 0.0) ? (acc / wSum) : original;
    float  mixV    = smoothstep(0.02, 0.12, coc);
    float3 outc    = mix(original, blurred, mixV);
    out_tex.write(float4(outc, 1.0), gid);
}
