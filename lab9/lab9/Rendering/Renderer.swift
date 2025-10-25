//
//  Renderer.swift
//  lab9
//
//  Created by Jose Ordoñez on 24/10/25.
//

import Foundation
import Metal
import MetalKit
import simd
import ModelIO

final class Renderer: NSObject, MTKViewDelegate {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipeline: MTLRenderPipelineState!
    private var depthState: MTLDepthStencilState!

    private var mesh: MTKMesh?

    // Cámara
    let camera = OrbitCamera()

    struct Uniforms {
        var model: simd_float4x4
        var view: simd_float4x4
        var proj: simd_float4x4
        var lightDir: SIMD3<Float>
    }
    private var uniforms = Uniforms(model: .identity,
                                    view: .identity,
                                    proj: .identity,
                                    lightDir: simd_normalize(SIMD3<Float>(-1, -1, -0.5)))

    init?(mtkView: MTKView) {
        if mtkView.device == nil { mtkView.device = MTLCreateSystemDefaultDevice() }
        guard let dev = mtkView.device, let q = dev.makeCommandQueue() else { return nil }
        device = dev
        commandQueue = q
        super.init()

        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.clearColor = MTLClearColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1)

        buildPipeline(view: mtkView)
        buildDepth()
        loadMesh()
    }

    private func buildPipeline(view: MTKView) {
        let lib = try! device.makeDefaultLibrary(bundle: .main)
        let v = lib.makeFunction(name: "v_main")!
        let f = lib.makeFunction(name: "f_main")!

        let vd = MTLVertexDescriptor()
        vd.attributes[0].format = .float3; vd.attributes[0].offset = 0; vd.attributes[0].bufferIndex = 0
        vd.attributes[1].format = .float3; vd.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride; vd.attributes[1].bufferIndex = 0
        vd.attributes[2].format = .float2; vd.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride*2; vd.attributes[2].bufferIndex = 0
        vd.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride*2 + MemoryLayout<SIMD2<Float>>.stride

        let p = MTLRenderPipelineDescriptor()
        p.vertexFunction = v
        p.fragmentFunction = f
        p.vertexDescriptor = vd
        p.colorAttachments[0].pixelFormat = view.colorPixelFormat
        p.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        pipeline = try! device.makeRenderPipelineState(descriptor: p)
    }

    private func buildDepth() {
        let d = MTLDepthStencilDescriptor()
        d.depthCompareFunction = .less
        d.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: d)
    }

    private func loadMesh() {
        do {
            let loaded: LoadedModel = try MeshLoader.loadOBJ(named: "luigidoll", subdir: "Models", device: device)
            self.mesh = loaded.mtk
        } catch {
            print("❌ Error cargando .obj:", error.localizedDescription)
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        camera.aspect = Float(size.width / max(size.height, 1))
    }

    func draw(in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let mesh = mesh else { return }

        uniforms.model = .identity
        uniforms.view  = camera.viewMatrix
        uniforms.proj  = camera.projMatrix

        let cmd = commandQueue.makeCommandBuffer()!
        let enc = cmd.makeRenderCommandEncoder(descriptor: pass)!
        enc.setRenderPipelineState(pipeline)
        enc.setDepthStencilState(depthState)

        for (i, vb) in mesh.vertexBuffers.enumerated() {
            enc.setVertexBuffer(vb.buffer, offset: vb.offset, index: i)
        }
        enc.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

        for sub in mesh.submeshes {
            enc.drawIndexedPrimitives(type: .triangle,
                                      indexCount: sub.indexCount,
                                      indexType: sub.indexType,
                                      indexBuffer: sub.indexBuffer.buffer,
                                      indexBufferOffset: sub.indexBuffer.offset)
        }

        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    // MARK: - Camera input (llamado desde la vista)
    func handleOrbit(delta: SIMD2<Float>) {
        // sensibilidad a gusto
        camera.orbit(deltaYaw: delta.x * 0.5, deltaPitch: delta.y * 0.5)
    }
    func handleZoom(by scale: Float) {
        camera.zoom(scale: scale)
    }
    func handlePan(delta: SIMD2<Float>) {
        camera.pan(delta: delta * 0.1) // ajustar sensibilidad
    }
}
