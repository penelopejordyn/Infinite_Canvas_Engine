import CoreGraphics
import XCTest
@testable import LabyrinthCanvas

final class LabyrinthCanvasModelTests: XCTestCase {
    func testStrokeCanRoundTripThroughJSON() throws {
        let model = LabyrinthCanvasModel()
        let viewSize = CGSize(width: 300, height: 300)

        try model.commitStroke(
            screenSamples: [
                LabyrinthStrokeInputSample(point: CGPoint(x: 150, y: 150), pressure: 0.4),
                LabyrinthStrokeInputSample(point: CGPoint(x: 180, y: 160), pressure: 0.7),
                LabyrinthStrokeInputSample(point: CGPoint(x: 210, y: 175), pressure: 1.0)
            ],
            viewSize: viewSize
        )

        let data = try model.exportJSON()
        let restored = try LabyrinthCanvasModel(jsonData: data)

        XCTAssertEqual(restored.allFrames().flatMap(\.objects).count, 1)
        let object = try XCTUnwrap(restored.allFrames().flatMap(\.objects).first)
        XCTAssertEqual(object.typeID, LabyrinthStrokePayload.typeID)
        let payload = try object.decodedPayload(as: LabyrinthStrokePayload.self)
        XCTAssertEqual(payload.samples.count, 3)
        XCTAssertEqual(payload.segments.count, 2)
        XCTAssertEqual(payload.brushID, LabyrinthInkBrush.id)
        XCTAssertGreaterThan(payload.cullingRadiusWorld, 0)
        XCTAssertNotEqual(payload.localBounds, .null)
    }

    func testStrokeEraserRemovesHitStroke() throws {
        let model = LabyrinthCanvasModel()
        let viewSize = CGSize(width: 300, height: 300)

        try model.commitStroke(
            screenSamples: [
                LabyrinthStrokeInputSample(point: CGPoint(x: 150, y: 150)),
                LabyrinthStrokeInputSample(point: CGPoint(x: 210, y: 150))
            ],
            viewSize: viewSize
        )

        XCTAssertEqual(model.activeFrame.objects.count, 1)
        XCTAssertTrue(model.eraseStroke(at: CGPoint(x: 180, y: 150), viewSize: viewSize, radiusPx: 20))
        XCTAssertEqual(model.activeFrame.objects.count, 0)
    }

    func testLegacyStrokePayloadBuildsRenderSegmentsOnDecode() throws {
        let legacy = """
        {
          "brushID": "labyrinth.ink",
          "worldWidth": 4,
          "color": { "red": 0.1, "green": 0.2, "blue": 0.3, "alpha": 1.0 },
          "creationZoom": 1,
          "samples": [
            { "x": 0, "y": 0 },
            { "x": 10, "y": 0, "pressure": 0.5 },
            { "x": 20, "y": 5, "pressure": 1.0 }
          ]
        }
        """.data(using: .utf8)!

        let payload = try LabyrinthJSONCodec.decoder().decode(LabyrinthStrokePayload.self, from: legacy)

        XCTAssertEqual(payload.samples.count, 3)
        XCTAssertEqual(payload.segments.count, 2)
        XCTAssertEqual(payload.segments[0].pressure0Storage, LabyrinthStrokePressureCurve.disabledStorageValue)
        XCTAssertEqual(payload.segments[0].pressure1, 0.5)
        XCTAssertGreaterThan(payload.cullingRadiusWorld, 0)
        XCTAssertTrue(payload.depthWriteEnabled)
    }

    func testZoomCreatesChildFrameAndRestoresActivePath() throws {
        let model = LabyrinthCanvasModel()
        let viewSize = CGSize(width: 400, height: 400)

        model.zoom(by: 6, anchorScreen: CGPoint(x: 200, y: 200), viewSize: viewSize)

        XCTAssertEqual(model.activeFrame.depthFromRoot, 1)
        XCTAssertEqual(model.camera.zoom, 1.2, accuracy: 0.0001)
        XCTAssertEqual(model.framePathFromRoot(to: model.activeFrame)?.count, 1)

        let restored = try LabyrinthCanvasModel(jsonData: model.exportJSON())
        XCTAssertEqual(restored.activeFrame.depthFromRoot, 1)
        XCTAssertEqual(restored.framePathFromRoot(to: restored.activeFrame)?.count, 1)
    }

