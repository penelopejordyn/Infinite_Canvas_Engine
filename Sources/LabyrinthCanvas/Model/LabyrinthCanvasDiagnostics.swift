import Foundation

public struct LabyrinthCanvasCameraSnapshot: Codable, Equatable, Sendable {
    public var activeFrameID: UUID
    public var activeFrameDepth: Int
    public var activeFramePath: [LabyrinthGridIndex]?
    public var cameraPan: LabyrinthPoint
    public var cameraZoom: Double
    public var cameraRotation: Float
    public var cameraCenterScreen: LabyrinthPoint
    public var cameraCenterInActiveFrame: LabyrinthPoint
    public var cameraCenterInRootFrame: LabyrinthPoint?
    public var inspectedScreenPoint: LabyrinthPoint?
    public var inspectedPointInActiveFrame: LabyrinthPoint?
    public var inspectedPointInRootFrame: LabyrinthPoint?

    public init(activeFrameID: UUID,
                activeFrameDepth: Int,
                activeFramePath: [LabyrinthGridIndex]?,
                cameraPan: LabyrinthPoint,
                cameraZoom: Double,
                cameraRotation: Float,
                cameraCenterScreen: LabyrinthPoint,
                cameraCenterInActiveFrame: LabyrinthPoint,
                cameraCenterInRootFrame: LabyrinthPoint?,
                inspectedScreenPoint: LabyrinthPoint?,
                inspectedPointInActiveFrame: LabyrinthPoint?,
                inspectedPointInRootFrame: LabyrinthPoint?) {
        self.activeFrameID = activeFrameID
        self.activeFrameDepth = activeFrameDepth
        self.activeFramePath = activeFramePath
        self.cameraPan = cameraPan
        self.cameraZoom = cameraZoom
        self.cameraRotation = cameraRotation
        self.cameraCenterScreen = cameraCenterScreen
        self.cameraCenterInActiveFrame = cameraCenterInActiveFrame
        self.cameraCenterInRootFrame = cameraCenterInRootFrame
        self.inspectedScreenPoint = inspectedScreenPoint
        self.inspectedPointInActiveFrame = inspectedPointInActiveFrame
        self.inspectedPointInRootFrame = inspectedPointInRootFrame
    }
}

public enum LabyrinthCanvasCameraChangeKind: String, Codable, Equatable, Sendable {
    case pan
    case zoom
    case rotate
}

public struct LabyrinthCanvasCameraChange: Codable, Equatable, Sendable {
    public var kind: LabyrinthCanvasCameraChangeKind
    public var didTransition: Bool
    public var before: LabyrinthCanvasCameraSnapshot
    public var after: LabyrinthCanvasCameraSnapshot

    public init(kind: LabyrinthCanvasCameraChangeKind,
                didTransition: Bool,
                before: LabyrinthCanvasCameraSnapshot,
                after: LabyrinthCanvasCameraSnapshot) {
        self.kind = kind
        self.didTransition = didTransition
        self.before = before
        self.after = after
    }
}
