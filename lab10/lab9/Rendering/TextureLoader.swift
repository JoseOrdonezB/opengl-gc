//
//  TextureLoader.swift
//  lab9
//
//  Created by Jose Ordoñez on 24/10/25.
//

import Foundation
import Metal
import MetalKit
import ImageIO
import CoreGraphics

enum TextureLoaderBMP {

    static func loadTexture(named name: String,
                            ext: String = "bmp",
                            subdir: String? = nil,
                            device: MTLDevice,
                            srgb: Bool = true,
                            flipVertical: Bool = false) throws -> MTLTexture {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdir) else {
            throw NSError(domain: "TextureLoaderBMP", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No encontré \(name).\(ext) en \(subdir ?? "(bundle)")"])
        }
        return try loadTexture(from: url, device: device, srgb: srgb, flipVertical: flipVertical)
    }

    static func loadTexture(from url: URL,
                            device: MTLDevice,
                            srgb: Bool = true,
                            flipVertical: Bool = false) throws -> MTLTexture {
        let loader = MTKTextureLoader(device: device)
        let ext = url.pathExtension.lowercased()

        var options: [MTKTextureLoader.Option: Any] = [
            .SRGB: srgb as NSNumber,
            .generateMipmaps: true as NSNumber,
            .allocateMipmaps: true as NSNumber,
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue)
        ]
        if flipVertical {
            options[.origin] = MTKTextureLoader.Origin.flippedVertically as NSString
        }

        if ext == "bmp" {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg  = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
                throw NSError(domain: "TextureLoaderBMP", code: -2,
                              userInfo: [NSLocalizedDescriptionKey: "No pude abrir BMP: \(url.lastPathComponent)"])
            }
            return try loader.newTexture(cgImage: cg, options: options)
        } else {
            return try loader.newTexture(URL: url, options: options)
        }
    }
}
