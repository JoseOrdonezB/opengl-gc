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
import ImageIO   // para leer BMP via ImageIO (CGImageSource)

final class Renderer: NSObject, MTKViewDelegate {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipeline: MTLRenderPipelineState!
    private var depthState: MTLDepthStencilState!

    private var mesh: MTKMesh?

    // === NOMBRE Y CARPETA DEL MODELO (.obj) ===
    private let modelName   = "luigidoll" // nombre del .obj SIN extensión
    private let modelSubdir = "Models"    // subcarpeta dentro del bundle donde están .obj y .bmp

    // Cámara
    let camera = OrbitCamera()

    // Textura BMP única + sampler
    private var baseTexture: MTLTexture?
    private lazy var sampler: MTLSamplerState = {
        let d = MTLSamplerDescriptor()
        d.minFilter = .linear
        d.magFilter = .linear
        d.mipFilter = .linear
        d.sAddressMode = .repeat
        d.tAddressMode = .repeat
        return device.makeSamplerState(descriptor: d)!
    }()

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
        loadBMPTexture()   // intenta encontrar un .bmp junto al .obj
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
            let loaded: LoadedModel = try MeshLoader.loadOBJ(named: modelName, subdir: modelSubdir, device: device)
            self.mesh = loaded.mtk
        } catch {
            print("❌ Error cargando .obj:", error.localizedDescription)
        }
    }

    // MARK: - BMP loader (auto-detección junto al .obj)
    private func loadBMPTexture() {
        let loader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: true as NSNumber,
            .allocateMipmaps: true as NSNumber
            // .origin: MTKTextureLoader.Origin.flippedVertically as NSString // descomenta si la ves invertida
        ]

        func texture(from url: URL) throws -> MTLTexture {
            if url.pathExtension.lowercased() == "bmp" {
                // ImageIO -> CGImage -> newTexture(cgImage:)
                guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cg  = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
                    throw NSError(domain: "Renderer",
                                  code: -100,
                                  userInfo: [NSLocalizedDescriptionKey: "ImageIO no pudo abrir BMP \(url.lastPathComponent)"])
                }
                return try loader.newTexture(cgImage: cg, options: options)
            } else {
                return try loader.newTexture(URL: url, options: options)
            }
        }

        // 1) Intentar modelName.bmp en la misma subcarpeta del modelo
        if let url = Bundle.main.url(forResource: modelName, withExtension: "bmp", subdirectory: modelSubdir),
           let tex = try? texture(from: url) {
            baseTexture = tex
            print("✅ BMP (match por nombre): \(url.lastPathComponent) \(tex.width)x\(tex.height)")
            return
        }

        // 2) Buscar cualquier .bmp en la carpeta del modelo
        if let urls = Bundle.main.urls(forResourcesWithExtension: "bmp", subdirectory: modelSubdir),
           let url = urls.first,
           let tex = try? texture(from: url) {
            baseTexture = tex
            print("✅ BMP (primero en carpeta \(modelSubdir)): \(url.lastPathComponent) \(tex.width)x\(tex.height)")
            return
        }

        // 3) Buscar cualquier .bmp en TODO el bundle
        if let urls = Bundle.main.urls(forResourcesWithExtension: "bmp", subdirectory: nil),
           let url = urls.first,
           let tex = try? texture(from: url) {
            baseTexture = tex
            print("✅ BMP (primero en bundle): \(url.lastPathComponent) \(tex.width)x\(tex.height)")
            return
        }

        // 4) Fallback visible (checkerboard) — te indica que no se halló el BMP
        print("❌ No encontré ninguna textura .bmp en el bundle.")
        baseTexture = makeCheckerTexture()
    }

    // Checkerboard para diagnosticar (si no se encontró BMP)
    private func makeCheckerTexture(size: Int = 128, tile: Int = 16) -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                            width: size, height: size, mipmapped: false)
        desc.usage = [.shaderRead]
        let tex = device.makeTexture(descriptor: desc)!
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let on = ((x / tile) + (y / tile)) % 2 == 0
                let c: UInt8 = on ? 230 : 30
                let i = (y * size + x) * 4
                pixels[i+0] = c; pixels[i+1] = c; pixels[i+2] = c; pixels[i+3] = 255
            }
        }
        pixels.withUnsafeBytes {
            tex.replace(region: MTLRegionMake2D(0, 0, size, size),
                        mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: size * 4)
        }
        return tex
    }

    // MARK: - MTKViewDelegate

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

        // Bind sampler + textura BMP (si no se encontró, quedará checkerboard)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.setFragmentTexture(baseTexture, index: 0)

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

    // MARK: - Camera input
    func handleOrbit(delta: SIMD2<Float>) {
        camera.orbit(deltaYaw: delta.x * -0.7, deltaPitch: delta.y * 0.7)
    }
    func handleZoom(by scale: Float) {
        camera.zoom(scale: scale)
    }
    func handlePan(delta: SIMD2<Float>) {
        camera.pan(delta: delta * 0.2)
    }
}
