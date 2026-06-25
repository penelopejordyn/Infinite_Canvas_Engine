# Getting Started

## Basic Editor

```swift
import LabyrinthCanvas
import SwiftUI

struct EditorScreen: View {
    @StateObject private var canvas = LabyrinthCanvasModel()

    var body: some View {
        LabyrinthCanvasView(model: canvas)
            .ignoresSafeArea()
    }
}
```

`LabyrinthCanvasView` is the whole canvas surface. It does not add any toolbar, menu, or inspector. Build those in your app and mutate `LabyrinthCanvasModel`.

## Tools

```swift
canvas.inputMode = .draw
canvas.inputMode = .erase
canvas.inputMode = .navigate
canvas.inputMode = .manipulate
```

- `draw`: creates strokes using the current `brushStyle`.
- `erase`: removes whole strokes touched by the eraser.
- `navigate`: one-finger pan plus pinch zoom and rotation.
- `manipulate`: drag objects to move them, pinch objects to scale them.

In draw and erase modes, navigation remains available with two-finger pan, pinch, and rotation.

## Brush Settings

```swift
canvas.brushStyle = LabyrinthBrushStyle(
    brushID: LabyrinthInkBrush.id,
    width: 8,
    color: LabyrinthColor(red: 0.05, green: 0.05, blue: 0.05),
    constantScreenSize: true
)
```

`constantScreenSize` keeps stroke width stable on screen as the user zooms. Set it to `false` when the stroke should scale with canvas content.

Or use the package-level mode:

```swift
canvas.strokeWidthMode = .fixedScreenSize
canvas.strokeWidthMode = .scalesWithZoom
```

## Options

```swift
canvas.drawingInputPolicy = .fingerAndStylus
canvas.drawingInputPolicy = .stylusOnly
canvas.options.eraserRadius = 24
canvas.options.backgroundColor = .paper
canvas.options.supportsRotation = true
```

`fingerAndStylus` uses one-finger draw/erase and two-finger pan. `stylusOnly` uses Apple Pencil/stylus for draw/erase and frees one-finger touches for panning.

These are canvas behavior settings only. They do not create UI.
