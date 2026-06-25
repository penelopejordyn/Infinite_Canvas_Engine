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

    public static func storageValue(for pressure: Float?) -> Float {
        guard let pressure else { return disabledStorageValue }
        return normalized(pressure)
    }

    public static func pressure(fromStorageValue value: Float) -> Float? {
        guard value >= 0, value.isFinite else { return nil }
        return normalized(value)
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

public struct LabyrinthStrokeSegmentInstance: Codable, Equatable, Sendable {
    public var p0: LabyrinthPoint
    public var p1: LabyrinthPoint
    public var color: LabyrinthColor
    public var pressure0Storage: Float
    public var pressure1Storage: Float

    public init(p0: SIMD2<Float>,
                p1: SIMD2<Float>,
                color: LabyrinthColor,
                pressure0: Float? = nil,
                pressure1: Float? = nil) {
        self.p0 = LabyrinthPoint(x: Double(p0.x), y: Double(p0.y))
        self.p1 = LabyrinthPoint(x: Double(p1.x), y: Double(p1.y))
        self.color = color
        self.pressure0Storage = LabyrinthStrokePressureCurve.storageValue(for: pressure0)
        self.pressure1Storage = LabyrinthStrokePressureCurve.storageValue(for: pressure1)
    }

    public var p0SIMD: SIMD2<Float> {
        SIMD2<Float>(Float(p0.x), Float(p0.y))
    }

    public var p1SIMD: SIMD2<Float> {
        SIMD2<Float>(Float(p1.x), Float(p1.y))
    }

    public var pressure0: Float? {
        LabyrinthStrokePressureCurve.pressure(fromStorageValue: pressure0Storage)
    }

    public var pressure1: Float? {
        LabyrinthStrokePressureCurve.pressure(fromStorageValue: pressure1Storage)
    }
}

public struct LabyrinthStrokeBounds: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        if rect == .null {
            self.init(x: 0, y: 0, width: 0, height: 0)
        } else {
            self.init(x: Double(rect.origin.x),
                      y: Double(rect.origin.y),
                      width: Double(rect.width),
                      height: Double(rect.height))
        }
    }

    public var cgRect: CGRect {
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite else { return .null }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

public struct LabyrinthStrokePayload: LabyrinthObjectPayload, Equatable {
    public static let typeID = "labyrinth.stroke"
    public static let minimumVisibleScreenWidth: Double = 0.005
    public static let minimumLiveScreenWidth: Double = 0.05

    public var brushID: String
    public var worldWidth: Double
    public var color: LabyrinthColor
    public var creationZoom: Double
    public var samples: [LabyrinthStrokeSample]
    public var segments: [LabyrinthStrokeSegmentInstance]
    public var segmentBounds: LabyrinthStrokeBounds
    public var cullingRadiusWorld: Double
    public var depthWriteEnabled: Bool

    public init(brushID: String = LabyrinthInkBrush.id,
                worldWidth: Double,
                color: LabyrinthColor,
                creationZoom: Double,
                samples: [LabyrinthStrokeSample],
                depthWriteEnabled: Bool = true) {
        self.brushID = brushID
        self.worldWidth = worldWidth
        self.color = color
        self.creationZoom = creationZoom
        self.samples = samples
        self.segments = Self.buildSegments(from: samples, color: color)
        let bounds = Self.calculateBounds(for: samples, baseRadius: Float(worldWidth) * 0.5)
        self.segmentBounds = LabyrinthStrokeBounds(bounds)
        self.cullingRadiusWorld = Self.cullingRadius(from: bounds)
        self.depthWriteEnabled = depthWriteEnabled
    }

    public var localBounds: CGRect {
        segmentBounds.cgRect
    }

    public func screenWidth(at zoom: Double) -> Double {
        worldWidth * max(zoom, 1e-6)
    }

    public func renderedHalfPixelWidth(at zoom: Double,
                                       cullBelowMinimum: Bool,
                                       minimumScreenWidth: Double = Self.minimumVisibleScreenWidth) -> Float? {
        let screenWidth = screenWidth(at: zoom)
        if cullBelowMinimum && screenWidth < Self.minimumVisibleScreenWidth {
            return nil
        }
        return Float(max(screenWidth, minimumScreenWidth) * 0.5)
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

    public static func buildSegments(from samples: [LabyrinthStrokeSample],
                                     color: LabyrinthColor) -> [LabyrinthStrokeSegmentInstance] {
        guard !samples.isEmpty else { return [] }

        if samples.count == 1 {
            let sample = samples[0]
            return [
                LabyrinthStrokeSegmentInstance(
                    p0: sample.point,
                    p1: sample.point,
                    color: color,
                    pressure0: sample.pressure,
                    pressure1: sample.pressure
                )
            ]
        }

        var segments: [LabyrinthStrokeSegmentInstance] = []
        segments.reserveCapacity(samples.count - 1)

        for index in 0..<(samples.count - 1) {
            let start = samples[index]
            let end = samples[index + 1]
            segments.append(
                LabyrinthStrokeSegmentInstance(
                    p0: start.point,
                    p1: end.point,
                    color: color,
                    pressure0: start.pressure,
                    pressure1: end.pressure
                )
            )
        }

        return segments
    }

    public static func calculateBounds(for samples: [LabyrinthStrokeSample],
                                       baseRadius: Float) -> CGRect {
        guard let first = samples.first else { return .null }

        let radius = baseRadius * maxPressureMultiplier(for: samples)
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

        minX -= radius
        maxX += radius
        minY -= radius
        maxY += radius

        return CGRect(
            x: Double(minX),
            y: Double(minY),
            width: Double(maxX - minX),
            height: Double(maxY - minY)
        )
    }

    public static func maxPressureMultiplier(for samples: [LabyrinthStrokeSample]) -> Float {
        guard !samples.isEmpty else { return 1.0 }
        return samples.reduce(Float(1.0)) { partial, sample in
            max(partial, LabyrinthStrokePressureCurve.multiplier(for: sample.pressure))
        }
    }

    public static func cullingRadius(from bounds: CGRect) -> Double {
        if bounds == .null { return 0 }
        let farX = max(abs(bounds.minX), abs(bounds.maxX))
        let farY = max(abs(bounds.minY), abs(bounds.maxY))
        return hypot(farX, farY)
    }

    private enum CodingKeys: String, CodingKey {
        case brushID
        case worldWidth
        case color
        case creationZoom
        case samples
        case segments
        case segmentBounds
        case cullingRadiusWorld
        case depthWriteEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        brushID = try container.decodeIfPresent(String.self, forKey: .brushID) ?? LabyrinthInkBrush.id
        worldWidth = try container.decode(Double.self, forKey: .worldWidth)
        color = try container.decode(LabyrinthColor.self, forKey: .color)
        creationZoom = try container.decode(Double.self, forKey: .creationZoom)
        samples = try container.decode([LabyrinthStrokeSample].self, forKey: .samples)
        segments = try container.decodeIfPresent([LabyrinthStrokeSegmentInstance].self, forKey: .segments)
            ?? Self.buildSegments(from: samples, color: color)

        let bounds = Self.calculateBounds(for: samples, baseRadius: Float(worldWidth) * 0.5)
        segmentBounds = try container.decodeIfPresent(LabyrinthStrokeBounds.self, forKey: .segmentBounds)
            ?? LabyrinthStrokeBounds(bounds)
        cullingRadiusWorld = try container.decodeIfPresent(Double.self, forKey: .cullingRadiusWorld)
            ?? Self.cullingRadius(from: segmentBounds.cgRect)
        depthWriteEnabled = try container.decodeIfPresent(Bool.self, forKey: .depthWriteEnabled) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(brushID, forKey: .brushID)
        try container.encode(worldWidth, forKey: .worldWidth)
        try container.encode(color, forKey: .color)
        try container.encode(creationZoom, forKey: .creationZoom)
        try container.encode(samples, forKey: .samples)
        try container.encode(segments, forKey: .segments)
        try container.encode(segmentBounds, forKey: .segmentBounds)
        try container.encode(cullingRadiusWorld, forKey: .cullingRadiusWorld)
        try container.encode(depthWriteEnabled, forKey: .depthWriteEnabled)
    }
}

public struct LabyrinthBrushStyle: Codable, Equatable, Sendable {
    public var brushID: String
    public var width: Double
    public var color: LabyrinthColor
    public var constantScreenSize: Bool
    public var scaleWithZoomBaseEffectiveZoom: Double

    public var strokeWidthMode: LabyrinthStrokeWidthMode {
        get { constantScreenSize ? .fixedScreenSize : .scalesWithZoom }
        set { constantScreenSize = newValue == .fixedScreenSize }
    }

    public init(brushID: String = LabyrinthInkBrush.id,
                width: Double = 6,
                color: LabyrinthColor = .ink,
                constantScreenSize: Bool = true,
                scaleWithZoomBaseEffectiveZoom: Double = 1.0) {
        self.brushID = brushID
        self.width = width
        self.color = color
        self.constantScreenSize = constantScreenSize
        self.scaleWithZoomBaseEffectiveZoom = Self.safeEffectiveZoom(scaleWithZoomBaseEffectiveZoom)
    }

    public init(brushID: String = LabyrinthInkBrush.id,
                width: Double = 6,
                color: LabyrinthColor = .ink,
                strokeWidthMode: LabyrinthStrokeWidthMode,
                scaleWithZoomBaseEffectiveZoom: Double = 1.0) {
        self.init(brushID: brushID,
                  width: width,
                  color: color,
                  constantScreenSize: strokeWidthMode == .fixedScreenSize,
                  scaleWithZoomBaseEffectiveZoom: scaleWithZoomBaseEffectiveZoom)
    }

    public mutating func setStrokeWidthMode(_ mode: LabyrinthStrokeWidthMode,
                                            currentEffectiveZoom: Double) {
        let shouldBeFixed = mode == .fixedScreenSize
        if constantScreenSize && !shouldBeFixed {
            scaleWithZoomBaseEffectiveZoom = Self.safeEffectiveZoom(currentEffectiveZoom)
        }
        constantScreenSize = shouldBeFixed
    }

    public mutating func adjustScaleWithZoomBaseEffectiveZoom(by factor: Double) {
        guard !constantScreenSize, factor.isFinite, factor > 0 else { return }
        scaleWithZoomBaseEffectiveZoom = Self.safeEffectiveZoom(scaleWithZoomBaseEffectiveZoom * factor)
    }

    public func worldStrokeWidth(effectiveZoom: Double) -> Double {
        if constantScreenSize {
            return width / Self.safeEffectiveZoom(effectiveZoom)
        }
        return width / Self.safeEffectiveZoom(scaleWithZoomBaseEffectiveZoom)
    }

    public func screenStrokeWidth(effectiveZoom: Double) -> Double {
        worldStrokeWidth(effectiveZoom: effectiveZoom) * Self.safeEffectiveZoom(effectiveZoom)
    }

    private static func safeEffectiveZoom(_ zoom: Double) -> Double {
        guard zoom.isFinite else { return 1.0 }
        return max(zoom, 1e-6)
    }

    private enum CodingKeys: String, CodingKey {
        case brushID
        case width
        case color
        case constantScreenSize
        case scaleWithZoomBaseEffectiveZoom
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        brushID = try container.decode(String.self, forKey: .brushID)
        width = try container.decode(Double.self, forKey: .width)
        color = try container.decode(LabyrinthColor.self, forKey: .color)
        constantScreenSize = try container.decode(Bool.self, forKey: .constantScreenSize)
        let baseZoom = try container.decodeIfPresent(Double.self, forKey: .scaleWithZoomBaseEffectiveZoom) ?? 1.0
        scaleWithZoomBaseEffectiveZoom = Self.safeEffectiveZoom(baseZoom)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(brushID, forKey: .brushID)
        try container.encode(width, forKey: .width)
        try container.encode(color, forKey: .color)
        try container.encode(constantScreenSize, forKey: .constantScreenSize)
        try container.encode(scaleWithZoomBaseEffectiveZoom, forKey: .scaleWithZoomBaseEffectiveZoom)
    }
}

public enum LabyrinthStrokeWidthMode: String, Codable, Sendable {
    /// Stroke width stays visually fixed as the user zooms.
    case fixedScreenSize
    /// Stroke width is authored in canvas units and scales with zoom.
    case scalesWithZoom
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
