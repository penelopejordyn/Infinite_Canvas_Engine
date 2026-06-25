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
        XCTAssertEqual(payload.brushID, LabyrinthInkBrush.id)
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

    func testPanWrapsToSameDepthNeighbor() {
        let model = LabyrinthCanvasModel()
        let viewSize = CGSize(width: 400, height: 400)
        let original = model.activeFrame

        model.pan(by: CGPoint(x: -700, y: 0), viewSize: viewSize)

        XCTAssertFalse(model.activeFrame === original)
        XCTAssertEqual(model.activeFrame.depthFromRoot, original.depthFromRoot)
        XCTAssertEqual(model.camera.pan.x, 324, accuracy: 0.0001)
    }

    func testStrokeWidthModeUpdatesBrushStyle() {
        let model = LabyrinthCanvasModel()

        XCTAssertEqual(model.strokeWidthMode, .fixedScreenSize)

        model.strokeWidthMode = .scalesWithZoom

        XCTAssertEqual(model.strokeWidthMode, .scalesWithZoom)
        XCTAssertFalse(model.brushStyle.constantScreenSize)

        model.strokeWidthMode = .fixedScreenSize

        XCTAssertEqual(model.strokeWidthMode, .fixedScreenSize)
        XCTAssertTrue(model.brushStyle.constantScreenSize)
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
