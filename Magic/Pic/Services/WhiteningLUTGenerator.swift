import Foundation
import Metal
import simd
import GPUImage

/// 美白 3D LUT 生成器。
///
/// 一次性在 CPU 端生成 32^3 的 Lab 空间美白映射 LUT，
/// 存为 rgba16Float 的 3D MTLTexture，供 `skinWhitenLUTFragment` shader 采样。
/// 美白强度由 shader 端通过 `mix(原色, LUT 色, strength)` 控制，因此 LUT 只需生成一次（最大强度）。
nonisolated enum WhiteningLUTGenerator {

    /// LUT 边长。32 在视觉质量与体积之间平衡良好（32^3 × 8B ≈ 256KB）。
    static let lutSize = 32

    /// 全局共享 LUT，App 生命周期内只生成一次。
    static let sharedLUT: MTLTexture? = generate()

    // MARK: - 生成

    private static func generate() -> MTLTexture? {
        let device = sharedMetalRenderingDevice.device

        let desc = MTLTextureDescriptor()
        desc.textureType = .type3D
        desc.pixelFormat = .rgba16Float
        desc.width = lutSize
        desc.height = lutSize
        desc.depth = lutSize
        desc.usage = [.shaderRead]
        desc.storageMode = .shared

        guard let tex = device.makeTexture(descriptor: desc) else { return nil }

        let count = lutSize * lutSize * lutSize
        var data = [UInt16](repeating: 0, count: count * 4)
        let n = Float(lutSize - 1)

        var idx = 0
        for bi in 0..<lutSize {
            for gi in 0..<lutSize {
                for ri in 0..<lutSize {
                    let rgb = SIMD3<Float>(Float(ri) / n, Float(gi) / n, Float(bi) / n)
                    let out = whitenAtMaxStrength(rgb: rgb)
                    data[idx * 4 + 0] = floatToHalf(out.x)
                    data[idx * 4 + 1] = floatToHalf(out.y)
                    data[idx * 4 + 2] = floatToHalf(out.z)
                    data[idx * 4 + 3] = floatToHalf(1.0)
                    idx += 1
                }
            }
        }

        let bytesPerRow = lutSize * 4 * MemoryLayout<UInt16>.size
        let bytesPerImage = bytesPerRow * lutSize
        data.withUnsafeBytes { ptr in
            tex.replace(
                region: MTLRegionMake3D(0, 0, 0, lutSize, lutSize, lutSize),
                mipmapLevel: 0,
                slice: 0,
                withBytes: ptr.baseAddress!,
                bytesPerRow: bytesPerRow,
                bytesPerImage: bytesPerImage
            )
        }
        return tex
    }

    // MARK: - 美白映射（最大强度，strength = 1.0）

    private static func whitenAtMaxStrength(rgb: SIMD3<Float>) -> SIMD3<Float> {
        var lab = xyzToLab(rgbToXyz(rgb))
        let s: Float = 1.0

        // 1) L 通道对数曲线提亮（暗部多、高光少）
        let lNorm = max(0, min(1, lab.x / 100.0))
        let lift = (1.0 - lNorm * lNorm) * s * 18.0
        lab.x = max(0, min(100, lab.x + lift))

        // 2) 去黄：压低正向 b*
        let yellow = max(lab.z, 0)
        lab.z -= yellow * s * 0.55

        // 3) 去红：轻微压低正向 a*
        let red = max(lab.y, 0)
        lab.y -= red * s * 0.25

        // 4) 整体轻微降饱和
        let satKeep: Float = 1.0 - s * 0.08
        lab.y *= satKeep
        lab.z *= satKeep

        return xyzToRgb(labToXyz(lab))
    }

    // MARK: - 色彩空间数学（与原 shader 实现一致）

    private static func rgbToXyz(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let cl = SIMD3<Float>(
            powf(clamp01(c.x), 2.2),
            powf(clamp01(c.y), 2.2),
            powf(clamp01(c.z), 2.2)
        )
        return SIMD3<Float>(
            simd_dot(cl, SIMD3<Float>(0.4124, 0.3576, 0.1805)),
            simd_dot(cl, SIMD3<Float>(0.2126, 0.7152, 0.0722)),
            simd_dot(cl, SIMD3<Float>(0.0193, 0.1192, 0.9505))
        )
    }

    private static func xyzToLab(_ xyz: SIMD3<Float>) -> SIMD3<Float> {
        let n = xyz / SIMD3<Float>(0.95047, 1.0, 1.08883)
        return SIMD3<Float>(
            116.0 * labF(n.y) - 16.0,
            500.0 * (labF(n.x) - labF(n.y)),
            200.0 * (labF(n.y) - labF(n.z))
        )
    }

    private static func labToXyz(_ lab: SIMD3<Float>) -> SIMD3<Float> {
        let fy = (lab.x + 16.0) / 116.0
        let fx = lab.y / 500.0 + fy
        let fz = fy - lab.z / 200.0
        return SIMD3<Float>(labFInv(fx), labFInv(fy), labFInv(fz))
            * SIMD3<Float>(0.95047, 1.0, 1.08883)
    }

    private static func xyzToRgb(_ xyz: SIMD3<Float>) -> SIMD3<Float> {
        let rgb = SIMD3<Float>(
            simd_dot(xyz, SIMD3<Float>( 3.2406, -1.5372, -0.4986)),
            simd_dot(xyz, SIMD3<Float>(-0.9689,  1.8758,  0.0415)),
            simd_dot(xyz, SIMD3<Float>( 0.0557, -0.2040,  1.0570))
        )
        return SIMD3<Float>(
            powf(clamp01(rgb.x), 1.0 / 2.2),
            powf(clamp01(rgb.y), 1.0 / 2.2),
            powf(clamp01(rgb.z), 1.0 / 2.2)
        )
    }

    private static func labF(_ t: Float) -> Float {
        t > 0.008856 ? powf(t, 1.0 / 3.0) : (7.787 * t + 16.0 / 116.0)
    }

    private static func labFInv(_ t: Float) -> Float {
        t > 0.206893 ? t * t * t : (t - 16.0 / 116.0) / 7.787
    }

    private static func clamp01(_ v: Float) -> Float {
        max(0, min(1, v))
    }

    // MARK: - Float → Half (IEEE 754 binary16)

    private static func floatToHalf(_ f: Float) -> UInt16 {
        Float16(f).bitPattern
    }
}
