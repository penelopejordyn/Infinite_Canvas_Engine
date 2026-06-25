# BasicCanvas Example App

This is a small SwiftUI iOS example that uses `LabyrinthCanvasView` directly and builds its own controls around `LabyrinthCanvasModel`.

## Run It

1. Open Xcode.
2. Create a new iOS App project named `BasicCanvas`.
3. Add this package as a dependency:

   ```text
   https://github.com/penelopejordyn/Infinite_Canvas_Engine.git
   ```

4. Link the `LabyrinthCanvas` product to the app target.
5. Replace the generated app files with the files in `BasicCanvasApp/`.

## What It Demonstrates

- Draw, erase, navigate, and manipulate modes.
- Fixed screen-size strokes vs strokes that scale with zoom.
- Finger + stylus drawing vs stylus-only drawing.
- The gesture difference between those input policies:
  - Finger + stylus: one-finger draw/erase, two-finger pan.
  - Stylus only: Apple Pencil/stylus draws, one-finger pans.
- JSON save/load using `exportJSON()` and `LabyrinthCanvasModel(jsonData:)`.
