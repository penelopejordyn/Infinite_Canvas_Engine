import Combine
import CoreGraphics
import Foundation
import simd

struct LabyrinthAnchorGestureResult {
    let anchorWorld: SIMD2<Double>
    let didTransition: Bool
}

public final class LabyrinthCanvasModel: ObservableObject {
    @Published public var inputMode: LabyrinthInputMode
    @Published public var brushStyle: LabyrinthBrushStyle
    @Published public var camera: LabyrinthCamera
    @Published public var options: LabyrinthCanvasOptions
    @Published public private(set) var lastCameraChange: LabyrinthCanvasCameraChange?

    public private(set) var rootFrame: LabyrinthFrame
    public private(set) var activeFrame: LabyrinthFrame
    public private(set) var fractal: LabyrinthFractalConfig

    public let brushes: LabyrinthBrushRegistry
    public let objects: LabyrinthObjectRegistry

    public var strokeWidthMode: LabyrinthStrokeWidthMode {
        get { brushStyle.strokeWidthMode }
        set {
            var style = brushStyle
            style.setStrokeWidthMode(newValue, currentEffectiveZoom: camera.zoom)
            brushStyle = style
        }
    }

    public var drawingInputPolicy: LabyrinthDrawingInputPolicy {
        get { options.drawingInputPolicy }
        set {
            var updated = options
            updated.drawingInputPolicy = newValue
            options = updated
        }
    }

    public var allowsFingerDrawing: Bool {
        get { options.allowsFingerDrawing }
        set {
            var updated = options
            updated.allowsFingerDrawing = newValue
            options = updated
        }
    }

    private var nextZIndex: UInt32
    private var createdAt: Date

    public init(rootFrame: LabyrinthFrame = LabyrinthFrame(),
                activeFrame: LabyrinthFrame? = nil,
                fractal: LabyrinthFractalConfig = LabyrinthFractalConfig(),
                camera: LabyrinthCamera = LabyrinthCamera(),
                inputMode: LabyrinthInputMode = .draw,
                brushStyle: LabyrinthBrushStyle = LabyrinthBrushStyle(),
                options: LabyrinthCanvasOptions = LabyrinthCanvasOptions(),
                brushes: LabyrinthBrushRegistry = LabyrinthBrushRegistry(),
                objects: LabyrinthObjectRegistry = LabyrinthObjectRegistry()) {
        self.rootFrame = rootFrame
        self.activeFrame = activeFrame ?? rootFrame
        self.fractal = fractal
        self.camera = camera
        self.inputMode = inputMode
        self.brushStyle = brushStyle
        self.options = options
        self.brushes = brushes
        self.objects = objects
        self.nextZIndex = LabyrinthCanvasModel.nextZIndex(in: rootFrame)
        self.createdAt = Date()
        self.lastCameraChange = nil
    }

    public convenience init(jsonData: Data) throws {
        let snapshot = try LabyrinthJSONCodec.decoder().decode(LabyrinthDocumentSnapshot.self, from: jsonData)
        self.init(snapshot: snapshot)
    }

    public convenience init(snapshot: LabyrinthDocumentSnapshot) {
        let root = LabyrinthFrame.fromSnapshot(snapshot.rootFrame)
        let active = LabyrinthCanvasModel.frame(at: snapshot.activeFramePath, root: root) ?? root
        self.init(rootFrame: root,
                  activeFrame: active,
                  fractal: snapshot.fractal,
                  camera: snapshot.camera)
        self.createdAt = snapshot.createdAt
    }

    public func snapshot() -> LabyrinthDocumentSnapshot {
        LabyrinthDocumentSnapshot(
            createdAt: createdAt,
            updatedAt: Date(),
            fractal: fractal,
            rootFrame: rootFrame.snapshot(),
            activeFramePath: framePathFromRoot(to: activeFrame) ?? [],
            camera: camera
        )
    }

    public func exportJSON(prettyPrinted: Bool = true) throws -> Data {
        let formatting: JSONEncoder.OutputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : []
        return try LabyrinthJSONCodec.encoder(outputFormatting: formatting).encode(snapshot())
    }

