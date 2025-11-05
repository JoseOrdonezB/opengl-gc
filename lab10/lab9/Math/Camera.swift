//
//  Camera.swift
//  lab9
//
//  Created by Jose Ordoñez on 24/10/25.
//

import simd

public final class OrbitCamera {

    public var minDistance: Float = 0.2
    public var maxDistance: Float = 50.0

    public var maxPitchAbs: Float = .pi * 0.499

    public var orbitSensitivity: SIMD2<Float> = SIMD2<Float>(x: 1.0, y: 1.0)
    public var zoomSensitivity: Float = 1.0
    public var panPixelScale: Float = 1.0

    public var target = SIMD3<Float>(0, 0.7, 0)
    public var distance: Float = 4.0
    public var yaw: Float = 0.0
    public var pitch: Float = 0.2

    public var fovY: Float = .pi / 4
    public var aspect: Float = 1
    public var nearZ: Float = 0.01
    public var farZ: Float = 100

    public init() {}

    public var viewMatrix: simd_float4x4 {
        let dir = viewDirection
        let eye = target - dir * distance
        return .lookAt(eye: eye, center: target, up: .init(0, 1, 0))
    }

    public var projMatrix: simd_float4x4 {
        .perspective(fovyRadians: fovY,
                     aspect: max(0.001, aspect),
                     nearZ: nearZ,
                     farZ: farZ)
    }

    public var viewDirection: SIMD3<Float> {
        let clampedPitch = clamp(pitch, -maxPitchAbs, maxPitchAbs)
        let cp = cosf(clampedPitch), sp = sinf(clampedPitch)
        let sy = sinf(yaw), cy = cosf(yaw)
        return SIMD3<Float>(cp * sy, sp, cp * cy)
    }

    public var rightVector: SIMD3<Float> {
        normalize(simd_cross(viewDirection, SIMD3<Float>(0, 1, 0)))
    }

    public var upVector: SIMD3<Float> {
        normalize(simd_cross(rightVector, viewDirection))
    }

    public func orbit(deltaYaw dx: Float, deltaPitch dy: Float) {
        yaw += dx * orbitSensitivity.x
        yaw = wrapAngle(yaw)
        pitch = clamp(pitch + dy * orbitSensitivity.y, -maxPitchAbs, maxPitchAbs)
    }

    public func zoom(scale: Float) {
        let scaled = powf(scale, zoomSensitivity)
        distance = clamp(distance * scaled, minDistance, maxDistance)
    }

    public func pan(delta: SIMD2<Float>) {
        let spanY = 2.0 * distance * tanf(fovY * 0.5)
        let spanX = spanY * aspect

        let dx = delta.x * spanX * (panPixelScale / 1000.0)
        let dy = delta.y * spanY * (panPixelScale / 1000.0)

        target += (-rightVector * dx) + (upVector * dy)
    }

    public func setDrawableSize(width: Float, height: Float) {
        aspect = width / max(height, 1)
    }

    @inline(__always)
    private func clamp(_ v: Float, _ a: Float, _ b: Float) -> Float {
        max(a, min(b, v))
    }

    private func wrapAngle(_ a: Float) -> Float {
        var x = fmodf(a, 2 * .pi)
        if x <= -.pi { x += 2 * .pi }
        if x >  .pi { x -= 2 * .pi }
        return x
    }
}
