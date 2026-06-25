# LabyrinthCanvas

LabyrinthCanvas is the open-source core of Labyrinth's recursive Metal drawing engine. It is a Swift package for building infinite, fractal canvases with strokes, movement gestures, stroke erasing, JSON persistence, and extension points for custom brushes and canvas objects.

The package deliberately does not ship app UI. There are no menus, inspectors, libraries, cards UI, collaboration screens, or toolbar controls. You provide those in your app and drive the canvas through `LabyrinthCanvasModel`.

## Included

- `LabyrinthCanvasView`: a drop-in SwiftUI view backed by `MTKView`.
- `LabyrinthCanvasModel`: document state, camera state, tools, JSON save/load, recursive frame navigation, object mutation.
- Built-in ink strokes rendered through Labyrinth-style Metal SDF segment instancing, with stored segment metadata, pressure interpolation, bounds-based culling, and FXAA post-processing.
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
.package(name: "LabyrinthCanvas", url: "https://github.com/penelopejordyn/Infinite_Canvas_Engine.git", branch: "main")
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

See `Examples/BasicCanvas` for a small SwiftUI example app with controls for tools, stroke size behavior, finger/stylus input, and JSON save/load.

Inspect camera/frame coordinates while debugging gestures:

```swift
let snapshot = canvas.cameraSnapshot(viewSize: viewSize)
print(snapshot.activeFramePath as Any, snapshot.cameraCenterInActiveFrame)
print(canvas.lastCameraChange as Any)
```

`cameraSnapshot` reports the active frame path and active-frame local coordinates. `lastCameraChange` stores the before/after frame path, local coordinates, pan, zoom, and transition flag from the most recent pan, zoom, or rotation.
Use the frame path with the coordinate readout: active-local coordinates are expected to change when the active depth changes, while retained-root coordinates help inspect continuity across ordinary child/parent depth changes.

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

## Stroke Width Mode

Labyrinth exposes the same behavior as the app's fixed-size toggle:

```swift
canvas.strokeWidthMode = .fixedScreenSize // width stays fixed on screen
canvas.strokeWidthMode = .scalesWithZoom  // width scales with canvas content
```

When you switch from fixed to scaled width, the package captures the current effective zoom and keeps that scale stable as recursive frame depth changes.

You can also set it when creating a brush style:

```swift
canvas.brushStyle = LabyrinthBrushStyle(
    width: 8,
    color: .ink,
    strokeWidthMode: .fixedScreenSize
)
```

## Finger vs Stylus Input

Set the input policy from your own UI:

```swift
canvas.drawingInputPolicy = .fingerAndStylus
canvas.drawingInputPolicy = .stylusOnly
```

The gesture policy changes with the input mode:

- `fingerAndStylus`: one-finger draw/erase, two-finger pan.
- `stylusOnly`: Apple Pencil/stylus draws, one-finger pan is available.

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
