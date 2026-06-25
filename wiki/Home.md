# LabyrinthCanvas Wiki

LabyrinthCanvas is a Swift package for recursive Metal canvases. It provides the engine surface: strokes, movement gestures, stroke erase, JSON persistence, and extension points. It does not provide app UI.

## Pages

- [Getting Started](Getting-Started.md)
- [Saving and Loading](Saving-and-Loading.md)
- [Brushes](Brushes.md)
- [Objects and Gestures](Objects-and-Gestures.md)
- [Rendering](Rendering.md)
- [Architecture](Architecture.md)

## Core Types

- `LabyrinthCanvasView`: the SwiftUI view you place in your app.
- `LabyrinthCanvasModel`: the observable document/controller object.
- `LabyrinthFrame`: one local coordinate system in the recursive 5x5 grid.
- `LabyrinthCanvasObject`: a first-class object on the canvas. A stroke is one object type.
- `LabyrinthStrokePayload`: the built-in stroke payload.
- `LabyrinthBrush`: protocol for adding new brush behavior.
- `LabyrinthObjectType`: registration point for custom object hit testing, gestures, and rendering.
