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

    private var lastDragPoint: NSPoint = .zero
    private var draggingLeft = false

    override var acceptsFirstResponder: Bool { true }

    // Designated init
    override init(frame frameRect: NSRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        sharedSetup()
    }

    // No failable
    required init(coder: NSCoder) {
        super.init(coder: coder)
        sharedSetup()
    }

    private func sharedSetup() {
        wantsLayer = true

        // Zoom (pinch / trackpad magnify)
        let mag = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnify(_:)))
        addGestureRecognizer(mag)
    }

    // MARK: Orbit / Pan con drag izquierdo (según modificador)
    override func mouseDown(with event: NSEvent) {
        draggingLeft = true
        lastDragPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard draggingLeft else { return }
        let p = convert(event.locationInWindow, from: nil)
        let dx = Float(p.x - lastDragPoint.x)
        let dy = Float(p.y - lastDragPoint.y)
        lastDragPoint = p

        // Si mantiene ⌥ Option → PAN; si no → ORBIT
        if event.modifierFlags.contains(.option) {
            onPan?(SIMD2<Float>(dx, -dy))
        } else {
            onOrbit?(SIMD2<Float>(dx, -dy)) // invertimos Y para pitch intuitivo
        }
    }

    override func mouseUp(with event: NSEvent) {
        draggingLeft = false
    }

    // MARK: Pan con dos dedos (scroll del trackpad)
    override func scrollWheel(with event: NSEvent) {
        // Deltas de scroll: usa phase para “gesto” de trackpad
        // Invertir Y para que scroll hacia arriba mueva la escena hacia arriba
        let dx = Float(event.scrollingDeltaX)
        let dy = Float(event.scrollingDeltaY)
        // En muchos trackpads, las deltas ya vienen “natural scroll”; este mapeo es cómodo:
        onPan?(SIMD2<Float>(dx, dy))  // si prefieres invertir: SIMD2(dx, -dy)
    }

    // MARK: Zoom (trackpad pinch)
    @objc private func handleMagnify(_ g: NSMagnificationGestureRecognizer) {
        // magnification > 0 separa dedos; usamos scale = 1 - magnification (clamp)
        let scale = max(0.2, 1.0 - Float(g.magnification))
        onZoom?(scale)
    }
}

// SwiftUI wrapper (macOS)
struct MetalView: NSViewRepresentable {
    func makeNSView(context: Context) -> MTKView {
        let v = GestureMTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        v.colorPixelFormat = .bgra8Unorm
        v.depthStencilPixelFormat = .depth32Float
        v.clearColor = MTLClearColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1)

        let renderer = Renderer(mtkView: v)
        context.coordinator.renderer = renderer
        v.delegate = renderer

        // Sensibilidades (ajusta a gusto)
        v.onOrbit = { delta in renderer?.handleOrbit(delta: delta * 0.01) }
        v.onPan   = { delta in renderer?.handlePan(delta: delta * 0.0015) } // un pelín más sensible para scroll
        v.onZoom  = { scale in renderer?.handleZoom(by: scale) }

        v.isPaused = false
        v.enableSetNeedsDisplay = false
        return v
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        // Asegura eventos de mouse
        if nsView.window?.firstResponder !== nsView {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var renderer: Renderer?
    }
}
