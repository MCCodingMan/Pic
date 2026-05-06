#include <metal_stdlib>
using namespace metal;

struct SkinSmoothSingleIO {
    float4 position [[position]];
    float2 textureCoordinate [[user(texturecoord)]];
};

struct SkinSmoothTwoInputIO {
    float4 position [[position]];
    float2 textureCoordinate [[user(texturecoord)]];
    float2 textureCoordinate2 [[user(texturecoord2)]];
};

// MARK: - 双边滤波 Bilateral Filter

typedef struct {
    float distanceNormalizationFactor;
} BilateralUniform;

fragment half4 bilateralFragment(SkinSmoothSingleIO fragmentInput [[stage_in]],
                                 texture2d<half> inputTexture [[texture(0)]],
                                 constant BilateralUniform& uniform [[buffer(1)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);

    float2 uv = fragmentInput.textureCoordinate;
    float texelWidth = 1.0 / float(inputTexture.get_width());
    float texelHeight = 1.0 / float(inputTexture.get_height());

    half4 centralColor = inputTexture.sample(textureSampler, uv);
    half3 centralRGB = centralColor.rgb;

    float sigma_s = uniform.distanceNormalizationFactor;
    float sigma_r = 0.15;
    float twoSigmaS2 = 2.0 * sigma_s * sigma_s;
    float twoSigmaR2 = 2.0 * sigma_r * sigma_r;

    half3 sum = half3(0.0);
    float weightSum = 0.0;

    const int RADIUS = 7;
    const int STEP   = 2;

    for (int dy = -RADIUS; dy <= RADIUS; dy++) {
        for (int dx = -RADIUS; dx <= RADIUS; dx++) {
            float2 offset = float2(float(dx * STEP) * texelWidth,
                                   float(dy * STEP) * texelHeight);
            half4 sampleColor = inputTexture.sample(textureSampler, uv + offset);

            float spatialDist = float(dx * dx + dy * dy) * float(STEP * STEP);
            float spatialWeight = exp(-spatialDist / twoSigmaS2);

            half3 diff = sampleColor.rgb - centralRGB;
            float colorDist = float(dot(diff, diff));
            float rangeWeight = exp(-colorDist / twoSigmaR2);

            float weight = spatialWeight * rangeWeight;
            sum += sampleColor.rgb * half(weight);
            weightSum += weight;
        }
    }

    half3 result = sum / half(max(weightSum, 0.001));
    return half4(result, centralColor.a);
}

// MARK: - 可分离 Bilateral（两 pass，性能 ~10×）
// 把 2D bilateral 拆成 H + V 两次 1D，从 (2R+1)^2 = 121 采样降到 2*(2R+1) = 22 采样。
// 双边滤波严格上不可分离，但在美颜场景下视觉差异极小，工业级 SDK 普遍采用。

typedef struct {
    float distanceNormalizationFactor;
} BilateralSeparableUniform;

static inline half4 bilateralPass(texture2d<half> tex, sampler s, float2 uv,
                                  float2 dirTexel, float sigma_s) {
    constexpr int RADIUS = 5;
    constexpr int STEP = 2;
    half4 centralColor = tex.sample(s, uv);
    half3 centralRGB = centralColor.rgb;

    float sigma_r = 0.15;
    float twoSigmaS2 = 2.0 * sigma_s * sigma_s;
    float twoSigmaR2 = 2.0 * sigma_r * sigma_r;

    half3 sum = half3(0.0);
    float weightSum = 0.0;
    for (int i = -RADIUS; i <= RADIUS; i++) {
        float2 offset = dirTexel * float(i * STEP);
        half4 sampleColor = tex.sample(s, uv + offset);
        float spatialDist = float(i * i) * float(STEP * STEP);
        float spatialWeight = exp(-spatialDist / twoSigmaS2);
        half3 diff = sampleColor.rgb - centralRGB;
        float colorDist = float(dot(diff, diff));
        float rangeWeight = exp(-colorDist / twoSigmaR2);
        float w = spatialWeight * rangeWeight;
        sum += sampleColor.rgb * half(w);
        weightSum += w;
    }
    return half4(sum / half(max(weightSum, 0.001)), centralColor.a);
}

fragment half4 bilateralHFragment(SkinSmoothSingleIO fragmentInput [[stage_in]],
                                  texture2d<half> inputTexture [[texture(0)]],
                                  constant BilateralSeparableUniform& uniform [[buffer(1)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    float2 uv = fragmentInput.textureCoordinate;
    float2 dir = float2(1.0 / float(inputTexture.get_width()), 0.0);
    return bilateralPass(inputTexture, textureSampler, uv, dir, uniform.distanceNormalizationFactor);
}

fragment half4 bilateralVFragment(SkinSmoothSingleIO fragmentInput [[stage_in]],
                                  texture2d<half> inputTexture [[texture(0)]],
                                  constant BilateralSeparableUniform& uniform [[buffer(1)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    float2 uv = fragmentInput.textureCoordinate;
    float2 dir = float2(0.0, 1.0 / float(inputTexture.get_height()));
    return bilateralPass(inputTexture, textureSampler, uv, dir, uniform.distanceNormalizationFactor);
}

// MARK: - 美白：肤色 Mask + 3D LUT + 高光保护（单 Pass）
//
// 方案：CPU 端预生成 32^3 3D LUT（Lab 空间美白映射），shader 内做：
//   1) 3D LUT trilinear 采样得到美白后颜色
//   2) YCbCr 椭圆肤色判定 + smoothstep 软过渡 → skinMask
//   3) 高光保护：高亮区域衰减强度 → highlightMask
//   4) mix(原色, LUT 色, strength * skinMask * highlightMask)
//
// 输入 0: 原图（或磨皮后的图）
// 输入 1: 3D 美白 LUT（rgba16Float, 32^3）

typedef struct {
    float whitenStrength;
} WhitenUniform;

fragment half4 skinWhitenLUTFragment(SkinSmoothSingleIO fragmentInput [[stage_in]],
                                      texture2d<half> inputTexture [[texture(0)]],
                                      texture3d<half> lutTexture   [[texture(1)]],
                                      texture2d<half> personMask   [[texture(2)]],
                                      constant WhitenUniform& uniform [[buffer(1)]]) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    constexpr sampler lutSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    constexpr sampler maskSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);

    half4 src = inputTexture.sample(texSampler, fragmentInput.textureCoordinate);
    half3 rgb = clamp(src.rgb, half3(0.0h), half3(1.0h));
    // 人物分割 mask：白=人物/黑=背景。fallback 为 1×1 白纹理 → 全 1 等价无分割
    half personMaskValue = personMask.sample(maskSampler, fragmentInput.textureCoordinate).r;

    // 1) 3D LUT 采样（GPU trilinear 自动插值，最大强度美白结果）
    half3 whitened = lutTexture.sample(lutSampler, float3(rgb)).rgb;

    // 2) YCbCr 肤色 mask
    half y  = dot(rgb, half3(0.299h, 0.587h, 0.114h));
    half cb = -0.168736h * rgb.r - 0.331264h * rgb.g + 0.5h       * rgb.b + 0.5h;
    half cr =  0.5h       * rgb.r - 0.418688h * rgb.g - 0.081312h * rgb.b + 0.5h;
    // 典型肤色中心 ≈ (cb 0.42, cr 0.59)
    half2 d = half2(cb - 0.42h, cr - 0.59h);
    half dist = length(d);
    half skinMask = 1.0h - smoothstep(0.08h, 0.18h, dist);
    // 亮度门限：排除过暗与过亮
    skinMask *= smoothstep(0.20h, 0.35h, y);
    skinMask *= 1.0h - smoothstep(0.86h, 0.98h, y);
    // 饱和度门限：皮肤约 0.15~0.55，排除浓郁棕发（>0.55）与灰白发（<0.10）
    half maxC = max(max(rgb.r, rgb.g), rgb.b);
    half minC = min(min(rgb.r, rgb.g), rgb.b);
    half sat = (maxC - minC) / max(maxC, 0.001h);
    skinMask *= smoothstep(0.10h, 0.18h, sat);
    skinMask *= 1.0h - smoothstep(0.55h, 0.72h, sat);
    // 红色主导：皮肤 R > B 且 R ≳ G，头发这个差值通常更小或反向
    half redDom = rgb.r - rgb.b;
    skinMask *= smoothstep(0.02h, 0.08h, redDom);

    // 3) 高光保护
    half highlightMask = 1.0h - smoothstep(0.78h, 0.95h, y);

    // 4) 强度混合（再乘 personMask，背景完全不变）
    half strength = half(uniform.whitenStrength) * skinMask * highlightMask * personMaskValue;
    half3 result = mix(rgb, whitened, strength);

    return half4(result, src.a);
}

// MARK: - 亮肤（YUV 单 Pass：肤色 mask + 亮度/色温/S 曲线 + 高光阴影保护 + Sobel 细节保护）
//
// 方案来源：用户需求中的"美白方案（二）"，与现有 LUT 美白互补：
//   - 现有"美白"：3D LUT 全局查表 → 整体白皙透亮（适合化妆感）
//   - 本"亮肤"：YUV 空间局部提亮 + 去黄偏粉 + 细节保护（适合自然透亮）
//
// 单 pass，不依赖外部 mask：肤色通过 YCbCr 椭圆判定 + 亮度 gating 得到，
// 细节由 3x3 Sobel 推得，边缘处衰减强度以避免"塑料脸"。

typedef struct {
    float yuvStrength;
} WhitenYUVUniform;

fragment half4 skinWhitenYUVFragment(SkinSmoothSingleIO fragmentInput [[stage_in]],
                                     texture2d<half> inputTexture [[texture(0)]],
                                     texture2d<half> personMask   [[texture(1)]],
                                     constant WhitenYUVUniform& uniform [[buffer(1)]]) {
    constexpr sampler s(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    constexpr sampler maskSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);

    float2 uv = fragmentInput.textureCoordinate;
    half4 src = inputTexture.sample(s, uv);
    half3 rgbSrc = clamp(src.rgb, half3(0.0h), half3(1.0h));
    // 人物分割 mask：背景处为 0 → effective=0 → 背景完全不变
    half personMaskValue = personMask.sample(maskSampler, uv).r;

    // 1) 高频残差分离（frequency separation）
    //    lowFreq  = 5-tap 盒式模糊（便宜的低通）
    //    highFreq = 原图 - lowFreq，毛孔/绒毛/微纹理细节
    //    所有美白调整只作用在 lowFreq，最后把 highFreq 加回 → 细节 100% 保留
    float tw = 1.0 / float(inputTexture.get_width());
    float th = 1.0 / float(inputTexture.get_height());
    half3 lowFreq = (
        rgbSrc +
        inputTexture.sample(s, uv + float2( tw, 0.0)).rgb +
        inputTexture.sample(s, uv + float2(-tw, 0.0)).rgb +
        inputTexture.sample(s, uv + float2( 0.0,  th)).rgb +
        inputTexture.sample(s, uv + float2( 0.0, -th)).rgb
    ) * 0.2h;
    half3 highFreq = rgbSrc - lowFreq;

    // 后续美白 pipeline 的工作对象是 lowFreq（clamp 防止负值溢出）
    half3 rgb = clamp(lowFreq, half3(0.0h), half3(1.0h));

    // 2) RGB -> YCbCr（作用在低频）
    half3 coefY = half3(0.299h, 0.587h, 0.114h);
    half Y  = dot(rgb, coefY);
    half Cb = -0.168736h * rgb.r - 0.331264h * rgb.g + 0.5h       * rgb.b + 0.5h;
    half Cr =  0.5h       * rgb.r - 0.418688h * rgb.g - 0.081312h * rgb.b + 0.5h;

    // 3) 肤色 mask（YCbCr 椭圆 + 亮度 + 饱和度 + 红色主导度，排除头发）
    half2 d = half2(Cb - 0.42h, Cr - 0.59h);
    half dist = length(d);
    half skinMask = 1.0h - smoothstep(0.08h, 0.18h, dist);
    skinMask *= smoothstep(0.20h, 0.35h, Y);
    skinMask *= 1.0h - smoothstep(0.86h, 0.98h, Y);
    // 饱和度：排除浓郁棕发（>0.55）与灰白发（<0.10）
    half maxC = max(max(rgb.r, rgb.g), rgb.b);
    half minC = min(min(rgb.r, rgb.g), rgb.b);
    half sat = (maxC - minC) / max(maxC, 0.001h);
    skinMask *= smoothstep(0.10h, 0.18h, sat);
    skinMask *= 1.0h - smoothstep(0.55h, 0.72h, sat);
    // 红色主导：皮肤 R > B 有显著差值
    half redDom = rgb.r - rgb.b;
    skinMask *= smoothstep(0.02h, 0.08h, redDom);

    // 4) 有效强度 = 用户强度 × 肤色 mask × 人物 mask（背景完全不变）
    half strength = half(uniform.yuvStrength);
    half effective = strength * skinMask * personMaskValue;

    // 5) 亮度提升（只作用皮肤）
    half Yw = Y + effective * 0.12h;

    // 6) S 曲线：y = x + k*(x - x*x)，避免过曝/死灰
    half k = effective * 0.20h;
    Yw = Yw + k * (Yw - Yw * Yw);

    // 7) 局部 tone mapping：压高光、抬阴影
    half highlight = smoothstep(0.70h, 1.00h, Yw);
    half shadow    = 1.0h - smoothstep(0.00h, 0.30h, Yw);
    Yw -= highlight * 0.10h * effective;
    Yw += shadow    * 0.05h * effective;
    Yw = clamp(Yw, 0.0h, 1.0h);

    // 8) 色温：微偏红、减蓝 → 去黄 / 偏粉更通透
    half Cbw = Cb - effective * 0.010h;
    half Crw = Cr + effective * 0.012h;

    // 9) YCbCr -> RGB
    half cbv = Cbw - 0.5h;
    half crv = Crw - 0.5h;
    half3 outRGB;
    outRGB.r = Yw + 1.402h    * crv;
    outRGB.g = Yw - 0.344136h * cbv - 0.714136h * crv;
    outRGB.b = Yw + 1.772h    * cbv;
    // 10) 把原图高频残差加回（detail preserve）
    //     非肤色区域：lowFreq + highFreq ≈ 原图（无失真）
    //     肤色区域：已美白的 lowFreq + 原图高频 → 白且有毛孔
    outRGB = clamp(outRGB + highFreq, half3(0.0h), half3(1.0h));

    return half4(outRGB, src.a);
}

// MARK: - MLS Rigid 瘦脸形变 Compute Kernel

struct WarpControlPoint {
    float2 src; // 输出空间（瘦脸后位置）
    float2 dst; // 输入空间（原始位置）
};

kernel void mlsRigidWarpKernel(
    texture2d<float, access::sample> inTex  [[texture(0)]],
    texture2d<float, access::write>  outTex [[texture(1)]],
    device WarpControlPoint *points         [[buffer(0)]],
    constant int &pointCount                [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;

    constexpr sampler s(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    float w = float(inTex.get_width());
    float h = float(inTex.get_height());

    // 当前输出像素归一化坐标
    float2 v = (float2(gid) + 0.5) / float2(w, h);

    int n = min(pointCount, 64);

    // 计算权重和加权质心
    float weights[64];
    float weightSum = 0.0;
    float2 pStar = float2(0.0);
    float2 qStar = float2(0.0);

    for (int i = 0; i < n; i++) {
        float2 pi = points[i].src / float2(w, h);
        float dist2 = distance_squared(v, pi);
        float wi = 1.0 / (dist2 + 1e-6);
        weights[i] = wi;
        weightSum += wi;
        pStar += pi * wi;
        qStar += (points[i].dst / float2(w, h)) * wi;
    }

    pStar /= weightSum;
    qStar /= weightSum;

    // 构建 MLS Rigid 旋转矩阵分量
    float a = 0.0, b = 0.0;
    for (int i = 0; i < n; i++) {
        float2 pHat = points[i].src / float2(w, h) - pStar;
        float2 qHat = points[i].dst / float2(w, h) - qStar;
        a += weights[i] * (pHat.x * qHat.x + pHat.y * qHat.y);
        b += weights[i] * (pHat.x * qHat.y - pHat.y * qHat.x);
    }

    float norm = sqrt(a * a + b * b);
    if (norm < 1e-8) {
        outTex.write(inTex.sample(s, v), gid);
        return;
    }
    a /= norm;
    b /= norm;

    // 旋转变换：输出坐标 → 输入采样坐标
    float2 vMinusP = v - pStar;
    float2 mapped = float2(
        a * vMinusP.x - b * vMinusP.y,
        b * vMinusP.x + a * vMinusP.y
    ) + qStar;

    mapped = clamp(mapped, float2(0.0), float2(1.0));
    outTex.write(inTex.sample(s, mapped), gid);
}

// MARK: - 磨皮融合（带人脸遮罩）
// 输入 0: 双边滤波后（模糊）
// 输入 1: 原图
// 输入 2: 人脸遮罩（R 通道，白色=磨皮区域）

typedef struct {
    float intensity;
} SkinSmoothCombineUniform;

fragment half4 skinSmoothCombineFragment(SkinSmoothTwoInputIO fragmentInput [[stage_in]],
                                         texture2d<half> inputTexture [[texture(0)]],
                                         texture2d<half> inputTexture2 [[texture(1)]],
                                         texture2d<half> faceMask [[texture(2)]],
                                         constant SkinSmoothCombineUniform& uniform [[buffer(1)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);

    half4 blurred  = inputTexture.sample(textureSampler, fragmentInput.textureCoordinate);
    half4 original = inputTexture2.sample(textureSampler, fragmentInput.textureCoordinate2);

    // 采样人脸遮罩（用 textureCoordinate，与 blurred 同尺寸）
    half maskValue = faceMask.sample(textureSampler, fragmentInput.textureCoordinate).r;

    // 最终强度 = 全局磨皮强度 × 遮罩（脸部=1，非脸部=0）
    half effectiveIntensity = half(uniform.intensity) * maskValue;

    half4 result = mix(original, blurred, effectiveIntensity);
    return result;
}
