# Brushes

Brushes convert pointer samples into canvas objects. The built-in `LabyrinthInkBrush` creates `labyrinth.stroke` objects rendered by the package Metal renderer.

## Register a Brush

```swift
struct HighlighterBrush: LabyrinthBrush {
    let id = "com.example.highlighter"

    func makeObject(from draft: LabyrinthStrokeDraft,
                    context: LabyrinthBrushContext) throws -> LabyrinthCanvasObject {
        let payload = LabyrinthStrokePayload(
            brushID: id,
            worldWidth: draft.worldWidth * 2.5,
            color: LabyrinthColor(red: 1.0, green: 0.88, blue: 0.2, alpha: 0.35),
            creationZoom: draft.creationZoom,
            samples: draft.localSamples
        )

        return try LabyrinthCanvasObject(
            transform: LabyrinthObjectTransform(position: LabyrinthPoint(draft.originInFrame)),
            zIndex: context.zIndex,
            payload: payload
        )
    }
}

canvas.brushes.register(HighlighterBrush())
canvas.brushStyle = LabyrinthBrushStyle(
    brushID: "com.example.highlighter",
    width: 10,
    color: LabyrinthColor(red: 1.0, green: 0.88, blue: 0.2, alpha: 0.35),
    strokeWidthMode: .fixedScreenSize
)
```

Use `.fixedScreenSize` when the brush should stay the same visual size while zooming. Use `.scalesWithZoom` when the mark should behave like authored canvas content.

## Returning Custom Objects

A brush can return any `LabyrinthCanvasObject`, not only strokes. For example, a shape brush can sample a drag gesture and create a rectangle object with a custom payload.

Register the matching object type in `canvas.objects` so the object can hit-test, manipulate, and render.
