#if canImport(UIKit) && canImport(SwiftUI) && canImport(MetalKit)
import MetalKit
import SwiftUI
import UIKit
import simd

public struct LabyrinthCanvasView: View {
    @ObservedObject private var model: LabyrinthCanvasModel

    public init(model: LabyrinthCanvasModel) {
        self.model = model
    }

    public var body: some View {
        LabyrinthCanvasRepresentable(model: model)
    }
}

private struct LabyrinthCanvasRepresentable: UIViewRepresentable {
    @ObservedObject var model: LabyrinthCanvasModel

    func makeUIView(context: Context) -> LabyrinthMetalCanvasView {
        LabyrinthMetalCanvasView(model: model)
    }

    func updateUIView(_ uiView: LabyrinthMetalCanvasView, context: Context) {
        uiView.model = model
        uiView.configureGesturePolicy()
        uiView.clearColor = model.options.backgroundColor.clearColor
    }
}

private final class LabyrinthMetalCanvasView: MTKView, MTKViewDelegate, UIGestureRecognizerDelegate {
    var model: LabyrinthCanvasModel

    private var renderer: LabyrinthMetalRenderer?
    private var activeStrokeTouch: UITouch?
    private var activeStrokeSamples: [LabyrinthStrokeInputSample] = []
    private var activeObject: (frame: LabyrinthFrame, id: UUID, lastPointInFrame: SIMD2<Double>, handler: LabyrinthObjectGestureHandler?)?
    private var activePinchObject: (frame: LabyrinthFrame, id: UUID)?

