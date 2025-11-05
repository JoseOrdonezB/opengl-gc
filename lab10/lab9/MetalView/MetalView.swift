//
//  MetalView.swift
//  lab9
//
//  Created by Jose Ordoñez on 24/10/25.
//

import SwiftUI
import MetalKit
import Cocoa

enum GameKey { case left, right, up, down, zoomIn, zoomOut }

final class GestureMTKView: MTKView {

    var onOrbit:      ((SIMD2<Float>) -> Void)?
    var onPan:        ((SIMD2<Float>) -> Void)?
    var onZoom:       ((Float) -> Void)?
    var onKey:        ((Character) -> Void)?
    var onKeyChange:  ((GameKey, Bool) -> Void)?

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

        let mag = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnify(_:)))
        addGestureRecognizer(mag)
    }

    override func keyDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        handleKey(event, isDown: true)

        if let s = event.charactersIgnoringModifiers {
            for ch in s { onKey?(ch) }
        } else {
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        handleKey(event, isDown: false)
    }

    private func handleKey(_ event: NSEvent, isDown: Bool) {
        switch event.keyCode {
        case 0:   onKeyChange?(.left,  isDown)
        case 2:   onKeyChange?(.right, isDown)
        case 13:  onKeyChange?(.down,  isDown)
        case 1:   onKeyChange?(.up,    isDown)

        case 12: onKeyChange?(.zoomIn,  isDown)
        case 14: onKeyChange?(.zoomOut, isDown)

        default:
            break
        }
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

        if draggingRight {
            let scale = exp(-dy * 0.01)
            onZoom?(scale)
            return
        }

        if draggingMiddle || event.modifierFlags.contains(.option) {
            onPan?(SIMD2<Float>(dx * panSensitivity, -dy * panSensitivity))
            return
        }

        if draggingLeft {
            onOrbit?(SIMD2<Float>(dx * orbitSensitivity, dy * orbitSensitivity))
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let dy = Float(event.hasPreciseScrollingDeltas ? event.scrollingDeltaY
                                                       : event.scrollingDeltaY * 0.1)
        let scale = exp(-dy * 0.01)
        onZoom?(scale)
    }

    @objc private func handleMagnify(_ g: NSMagnificationGestureRecognizer) {
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

        context.coordinator.renderer = renderer
        view.delegate = renderer

        view.onOrbit = { [weak renderer] delta in renderer?.handleOrbit(delta: delta) }
        view.onPan   = { [weak renderer] delta in renderer?.handlePan(delta: delta) }
        view.onZoom  = { [weak renderer] scale in renderer?.handleZoom(by: scale) }

        view.onKeyChange = { [weak renderer] key, isDown in
            renderer?.setKey(key, isDown: isDown)
        }

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

            case "j", "J": renderer?.selectModel(index: 0)
            case "k", "K": renderer?.selectModel(index: 1)
            case "l", "L": renderer?.selectModel(index: 2)

            default: break
            }
        }

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
        var renderer: Renderer?
    }
}
