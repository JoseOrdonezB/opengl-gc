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

final class Renderer: NSObject, MTKViewDelegate {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    private var pipeline: MTLRenderPipelineState!
    private var depthState: MTLDepthStencilState!

    private var mesh: MTKMesh?
    private var modelVertexDescriptor: MTLVertexDescriptor?

    private var cachedColorFormat: MTLPixelFormat = .bgra8Unorm
    private var cachedDepthFormat: MTLPixelFormat = .depth32Float

    private var currentVertexFnName: String   = "v_main"
    private var currentFragmentFnName: String = "f_main"

    private let modelName   = "luigidoll"
    private let modelSubdir = "Models"

    let camera = OrbitCamera()
    private var useDebugCamera = false

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

    private var skyboxPipeline: MTLRenderPipelineState!
    private var skyboxDepthState: MTLDepthStencilState!
    private var skyboxVB: MTLBuffer!
    private var skyboxTexture: MTLTexture?
    private lazy var skySampler: MTLSamplerState = {
        let d = MTLSamplerDescriptor()
        d.minFilter = .linear
        d.magFilter = .linear
        d.mipFilter = .linear
        d.sAddressMode = .clampToEdge
        d.tAddressMode = .clampToEdge
        d.rAddressMode = .clampToEdge
        return device.makeSamplerState(descriptor: d)!
    }()

    struct Uniforms {
        var model:    simd_float4x4
        var view:     simd_float4x4
        var proj:     simd_float4x4
        var lightDir: SIMD3<Float>
        var ambient:  Float
    }
    private var uniforms = Uniforms(model: .identity,
                                    view:  .identity,
                                    proj:  .identity,
                                    lightDir: simd_normalize(SIMD3<Float>(-1, -1, -0.5)),
                                    ambient: 0.9)

    struct SkyboxUniforms { var viewProjNoTrans: simd_float4x4 }
    private var skyU = SkyboxUniforms(viewProjNoTrans: .identity)

    private var printedIndexInfo = false

    init?(mtkView: MTKView) {
        if mtkView.device == nil { mtkView.device = MTLCreateSystemDefaultDevice() }
        guard let dev = mtkView.device, let q = dev.makeCommandQueue() else { return nil }
        device = dev
        commandQueue = q
        super.init()

        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.clearColor = MTLClearColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1)

        cachedColorFormat = mtkView.colorPixelFormat
        cachedDepthFormat = mtkView.depthStencilPixelFormat

        let ds = mtkView.drawableSize
        camera.aspect = Float(ds.width / max(1.0, ds.height))

        loadMesh()
        buildMeshPipeline()
        buildDepth()
        loadBMPTexture()
        buildSkyboxPipeline(view: mtkView)
        loadSkybox()