    public func replace(with snapshot: LabyrinthDocumentSnapshot) {
        objectWillChange.send()
        let root = LabyrinthFrame.fromSnapshot(snapshot.rootFrame)
        rootFrame = root
        activeFrame = Self.frame(at: snapshot.activeFramePath, root: root) ?? root
        fractal = snapshot.fractal
        camera = snapshot.camera
        nextZIndex = Self.nextZIndex(in: root)
        createdAt = snapshot.createdAt
        lastCameraChange = nil
    }

    public func addObject(_ object: LabyrinthCanvasObject, to frame: LabyrinthFrame? = nil) {
        objectWillChange.send()
        let target = frame ?? activeFrame
        target.objects.append(object)
        nextZIndex = max(nextZIndex, object.zIndex + 1)
    }

    @discardableResult
    public func removeObject(id: UUID, from frame: LabyrinthFrame? = nil) -> LabyrinthCanvasObject? {
        let targetFrames = frame.map { [$0] } ?? allFrames()
        for target in targetFrames {
            guard let index = target.objects.firstIndex(where: { $0.id == id }) else { continue }
            objectWillChange.send()
            return target.objects.remove(at: index)
        }
        return nil
    }

    public func commitStroke(screenSamples: [LabyrinthStrokeInputSample],
                             viewSize: CGSize) throws {
        guard let first = screenSamples.first else {
            throw LabyrinthCanvasError.emptyStroke
        }

        let firstActive = LabyrinthCanvasMath.screenToWorld(first.point, viewSize: viewSize, camera: camera)
        let resolved = resolveFrame(forActivePoint: firstActive)
        let originInFrame = resolved.pointInFrame
        let effectiveZoom = max(camera.zoom / max(resolved.conversionScale, 1e-9), 1e-9)
        let worldWidth = brushStyle.worldStrokeWidth(effectiveZoom: effectiveZoom)
        let localSamples = makeLocalStrokeSamples(screenSamples,
                                                  firstScreenPoint: first.point,
                                                  zoom: effectiveZoom)
        let draft = LabyrinthStrokeDraft(
            screenSamples: screenSamples,
            localSamples: localSamples,
            originInFrame: originInFrame,
            worldWidth: worldWidth,
            creationZoom: effectiveZoom,
            brushStyle: brushStyle
        )
        guard let brush = brushes.brush(for: brushStyle.brushID) else {
            throw LabyrinthCanvasError.unknownBrush(brushStyle.brushID)
        }
        let context = LabyrinthBrushContext(
            frameID: resolved.frame.id,
            frameDepth: resolved.frame.depthFromRoot,
            zIndex: allocateZIndex(),
            viewSize: viewSize,
            camera: camera
        )
        let object = try brush.makeObject(from: draft, context: context)
        addObject(object, to: resolved.frame)
    }

    @discardableResult
    public func eraseStroke(at screenPoint: CGPoint, viewSize: CGSize, radiusPx: Double? = nil) -> Bool {
        let pointActive = LabyrinthCanvasMath.screenToWorld(screenPoint, viewSize: viewSize, camera: camera)
        let radiusPx = radiusPx ?? options.eraserRadius
        var best: (frame: LabyrinthFrame, index: Int, zIndex: UInt32)?

        for frame in allFrames() {
            guard let transform = transformFromActive(to: frame) else { continue }
            let pointInFrame = pointActive * transform.scale + transform.translation
            let eraserRadius = radiusPx * transform.scale / max(camera.zoom, 1e-9)

            for (index, object) in frame.objects.enumerated().reversed() where object.typeID == LabyrinthStrokePayload.typeID {
                guard let stroke = try? object.decodedPayload(as: LabyrinthStrokePayload.self) else { continue }
                guard stroke.hitTest(pointInFrame: pointInFrame,
                                     origin: object.transform.positionSIMD,
                                     eraserRadius: eraserRadius) else { continue }
                if best == nil || object.zIndex > best!.zIndex {
                    best = (frame, index, object.zIndex)
                }
                break
            }
        }

        guard let hit = best else { return false }
        objectWillChange.send()
        hit.frame.objects.remove(at: hit.index)
        return true
    }

