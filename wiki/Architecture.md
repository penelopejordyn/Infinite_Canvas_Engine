# Architecture

LabyrinthCanvas uses a sparse recursive frame tree instead of one giant world coordinate system.

## Frames

A `LabyrinthFrame` is a bounded local coordinate system. It owns objects and child frames. Child frames live in a 5x5 grid:

- Grid indices are `0...4` for both axes.
- The center tile is `(2, 2)`.
- The scale step is `5.0`.
- The default frame extent is `1024 x 1024` world units.

When the user pans past a frame edge, the active frame moves to a same-depth neighbor. When the user zooms past the scale threshold, the active frame moves into the relevant child tile. When the user zooms out below `1.0`, the active frame moves to its parent.

## Local Coordinates

Objects are stored in frame-local coordinates. A stroke stores:

- object transform position: stroke origin in the frame
- payload samples: Float offsets from that origin
- payload segment instances: render-ready SDF centerline segments
- payload width: width in that frame's world units
- payload bounds and culling radius: fast visibility rejection before encoding draw instances

This keeps authored geometry numerically small even after deep recursive navigation.

## Object Model

`LabyrinthCanvasObject` is the only document-level item type:

```text
object
  id
  typeID
  transform
  zIndex
  payload JSON
```

The package knows how to render and erase `labyrinth.stroke`. Your app can register more types.

## Public Boundary

The package intentionally stops at the engine boundary. It owns:

- document graph
- camera
- gestures
- Metal stroke rendering
- JSON encoding
- extension protocols

Your app owns:

- toolbars and controls
- file locations
- object-specific UI
- collaboration
- account state
- non-stroke business logic
