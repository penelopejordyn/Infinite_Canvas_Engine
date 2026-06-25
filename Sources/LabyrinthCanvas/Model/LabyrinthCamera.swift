import Foundation
import simd

public struct LabyrinthCamera: Codable, Equatable, Sendable {
    public var pan: LabyrinthPoint
    public var zoom: Double
    public var rotation: Float

    public init(pan: LabyrinthPoint = LabyrinthPoint(x: 0, y: 0),
                zoom: Double = 1.0,
                rotation: Float = 0) {
        self.pan = pan
        self.zoom = max(zoom, 1e-9)
        self.rotation = rotation
    }

    public var panSIMD: SIMD2<Double> {
        get { pan.simd }
        set { pan = LabyrinthPoint(newValue) }
    }
}

public enum LabyrinthInputMode: String, Codable, Sendable {
    case draw
    case erase
    case navigate
    case manipulate
}

public struct LabyrinthCanvasOptions: Sendable {
    public var backgroundColor: LabyrinthColor
    public var allowsFingerDrawing: Bool
    public var eraserRadius: Double
    public var minimumStrokeSampleDistance: Double
    public var supportsRotation: Bool

    public init(backgroundColor: LabyrinthColor = .paper,
                allowsFingerDrawing: Bool = true,
                eraserRadius: Double = 18,
                minimumStrokeSampleDistance: Double = 2,
                supportsRotation: Bool = true) {
        self.backgroundColor = backgroundColor
        self.allowsFingerDrawing = allowsFingerDrawing
        self.eraserRadius = eraserRadius
        self.minimumStrokeSampleDistance = minimumStrokeSampleDistance
        self.supportsRotation = supportsRotation
    }
}
