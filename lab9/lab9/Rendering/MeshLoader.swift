//
//  MeshLoader.swift
//  lab9
//
//  Created by Jose Ordoñez on 24/10/25.
//

import Foundation
import Metal
import MetalKit
import ModelIO
import simd

struct LoadedModel {
    let mdl: MDLMesh
    let mtk: MTKMesh
    let mtlVertexDescriptor: MTLVertexDescriptor
}

enum MeshLoader {

    static func loadOBJ(named name: String,
                        subdir: String?,
                        device: MTLDevice,
                        flipVTexcoords: Bool = false) throws -> LoadedModel {

        let allocator = MTKMeshBufferAllocator(device: device)
        let mtlVDReq  = makeMTLVertexDescriptor()
        let mdlVDReq  = makeMDLVertexDescriptor(from: mtlVDReq)

        let url = try findOBJ(named: name, subdir: subdir)
        let asset = MDLAsset(url: url, vertexDescriptor: mdlVDReq, bufferAllocator: allocator)

        guard let mdlMesh = (asset.childObjects(of: MDLMesh.self) as? [MDLMesh])?.first else {
            throw makeError("No hay mallas en \(name).obj")
        }

        for case let m as MDLMesh in (asset.childObjects(of: MDLMesh.self) as? [MDLMesh]) ?? [] {
            m.vertexDescriptor = mdlVDReq
        }

        if mdlMesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal, as: .float3) == nil {
            mdlMesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.5)
        }

        if flipVTexcoords { flipTexcoordV(in: mdlMesh) }

        centerAndScale(mdlMesh: mdlMesh, targetExtent: 1.5)

        let mtk = try MTKMesh(mesh: mdlMesh, device: device)

        let mtlVDActual = MTKMetalVertexDescriptorFromModelIO(mdlMesh.vertexDescriptor) ?? mtlVDReq

        return LoadedModel(mdl: mdlMesh, mtk: mtk, mtlVertexDescriptor: mtlVDActual)
    }

    private static func makeMTLVertexDescriptor() -> MTLVertexDescriptor {
        let vd = MTLVertexDescriptor()
        vd.attributes[0].format = .float3
        vd.attributes[0].offset = 0
        vd.attributes[0].bufferIndex = 0

        vd.attributes[1].format = .float3
        vd.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vd.attributes[1].bufferIndex = 0

        vd.attributes[2].format = .float2
        vd.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride * 2
        vd.attributes[2].bufferIndex = 0

        vd.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride * 2 + MemoryLayout<SIMD2<Float>>.stride
        vd.layouts[0].stepFunction = .perVertex
        return vd
    }

    private static func makeMDLVertexDescriptor(from mtlVD: MTLVertexDescriptor) -> MDLVertexDescriptor {
        let mdlVD = MTKModelIOVertexDescriptorFromMetal(mtlVD)
        (mdlVD.attributes[0] as? MDLVertexAttribute)?.name = MDLVertexAttributePosition
        (mdlVD.attributes[1] as? MDLVertexAttribute)?.name = MDLVertexAttributeNormal
        (mdlVD.attributes[2] as? MDLVertexAttribute)?.name = MDLVertexAttributeTextureCoordinate
        return mdlVD
    }

    private static func findOBJ(named name: String, subdir: String?) throws -> URL {
        if let sub = subdir,
           let u = Bundle.main.url(forResource: name, withExtension: "obj", subdirectory: sub) { return u }
        if let u = Bundle.main.url(forResource: name, withExtension: "obj") { return u }
        if let resURL = Bundle.main.resourceURL,
           let items = try? FileManager.default.contentsOfDirectory(at: resURL, includingPropertiesForKeys: nil),
           let match = items.first(where: { $0.lastPathComponent.lowercased() == "\(name).obj" }) { return match }
        throw makeError("No pude encontrar \(name).obj en el bundle")
    }

    static func centerAndScale(mdlMesh: MDLMesh, targetExtent: Float) {
        guard let pos = mdlMesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition, as: .float3) else { return }
        let count  = Int(mdlMesh.vertexCount)
        let stride = pos.stride
        let base   = pos.dataStart

        var minV = SIMD3<Float>( repeating: .infinity)
        var maxV = SIMD3<Float>( repeating: -.infinity)

        for i in 0..<count {
            let p = base.advanced(by: i * stride).assumingMemoryBound(to: SIMD3<Float>.self).pointee
            minV = simd_min(minV, p)
            maxV = simd_max(maxV, p)
        }

        let center = (minV + maxV) * 0.5
        let extent = maxV - minV
        let maxE = max(extent.x, max(extent.y, extent.z))
        let s: Float = maxE > 0 ? (targetExtent / maxE) : 1

        for i in 0..<count {
            let ptr = base.advanced(by: i * stride).assumingMemoryBound(to: SIMD3<Float>.self)
            var p = ptr.pointee
            p = (p - center) * s
            ptr.pointee = p
        }
    }

    private static func flipTexcoordV(in mdlMesh: MDLMesh) {
        guard let uv = mdlMesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeTextureCoordinate, as: .float2) else { return }
        let count  = Int(mdlMesh.vertexCount)
        let stride = uv.stride
        let base   = uv.dataStart

        for i in 0..<count {
            let ptr = base.advanced(by: i * stride).assumingMemoryBound(to: SIMD2<Float>.self)
            var t = ptr.pointee
            t.y = 1 - t.y
            ptr.pointee = t
        }
    }

    private static func makeError(_ msg: String) -> NSError {
        NSError(domain: "MeshLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
    }
}
