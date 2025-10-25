//
//  Simd+Matrices.swift
//  lab9
//
//  Created by Jose Ordoñez on 24/10/25.
//

import simd

public extension simd_float4x4 {
    static var identity: simd_float4x4 { matrix_identity_float4x4 }

    static func perspective(fovyRadians: Float, aspect: Float, nearZ: Float, farZ: Float) -> simd_float4x4 {
        let y = 1 / tanf(fovyRadians * 0.5)
        let x = y / max(aspect, 0.0001)
        let zRange = farZ - nearZ
        let z = -(farZ + nearZ) / zRange
        let wz = -(2 * farZ * nearZ) / zRange
        return simd_float4x4(columns: (
            SIMD4<Float>(x, 0, 0, 0),
            SIMD4<Float>(0, y, 0, 0),
            SIMD4<Float>(0, 0, z, -1),
            SIMD4<Float>(0, 0, wz, 0)
        ))
    }

    static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let z = simd_normalize(eye - center)
        let x = simd_normalize(simd_cross(up, z))
        let y = simd_cross(z, x)
        return simd_float4x4(columns: (
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1)
        ))
    }
}