    func testLockedZoomKeepsAnchorUnderLiveCentroid() {
        let model = LabyrinthCanvasModel()
        let viewSize = CGSize(width: 400, height: 400)
        let anchorScreen = CGPoint(x: 120, y: 160)
        let targetScreen = CGPoint(x: 155, y: 190)
        let anchorWorld = LabyrinthCanvasMath.screenToWorld(anchorScreen, viewSize: viewSize, camera: model.camera)

        let result = model.zoom(by: 1.5,
                                lockedAnchorWorld: anchorWorld,
                                anchorScreen: anchorScreen,
                                targetScreen: targetScreen,
                                viewSize: viewSize)

        XCTAssertFalse(result.didTransition)
        XCTAssertEqual(result.anchorWorld.x, anchorWorld.x, accuracy: 0.0001)
        XCTAssertEqual(result.anchorWorld.y, anchorWorld.y, accuracy: 0.0001)

        let screenAfterZoom = LabyrinthCanvasMath.worldToScreen(result.anchorWorld,
                                                                viewSize: viewSize,
                                                                camera: model.camera)
        XCTAssertEqual(screenAfterZoom.x, targetScreen.x, accuracy: 0.0001)
        XCTAssertEqual(screenAfterZoom.y, targetScreen.y, accuracy: 0.0001)
    }

    func testLockedZoomRefreshesAnchorAfterDepthTransition() throws {
        let model = LabyrinthCanvasModel()
        let viewSize = CGSize(width: 400, height: 400)
        let anchorScreen = CGPoint(x: 200, y: 200)
        let anchorWorld = LabyrinthCanvasMath.screenToWorld(anchorScreen, viewSize: viewSize, camera: model.camera)

        let result = model.zoom(by: 6,
                                lockedAnchorWorld: anchorWorld,
                                anchorScreen: anchorScreen,
                                targetScreen: anchorScreen,
                                viewSize: viewSize)

        XCTAssertTrue(result.didTransition)
        XCTAssertEqual(model.activeFrame.depthFromRoot, 1)
        let event = try XCTUnwrap(model.lastCameraChange)
        let inspectedPoint = try XCTUnwrap(event.after.inspectedPointInActiveFrame)
        XCTAssertEqual(event.kind, .zoom)
        XCTAssertEqual(event.didTransition, true)
        XCTAssertEqual(event.after.activeFrameDepth, 1)
        XCTAssertEqual(event.after.activeFramePath?.count, 1)
        XCTAssertEqual(inspectedPoint.x, 0, accuracy: 0.0001)
        XCTAssertEqual(inspectedPoint.y, 0, accuracy: 0.0001)
        let centerRoot = try XCTUnwrap(event.after.cameraCenterInRootFrame)
        XCTAssertEqual(centerRoot.x, 0, accuracy: 0.0001)
        XCTAssertEqual(centerRoot.y, 0, accuracy: 0.0001)

        let screenAfterTransition = LabyrinthCanvasMath.worldToScreen(result.anchorWorld,
                                                                      viewSize: viewSize,
                                                                      camera: model.camera)
        XCTAssertEqual(screenAfterTransition.x, anchorScreen.x, accuracy: 0.0001)
        XCTAssertEqual(screenAfterTransition.y, anchorScreen.y, accuracy: 0.0001)
    }

    func testRootCameraCenterMatchesContinuousZoomAcrossDepthTransition() throws {
        let model = LabyrinthCanvasModel()
        let viewSize = CGSize(width: 400, height: 400)
        let anchorScreen = CGPoint(x: 250, y: 200)

        model.zoom(by: 6, anchorScreen: anchorScreen, viewSize: viewSize)

        let event = try XCTUnwrap(model.lastCameraChange)
        let centerRoot = try XCTUnwrap(event.after.cameraCenterInRootFrame)

        XCTAssertEqual(model.activeFrame.depthFromRoot, 1)
        XCTAssertEqual(centerRoot.x, 50 - (50 / 6), accuracy: 0.0001)
        XCTAssertEqual(centerRoot.y, 0, accuracy: 0.0001)
    }

    func testZoomInitialWrapCountsAsCameraTransition() throws {
        let model = LabyrinthCanvasModel()
        let viewSize = CGSize(width: 400, height: 400)
        let center = CGPoint(x: 200, y: 200)

        model.camera.pan = LabyrinthPoint(x: -700, y: 0)
        let originalFrame = model.activeFrame

        model.zoom(by: 1.1, anchorScreen: center, viewSize: viewSize)

        XCTAssertFalse(model.activeFrame === originalFrame)
        let event = try XCTUnwrap(model.lastCameraChange)
        let beforePoint = try XCTUnwrap(event.before.inspectedPointInActiveFrame)
        let afterPoint = try XCTUnwrap(event.after.inspectedPointInActiveFrame)
        let afterRootPoint = try XCTUnwrap(event.after.inspectedPointInRootFrame)
        XCTAssertEqual(event.kind, .zoom)
        XCTAssertEqual(event.didTransition, true)
        XCTAssertEqual(event.after.activeFramePath, [LabyrinthGridIndex(col: 3, row: 2)])
        XCTAssertEqual(beforePoint.x, 700, accuracy: 0.0001)
        XCTAssertEqual(afterPoint.x, -324, accuracy: 0.0001)
        XCTAssertEqual(afterRootPoint.x, 140, accuracy: 0.0001)
    }

