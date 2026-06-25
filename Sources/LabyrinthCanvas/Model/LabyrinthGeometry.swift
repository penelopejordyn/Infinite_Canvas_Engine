import CoreGraphics
import Foundation
import simd

public struct LabyrinthSize: Codable, Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public var simd: SIMD2<Double> {
        SIMD2<Double>(width, height)
    }
}

public struct LabyrinthPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(_ vector: SIMD2<Double>) {
        self.init(x: vector.x, y: vector.y)
    }

    public var simd: SIMD2<Double> {
        SIMD2<Double>(x, y)
    }
}

public struct LabyrinthObjectTransform: Codable, Equatable, Sendable {
    public var position: LabyrinthPoint
    public var size: LabyrinthSize
    public var rotation: Float

    public init(position: LabyrinthPoint = LabyrinthPoint(x: 0, y: 0),
                size: LabyrinthSize = LabyrinthSize(width: 0, height: 0),
                rotation: Float = 0) {
        self.position = position
        self.size = size
        self.rotation = rotation
    }

    public var positionSIMD: SIMD2<Double> {
        get { position.simd }
        set { position = LabyrinthPoint(newValue) }
    }

    public var sizeSIMD: SIMD2<Double> {
        get { size.simd }
        set { size = LabyrinthSize(width: newValue.x, height: newValue.y) }
    }

    public func contains(pointInFrame point: SIMD2<Double>, padding: Double = 0) -> Bool {
        let origin = position.simd
        let delta = point - origin
        let angle = -Double(rotation)
        let c = cos(angle)
        let s = sin(angle)
        let local = SIMD2<Double>(
            delta.x * c - delta.y * s,
            delta.x * s + delta.y * c
        )
        let half = size.simd * 0.5
        return abs(local.x) <= half.x + padding && abs(local.y) <= half.y + padding
    }
}

public enum LabyrinthCanvasMath {
    public static func screenToWorld(_ point: CGPoint,
                                     viewSize: CGSize,
                                     camera: LabyrinthCamera) -> SIMD2<Double> {
        let center = SIMD2<Double>(Double(viewSize.width) / 2.0, Double(viewSize.height) / 2.0)
        let screen = SIMD2<Double>(Double(point.x), Double(point.y))
        let offset = screen - center - camera.panSIMD

        let angle = Double(camera.rotation)
        let c = cos(angle)
        let s = sin(angle)
        let unrotated = SIMD2<Double>(
            offset.x * c + offset.y * s,
            -offset.x * s + offset.y * c
        )

        return unrotated / max(camera.zoom, 1e-9)
    }

    public static func worldToScreen(_ world: SIMD2<Double>,
                                     viewSize: CGSize,
                                     camera: LabyrinthCamera) -> CGPoint {
        let center = SIMD2<Double>(Double(viewSize.width) / 2.0, Double(viewSize.height) / 2.0)
        let zoomed = world * max(camera.zoom, 1e-9)

        let angle = Double(camera.rotation)
        let c = cos(angle)
        let s = sin(angle)
        let rotated = SIMD2<Double>(
            zoomed.x * c - zoomed.y * s,
            zoomed.x * s + zoomed.y * c
        )

        let screen = rotated + camera.panSIMD + center
        return CGPoint(x: screen.x, y: screen.y)
    }

    public static func solvePanOffset(anchorWorld: SIMD2<Double>,
                                      desiredScreen: CGPoint,
                                      viewSize: CGSize,
                                      zoom: Double,
                                      rotation: Float) -> SIMD2<Double> {
        let center = SIMD2<Double>(Double(viewSize.width) / 2.0, Double(viewSize.height) / 2.0)
        let angle = Double(rotation)
        let c = cos(angle)
        let s = sin(angle)
        let rotated = SIMD2<Double>(
            anchorWorld.x * c - anchorWorld.y * s,
            anchorWorld.x * s + anchorWorld.y * c
        )
        let zoomed = rotated * max(zoom, 1e-9)
        let desired = SIMD2<Double>(Double(desiredScreen.x), Double(desiredScreen.y))
        return desired - center - zoomed
    }
}
