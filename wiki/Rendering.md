# Rendering

The package renders built-in strokes with Metal. Custom objects can render in two ways:

- Draw your own SwiftUI/UIKit overlays in your app using the model and camera projection helpers.
- Register a Metal renderer for the object type.

## Built-In Stroke Renderer

`LabyrinthStrokePayload` is rendered through the same default stroke approach used by the Labyrinth app: SDF capsule segment instances with pressure interpolation, stored local bounds, culling radius, and minimum visible screen-width culling. Stroke points are stored locally relative to each stroke origin, and the renderer projects them through the active recursive frame transform.

The package shader uses Labyrinth's hard SDF edge discard for built-in strokes. It does not use the package's older smooth alpha edge, which could create halos around overlapping strokes. The renderer then applies the Labyrinth app's FXAA fullscreen post-process before presenting the drawable.

## Custom Metal Renderer

```swift
final class StickyNoteRenderer: LabyrinthObjectRenderer {
    let typeID = StickyNotePayload.typeID

    func draw(object: LabyrinthCanvasObject,
              frame: LabyrinthFrame,
              context: LabyrinthObjectRenderContext) {
        // Use context.encoder with your own pipeline state.
        // context.transformFromActive maps active-frame coordinates into this frame.
    }
}

canvas.objects.register(
    LabyrinthObjectType(
        typeID: StickyNotePayload.typeID,
        makeRenderer: { StickyNoteRenderer() }
    )
)
```

The renderer is called inside the package draw pass after built-in strokes. Keep custom renderers fast and cache pipeline state outside `draw`.

## Coordinate Conversion

Use these helpers when rendering overlays:

```swift
let screen = LabyrinthCanvasMath.worldToScreen(
    pointInActiveFrame,
    viewSize: viewSize,
    camera: canvas.camera
)

let active = LabyrinthCanvasMath.screenToWorld(
    screenPoint,
    viewSize: viewSize,
    camera: canvas.camera
)
```

For an object in a non-active frame:

```swift
let transform = canvas.transformFromActive(to: frame)!
let pointInActive = (pointInFrame - transform.translation) / transform.scale
```
