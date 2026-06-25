# Saving and Loading

The package persists a complete canvas as JSON. You decide whether to store that JSON in files, Core Data, CloudKit, a backend, or document storage.

## Export

```swift
let data = try canvas.exportJSON()
```

Use compact JSON when sending over a network:

```swift
let data = try canvas.exportJSON(prettyPrinted: false)
```

## Import

```swift
let canvas = try LabyrinthCanvasModel(jsonData: data)
```

Or replace an existing model:

```swift
let snapshot = try LabyrinthJSONCodec.decoder()
    .decode(LabyrinthDocumentSnapshot.self, from: data)

canvas.replace(with: snapshot)
```

## JSON Shape

Top-level fields:

- `schema`: currently `org.labyrinth.canvas`.
- `version`: package document version.
- `createdAt`, `updatedAt`: ISO-8601 dates.
- `fractal`: grid size, scale, and frame extent.
- `rootFrame`: recursive frame tree.
- `activeFramePath`: active frame path from the root.
- `camera`: pan, zoom, and rotation.

Each frame stores:

- `id`
- `depthFromRoot`
- `indexInParent`
- `objects`
- `children`

Each object stores:

- `id`
- `typeID`
- `transform`
- `zIndex`
- `payload`

The payload is open JSON. Built-in strokes use `typeID == "labyrinth.stroke"` and decode as `LabyrinthStrokePayload`.