    public func translateObject(id: UUID, in frame: LabyrinthFrame, by delta: SIMD2<Double>) {
        guard let index = frame.objects.firstIndex(where: { $0.id == id }) else { return }
        objectWillChange.send()
        frame.objects[index].transform.positionSIMD += delta
    }

    public func scaleObject(id: UUID, in frame: LabyrinthFrame, by scale: Double) {
        guard scale.isFinite, scale > 0,
              let index = frame.objects.firstIndex(where: { $0.id == id }) else { return }
        objectWillChange.send()
        frame.objects[index].transform.sizeSIMD *= scale
        if frame.objects[index].typeID == LabyrinthStrokePayload.typeID,
           var stroke = try? frame.objects[index].decodedPayload(as: LabyrinthStrokePayload.self) {
            stroke.worldWidth *= scale
            stroke.samples = stroke.samples.map {
                LabyrinthStrokeSample(x: $0.x * Float(scale), y: $0.y * Float(scale), pressure: $0.pressure)
            }
            stroke.segments = LabyrinthStrokePayload.buildSegments(from: stroke.samples, color: stroke.color)
            let bounds = LabyrinthStrokePayload.calculateBounds(
                for: stroke.samples,
                baseRadius: Float(stroke.worldWidth) * 0.5
            )
            stroke.segmentBounds = LabyrinthStrokeBounds(bounds)
            stroke.cullingRadiusWorld = LabyrinthStrokePayload.cullingRadius(from: bounds)
            if let payload = try? LabyrinthJSONValue.encodePayload(stroke) {
                frame.objects[index].payload = payload
            }
        }
    }

    public func mutateObject(id: UUID,
                             in frame: LabyrinthFrame,
                             _ mutate: (inout LabyrinthCanvasObject) -> Void) {
        guard let index = frame.objects.firstIndex(where: { $0.id == id }) else { return }
        objectWillChange.send()
        mutate(&frame.objects[index])
    }

    public func pan(by translation: CGPoint, viewSize: CGSize) {
        let beforeFrame = activeFrame
        let before = cameraSnapshot(viewSize: viewSize)
        objectWillChange.send()
        camera.panSIMD += SIMD2<Double>(Double(translation.x), Double(translation.y))
        let center = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        let anchor = LabyrinthCanvasMath.screenToWorld(center, viewSize: viewSize, camera: camera)
        _ = wrapFractalIfNeeded(anchorWorld: anchor, anchorScreen: center, viewSize: viewSize)
        lastCameraChange = LabyrinthCanvasCameraChange(
            kind: .pan,
            didTransition: activeFrame !== beforeFrame,
            before: before,
            after: cameraSnapshot(viewSize: viewSize)
        )
    }

    public func zoom(by scale: Double, anchorScreen: CGPoint, viewSize: CGSize) {
        let anchorWorld = LabyrinthCanvasMath.screenToWorld(anchorScreen, viewSize: viewSize, camera: camera)
        zoom(by: scale,
             lockedAnchorWorld: anchorWorld,
             anchorScreen: anchorScreen,
             targetScreen: anchorScreen,
             viewSize: viewSize)
    }