    private lazy var cameraPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleCameraPan(_:)))
    private lazy var objectPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleObjectPan(_:)))
    private lazy var pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
    private lazy var rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
    private lazy var objectPinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handleObjectPinch(_:)))

    init(model: LabyrinthCanvasModel) {
        self.model = model
        let device = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: device)

        self.device = device
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        isPaused = false
        enableSetNeedsDisplay = false
        preferredFramesPerSecond = UIScreen.main.maximumFramesPerSecond
        isMultipleTouchEnabled = true
        clearColor = model.options.backgroundColor.clearColor

        if let device {
            renderer = LabyrinthMetalRenderer(device: device, colorPixelFormat: colorPixelFormat)
        }

        delegate = self
        installGestures()
        configureGesturePolicy()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func draw(in view: MTKView) {
        renderer?.draw(in: self, model: model)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    fileprivate func configureGesturePolicy() {
        cameraPanGesture.minimumNumberOfTouches = model.inputMode == .navigate ? 1 : 2
        cameraPanGesture.maximumNumberOfTouches = 0
        objectPanGesture.minimumNumberOfTouches = 1
        objectPanGesture.maximumNumberOfTouches = 1
    }

    private func installGestures() {
        cameraPanGesture.delegate = self
        objectPanGesture.delegate = self
        pinchGesture.delegate = self
        rotationGesture.delegate = self
        objectPinchGesture.delegate = self

        addGestureRecognizer(cameraPanGesture)
        addGestureRecognizer(objectPanGesture)
        addGestureRecognizer(pinchGesture)
        addGestureRecognizer(rotationGesture)
        addGestureRecognizer(objectPinchGesture)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === objectPanGesture {
            guard model.inputMode == .manipulate else { return false }
            let point = gestureRecognizer.location(in: self)
            return hitTestCanvasObject(at: point) != nil
        }

        if gestureRecognizer === objectPinchGesture {
            guard model.inputMode == .manipulate else { return false }
            let point = gestureRecognizer.location(in: self)
            return hitTestCanvasObject(at: point) != nil
        }

        if gestureRecognizer === cameraPanGesture {
            return model.inputMode == .navigate || cameraPanGesture.numberOfTouches >= 2
        }

        if gestureRecognizer === pinchGesture {
            if model.inputMode == .manipulate,
               hitTestCanvasObject(at: gestureRecognizer.location(in: self)) != nil {
                return false
            }
            return true
        }

        if gestureRecognizer === rotationGesture {
            return model.options.supportsRotation
        }

        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        let pair = Set([ObjectIdentifier(gestureRecognizer), ObjectIdentifier(otherGestureRecognizer)])
        let cameraPair = Set([ObjectIdentifier(pinchGesture), ObjectIdentifier(rotationGesture)])
        return pair == cameraPair
    }

    @objc private func handleCameraPan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .began || gesture.state == .changed else { return }
        let translation = gesture.translation(in: self)
        model.pan(by: translation, viewSize: bounds.size)
        gesture.setTranslation(.zero, in: self)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            let location = gesture.location(in: self)
            model.zoom(by: Double(gesture.scale), anchorScreen: location, viewSize: bounds.size)
            gesture.scale = 1.0
        default:
            break
        }
    }

    @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            let location = gesture.location(in: self)
            model.rotate(by: Float(gesture.rotation), anchorScreen: location, viewSize: bounds.size)
            gesture.rotation = 0
        default:
            break
        }
    }

    @objc private func handleObjectPan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self)

        switch gesture.state {
        case .began:
            guard let hit = hitTestCanvasObject(at: location) else { return }
            let handler = model.objects.type(for: hit.object.typeID)?.makeGestureHandler?()
            activeObject = (hit.frame, hit.object.id, hit.pointInFrame, handler)
            if let handler {
                model.mutateObject(id: hit.object.id, in: hit.frame) { object in
                    handler.begin(object: &object, context: gestureContext(frame: hit.frame, pointInFrame: hit.pointInFrame))
                }
            }

        case .changed:
            guard let activeObject,
                  let transform = model.transformFromActive(to: activeObject.frame) else { return }
            let activePoint = LabyrinthCanvasMath.screenToWorld(location, viewSize: bounds.size, camera: model.camera)
            let pointInFrame = activePoint * transform.scale + transform.translation
            let delta = pointInFrame - activeObject.lastPointInFrame
            self.activeObject?.lastPointInFrame = pointInFrame

            if let handler = activeObject.handler {
                model.mutateObject(id: activeObject.id, in: activeObject.frame) { object in
                    handler.update(object: &object, context: gestureContext(frame: activeObject.frame, pointInFrame: pointInFrame))
                }
            } else {
                model.translateObject(id: activeObject.id, in: activeObject.frame, by: delta)
            }

        case .ended, .cancelled, .failed:
            if let activeObject,
               let handler = activeObject.handler,
               let transform = model.transformFromActive(to: activeObject.frame) {
                let activePoint = LabyrinthCanvasMath.screenToWorld(location, viewSize: bounds.size, camera: model.camera)
                let pointInFrame = activePoint * transform.scale + transform.translation
                model.mutateObject(id: activeObject.id, in: activeObject.frame) { object in
                    handler.end(object: &object, context: gestureContext(frame: activeObject.frame, pointInFrame: pointInFrame))
                }
            }
            activeObject = nil

        default:
            break
        }
    }

    @objc private func handleObjectPinch(_ gesture: UIPinchGestureRecognizer) {
        let location = gesture.location(in: self)
        switch gesture.state {
        case .began:
            guard let hit = hitTestCanvasObject(at: location) else { return }
            activePinchObject = (hit.frame, hit.object.id)
            gesture.scale = 1.0

        case .changed:
            guard let activePinchObject else { return }
            model.scaleObject(id: activePinchObject.id, in: activePinchObject.frame, by: Double(gesture.scale))
            gesture.scale = 1.0

        case .ended, .cancelled, .failed:
            activePinchObject = nil

        default:
            break
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeStrokeTouch == nil,
              let touch = touches.first(where: acceptsDrawingTouch(_:)) else {
            super.touchesBegan(touches, with: event)
            return
        }

        activeStrokeTouch = touch
        activeStrokeSamples = [sample(from: touch)]
        if model.inputMode == .erase {
            _ = model.eraseStroke(at: touch.location(in: self), viewSize: bounds.size)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeStrokeTouch,
              touches.contains(activeStrokeTouch) else {
            super.touchesMoved(touches, with: event)
            return
        }

        let movedTouches = event?.coalescedTouches(for: activeStrokeTouch) ?? [activeStrokeTouch]
        for touch in movedTouches {
            let next = sample(from: touch)
            appendStrokeSampleIfNeeded(next)
            if model.inputMode == .erase {
                _ = model.eraseStroke(at: touch.location(in: self), viewSize: bounds.size)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeStrokeTouch,
              touches.contains(activeStrokeTouch) else {
            super.touchesEnded(touches, with: event)
            return
        }

        let finalSample = sample(from: activeStrokeTouch)
        appendStrokeSampleIfNeeded(finalSample)
        finishActiveStroke()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeStrokeTouch,
              touches.contains(activeStrokeTouch) else {
            super.touchesCancelled(touches, with: event)
            return
        }
        self.activeStrokeTouch = nil
        activeStrokeSamples = []
    }

    private func finishActiveStroke() {
        defer {
            activeStrokeTouch = nil
            activeStrokeSamples = []
        }

        guard model.inputMode == .draw else { return }
        do {
            try model.commitStroke(screenSamples: activeStrokeSamples, viewSize: bounds.size)
        } catch {
            assertionFailure("Failed to commit Labyrinth stroke: \(error)")
        }
    }

    private func acceptsDrawingTouch(_ touch: UITouch) -> Bool {
        guard model.inputMode == .draw || model.inputMode == .erase else { return false }
        if touch.type == .pencil { return true }
        if touch.type == .direct { return model.options.allowsFingerDrawing }
        return false
    }

    private func sample(from touch: UITouch) -> LabyrinthStrokeInputSample {
        let pressure: Float?
        if touch.type == .pencil, touch.maximumPossibleForce > 0 {
            pressure = Float(touch.force / touch.maximumPossibleForce)
        } else {
            pressure = nil
        }
        return LabyrinthStrokeInputSample(point: touch.location(in: self), pressure: pressure)
    }

    private func appendStrokeSampleIfNeeded(_ sample: LabyrinthStrokeInputSample) {
        guard let last = activeStrokeSamples.last else {
            activeStrokeSamples.append(sample)
            return
        }
        let dx = sample.point.x - last.point.x
        let dy = sample.point.y - last.point.y
        let minimum = CGFloat(model.options.minimumStrokeSampleDistance)
        if dx * dx + dy * dy >= minimum * minimum {
            activeStrokeSamples.append(sample)
        }
    }

    private func hitTestCanvasObject(at screenPoint: CGPoint) -> (frame: LabyrinthFrame, object: LabyrinthCanvasObject, pointInFrame: SIMD2<Double>)? {
        let pointActive = LabyrinthCanvasMath.screenToWorld(screenPoint, viewSize: bounds.size, camera: model.camera)
        var best: (frame: LabyrinthFrame, object: LabyrinthCanvasObject, pointInFrame: SIMD2<Double>)?

        for frame in model.allFrames() {
            guard let transform = model.transformFromActive(to: frame) else { continue }
            let pointInFrame = pointActive * transform.scale + transform.translation
            for object in frame.objects {
                guard let type = model.objects.type(for: object.typeID),
                      type.usesDefaultTransformGestures || type.makeGestureHandler != nil,
                      type.hitTest(object, pointInFrame) else {
                    continue
                }
                if best == nil || object.zIndex > best!.object.zIndex {
                    best = (frame, object, pointInFrame)
                }
            }
        }

        return best
    }

    private func gestureContext(frame: LabyrinthFrame,
                                pointInFrame: SIMD2<Double>) -> LabyrinthGestureContext {
        LabyrinthGestureContext(
            model: model,
            frame: frame,
            viewSize: bounds.size,
            pointInFrame: pointInFrame
        )
    }
}

private extension LabyrinthColor {
    var clearColor: MTLClearColor {
        MTLClearColor(red: Double(red),
                      green: Double(green),
                      blue: Double(blue),
                      alpha: Double(alpha))
    }
}
#endif
