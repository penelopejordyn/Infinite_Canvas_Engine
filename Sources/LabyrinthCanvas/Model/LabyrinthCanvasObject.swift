import Foundation
import simd

public protocol LabyrinthObjectPayload: Codable, Sendable {
    static var typeID: String { get }
}

public struct LabyrinthCanvasObject: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var typeID: String
    public var transform: LabyrinthObjectTransform
    public var zIndex: UInt32
    public var payload: LabyrinthJSONValue

    public init(id: UUID = UUID(),
                typeID: String,
                transform: LabyrinthObjectTransform = LabyrinthObjectTransform(),
                zIndex: UInt32 = 0,
                payload: LabyrinthJSONValue = .object([:])) {
        self.id = id
        self.typeID = typeID
        self.transform = transform
        self.zIndex = zIndex
        self.payload = payload
    }

    public init<T: LabyrinthObjectPayload>(id: UUID = UUID(),
                                           transform: LabyrinthObjectTransform = LabyrinthObjectTransform(),
                                           zIndex: UInt32 = 0,
                                           payload: T) throws {
        self.id = id
        self.typeID = T.typeID
        self.transform = transform
        self.zIndex = zIndex
        self.payload = try LabyrinthJSONValue.encodePayload(payload)
    }

    public func decodedPayload<T: LabyrinthObjectPayload>(as type: T.Type = T.self) throws -> T {
        guard typeID == T.typeID else {
            throw LabyrinthCanvasError.invalidPayload("Object has type '\(typeID)' but requested '\(T.typeID)'.")
        }
        return try payload.decodePayload(as: T.self)
    }
}

public struct LabyrinthObjectType {
    public var typeID: String
    public var usesDefaultTransformGestures: Bool
    public var hitTest: (LabyrinthCanvasObject, SIMD2<Double>) -> Bool
    public var makeGestureHandler: (() -> LabyrinthObjectGestureHandler?)?
    public var makeRenderer: (() -> LabyrinthObjectRenderer?)?

    public init(typeID: String,
                usesDefaultTransformGestures: Bool = true,
                hitTest: @escaping (LabyrinthCanvasObject, SIMD2<Double>) -> Bool = { object, point in
                    object.transform.contains(pointInFrame: point, padding: 8)
                },
                makeGestureHandler: (() -> LabyrinthObjectGestureHandler?)? = nil,
                makeRenderer: (() -> LabyrinthObjectRenderer?)? = nil) {
        self.typeID = typeID
        self.usesDefaultTransformGestures = usesDefaultTransformGestures
        self.hitTest = hitTest
        self.makeGestureHandler = makeGestureHandler
        self.makeRenderer = makeRenderer
    }
}

public final class LabyrinthObjectRegistry {
    private var types: [String: LabyrinthObjectType] = [:]

    public init() {
        register(.stroke)
    }

    public func register(_ type: LabyrinthObjectType) {
        types[type.typeID] = type
    }

    public func type(for typeID: String) -> LabyrinthObjectType? {
        types[typeID]
    }

    public var registeredTypeIDs: [String] {
        types.keys.sorted()
    }
}

extension LabyrinthObjectType {
    public static let stroke = LabyrinthObjectType(
        typeID: LabyrinthStrokePayload.typeID,
        usesDefaultTransformGestures: true,
        hitTest: { object, point in
            guard let stroke = try? object.decodedPayload(as: LabyrinthStrokePayload.self) else {
                return false
            }
            return stroke.hitTest(pointInFrame: point,
                                  origin: object.transform.positionSIMD,
                                  eraserRadius: max(stroke.worldWidth, 1))
        }
    )
}
