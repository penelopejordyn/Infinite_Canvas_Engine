import Foundation

public struct LabyrinthDocumentSnapshot: Codable, Equatable, Sendable {
    public var schema: String
    public var version: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var fractal: LabyrinthFractalConfig
    public var rootFrame: LabyrinthFrameSnapshot
    public var activeFramePath: [LabyrinthGridIndex]
    public var camera: LabyrinthCamera

    public init(schema: String = "org.labyrinth.canvas",
                version: Int = 1,
                createdAt: Date = Date(),
                updatedAt: Date = Date(),
                fractal: LabyrinthFractalConfig = LabyrinthFractalConfig(),
                rootFrame: LabyrinthFrameSnapshot,
                activeFramePath: [LabyrinthGridIndex] = [],
                camera: LabyrinthCamera = LabyrinthCamera()) {
        self.schema = schema
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.fractal = fractal
        self.rootFrame = rootFrame
        self.activeFramePath = activeFramePath
        self.camera = camera
    }
}