    @discardableResult
    func zoom(by scale: Double,
              lockedAnchorWorld anchorWorld: SIMD2<Double>,
              anchorScreen: CGPoint,
              targetScreen: CGPoint,
              viewSize: CGSize) -> LabyrinthAnchorGestureResult {
        guard scale.isFinite, scale > 0 else {
            return LabyrinthAnchorGestureResult(anchorWorld: anchorWorld, didTransition: false)
        }

        let before = cameraSnapshot(viewSize: viewSize, inspecting: anchorScreen)
        objectWillChange.send()
        camera.zoom = max(camera.zoom * scale, 1e-9)
        if checkFractalTransitions(anchorWorld: anchorWorld, anchorScreen: anchorScreen, viewSize: viewSize) {
            let refreshedAnchor = LabyrinthCanvasMath.screenToWorld(anchorScreen, viewSize: viewSize, camera: camera)
            lastCameraChange = LabyrinthCanvasCameraChange(
                kind: .zoom,
                didTransition: true,
                before: before,
                after: cameraSnapshot(viewSize: viewSize, inspecting: anchorScreen)
            )
            return LabyrinthAnchorGestureResult(anchorWorld: refreshedAnchor, didTransition: true)
        }

        camera.panSIMD = LabyrinthCanvasMath.solvePanOffset(
            anchorWorld: anchorWorld,
            desiredScreen: targetScreen,
            viewSize: viewSize,
            zoom: camera.zoom,
            rotation: camera.rotation
        )
        let beforeFinalWrapFrame = activeFrame
        let wrappedAnchor = wrapFractalIfNeeded(anchorWorld: anchorWorld,
                                                anchorScreen: targetScreen,
                                                viewSize: viewSize)
        lastCameraChange = LabyrinthCanvasCameraChange(
            kind: .zoom,
            didTransition: activeFrame !== beforeFinalWrapFrame,
            before: before,
            after: cameraSnapshot(viewSize: viewSize, inspecting: targetScreen)
        )
        return LabyrinthAnchorGestureResult(anchorWorld: wrappedAnchor, didTransition: false)
    }

    public func rotate(by radians: Float, anchorScreen: CGPoint, viewSize: CGSize) {
        let anchorWorld = LabyrinthCanvasMath.screenToWorld(anchorScreen, viewSize: viewSize, camera: camera)
        rotate(to: camera.rotation + radians,
               lockedAnchorWorld: anchorWorld,
               anchorScreen: anchorScreen,
               targetScreen: anchorScreen,
               viewSize: viewSize)
    }

    @discardableResult
    func rotate(to radians: Float,
                lockedAnchorWorld anchorWorld: SIMD2<Double>,
                anchorScreen: CGPoint,
                targetScreen: CGPoint,
                viewSize: CGSize) -> LabyrinthAnchorGestureResult {
        guard options.supportsRotation else {
            return LabyrinthAnchorGestureResult(anchorWorld: anchorWorld, didTransition: false)
        }

        let beforeFrame = activeFrame
        let before = cameraSnapshot(viewSize: viewSize, inspecting: anchorScreen)
        objectWillChange.send()
        camera.rotation = radians
        camera.panSIMD = LabyrinthCanvasMath.solvePanOffset(
            anchorWorld: anchorWorld,
            desiredScreen: targetScreen,
            viewSize: viewSize,
            zoom: camera.zoom,
            rotation: camera.rotation
        )
        let beforeFinalWrapFrame = activeFrame
        let wrappedAnchor = wrapFractalIfNeeded(anchorWorld: anchorWorld,
                                                anchorScreen: targetScreen,
                                                viewSize: viewSize)
        lastCameraChange = LabyrinthCanvasCameraChange(
            kind: .rotate,
            didTransition: activeFrame !== beforeFrame || activeFrame !== beforeFinalWrapFrame,
            before: before,
            after: cameraSnapshot(viewSize: viewSize, inspecting: targetScreen)
        )
        return LabyrinthAnchorGestureResult(anchorWorld: wrappedAnchor, didTransition: false)
    }

    public func cameraSnapshot(viewSize: CGSize,
                               inspecting screenPoint: CGPoint? = nil) -> LabyrinthCanvasCameraSnapshot {
        let centerScreen = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        let centerWorld = LabyrinthCanvasMath.screenToWorld(centerScreen,
                                                            viewSize: viewSize,
                                                            camera: camera)
        let inspectedWorld = screenPoint.map {
            LabyrinthCanvasMath.screenToWorld($0, viewSize: viewSize, camera: camera)
        }
        let centerRoot = pointInRootFrame(centerWorld, from: activeFrame)
        let inspectedRoot = inspectedWorld.flatMap { pointInRootFrame($0, from: activeFrame) }

        return LabyrinthCanvasCameraSnapshot(
            activeFrameID: activeFrame.id,
            activeFrameDepth: activeFrame.depthFromRoot,
            activeFramePath: framePathFromRoot(to: activeFrame),
            cameraPan: camera.pan,
            cameraZoom: camera.zoom,
            cameraRotation: camera.rotation,
            cameraCenterScreen: LabyrinthPoint(x: Double(centerScreen.x), y: Double(centerScreen.y)),
            cameraCenterInActiveFrame: LabyrinthPoint(centerWorld),
            cameraCenterInRootFrame: centerRoot.map(LabyrinthPoint.init),
            inspectedScreenPoint: screenPoint.map { LabyrinthPoint(x: Double($0.x), y: Double($0.y)) },
            inspectedPointInActiveFrame: inspectedWorld.map(LabyrinthPoint.init),
            inspectedPointInRootFrame: inspectedRoot.map(LabyrinthPoint.init)
        )
    }

