//
//  MetalView.swift
//  lab9
//
//  Created by Jose Ordoñez on 24/10/25.
//

import SwiftUI
import MetalKit
import Cocoa

final class GestureMTKView: MTKView {

    var onOrbit: ((SIMD2<Float>) -> Void)?
    var onPan:   ((SIMD2<Float>) -> Void)?
    var onZoom:  ((Float) -> Void)?

    private let orbitSensitivity:  Float = 0.01
    private let panSensitivity:    Float = 0.0015
    private let wheelPanScale:     Float = 0.8

    private var lastDragPoint: NSPoint = .zero
    private var draggingLeft  = false
    private var draggingMiddle = false

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device ?? MTLCreateSystemDefaultDevice())
        sharedSetup()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        if self.device == nil { self.device = MTLCreateSystemDefaultDevice() }
        sharedSetup()
    }

    private func sharedSetup() {
        framebufferOnly = true
        preferredFramesPerSecond = 60
        let mag = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnify(_:)))
        addGestureRecognizer(mag)
    }

    override func mouseDown(with event: NSEvent) {
        draggingLeft = true
        lastDragPoint = convert(event.locationInWindow, from: nil)
    }
    override func mouseUp(with event: NSEvent) { draggingLeft = false }

    override func otherMouseDown(with event: NSEvent) {
        draggingMiddle = true
        lastDragPoint = convert(event.locationInWindow, from: nil)
    }
    override func otherMouseUp(with event: NSEvent) { draggingMiddle = false }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let dx = Float(p.x - lastDragPoint.x)
        let dy = Float(p.y - lastDragPoint.y)
        lastDragPoint = p

        if draggingMiddle || event.modifierFlags.contains(.option) {
            onPan?(SIMD2<Float>(dx * panSensitivity, -dy * panSensitivity))
        } else if draggingLeft {
            onOrbit?(SIMD2<Float>(dx * orbitSensitivity, dy * orbitSensitivity))
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let sx = Float(event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.scrollingDeltaX * 0.1)
        let sy = Float(event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 0.1)
        onPan?(SIMD2<Float>(sx * wheelPanScale * panSensitivity,
                            -sy * wheelPanScale * panSensitivity))
    }

    @objc private func handleMagnify(_ g: NSMagnificationGestureRecognizer) {
        let k: Float = 1.0 - Float(g.magnification)
        let scale = max(0.2, min(5.0, k))
        onZoom?(scale)
    }
}

struct MetalView: NSViewRepresentable {

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MTKView {
        let view = GestureMTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1)
        view.isPaused = false
        view.enableSetNeedsDisplay = false

        let renderer = Renderer(mtkView: view)
        context.coordinator.renderer = renderer
        view.delegate = renderer

        view.onOrbit = { [weak renderer] delta in renderer?.handleOrbit(delta: delta) }
        view.onPan   = { [weak renderer] delta in renderer?.handlePan(delta: delta) }
        view.onZoom  = { [weak renderer] scale in renderer?.handleZoom(by: scale) }

        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        if nsView.window?.firstResponder !== nsView {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    final class Coordinator {
        var renderer: Renderer?
    }
}