        if let m = mesh {
            print("ℹ️ Mesh: \(m.vertexBuffers.count) vertexBuffers, \(m.submeshes.count) submeshes")
            for (i, vb) in m.vertexBuffers.enumerated() {
                print("   • VB[\(i)]: length=\(vb.buffer.length) offset=\(vb.offset)")
            }
        }
    }

    private func buildMeshPipeline() { rebuildPipeline() }

    private func rebuildPipeline() {
        guard let lib = device.makeDefaultLibrary() else {
            print("❌ Default library ausente (Target Membership .metal)")
            return
        }
        guard let v = lib.makeFunction(name: currentVertexFnName) else {
            print("❌ Vertex '\(currentVertexFnName)' no encontrado")
            return
        }
        guard let f = lib.makeFunction(name: currentFragmentFnName) else {
            print("❌ Fragment '\(currentFragmentFnName)' no encontrado")
            return
        }

        let p = MTLRenderPipelineDescriptor()
        p.vertexFunction   = v
        p.fragmentFunction = f

        p.vertexDescriptor = modelVertexDescriptor ?? {
            let vd = MTLVertexDescriptor()
            vd.attributes[0].format = .float3; vd.attributes[0].offset = 0; vd.attributes[0].bufferIndex = 0
            vd.attributes[1].format = .float3; vd.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride; vd.attributes[1].bufferIndex = 0
            vd.attributes[2].format = .float2; vd.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride * 2; vd.attributes[2].bufferIndex = 0
            vd.layouts[0].stride    = MemoryLayout<SIMD3<Float>>.stride * 2 + MemoryLayout<SIMD2<Float>>.stride
            vd.layouts[0].stepFunction = .perVertex
            return vd
        }()

        p.colorAttachments[0].pixelFormat = cachedColorFormat
        p.depthAttachmentPixelFormat      = cachedDepthFormat

        do {
            pipeline = try device.makeRenderPipelineState(descriptor: p)
            print("✅ Pipeline: \(currentVertexFnName) / \(currentFragmentFnName)")
        } catch {
            print("❌ Pipeline malla:", error.localizedDescription)
            pipeline = nil
        }
    }

    func selectVertexShader(index: Int) {
        switch index {
        case 1: currentVertexFnName = "v_noise_deform"
        case 2: currentVertexFnName = "v_thin_shrink"
        case 3: currentVertexFnName = "v_twist_y"
        default: currentVertexFnName = "v_main"
        }
        rebuildPipeline()
    }

    func selectFragmentShader(index: Int) {
        switch index {
        case 1: currentFragmentFnName = "f_metal"
        case 2: currentFragmentFnName = "f_toon_rim"
        case 3: currentFragmentFnName = "f_matcap_solid"
        default: currentFragmentFnName = "f_main"
        }
        rebuildPipeline()
    }

    func resetShadersToDefault() {
        currentVertexFnName   = "v_main"
        currentFragmentFnName = "f_main"
        rebuildPipeline()
    }

    func toggleDebugCamera() { useDebugCamera.toggle() }

    private func buildDepth() {
        let d = MTLDepthStencilDescriptor()
        d.depthCompareFunction = .less
        d.isDepthWriteEnabled  = true
        depthState = device.makeDepthStencilState(descriptor: d)
    }

    private func buildSkyboxPipeline(view: MTKView) {
        guard let lib = device.makeDefaultLibrary(),
              let v = lib.makeFunction(name: "skybox_v_main"),
              let f = lib.makeFunction(name: "skybox_f_main") else {
            print("❌ Skybox shaders no encontrados")
            return
        }
        let p = MTLRenderPipelineDescriptor()
        p.vertexFunction = v
        p.fragmentFunction = f
        p.vertexDescriptor = nil
        p.colorAttachments[0].pixelFormat = view.colorPixelFormat
        p.depthAttachmentPixelFormat      = view.depthStencilPixelFormat
        do {
            skyboxPipeline = try device.makeRenderPipelineState(descriptor: p)
        } catch {
            print("❌ Pipeline skybox:", error.localizedDescription)
        }

        let d = MTLDepthStencilDescriptor()
        d.isDepthWriteEnabled   = false
        d.depthCompareFunction  = .lessEqual
        skyboxDepthState = device.makeDepthStencilState(descriptor: d)
    }

    private func loadMesh() {
        do {
            let loaded = try MeshLoader.loadOBJ(named: modelName,
                                                subdir: modelSubdir,
                                                device: device,
                                                flipVTexcoords: false)
            mesh = loaded.mtk
            modelVertexDescriptor = loaded.mtlVertexDescriptor
        } catch {
            print("❌ OBJ:", error.localizedDescription)
        }
    }

    private func loadBMPTexture() {
        let flip = false
        if let url = Bundle.main.url(forResource: modelName, withExtension: "bmp", subdirectory: modelSubdir),
           let tex = try? TextureLoaderBMP.loadTexture(from: url, device: device, srgb: true, flipVertical: flip) {
            baseTexture = tex; print("✅ BMP:", url.lastPathComponent, "\(tex.width)x\(tex.height)"); return
        }
        if let urls = Bundle.main.urls(forResourcesWithExtension: "bmp", subdirectory: modelSubdir),
           let url = urls.first,
           let tex = try? TextureLoaderBMP.loadTexture(from: url, device: device, srgb: true, flipVertical: flip) {
            baseTexture = tex; print("✅ BMP:", url.lastPathComponent, "\(tex.width)x\(tex.height)"); return
        }
        if let urls = Bundle.main.urls(forResourcesWithExtension: "bmp", subdirectory: nil),
           let url = urls.first,
           let tex = try? TextureLoaderBMP.loadTexture(from: url, device: device, srgb: true, flipVertical: flip) {
            baseTexture = tex; print("✅ BMP:", url.lastPathComponent, "\(tex.width)x\(tex.height)"); return
        }
        baseTexture = makeCheckerTexture()
        print("⚠️ BMP no encontrada. Usando checker.")
    }

    private func loadSkybox() {
        let verts: [SIMD3<Float>] = [
            [ 1,-1,-1],[ 1,-1, 1],[ 1, 1, 1],[ 1,-1,-1],[ 1, 1, 1],[ 1, 1,-1],
            [-1,-1, 1],[-1,-1,-1],[-1, 1,-1],[-1,-1, 1],[-1, 1,-1],[-1, 1, 1],
            [-1, 1,-1],[ 1, 1,-1],[ 1, 1, 1],[-1, 1,-1],[ 1, 1, 1],[-1, 1, 1],
            [-1,-1, 1],[ 1,-1, 1],[ 1,-1,-1],[-1,-1, 1],[ 1,-1,-1],[-1,-1,-1],
            [ 1,-1, 1],[-1,-1, 1],[-1, 1, 1],[ 1,-1, 1],[-1, 1, 1],[ 1, 1, 1],
            [-1,-1,-1],[ 1,-1,-1],[ 1, 1,-1],[-1,-1,-1],[ 1, 1,-1],[-1, 1,-1],
        ]
        skyboxVB = device.makeBuffer(bytes: verts,
                                     length: verts.count * MemoryLayout<SIMD3<Float>>.stride,
                                     options: .storageModeShared)

        do {
            skyboxTexture = try SkyboxLoader.loadCubeTextureSmart(device: device,
                                                                  base: "sky_",
                                                                  ext: "png",
                                                                  subdir: "Sky",
                                                                  srgb: false,
                                                                  flipVertical: false)
            if let t = skyboxTexture { print("✅ Skybox: \(t.width)x\(t.height)") }
        } catch {
            print("⚠️ Skybox:", error.localizedDescription)
            skyboxTexture = nil
        }
    }

    private func makePerspective(fovyRadians fovY: Float, aspect: Float,
                                 near: Float, far: Float) -> simd_float4x4 {
        let f = 1.0 / tanf(fovY * 0.5)
        let nf = 1.0 / (near - far)
        var m = simd_float4x4()
        m.columns = (
            SIMD4<Float>( f/aspect, 0, 0, 0),
            SIMD4<Float>( 0, f, 0, 0),
            SIMD4<Float>( 0, 0, (far+near)*nf, -1),
            SIMD4<Float>( 0, 0, (2*far*near)*nf, 0)
        )
        return m
    }

    private func makeLookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let f = simd_normalize(center - eye)
        let s = simd_normalize(simd_cross(f, up))
        let u = simd_cross(s, f)
        var m = simd_float4x4()
        m.columns = (
            SIMD4<Float>( s.x,  u.x, -f.x, 0),
            SIMD4<Float>( s.y,  u.y, -f.y, 0),
            SIMD4<Float>( s.z,  u.z, -f.z, 0),
            SIMD4<Float>(-simd_dot(s, eye),
                         -simd_dot(u, eye),
                          simd_dot(f, eye), 1)
        )
        return m
    }

    private func viewProjNoTranslation(view: simd_float4x4, proj: simd_float4x4) -> simd_float4x4 {
        var v = view
        v.columns.3 = .init(0, 0, 0, v.columns.3.w)
        return proj * v
    }

    private func makeCheckerTexture(size: Int = 128, tile: Int = 16) -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                            width: size, height: size, mipmapped: false)
        desc.usage = .shaderRead
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

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        cachedColorFormat = view.colorPixelFormat
        cachedDepthFormat = view.depthStencilPixelFormat
        camera.aspect = Float(size.width / max(size.height, 1))
    }

    func draw(in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else { return }

        let ds = view.drawableSize
        let aspect = Float(ds.width / max(1.0, ds.height))

        let vp = MTLViewport(originX: 0, originY: 0,
                             width: Double(ds.width),
                             height: Double(ds.height),
                             znear: 0.0, zfar: 1.0)

        uniforms.model = .identity
        if useDebugCamera {
            uniforms.view = makeLookAt(eye: SIMD3<Float>(0, 0, 3),
                                       center: SIMD3<Float>(0, 0, 0),
                                       up: SIMD3<Float>(0, 1, 0))
            uniforms.proj = makePerspective(fovyRadians: .pi/3, aspect: aspect, near: 0.01, far: 100)
        } else {
            camera.aspect = aspect
            uniforms.view  = camera.viewMatrix
            uniforms.proj  = camera.projMatrix
        }

        guard let cmd = commandQueue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setViewport(vp)

        if let skyTex = skyboxTexture, let skyVB = skyboxVB, skyboxPipeline != nil {
            skyU.viewProjNoTrans = viewProjNoTranslation(view: uniforms.view, proj: uniforms.proj)
            enc.setRenderPipelineState(skyboxPipeline)
            enc.setDepthStencilState(skyboxDepthState)
            enc.setCullMode(.none)
            enc.setVertexBuffer(skyVB, offset: 0, index: 0)
            enc.setVertexBytes(&skyU, length: MemoryLayout<SkyboxUniforms>.stride, index: 1)
            enc.setFragmentTexture(skyTex, index: 0)
            enc.setFragmentSamplerState(skySampler, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36)
        }

        if let mesh = mesh, let pipeline = pipeline, let depthState = depthState {
            enc.setRenderPipelineState(pipeline)
            enc.setDepthStencilState(depthState)
            enc.setCullMode(.none)
            enc.setFrontFacing(.counterClockwise)

            for (i, vb) in mesh.vertexBuffers.enumerated() {
                enc.setVertexBuffer(vb.buffer, offset: vb.offset, index: i)
            }
            enc.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            enc.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            enc.setFragmentSamplerState(sampler, index: 0)
            enc.setFragmentTexture(baseTexture, index: 0)

            if !printedIndexInfo {
                for (si, sub) in mesh.submeshes.enumerated() {
                    print("   • Submesh[\(si)] indexCount=\(sub.indexCount) type=\(sub.indexType.rawValue)")
                }
                printedIndexInfo = true
            }

            for sub in mesh.submeshes where sub.indexCount > 0 {
                enc.drawIndexedPrimitives(type: .triangle,
                                          indexCount: sub.indexCount,
                                          indexType: sub.indexType,
                                          indexBuffer: sub.indexBuffer.buffer,
                                          indexBufferOffset: sub.indexBuffer.offset)
            }
        }

        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    func handleOrbit(delta: SIMD2<Float>) { camera.orbit(deltaYaw: delta.x * -0.5, deltaPitch: delta.y * 0.5) }
    func handleZoom(by scale: Float)      { camera.zoom(scale: scale) }
    func handlePan(delta: SIMD2<Float>)   { camera.pan(delta: delta * 80.0) }
}