    public func allFrames() -> [LabyrinthFrame] {
        var frames: [LabyrinthFrame] = []
        func visit(_ frame: LabyrinthFrame) {
            frames.append(frame)
            for child in frame.children.values {
                visit(child)
            }
        }
        visit(rootFrame)
        return frames
    }

    public func framePathFromRoot(to frame: LabyrinthFrame) -> [LabyrinthGridIndex]? {
        var path: [LabyrinthGridIndex] = []
        var cursor: LabyrinthFrame? = frame
        while let current = cursor, current !== rootFrame {
            guard let index = current.indexInParent, let parent = current.parent else {
                return nil
            }
            path.append(index)
            cursor = parent
        }
        guard cursor === rootFrame else { return nil }
        return path.reversed()
    }

    public func pointInRootFrame(_ point: SIMD2<Double>, from frame: LabyrinthFrame) -> SIMD2<Double>? {
        guard let path = framePathFromRoot(to: frame) else { return nil }

        var rootPoint = point
        for index in path.reversed() {
            let childCenter = LabyrinthFractalGrid.childCenterInParent(frameExtent: fractal.extentSIMD,
                                                                       index: index)
            rootPoint = childCenter + (rootPoint / fractal.scale)
        }
        return rootPoint
    }

    public func transformFromActive(to target: LabyrinthFrame) -> (scale: Double, translation: SIMD2<Double>)? {
        if target === activeFrame {
            return (1.0, .zero)
        }

        guard let activePath = framePathFromRoot(to: activeFrame),
              let targetPath = framePathFromRoot(to: target) else {
            return nil
        }

        let extent = fractal.extentSIMD
        var commonPrefixCount = 0
        let maxCommon = min(activePath.count, targetPath.count)
        while commonPrefixCount < maxCommon && activePath[commonPrefixCount] == targetPath[commonPrefixCount] {
            commonPrefixCount += 1
        }

        var scaleFromActive = 1.0
        var translation = SIMD2<Double>(0, 0)

        if commonPrefixCount < activePath.count {
            for index in activePath[commonPrefixCount...].reversed() {
                let center = LabyrinthFractalGrid.childCenterInParent(frameExtent: extent, index: index)
                scaleFromActive /= fractal.scale
                translation = center + (translation / fractal.scale)
            }
        }

        if commonPrefixCount < targetPath.count {
            for index in targetPath[commonPrefixCount...] {
                let center = LabyrinthFractalGrid.childCenterInParent(frameExtent: extent, index: index)
                scaleFromActive *= fractal.scale
                translation = (translation - center) * fractal.scale
            }
        }

        return (scaleFromActive, translation)
    }

    public func resolveFrame(forActivePoint pointActive: SIMD2<Double>) -> (frame: LabyrinthFrame, pointInFrame: SIMD2<Double>, conversionScale: Double) {
        let extent = fractal.extentSIMD
        let half = extent * 0.5
        var frame = activeFrame
        var point = pointActive

        while point.x > half.x {
            frame = neighborFrame(from: frame, direction: .right)
            point.x -= extent.x
        }
        while point.x < -half.x {
            frame = neighborFrame(from: frame, direction: .left)
            point.x += extent.x
        }
        while point.y > half.y {
            frame = neighborFrame(from: frame, direction: .down)
            point.y -= extent.y
        }
        while point.y < -half.y {
            frame = neighborFrame(from: frame, direction: .up)
            point.y += extent.y
        }

        return (frame, point, 1.0)
    }

