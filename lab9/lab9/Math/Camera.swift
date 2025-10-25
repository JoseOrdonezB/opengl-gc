//
//  Camera.swift
//  lab9
//
//  Created by Jose Ordoñez on 24/10/25.
//

import simd

public final class OrbitCamera {
    public var target = SIMD3<Float>(0, 0.7, 0)
    public var distance: Float = 4.0  // radio
    public var yaw: Float = 0.0       // en radianes
    public var pitch: Float = 0.2     // en radianes

    public var fovY: Float = .pi / 4
    public var aspect: Float = 1
    public var nearZ: Float = 0.01
    public var farZ: Float = 100

    public init() {}

    public var viewMatrix: simd_float4x4 {
        // limitar pitch para evitar flip
        let p = max(-.pi * 0.499, min(.pi * 0.499, pitch))
        let dir = SIMD3<Float>(
            cosf(p) * sinf(yaw),
            sinf(p),
            cosf(p) * cosf(yaw)
        )
        let eye = target - dir * distance
        return .lookAt(eye: eye, center: target, up: SIMD3<Float>(0, 1, 0))
    }

    public var projMatrix: simd_float4x4 {
        .perspective(fovyRadians: fovY, aspect: max(0.001, aspect), nearZ: nearZ, farZ: farZ)
    }

    // Controles
    public func orbit(deltaYaw dx: Float, deltaPitch dy: Float) {
        yaw += dx
        pitch += dy
    }

    public func zoom(scale: Float) {
        // scale < 1 acerca, > 1 aleja; clamp
        distance = max(0.2, min(50.0, distance * scale))
    }

    public func pan(delta: SIMD2<Float>) {
        // pan en espacio de la cámara, proporcional a distancia y FOV
        let sp = distance * tanf(fovY * 0.5) * 2  // tamaño del plano cercano relativo
        let sx = sp * aspect
        // vectores cámara
        let p = max(-.pi * 0.499, min(.pi * 0.499, pitch))
        let forward = normalize(SIMD3<Float>(cosf(p) * sinf(yaw), sinf(p), cosf(p) * cosf(yaw)))
        let right = normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
        let up = normalize(simd_cross(right, forward))
        target += (-right * delta.x * sx) + (up * delta.y * sp)
    }
}
