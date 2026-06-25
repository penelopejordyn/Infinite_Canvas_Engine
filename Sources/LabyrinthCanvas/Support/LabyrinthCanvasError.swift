import Foundation

public enum LabyrinthCanvasError: Error, LocalizedError, Equatable {
    case invalidPayload(String)
    case unknownBrush(String)
    case unknownObjectType(String)
    case emptyStroke
    case frameNotConnected(UUID)

    public var errorDescription: String? {
        switch self {
        case .invalidPayload(let message):
            return message
        case .unknownBrush(let id):
            return "No Labyrinth brush is registered for id '\(id)'."
        case .unknownObjectType(let id):
            return "No Labyrinth object type is registered for id '\(id)'."
        case .emptyStroke:
            return "Cannot create a stroke without samples."
        case .frameNotConnected(let id):
            return "Frame \(id.uuidString) is not connected to the retained root frame."
        }
    }
}
