# LabyrinthCanvas

LabyrinthCanvas is the open-source core of Labyrinth's recursive Metal drawing engine. It is a Swift package for building infinite, fractal canvases with strokes, movement gestures, stroke erasing, JSON persistence, and extension points for custom brushes and canvas objects.

The package deliberately does not ship app UI. There are no menus, inspectors, libraries, cards UI, collaboration screens, or toolbar controls. You provide those in your app and drive the canvas through `LabyrinthCanvasModel`.

## Included

- `LabyrinthCanvasView`: a drop-in SwiftUI view backed by `MTKView`.
- `LabyrinthCanvasModel`: document state, camera state, tools, JSON save/load, recursive frame navigation, object mutation.
- Built-in ink strokes rendered through Metal SDF segment instancing.
- Movement gestures: pan, pinch zoom, and rotation.
- Stroke erase mode.
- A sparse recursive 5x5 frame graph so authored coordinates stay local at deep zoom.
- Custom brush registration.
- Custom object payload registration, hit testing, default move/scale gestures, custom gesture handlers, and custom Metal renderers.

## Not Included

- Labyrinth app chrome or menus.
- Cards, text editors, PDF/image/YouTube cards, sections, lasso, layers, links, OCR, realtime collaboration, Supabase, or archive packaging.
- Opinionated persistence storage. The package gives you JSON data; your app decides where to store it.

## Install

Add this directory as a Swift package dependency:

```swift
.package(url: "https://github.com/your-org/LabyrinthCanvas.git", branch: "main")
```

Then add the product:

```swift
.product(name: "LabyrinthCanvas", package: "LabyrinthCanvas")
```

## Quick Start

```swift
import LabyrinthCanvas
import SwiftUI

struct EditorScreen: View {
    @StateObject private var canvas = LabyrinthCanvasModel()

    var body: some View {
        LabyrinthCanvasView(model: canvas)
            .ignoresSafeArea()
            .onAppear {
                canvas.inputMode = .draw
                canvas.brushStyle = LabyrinthBrushStyle(width: 7, color: .ink)
            }
    }
}
```

Save the canvas:

```swift
let jsonData = try canvas.exportJSON()
```

Load it:

```swift
let canvas = try LabyrinthCanvasModel(jsonData: jsonData)
```

## Tool Modes

Set `canvas.inputMode` from your own UI:

```swift
canvas.inputMode = .draw       // Apple Pencil or finger strokes
canvas.inputMode = .erase      // stroke erase
canvas.inputMode = .navigate   // one-finger pan, pinch, rotation
canvas.inputMode = .manipulate // move/scale objects
```

In draw and erase modes, two-finger pan, pinch, and rotation still navigate the canvas.

## Wiki

The `wiki/` directory has copy-ready pages for a GitHub wiki:

- `Home.md`
- `Getting-Started.md`
- `Saving-and-Loading.md`
- `Brushes.md`
- `Objects-and-Gestures.md`
- `Rendering.md`
- `Architecture.md`

## Verify

```bash
swift test
```
