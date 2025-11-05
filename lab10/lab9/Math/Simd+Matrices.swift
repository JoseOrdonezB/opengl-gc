//
//  Simd+Matrices.swift
//  lab9
//
//  Created by Jose Ordoñez on 24/10/25.
//

import simd

public extension simd_float4x4 {
    @inlinable
    static var identity: simd_float4x4 { matrix_identity_float4x4 }
    @inlinable
    static func perspective(fovyRadians fovy: Float,
                            aspect a: Float,
                            nearZ n: Float,
                            farZ f: Float) -> simd_float4x4
    {
        let fovyClamped = max(0.001, min(Float.pi - 0.001, fovy))
        let aspect = max(0.0001, a)
        let nearZ  = max(0.000001, n)
        let farZ   = max(nearZ + 0.000001, f)

        let y = 1 / tanf(fovyClamped * 0.5)
        let x = y / aspect
        let zRange = farZ - nearZ
        let z = -(farZ + nearZ) / zRange
        let wz = -(2 * farZ * nearZ) / zRange

        return simd_float4x4(columns: (
            SIMD4<Float>(x, 0, 0, 0),
            SIMD4<Float>(0, y, 0, 0),
            SIMD4<Float>(0, 0,  z, -1),
            SIMD4<Float>(0, 0, wz,  0)
        ))
    }

    @inlinable
    static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up upHint: SIMD3<Float>) -> simd_float4x4 {
        let z = simd_normalize(eye - center)
        let tmpX = simd_cross(upHint, z)
        let x = simd_normalize(length_squared(tmpX) > 1e-8 ? tmpX : simd_cross(SIMD3<Float>(0,1,0), z))
        let y = simd_cross(z, x)

        return simd_float4x4(columns: (
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1)
        ))
    }

    @inlinable
    static func translation(_ t: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(t.x, t.y, t.z, 1)
        ))
    }

    @inlinable
    static func rotation(radians: Float, axis: SIMD3<Float>) -> simd_float4x4 {
        let a = simd_normalize(axis)
        let c = cosf(radians), s = sinf(radians)
        let ci = 1 - c

        let x = a.x, y = a.y, z = a.z
        let r00 = c + x*x*ci
        let r01 = x*y*ci - z*s
        let r02 = x*z*ci + y*s

        let r10 = y*x*ci + z*s
        let r11 = c + y*y*ci
        let r12 = y*z*ci - x*s

        let r20 = z*x*ci - y*s
        let r21 = z*y*ci + x*s
        let r22 = c + z*z*ci

        return simd_float4x4(columns: (
            SIMD4<Float>(r00, r10, r20, 0),
            SIMD4<Float>(r01, r11, r21, 0),
            SIMD4<Float>(r02, r12, r22, 0),
            SIMD4<Float>(  0,   0,   0, 1)
        ))
    }

    @inlinable
    static func scale(_ s: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(s.x, 0,   0,   0),
            SIMD4<Float>(0,   s.y, 0,   0),
            SIMD4<Float>(0,   0,   s.z, 0),
            SIMD4<Float>(0,   0,   0,   1)
        ))
    }
}
