import CoreGraphics
import Foundation
import simd

public enum LabyrinthStrokePressureCurve {
    public static let disabledStorageValue: Float = -1.0
    public static let minMultiplier: Float = 0.6
    public static let maxMultiplier: Float = 1.8
    public static let gamma: Float = 1.5

    public static func normalized(_ pressure: Float) -> Float {
        min(max(pressure, 0), 1)
    }

    public static func multiplier(for pressure: Float?) -> Float {
        guard let pressure else { return 1.0 }
        let curved = pow(normalized(pressure), gamma)
        return minMultiplier + curved * (maxMultiplier - minMultiplier)
    }
}

public struct LabyrinthStrokeSample: Codable, Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var pressure: Float?

    public init(x: Float, y: Float, pressure: Float? = nil) {
        self.x = x
        self.y = y
        self.pressure = pressure.map(LabyrinthStrokePressureCurve.normalized)
    }

    public init(_ point: SIMD2<Float>, pressure: Float? = nil) {
        self.init(x: point.x, y: point.y, pressure: pressure)
    }

    public var point: SIMD2<Float> {
        SIMD2<Float>(x, y)
    }
}

public struct LabyrinthStrokeInputSample: Sendable {
    public var point: CGPoint
    public var pressure: Float?

    public init(point: CGPoint, pressure: Float? = nil) {
        self.point = point
        self.pressure = pressure.map(LabyrinthStrokePressureCurve.normalized)
    }
}

public struct LabyrinthStrokePayload: LabyrinthObjectPayload, Equatable {
    public static let typeID = "labyrinth.stroke"

    public var brushID: String
    public var worldWidth: Double
    public var color: LabyrinthColor
    public var creationZoom: Double
    public var samples: [LabyrinthStrokeSample]

    public init(brushID: String = LabyrinthInkBrush.id,
                worldWidth: Double,
                color: LabyrinthColor,
                creationZoom: Double,
                samples: [LabyrinthStrokeSample]) {
        self.brushID = brushID
        self.worldWidth = worldWidth
        self.color = color
        self.creationZoom = creationZoom
        self.samples = samples
    }

    public var localBounds: CGRect {
        guard let first = samples.first else { return .null }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y

        for sample in samples.dropFirst() {
            minX = min(minX, sample.x)
            maxX = max(maxX, sample.x)
            minY = min(minY, sample.y)
            maxY = max(maxY, sample.y)
        }

        let maxPressure = samples.reduce(Float(1)) { partial, sample in
            max(partial, LabyrinthStrokePressureCurve.multiplier(for: sample.pressure))
        }
        let radius = CGFloat(Float(worldWidth) * 0.5 * maxPressure)
        return CGRect(
            x: CGFloat(minX) - radius,
            y: CGFloat(minY) - radius,
            width: CGFloat(maxX - minX) + radius * 2,
            height: CGFloat(maxY - minY) + radius * 2
        )
    }

    public func hitTest(pointInFrame: SIMD2<Double>,
                        origin: SIMD2<Double>,
                        eraserRadius: Double) -> Bool {
        let local = SIMD2<Float>(
            Float(pointInFrame.x - origin.x),
            Float(pointInFrame.y - origin.y)
        )

        let bounds = localBounds
        if bounds != .null {
            let radius = CGFloat(eraserRadius)
            if CGFloat(local.x) < bounds.minX - radius ||
                CGFloat(local.x) > bounds.maxX + radius ||
                CGFloat(local.y) < bounds.minY - radius ||
                CGFloat(local.y) > bounds.maxY + radius {
                return false
            }
        }

        guard !samples.isEmpty else { return false }
        if samples.count == 1 {
            let delta = local - samples[0].point
            let pressureRadius = Float(worldWidth * 0.5) * LabyrinthStrokePressureCurve.multiplier(for: samples[0].pressure)
            let radius = pressureRadius + Float(eraserRadius)
            return simd_dot(delta, delta) <= radius * radius
        }

        for index in 0..<(samples.count - 1) {
            let start = samples[index]
            let end = samples[index + 1]
            let a = start.point
            let b = end.point
            let ab = b - a
            let denominator = simd_dot(ab, ab)
            let t = denominator > 0 ? max(0, min(1, simd_dot(local - a, ab) / denominator)) : 0
            let closest = a + ab * t
            let delta = local - closest
            let pressure: Float? = {
                switch (start.pressure, end.pressure) {
                case let (lhs?, rhs?):
                    return lhs + (rhs - lhs) * t
                case let (lhs?, nil):
                    return lhs
                case let (nil, rhs?):
                    return rhs
                case (nil, nil):
                    return nil
                }
            }()
            let radius = Float(worldWidth * 0.5) * LabyrinthStrokePressureCurve.multiplier(for: pressure) + Float(eraserRadius)
            if simd_dot(delta, delta) <= radius * radius {
                return true
            }
        }

        return false
    }
}

public struct LabyrinthBrushStyle: Codable, Equatable, Sendable {
    public var brushID: String
    public var width: Double
    public var color: LabyrinthColor
    public var constantScreenSize: Bool

    public init(brushID: String = LabyrinthInkBrush.id,
                width: Double = 6,
                color: LabyrinthColor = .ink,
                constantScreenSize: Bool = true) {
        self.brushID = brushID
        self.width = width
        self.color = color
        self.constantScreenSize = constantScreenSize
    }
}

public struct LabyrinthStrokeDraft: Sendable {
    public var screenSamples: [LabyrinthStrokeInputSample]
    public var localSamples: [LabyrinthStrokeSample]
    public var originInFrame: SIMD2<Double>
    public var worldWidth: Double
    public var creationZoom: Double
    public var brushStyle: LabyrinthBrushStyle

    public init(screenSamples: [LabyrinthStrokeInputSample],
                localSamples: [LabyrinthStrokeSample],
                originInFrame: SIMD2<Double>,
                worldWidth: Double,
                creationZoom: Double,
                brushStyle: LabyrinthBrushStyle) {
        self.screenSamples = screenSamples
        self.localSamples = localSamples
        self.originInFrame = originInFrame
        self.worldWidth = worldWidth
        self.creationZoom = creationZoom
        self.brushStyle = brushStyle
    }
}