    private func makeLocalStrokeSamples(_ screenSamples: [LabyrinthStrokeInputSample],
                                        firstScreenPoint: CGPoint,
                                        zoom: Double) -> [LabyrinthStrokeSample] {
        let angle = Double(camera.rotation)
        let c = cos(angle)
        let s = sin(angle)
        let maxSamples = 1000
        let stride = screenSamples.count > maxSamples ? max(1, screenSamples.count / maxSamples) : 1

        var localSamples: [LabyrinthStrokeSample] = []
        localSamples.reserveCapacity(min(screenSamples.count, maxSamples + 1))

        for index in Swift.stride(from: 0, to: screenSamples.count, by: stride) {
            let sample = screenSamples[index]
            let dx = Double(sample.point.x) - Double(firstScreenPoint.x)
            let dy = Double(sample.point.y) - Double(firstScreenPoint.y)
            let unrotatedX = dx * c + dy * s
            let unrotatedY = -dx * s + dy * c
            localSamples.append(LabyrinthStrokeSample(
                x: Float(unrotatedX / zoom),
                y: Float(unrotatedY / zoom),
                pressure: sample.pressure
            ))
        }

        let lastIndex = screenSamples.count - 1
        if lastIndex >= 0,
           lastIndex % stride != 0,
           let last = screenSamples.last {
            let dx = Double(last.point.x) - Double(firstScreenPoint.x)
            let dy = Double(last.point.y) - Double(firstScreenPoint.y)
            let unrotatedX = dx * c + dy * s
            let unrotatedY = -dx * s + dy * c
            localSamples.append(LabyrinthStrokeSample(
                x: Float(unrotatedX / zoom),
                y: Float(unrotatedY / zoom),
                pressure: last.pressure
            ))
        }

        return localSamples
    }

    private func allocateZIndex() -> UInt32 {
        let value = nextZIndex
        nextZIndex = nextZIndex == UInt32.max ? UInt32.max : nextZIndex + 1
        return value
    }

    private func neighborFrame(from frame: LabyrinthFrame, direction: LabyrinthGridDirection) -> LabyrinthFrame {
        let neighbor = frame.neighbor(direction) { newRoot in
            self.rootFrame = self.topmostFrame(from: newRoot)
        }
        rootFrame = topmostFrame(from: rootFrame)
        return neighbor
    }

    private func topmostFrame(from frame: LabyrinthFrame) -> LabyrinthFrame {
        var top = frame
        while let parent = top.parent {
            top = parent
        }
        return top
    }

    @discardableResult
    private func wrapFractalIfNeeded(anchorWorld: SIMD2<Double>,
                                     anchorScreen: CGPoint,
                                     viewSize: CGSize) -> SIMD2<Double> {
        let extent = fractal.extentSIMD
        let half = extent * 0.5
        var anchor = anchorWorld
        var moved = false

        while anchor.x > half.x {
            activeFrame = neighborFrame(from: activeFrame, direction: .right)
            anchor.x -= extent.x
            moved = true
        }
        while anchor.x < -half.x {
            activeFrame = neighborFrame(from: activeFrame, direction: .left)
            anchor.x += extent.x
            moved = true
        }
        while anchor.y > half.y {
            activeFrame = neighborFrame(from: activeFrame, direction: .down)
            anchor.y -= extent.y
            moved = true
        }
        while anchor.y < -half.y {
            activeFrame = neighborFrame(from: activeFrame, direction: .up)
            anchor.y += extent.y
            moved = true
        }

        if moved {
            camera.panSIMD = LabyrinthCanvasMath.solvePanOffset(
                anchorWorld: anchor,
                desiredScreen: anchorScreen,
                viewSize: viewSize,
                zoom: camera.zoom,
                rotation: camera.rotation
            )
        }

        return anchor
    }

