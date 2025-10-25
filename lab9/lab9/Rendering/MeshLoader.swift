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
}

enum MeshLoader {
    static func mdlVertexDescriptor() -> MDLVertexDescriptor {
        let mdl = MDLVertexDescriptor()

        mdl.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition,
                                               format: .float3, offset: 0, bufferIndex: 0)

        mdl.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal,
                                               format: .float3, offset: MemoryLayout<SIMD3<Float>>.stride, bufferIndex: 0)

        mdl.attributes[2] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate,
                                               format: .float2, offset: MemoryLayout<SIMD3<Float>>.stride*2, bufferIndex: 0)

        mdl.layouts[0] = MDLVertexBufferLayout(stride:
            MemoryLayout<SIMD3<Float>>.stride*2 + MemoryLayout<SIMD2<Float>>.stride)
        return mdl
    }

    static func loadOBJ(named name: String,
                        subdir: String?,
                        device: MTLDevice) throws -> LoadedModel {
        let allocator = MTKMeshBufferAllocator(device: device)
        let vdesc = mdlVertexDescriptor()
        let url = try findOBJ(named: name, subdir: subdir)

        let asset = MDLAsset(url: url, vertexDescriptor: vdesc, bufferAllocator: allocator)

        guard let mdlMesh = (asset.childObjects(of: MDLMesh.self) as? [MDLMesh])?.first else {
            throw NSError(domain: "MeshLoader", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "No hay mallas en el OBJ"])
        }

        if mdlMesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal, as: .float3) == nil {
            mdlMesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.5)
        }

        centerAndScale(mdlMesh: mdlMesh, targetExtent: 1.5)

        let mtk = try MTKMesh(mesh: mdlMesh, device: device)
        return LoadedModel(mdl: mdlMesh, mtk: mtk)
    }

    private static func findOBJ(named name: String, subdir: String?) throws -> URL {
        var candidates: [URL] = []
        if let sub = subdir,
           let u = Bundle.main.url(forResource: name, withExtension: "obj", subdirectory: sub) {
            candidates.append(u)
        }
        if let u = Bundle.main.url(forResource: name, withExtension: "obj") { candidates.append(u) }
        if candidates.isEmpty,
           let resURL = Bundle.main.resourceURL,
           let items = try? FileManager.default.contentsOfDirectory(at: resURL, includingPropertiesForKeys: nil) {
            if let match = items.first(where: { $0.lastPathComponent.lowercased() == "\(name).obj" }) {
                candidates.append(match)
            }
        }
        guard let url = candidates.first else {
            throw NSError(domain: "MeshLoader", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No pude encontrar \(name).obj en el bundle"])
        }
        return url
    }

    static func centerAndScale(mdlMesh: MDLMesh, targetExtent: Float) {
        guard let pos = mdlMesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition, as: .float3) else { return }
        let count = Int(mdlMesh.vertexCount), stride = pos.stride, base = pos.dataStart

        var minV = SIMD3<Float>(repeating: .infinity)
        var maxV = SIMD3<Float>(repeating: -.infinity)
        for i in 0..<count {
            let p = base.advanced(by: i * stride).assumingMemoryBound(to: SIMD3<Float>.self).pointee
            minV = simd_min(minV, p); maxV = simd_max(maxV, p)
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
}
