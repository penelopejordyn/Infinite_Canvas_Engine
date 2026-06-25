import CoreGraphics
import Foundation
#if canImport(Metal)
import Metal
#endif
import simd

public struct LabyrinthBrushContext {
    public var frameID: UUID
    public var frameDepth: Int
    public var zIndex: UInt32
    public var viewSize: CGSize
    public var camera: LabyrinthCamera

    public init(frameID: UUID,
                frameDepth: Int,
                zIndex: UInt32,
                viewSize: CGSize,
                camera: LabyrinthCamera) {
        self.frameID = frameID
        self.frameDepth = frameDepth
        self.zIndex = zIndex
        self.viewSize = viewSize
        self.camera = camera
    }
}

public protocol LabyrinthBrush {
    var id: String { get }
    func makeObject(from draft: LabyrinthStrokeDraft,
                    context: LabyrinthBrushContext) throws -> LabyrinthCanvasObject
}

public struct LabyrinthInkBrush: LabyrinthBrush {
    public static let id = "labyrinth.ink"
    public var id: String { Self.id }

    public init() {}

    public func makeObject(from draft: LabyrinthStrokeDraft,
                           context: LabyrinthBrushContext) throws -> LabyrinthCanvasObject {
        guard !draft.localSamples.isEmpty else {
            throw LabyrinthCanvasError.emptyStroke
        }

        let payload = LabyrinthStrokePayload(
            brushID: id,
            worldWidth: draft.worldWidth,
            color: draft.brushStyle.color,
            creationZoom: draft.creationZoom,
            samples: draft.localSamples
        )
        let bounds = payload.localBounds
        let size = bounds == .null
            ? LabyrinthSize(width: draft.worldWidth, height: draft.worldWidth)
            : LabyrinthSize(width: max(Double(bounds.width), draft.worldWidth),
                            height: max(Double(bounds.height), draft.worldWidth))

        return try LabyrinthCanvasObject(
            transform: LabyrinthObjectTransform(
                position: LabyrinthPoint(draft.originInFrame),
                size: size,
                rotation: 0
            ),
            zIndex: context.zIndex,
            payload: payload
        )
    }
}

public final class LabyrinthBrushRegistry {
    private var brushes: [String: LabyrinthBrush] = [:]

    public init() {
        register(LabyrinthInkBrush())
    }

    public func register(_ brush: LabyrinthBrush) {
        brushes[brush.id] = brush
    }

    public func brush(for id: String) -> LabyrinthBrush? {
        brushes[id]
    }

    public var registeredBrushIDs: [String] {
        brushes.keys.sorted()
    }
}

public struct LabyrinthGestureContext {
    public var model: LabyrinthCanvasModel
    public var frame: LabyrinthFrame
    public var viewSize: CGSize
    public var pointInFrame: SIMD2<Double>

    public init(model: LabyrinthCanvasModel,
                frame: LabyrinthFrame,
                viewSize: CGSize,
                pointInFrame: SIMD2<Double>) {
        self.model = model
        self.frame = frame
        self.viewSize = viewSize
        self.pointInFrame = pointInFrame
    }
}

public protocol LabyrinthObjectGestureHandler {
    func begin(object: inout LabyrinthCanvasObject, context: LabyrinthGestureContext)
    func update(object: inout LabyrinthCanvasObject, context: LabyrinthGestureContext)
    func end(object: inout LabyrinthCanvasObject, context: LabyrinthGestureContext)
}

#if canImport(Metal)
public struct LabyrinthObjectRenderContext {
    public let device: MTLDevice
    public let commandBuffer: MTLCommandBuffer
    public let encoder: MTLRenderCommandEncoder
    public let viewSize: CGSize
    public let camera: LabyrinthCamera
    public let transformFromActive: (scale: Double, translation: SIMD2<Double>)

    public init(device: MTLDevice,
                commandBuffer: MTLCommandBuffer,
                encoder: MTLRenderCommandEncoder,
                viewSize: CGSize,
                camera: LabyrinthCamera,
                transformFromActive: (scale: Double, translation: SIMD2<Double>)) {
        self.device = device
        self.commandBuffer = commandBuffer
        self.encoder = encoder
        self.viewSize = viewSize
        self.camera = camera
        self.transformFromActive = transformFromActive
    }
}

public protocol LabyrinthObjectRenderer: AnyObject {
    var typeID: String { get }
    func draw(object: LabyrinthCanvasObject,
              frame: LabyrinthFrame,
              context: LabyrinthObjectRenderContext)
}
#else
public protocol LabyrinthObjectRenderer: AnyObject {
    var typeID: String { get }
}
#endif