    @discardableResult
    private func checkFractalTransitions(anchorWorld: SIMD2<Double>,
                                         anchorScreen: CGPoint,
                                         viewSize: CGSize) -> Bool {
        let beforeWrapFrame = activeFrame
        var anchor = wrapFractalIfNeeded(anchorWorld: anchorWorld, anchorScreen: anchorScreen, viewSize: viewSize)
        var transitioned = activeFrame !== beforeWrapFrame

        while camera.zoom >= fractal.scale {
            anchor = drillDownToChildTile(anchorWorld: anchor, anchorScreen: anchorScreen, viewSize: viewSize)
            transitioned = true
        }

        while camera.zoom < 1.0 {
            anchor = popUpToParentTile(anchorWorld: anchor, anchorScreen: anchorScreen, viewSize: viewSize)
            transitioned = true
        }

        let beforeWrap = activeFrame
        _ = wrapFractalIfNeeded(anchorWorld: anchor, anchorScreen: anchorScreen, viewSize: viewSize)
        if activeFrame !== beforeWrap {
            transitioned = true
        }

        return transitioned
    }

    private func drillDownToChildTile(anchorWorld: SIMD2<Double>,
                                      anchorScreen: CGPoint,
                                      viewSize: CGSize) -> SIMD2<Double> {
        let extent = fractal.extentSIMD
        let index = LabyrinthFractalGrid.childIndex(frameExtent: extent, pointInParent: anchorWorld)
        let child = activeFrame.child(at: index)
        let childCenter = LabyrinthFractalGrid.childCenterInParent(frameExtent: extent, index: index)
        let anchorInChild = (anchorWorld - childCenter) * fractal.scale

        activeFrame = child
        camera.zoom /= fractal.scale
        adjustScaleWithZoomBaseEffectiveZoom(by: 1.0 / fractal.scale)
        camera.panSIMD = LabyrinthCanvasMath.solvePanOffset(
            anchorWorld: anchorInChild,
            desiredScreen: anchorScreen,
            viewSize: viewSize,
            zoom: camera.zoom,
            rotation: camera.rotation
        )
        return anchorInChild
    }

    private func popUpToParentTile(anchorWorld: SIMD2<Double>,
                                   anchorScreen: CGPoint,
                                   viewSize: CGSize) -> SIMD2<Double> {
        let child = activeFrame
        if child.parent == nil {
            rootFrame = child.ensureSuperRoot()
        }

        guard let parent = child.parent, let index = child.indexInParent else {
            return anchorWorld
        }

        let childCenter = LabyrinthFractalGrid.childCenterInParent(frameExtent: fractal.extentSIMD, index: index)
        let anchorInParent = childCenter + (anchorWorld / fractal.scale)
        activeFrame = parent
        camera.zoom *= fractal.scale
        adjustScaleWithZoomBaseEffectiveZoom(by: fractal.scale)
        camera.panSIMD = LabyrinthCanvasMath.solvePanOffset(
            anchorWorld: anchorInParent,
            desiredScreen: anchorScreen,
            viewSize: viewSize,
            zoom: camera.zoom,
            rotation: camera.rotation
        )
        return anchorInParent
    }

    private func adjustScaleWithZoomBaseEffectiveZoom(by factor: Double) {
        var style = brushStyle
        style.adjustScaleWithZoomBaseEffectiveZoom(by: factor)
        if style != brushStyle {
            brushStyle = style
        }
    }

    private static func frame(at path: [LabyrinthGridIndex], root: LabyrinthFrame) -> LabyrinthFrame? {
        var frame: LabyrinthFrame? = root
        for index in path {
            frame = frame?.childIfExists(at: index)
            if frame == nil { return nil }
        }
        return frame
    }

    private static func nextZIndex(in root: LabyrinthFrame) -> UInt32 {
        var maxZ: UInt32 = 0
        func visit(_ frame: LabyrinthFrame) {
            for object in frame.objects {
                maxZ = max(maxZ, object.zIndex)
            }
            for child in frame.children.values {
                visit(child)
            }
        }
        visit(root)
        return maxZ == UInt32.max ? UInt32.max : maxZ + 1
    }
}
