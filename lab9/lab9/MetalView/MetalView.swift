//
//  MetalView.swift
//  lab9
//
//  Created by Jose Ordoñez on 24/10/25.
//

import SwiftUI
import MetalKit

#if os(macOS)
struct MetalView: NSViewRepresentable {
    func makeNSView(context: Context) -> MTKView {
        let v = MTKView()
        if v.device == nil { v.device = MTLCreateSystemDefaultDevice() }
        v.colorPixelFormat = .bgra8Unorm
        v.depthStencilPixelFormat = .depth32Float
        v.clearColor = MTLClearColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1)
        context.coordinator.renderer = Renderer(mtkView: v)
        v.delegate = context.coordinator.renderer
        v.isPaused = false
        v.enableSetNeedsDisplay = false
        return v
    }
    func updateNSView(_ nsView: MTKView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var renderer: Renderer? }
}
#else
struct MetalView: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView {
        let v = MTKView()
        if v.device == nil { v.device = MTLCreateSystemDefaultDevice() }
        v.colorPixelFormat = .bgra8Unorm
        v.depthStencilPixelFormat = .depth32Float
        v.clearColor = MTLClearColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1)
        context.coordinator.renderer = Renderer(mtkView: v)
        v.delegate = context.coordinator.renderer
        v.isPaused = false
        v.enableSetNeedsDisplay = false
        return v
    }
    func updateUIView(_ uiView: MTKView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var renderer: Renderer? }
}
#endif