    func testPanWrapsToSameDepthNeighbor() {
        let model = LabyrinthCanvasModel()
        let viewSize = CGSize(width: 400, height: 400)
        let original = model.activeFrame

        model.pan(by: CGPoint(x: -700, y: 0), viewSize: viewSize)

        XCTAssertFalse(model.activeFrame === original)
        XCTAssertEqual(model.activeFrame.depthFromRoot, original.depthFromRoot)
        XCTAssertEqual(model.camera.pan.x, 324, accuracy: 0.0001)
        XCTAssertEqual(model.lastCameraChange?.kind, .pan)
        XCTAssertEqual(model.lastCameraChange?.didTransition, true)
        XCTAssertEqual(model.lastCameraChange?.after.activeFramePath, model.framePathFromRoot(to: model.activeFrame))
    }

    func testStrokeWidthModeUpdatesBrushStyle() {
        let model = LabyrinthCanvasModel()
        model.camera.zoom = 3

        XCTAssertEqual(model.strokeWidthMode, .fixedScreenSize)

        model.strokeWidthMode = .scalesWithZoom

        XCTAssertEqual(model.strokeWidthMode, .scalesWithZoom)
        XCTAssertFalse(model.brushStyle.constantScreenSize)
        XCTAssertEqual(model.brushStyle.scaleWithZoomBaseEffectiveZoom, 3, accuracy: 0.0001)

        model.strokeWidthMode = .fixedScreenSize

        XCTAssertEqual(model.strokeWidthMode, .fixedScreenSize)
        XCTAssertTrue(model.brushStyle.constantScreenSize)
    }

    func testScaleWithZoomStrokeWidthSurvivesDepthTransition() throws {
        let model = LabyrinthCanvasModel()
        let viewSize = CGSize(width: 400, height: 400)
        let center = CGPoint(x: 200, y: 200)

        model.camera.zoom = 2
        model.brushStyle = LabyrinthBrushStyle(width: 10, color: .ink)
        model.strokeWidthMode = .scalesWithZoom

        let parentFrame = model.activeFrame
        try model.commitStroke(
            screenSamples: [
                LabyrinthStrokeInputSample(point: center),
                LabyrinthStrokeInputSample(point: CGPoint(x: 220, y: 200))
            ],
            viewSize: viewSize
        )
        let parentObject = try XCTUnwrap(parentFrame.objects.first)
        let parentStroke = try parentObject.decodedPayload(as: LabyrinthStrokePayload.self)
        XCTAssertEqual(parentStroke.worldWidth, 5, accuracy: 0.0001)

        model.zoom(by: 2.5, anchorScreen: center, viewSize: viewSize)

        XCTAssertEqual(model.activeFrame.depthFromRoot, 1)
        XCTAssertEqual(model.camera.zoom, 1, accuracy: 0.0001)
        XCTAssertEqual(model.brushStyle.scaleWithZoomBaseEffectiveZoom, 0.4, accuracy: 0.0001)

        try model.commitStroke(
            screenSamples: [
                LabyrinthStrokeInputSample(point: center),
                LabyrinthStrokeInputSample(point: CGPoint(x: 220, y: 200))
            ],
            viewSize: viewSize
        )
        let childObject = try XCTUnwrap(model.activeFrame.objects.first)
        let childStroke = try childObject.decodedPayload(as: LabyrinthStrokePayload.self)
        let parentToActive = try XCTUnwrap(model.transformFromActive(to: parentFrame))

        XCTAssertEqual(childStroke.worldWidth, 25, accuracy: 0.0001)
        XCTAssertEqual(parentStroke.worldWidth / parentToActive.scale, childStroke.worldWidth, accuracy: 0.0001)
    }

    func testDrawingInputPolicyKeepsLegacyBooleanInSync() {
        let model = LabyrinthCanvasModel()

        XCTAssertEqual(model.drawingInputPolicy, .fingerAndStylus)
        XCTAssertTrue(model.allowsFingerDrawing)

        model.drawingInputPolicy = .stylusOnly

        XCTAssertEqual(model.drawingInputPolicy, .stylusOnly)
        XCTAssertFalse(model.allowsFingerDrawing)

        model.allowsFingerDrawing = true

        XCTAssertEqual(model.drawingInputPolicy, .fingerAndStylus)
        XCTAssertTrue(model.allowsFingerDrawing)
    }
}
