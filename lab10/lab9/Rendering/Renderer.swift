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
import QuartzCore

struct ModelAsset {
    let name: String
    let subdir: String
    let textureBaseName: String?
    let preRotateDegXYZ: SIMD3<Float>

    init(name: String,
         subdir: String,
         textureBaseName: String?,
         preRotateDegXYZ: SIMD3<Float> = .zero) {
        self.name = name
        self.subdir = subdir
        self.textureBaseName = textureBaseName
        self.preRotateDegXYZ = preRotateDegXYZ
    }
}

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

    private var models: [ModelAsset] = [
        ModelAsset(name: "luigidoll",
                   subdir: "Resources/Models",
                   textureBaseName: "7c33ed83",
                   preRotateDegXYZ: SIMD3<Float>(0, 180, 0)),

        ModelAsset(name: "13463_Australian_Cattle_Dog_v3",
                   subdir: "Resources/Models",
                   textureBaseName: "Australian_Cattle_Dog_dif",
                   preRotateDegXYZ: SIMD3<Float>(90, 180, 0)),

        ModelAsset(name: "12222_Cat_v1_l3",
                   subdir: "Resources/Models",
                   textureBaseName: "Cat_diffuse",
                   preRotateDegXYZ: SIMD3<Float>(90, 180, 0))
    ]
    private var currentModelIndex: Int = 0

    private struct Cached {
        let mesh: MTKMesh
        let vdesc: MTLVertexDescriptor
        let texture: MTLTexture
    }
    private var cache: [Int: Cached] = [:]

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
        var _pad0: SIMD4<Float> = .zero
    }
    private var uniforms = Uniforms(model: .identity,
                                    view:  .identity,
                                    proj:  .identity,
                                    lightDir: simd_normalize(SIMD3<Float>(-1, -1, -0.5)),
                                    ambient: 0.9)

    struct SkyboxUniforms { var viewProjNoTrans: simd_float4x4 }
    private var skyU = SkyboxUniforms(viewProjNoTrans: .identity)

    private var printedIndexInfo = false

    private var keyLeft  = false
    private var keyRight = false
    private var keyUp    = false
    private var keyDown  = false
    private var keyZIn   = false
    private var keyZOut  = false
    private var fastMove = false

    private let orbitSpeed: Float = 1.8
    private let zoomRatePerSec: Float = 2.0

    private var lastFrameTime: CFTimeInterval = CACurrentMediaTime()

    private var preModelTransform: simd_float4x4 = .identity

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

        buildDepth()
        buildSkyboxPipeline(view: mtkView)
        loadSkybox()

        loadCurrentModelAssets()

        if let m = mesh {
            print("ℹ️ Mesh: \(m.vertexBuffers.count) VBs, \(m.submeshes.count) submeshes")
        }
    }

    func selectModel(index: Int) {
        guard !models.isEmpty else { return }
        let clamped = max(0, min(index, models.count - 1))
        guard clamped != currentModelIndex else { return }
        currentModelIndex = clamped
        loadCurrentModelAssets()
    }
    func nextModel() { selectModel(index: currentModelIndex + 1) }
    func prevModel() { selectModel(index: currentModelIndex - 1) }

    private func loadCurrentModelAssets() {
        let idx = currentModelIndex
        let asset = models[idx]

        if let c = cache[idx] {
            mesh = c.mesh
            modelVertexDescriptor = c.vdesc
            baseTexture = c.texture
            preModelTransform = rotXYZ(deg: asset.preRotateDegXYZ)
            buildMeshPipeline()
            printedIndexInfo = false
            print("✅ Modelo (cache): \(asset.name)")
            return
        }

        do {
            let loaded = try MeshLoader.loadOBJ(named: asset.name,
                                                subdir: asset.subdir,
                                                device: device,
                                                flipVTexcoords: false)
            mesh = loaded.mtk
            modelVertexDescriptor = loaded.mtlVertexDescriptor

            baseTexture = loadModelTexture(baseName: asset.textureBaseName ?? asset.name,
                                           preferredSubdir: asset.subdir)
                          ?? makeCheckerTexture()

            preModelTransform = rotXYZ(deg: asset.preRotateDegXYZ)

            buildMeshPipeline()
            printedIndexInfo = false

            if let tex = baseTexture {
                cache[idx] = .init(mesh: loaded.mtk, vdesc: loaded.mtlVertexDescriptor, texture: tex)
            }

            print("✅ Modelo activo: \(asset.name)")
        } catch {
            print("❌ Error cargando modelo \(asset.name):", error.localizedDescription)
            mesh = nil
            baseTexture = makeCheckerTexture()
            preModelTransform = .identity
        }
    }

    private func loadModelTexture(baseName: String, preferredSubdir: String?) -> MTLTexture? {
        let subdirs: [String?] = Array(
            [preferredSubdir, "Resources/Models", "Models", nil]
                .reduce(into: LinkedHashSet<String?>()) { $0.insert($1) }
        )
        for sd in subdirs {
            if let tex = TextureLoaderBMP.loadAny(baseName: baseName,
                                                 subdir: sd,
                                                 device: device,
                                                 srgb: true,
                                                 flipVertical: false,
                                                 preferredExts: ["bmp","png","jpg","jpeg","tga"]) {
                print("✅ Textura modelo: \(baseName) en \(sd ?? "(bundle root)")")
                return tex
            }
        }
        print("⚠️ No se encontró textura para \(baseName). Usando checker.")
        return nil
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

        let subdirs: [String] = ["Sky", "Resources/Sky", ""]
        let exts:    [String] = ["jpg", "png", "jpeg"]

        for sd in subdirs {
            for ext in exts {
                do {
                    let t = try SkyboxLoader.loadCubeTextureSmart(device: device,
                                                                  base: "sky_",
                                                                  ext: ext,
                                                                  subdir: sd.isEmpty ? nil : sd,
                                                                  srgb: false,
                                                                  flipVertical: false)
                    skyboxTexture = t
                    print("✅ Skybox: \(t.width)x\(t.height) en \(sd.isEmpty ? "(bundle root)" : sd) .\(ext)")
                    return
                } catch {
                    
                }
            }
        }
        print("⚠️ No se encontró skybox (probé \(subdirs) con \(exts)).")
        skyboxTexture = nil
    }


    @inline(__always) private func deg2rad(_ d: Float) -> Float { d * .pi / 180 }
    private func rotX(_ r: Float) -> simd_float4x4 {
        let c = cos(r), s = sin(r)
        return .init(columns: (
            .init(1, 0, 0, 0),
            .init(0, c,-s, 0),
            .init(0, s, c, 0),
            .init(0, 0, 0, 1)
        ))
    }
    private func rotY(_ r: Float) -> simd_float4x4 {
        let c = cos(r), s = sin(r)
        return .init(columns: (
            .init( c, 0, s, 0),
            .init( 0, 1, 0, 0),
            .init(-s, 0, c, 0),
            .init( 0, 0, 0, 1)
        ))
    }
    private func rotZ(_ r: Float) -> simd_float4x4 {
        let c = cos(r), s = sin(r)
        return .init(columns: (
            .init( c,-s, 0, 0),
            .init( s, c, 0, 0),
            .init( 0, 0, 1, 0),
            .init( 0, 0, 0, 1)
        ))
    }
    private func rotXYZ(deg: SIMD3<Float>) -> simd_float4x4 {
        let r = SIMD3<Float>(deg2rad(deg.x), deg2rad(deg.y), deg2rad(deg.z))

        return rotZ(r.z) * rotY(r.y) * rotX(r.x)
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

        let dt = tickDT()
        if !useDebugCamera {
            updateCameraFromKeyboard(dt: dt)
        }

        let ds = view.drawableSize
        let aspect = Float(ds.width / max(1.0, ds.height))

        let vp = MTLViewport(originX: 0, originY: 0,
                             width: Double(ds.width),
                             height: Double(ds.height),
                             znear: 0.0, zfar: 1.0)

        uniforms.model = preModelTransform

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

extension Renderer {

    func setKey(_ key: GameKey, isDown: Bool) {
        switch key {
        case .left:   keyLeft  = isDown
        case .right:  keyRight = isDown
        case .up:     keyUp    = isDown
        case .down:   keyDown  = isDown
        case .zoomIn: keyZIn   = isDown
        case .zoomOut:keyZOut  = isDown
        }
    }

    private func updateCameraFromKeyboard(dt: Float) {
        let boost: Float = fastMove ? 2.25 : 1.0

        var dYaw:   Float = 0
        var dPitch: Float = 0
        if keyLeft  { dYaw   -= orbitSpeed * dt * boost }
        if keyRight { dYaw   += orbitSpeed * dt * boost }
        if keyUp    { dPitch += orbitSpeed * dt * boost }
        if keyDown  { dPitch -= orbitSpeed * dt * boost }

        if dYaw != 0 || dPitch != 0 {
            camera.orbit(deltaYaw: dYaw, deltaPitch: dPitch)
        }

        if keyZIn != keyZOut {
            let dir: Float = keyZIn ? 1 : -1
            let scale = exp(dir * zoomRatePerSec * dt * boost)
            camera.zoom(scale: scale)
        }
    }

    private func tickDT() -> Float {
        let now = CACurrentMediaTime()
        let dt  = Float(now - lastFrameTime)
        lastFrameTime = now
        return max(dt, 1.0/600.0)
    }
}

fileprivate struct LinkedHashSet<T: Hashable>: Sequence {
    private var array: [T] = []
    private var set: Set<T> = []
    mutating func insert(_ element: T) { if set.insert(element).inserted { array.append(element) } }
    func makeIterator() -> IndexingIterator<[T]> { array.makeIterator() }
}
