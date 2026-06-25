# BasicCanvas Example

This is a small SwiftUI example app that uses `LabyrinthCanvasView` directly and builds its own controls around `LabyrinthCanvasModel`.

## Run It

1. Open `BasicCanvas.xcodeproj` in Xcode.
2. Select the `BasicCanvas` scheme.
3. Choose an iPhone/iPad simulator, an attached iOS device, or `My Mac (Mac Catalyst)`.
4. Press Run.

For a physical iPhone or iPad, select your Apple development team in the target's Signing & Capabilities settings if Xcode asks for one. The Mac Catalyst destination is configured for local ad-hoc signing.

## What It Demonstrates

- Draw, erase, navigate, and manipulate modes.
- Fixed screen-size strokes vs strokes that scale with zoom.
- Finger + stylus drawing vs stylus-only drawing.
- The gesture difference between those input policies:
  - Finger + stylus: one-finger draw/erase, two-finger pan.
  - Stylus only: Apple Pencil/stylus draws, one-finger pans.
- JSON save/load using `exportJSON()` and `LabyrinthCanvasModel(jsonData:)`.
