import Foundation
import simd

public struct LabyrinthGridIndex: Hashable, Codable, Sendable {
    public static let gridSize = 5
    public static let center = LabyrinthGridIndex(col: 2, row: 2)

    public var col: Int
    public var row: Int

    public init(col: Int, row: Int) {
        self.col = col
        self.row = row
    }

    public var isValid: Bool {
        (0..<Self.gridSize).contains(col) && (0..<Self.gridSize).contains(row)
    }

    public func clamped() -> LabyrinthGridIndex {
        LabyrinthGridIndex(
            col: min(max(col, 0), Self.gridSize - 1),
            row: min(max(row, 0), Self.gridSize - 1)
        )
    }

    public func wrapped() -> LabyrinthGridIndex {
        func wrap(_ value: Int) -> Int {
            let modulo = Self.gridSize
            let remainder = value % modulo
            return remainder < 0 ? remainder + modulo : remainder
        }

        return LabyrinthGridIndex(col: wrap(col), row: wrap(row))
    }
}

public enum LabyrinthGridDirection: CaseIterable, Sendable {
    case left
    case right
    case up
    case down

    public var delta: (dx: Int, dy: Int) {
        switch self {
        case .left:
            return (-1, 0)
        case .right:
            return (1, 0)
        case .up:
            return (0, -1)
        case .down:
            return (0, 1)
        }
    }
}

public struct LabyrinthFractalConfig: Codable, Equatable, Sendable {
    public var gridSize: Int
    public var scale: Double
    public var frameExtent: LabyrinthSize

    public init(gridSize: Int = LabyrinthGridIndex.gridSize,
                scale: Double = LabyrinthFractalGrid.scale,
                frameExtent: LabyrinthSize = LabyrinthSize(width: 1024, height: 1024)) {
        self.gridSize = gridSize
        self.scale = scale
        self.frameExtent = frameExtent
    }

    public var extentSIMD: SIMD2<Double> {
        frameExtent.simd
    }
}

public enum LabyrinthFractalGrid {
    public static let scale: Double = 5.0
    public static let defaultFrameExtent = SIMD2<Double>(1024.0, 1024.0)

    public static func tileExtent(frameExtent: SIMD2<Double>) -> SIMD2<Double> {
        frameExtent / Double(LabyrinthGridIndex.gridSize)
    }

    public static func childCenterInParent(frameExtent: SIMD2<Double>,
                                           index: LabyrinthGridIndex) -> SIMD2<Double> {
        let tile = tileExtent(frameExtent: frameExtent)
        let x = (Double(index.col) - Double(LabyrinthGridIndex.center.col)) * tile.x
        let y = (Double(index.row) - Double(LabyrinthGridIndex.center.row)) * tile.y
        return SIMD2<Double>(x, y)
    }

    public static func childIndex(frameExtent: SIMD2<Double>,
                                  pointInParent: SIMD2<Double>) -> LabyrinthGridIndex {
        let tile = tileExtent(frameExtent: frameExtent)
        let half = frameExtent * 0.5
        let fx = (pointInParent.x + half.x) / max(tile.x, 1e-9)
        let fy = (pointInParent.y + half.y) / max(tile.y, 1e-9)
        return LabyrinthGridIndex(col: Int(floor(fx)), row: Int(floor(fy))).clamped()
    }
}
