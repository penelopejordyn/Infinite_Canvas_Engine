# Objects and Gestures

Everything on the canvas is a `LabyrinthCanvasObject`. The built-in stroke is just one object type.

## Define a Payload

```swift
struct StickyNotePayload: LabyrinthObjectPayload {
    static let typeID = "com.example.sticky-note"
    var text: String
    var colorHex: String
}
```

## Register the Object Type

```swift
canvas.objects.register(
    LabyrinthObjectType(
        typeID: StickyNotePayload.typeID,
        usesDefaultTransformGestures: true,
        hitTest: { object, point in
            object.transform.contains(pointInFrame: point, padding: 12)
        }
    )
)
```

With `usesDefaultTransformGestures`, manipulate mode gives the object default behavior:

- Drag to move.
- Pinch to scale.

## Add an Object

```swift
let note = try LabyrinthCanvasObject(
    transform: LabyrinthObjectTransform(
        position: LabyrinthPoint(x: 0, y: 0),
        size: LabyrinthSize(width: 220, height: 140)
    ),
    zIndex: 100,
    payload: StickyNotePayload(text: "Hello", colorHex: "#FFF4A8")
)

canvas.addObject(note)
```

## Custom Gesture Handler

Use a gesture handler when default move/scale behavior is not enough.

```swift
final class StickyNoteGestureHandler: LabyrinthObjectGestureHandler {
    func begin(object: inout LabyrinthCanvasObject, context: LabyrinthGestureContext) {}

    func update(object: inout LabyrinthCanvasObject, context: LabyrinthGestureContext) {
        object.transform.position = LabyrinthPoint(context.pointInFrame)
    }

    func end(object: inout LabyrinthCanvasObject, context: LabyrinthGestureContext) {}
}

canvas.objects.register(
    LabyrinthObjectType(
        typeID: StickyNotePayload.typeID,
        usesDefaultTransformGestures: false,
        makeGestureHandler: { StickyNoteGestureHandler() }
    )
)
```

The handler mutates the object directly and receives the active model, frame, view size, and pointer location in frame coordinates.
