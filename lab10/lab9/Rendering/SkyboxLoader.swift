//
//  SkyboxLoader.swift
//  lab9
//
//  Created by Jose Ordoñez on 25/10/25.
//

import Foundation
import Metal
import MetalKit
import ImageIO
import CoreGraphics

enum SkyboxLoader {

    private static let faceSuffixes = ["px","nx","py","ny","pz","nz"]

    static func loadCubeTextureSmart(device: MTLDevice,
                                     base: String,
                                     ext: String = "jpg",
                                     subdir: String? = nil,
                                     srgb: Bool = false,
                                     flipVertical: Bool = false) throws -> MTLTexture {
        if let subdir, let urls = findFaceURLsInSubdir(base: base, ext: ext, subdir: subdir) {
            return try buildCubeTexture(device: device, urls: urls, srgb: srgb, flipVertical: flipVertical)
        }
        if let urls = findFaceURLsAnywhere(base: base, ext: ext) {
            return try buildCubeTexture(device: device, urls: urls, srgb: srgb, flipVertical: flipVertical)
        }
        let expected = faceSuffixes.map { "\(base)\($0).\(ext)" }.joined(separator: ", ")
        throw NSError(domain: "SkyboxLoader", code: -100,
                      userInfo: [NSLocalizedDescriptionKey: "No se encontraron las 6 caras del cubemap. Esperaba: \(expected)"])
    }

    static func loadCubeTexture(device: MTLDevice,
                                base: String,
                                ext: String = "jpg",
                                subdir: String? = nil,
                                srgb: Bool = false,
                                flipVertical: Bool = false) throws -> MTLTexture {
        try loadCubeTextureSmart(device: device, base: base, ext: ext, subdir: subdir, srgb: srgb, flipVertical: flipVertical)
    }

    private static func findFaceURLsInSubdir(base: String, ext: String, subdir: String) -> [URL]? {
        var urls: [URL] = []
        urls.reserveCapacity(6)
        for suf in faceSuffixes {
            guard let u = Bundle.main.url(forResource: base + suf, withExtension: ext, subdirectory: subdir) else {
                return nil
            }
            urls.append(u)
        }
        return urls
    }

    private static func findFaceURLsAnywhere(base: String, ext: String) -> [URL]? {
        guard let all = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) else { return nil }
        var slots: [URL?] = Array(repeating: nil, count: 6)

        let wantWithPrefix  = faceSuffixes.map { (base + $0 + "." + ext).lowercased() }
        let wantNoPrefix    = faceSuffixes.map { ($0 + "." + ext).lowercased() }
        let usePrefixMatch  = !base.isEmpty

        for url in all {
            let name = url.lastPathComponent.lowercased()
            if usePrefixMatch, let idx = wantWithPrefix.firstIndex(of: name) {
                slots[idx] = url
            } else if !usePrefixMatch, let idx = wantNoPrefix.firstIndex(of: name) {
                slots[idx] = url
            }
        }
        guard slots.allSatisfy({ $0 != nil }) else { return nil }
        return slots.compactMap { $0 }
    }

    private static func buildCubeTexture(device: MTLDevice,
                                         urls: [URL],
                                         srgb: Bool,
                                         flipVertical: Bool) throws -> MTLTexture {
        precondition(urls.count == 6, "Se requieren 6 URLs en orden px,nx,py,ny,pz,nz")

        var images: [CGImage] = []
        images.reserveCapacity(6)
        for u in urls {
            guard let src = CGImageSourceCreateWithURL(u as CFURL, nil),
                  let cg  = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
                throw NSError(domain: "SkyboxLoader", code: -2,
                              userInfo: [NSLocalizedDescriptionKey: "No pude abrir \(u.lastPathComponent)"])
            }
            images.append(cg)
        }

        guard let first = images.first else {
            throw NSError(domain: "SkyboxLoader", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "No hay caras para el cubemap"])
        }
        let w = first.width, h = first.height
        guard w == h else {
            throw NSError(domain: "SkyboxLoader", code: -4,
                          userInfo: [NSLocalizedDescriptionKey: "Las caras del cubemap deben ser cuadradas (recibí \(w)x\(h))"])
        }
        for (i, img) in images.enumerated() where img.width != w || img.height != h {
            throw NSError(domain: "SkyboxLoader", code: -4,
                          userInfo: [NSLocalizedDescriptionKey: "Todas las caras deben tener el mismo tamaño. Cara \(i): \(img.width)x\(img.height), esperado \(w)x\(h)."])
        }

        let pixelFormat: MTLPixelFormat = srgb ? .bgra8Unorm_srgb : .bgra8Unorm
        let desc = MTLTextureDescriptor()
        desc.textureType = .typeCube
        desc.pixelFormat = pixelFormat
        desc.width  = w
        desc.height = h
        desc.mipmapLevelCount = 1
        desc.arrayLength = 1
        desc.usage = .shaderRead

        guard let cube = device.makeTexture(descriptor: desc) else {
            throw NSError(domain: "SkyboxLoader", code: -5,
                          userInfo: [NSLocalizedDescriptionKey: "No pude crear textura de cubemap"])
        }

        for (i, cg) in images.enumerated() {
            let data = try rgbaData(from: cg, flipVertical: flipVertical)
            data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                cube.replace(region: MTLRegionMake2D(0, 0, w, h),
                             mipmapLevel: 0,
                             slice: i,
                             withBytes: ptr.baseAddress!,
                             bytesPerRow: w * 4,
                             bytesPerImage: w * 4 * h)
            }
        }

        return cube
    }

    private static func rgbaData(from image: CGImage, flipVertical: Bool) throws -> Data {
        let w = image.width, h = image.height
        var data = Data(count: w * h * 4)

        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue
                       | CGImageAlphaInfo.premultipliedFirst.rawValue

        data.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) in
            if let ctx = CGContext(data: ptr.baseAddress,
                                   width: w, height: h,
                                   bitsPerComponent: 8,
                                   bytesPerRow: w * 4,
                                   space: cs,
                                   bitmapInfo: bitmapInfo) {
                if flipVertical {
                    ctx.translateBy(x: 0, y: CGFloat(h))
                    ctx.scaleBy(x: 1, y: -1)
                }
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        }
        return data
    }

    static func makeSkyboxPositions(device: MTLDevice) -> MTLBuffer {
        let v: [SIMD3<Float>] = [
            [ 1,-1,-1],[ 1,-1, 1],[ 1, 1, 1],[ 1,-1,-1],[ 1, 1, 1],[ 1, 1,-1],
            [-1,-1, 1],[-1,-1,-1],[-1, 1,-1],[-1,-1, 1],[-1, 1,-1],[-1, 1, 1],
            [-1, 1,-1],[ 1, 1,-1],[ 1, 1, 1],[-1, 1,-1],[ 1, 1, 1],[-1, 1, 1],
            [-1,-1, 1],[ 1,-1, 1],[ 1,-1,-1],[-1,-1, 1],[ 1,-1,-1],[-1,-1,-1],
            [ 1,-1, 1],[-1,-1, 1],[-1, 1, 1],[ 1,-1, 1],[-1, 1, 1],[ 1, 1, 1],
            [-1,-1,-1],[ 1,-1,-1],[ 1, 1,-1],[-1,-1,-1],[ 1, 1,-1],[-1, 1,-1],
        ]
        return device.makeBuffer(bytes: v,
                                 length: v.count * MemoryLayout<SIMD3<Float>>.stride,
                                 options: .storageModeShared)!
    }
}
