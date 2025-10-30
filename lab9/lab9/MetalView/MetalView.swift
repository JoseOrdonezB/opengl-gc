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

    // Callbacks hacia el renderer
    var onOrbit: ((SIMD2<Float>) -> Void)?
    var onPan:   ((SIMD2<Float>) -> Void)?
    var onZoom:  ((Float) -> Void)?
    var onKey:   ((Character) -> Void)?

    // Sensibilidades
    private let orbitSensitivity:  Float = 0.015
    private let panSensitivity:    Float = 0.0035

    private var lastDragPoint: NSPoint = .zero
    private var draggingLeft  = false
    private var draggingMiddle = false
    private var draggingRight = false

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
        isPaused = false
        enableSetNeedsDisplay = false
        preferredFramesPerSecond = 60

        // Pinch para zoom
        let mag = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnify(_:)))
        addGestureRecognizer(mag)
    }

    // MARK: - Teclado
    override func keyDown(with event: NSEvent) {
        if let s = event.charactersIgnoringModifiers {
            for ch in s { onKey?(ch) }
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Ratón
    override func mouseDown(with event: NSEvent) {
        draggingLeft = true
        lastDragPoint = convert(event.locationInWindow, from: nil)
    }
    override func mouseUp(with event: NSEvent) { draggingLeft = false }

    override func otherMouseDown(with event: NSEvent) {
        // Botón medio
        draggingMiddle = true
        lastDragPoint = convert(event.locationInWindow, from: nil)
    }
    override func otherMouseUp(with event: NSEvent) { draggingMiddle = false }

    override func rightMouseDown(with event: NSEvent) {
        draggingRight = true
        lastDragPoint = convert(event.locationInWindow, from: nil)
    }
    override func rightMouseUp(with event: NSEvent) { draggingRight = false }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let dx = Float(p.x - lastDragPoint.x)
        let dy = Float(p.y - lastDragPoint.y)
        lastDragPoint = p

        // Zoom arrastrando vertical con botón derecho (opcional)
        if draggingRight {
            let scale = exp(-dy * 0.01) // arriba acerca, abajo aleja
            onZoom?(scale)
            return
        }

        // Pan con botón medio o con Option (⌥)
        if draggingMiddle || event.modifierFlags.contains(.option) {
            onPan?(SIMD2<Float>(dx * panSensitivity, -dy * panSensitivity))
            return
        }

        // Orbit con botón izquierdo
        if draggingLeft {
            onOrbit?(SIMD2<Float>(dx * orbitSensitivity, dy * orbitSensitivity))
        }
    }

    // Scroll = ZOOM (dos dedos en trackpad o rueda)
    override func scrollWheel(with event: NSEvent) {
        // Usa deltaY (vertical). Si es “precise”, viene en valores finos.
        let dy = Float(event.hasPreciseScrollingDeltas ? event.scrollingDeltaY
                                                       : event.scrollingDeltaY * 0.1)
        // Exponencial suave: >1 acerca, <1 aleja
        let scale = exp(-dy * 0.01) // invertir signo para que “arriba” acerque
        onZoom?(scale)
    }

    @objc private func handleMagnify(_ g: NSMagnificationGestureRecognizer) {
        // g.magnification ~ delta, 0 = sin cambio
        let scale = max(0.2, min(5.0, 1.0 - Float(g.magnification)))
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
        view.preferredFramesPerSecond = 60

        guard let renderer = Renderer(mtkView: view) else {
            assertionFailure("No se pudo crear Renderer(mtkView:)")
            return view
        }

        // Mantener referencia FUERTE al renderer en el coordinator
        context.coordinator.renderer = renderer

        // delegate es weak → si no retenemos renderer, no dibuja
        view.delegate = renderer

        // Gestos → renderer
        view.onOrbit = { [weak renderer] delta in renderer?.handleOrbit(delta: delta) }
        view.onPan   = { [weak renderer] delta in renderer?.handlePan(delta: delta) }
        view.onZoom  = { [weak renderer] scale in renderer?.handleZoom(by: scale) }

        // Teclas:
        // 1 = f_metal, 2 = f_toon_rim, 3 = f_matcap_solid
        // v = v_creative, b = v_main, 0 = reset
        view.onKey = { [weak renderer] ch in
            switch ch {
            case "1": renderer?.selectFragmentShader(index: 1)
            case "2": renderer?.selectFragmentShader(index: 2)
            case "3": renderer?.selectFragmentShader(index: 3)
            case "4": renderer?.selectVertexShader(index: 1)
            case "5": renderer?.selectVertexShader(index: 2)
            case "6": renderer?.selectVertexShader(index: 3)
            case "v", "V": renderer?.selectVertexShader(index: 1)
            case "b", "B": renderer?.selectVertexShader(index: 0)
            case "0": renderer?.resetShadersToDefault()
            default: break
            }
        }

        // Foco de teclado
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }

        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        if nsView.window?.firstResponder !== nsView {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    final class Coordinator {
        // FUERTE, no weak
        var renderer: Renderer?
    }
}
