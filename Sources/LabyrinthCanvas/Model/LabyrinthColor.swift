import Foundation
import simd

public struct LabyrinthColor: Codable, Equatable, Sendable {
    public var red: Float
    public var green: Float
    public var blue: Float
    public var alpha: Float

    public init(red: Float, green: Float, blue: Float, alpha: Float = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(_ vector: SIMD4<Float>) {
        self.init(red: vector.x, green: vector.y, blue: vector.z, alpha: vector.w)
    }

    public var simd: SIMD4<Float> {
        SIMD4<Float>(red, green, blue, alpha)
    }

    public static let ink = LabyrinthColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1.0)
    public static let paper = LabyrinthColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1.0)
    public static let clear = LabyrinthColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
}
