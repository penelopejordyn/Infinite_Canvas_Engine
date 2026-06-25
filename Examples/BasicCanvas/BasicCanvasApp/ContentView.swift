import LabyrinthCanvas
import Foundation
import SwiftUI

struct ContentView: View {
    @StateObject private var canvas = LabyrinthCanvasModel()

    @State private var mode: LabyrinthInputMode = .draw
    @State private var strokeWidth: Double = 7
    @State private var strokeWidthMode: LabyrinthStrokeWidthMode = .fixedScreenSize
    @State private var drawingInputPolicy: LabyrinthDrawingInputPolicy = .fingerAndStylus
    @State private var savedDocument: Data?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                LabyrinthCanvasView(model: canvas)
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    controlPanel
                    Spacer(minLength: 0)
                    debugPanel(snapshot: canvas.cameraSnapshot(viewSize: proxy.size),
                               change: canvas.lastCameraChange)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
        .onAppear(perform: applyControls)
        .onChange(of: mode) { newValue in
            canvas.inputMode = newValue
        }
        .onChange(of: strokeWidth) { _ in
            applyBrushStyle()
        }
        .onChange(of: strokeWidthMode) { newValue in
            canvas.strokeWidthMode = newValue
            applyBrushStyle()
        }
        .onChange(of: drawingInputPolicy) { newValue in
            canvas.drawingInputPolicy = newValue
        }
    }

    private var controlPanel: some View {
        VStack(spacing: 12) {
            Picker("Mode", selection: $mode) {
                Text("Draw").tag(LabyrinthInputMode.draw)
                Text("Erase").tag(LabyrinthInputMode.erase)
                Text("Move").tag(LabyrinthInputMode.manipulate)
                Text("Nav").tag(LabyrinthInputMode.navigate)
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Width")
                Slider(value: $strokeWidth, in: 2...36)
                Text("\(Int(strokeWidth))")
                    .monospacedDigit()
                    .frame(width: 32, alignment: .trailing)
            }

            Picker("Stroke Size", selection: $strokeWidthMode) {
                Text("Fixed").tag(LabyrinthStrokeWidthMode.fixedScreenSize)
                Text("Scales").tag(LabyrinthStrokeWidthMode.scalesWithZoom)
            }
            .pickerStyle(.segmented)

            Picker("Input", selection: $drawingInputPolicy) {
                Text("Finger + Pencil").tag(LabyrinthDrawingInputPolicy.fingerAndStylus)
                Text("Pencil Only").tag(LabyrinthDrawingInputPolicy.stylusOnly)
            }
            .pickerStyle(.segmented)

            HStack {
                Button("Save") {
                    savedDocument = try? canvas.exportJSON(prettyPrinted: false)
                }

                Button("Load") {
                    guard let savedDocument,
                          let restored = try? LabyrinthCanvasModel(jsonData: savedDocument) else {
                        return
                    }
                    canvas.replace(with: restored.snapshot())
                    applyControls()
                }
                .disabled(savedDocument == nil)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func debugPanel(snapshot: LabyrinthCanvasCameraSnapshot,
                            change: LabyrinthCanvasCameraChange?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Frame d\(snapshot.activeFrameDepth) path \(formattedPath(snapshot.activeFramePath))")
            Text("Zoom \(formatted(snapshot.cameraZoom)) pan offset \(formatted(snapshot.cameraPan))")
            Text("Center root \(formattedOptional(snapshot.cameraCenterInRootFrame))")
            Text("Center local \(formatted(snapshot.cameraCenterInActiveFrame))")

            if let change {
                Text("\(change.kind.rawValue) transition \(change.didTransition ? "yes" : "no")")
                Text("Root before \(formattedOptional(change.before.cameraCenterInRootFrame)) after \(formattedOptional(change.after.cameraCenterInRootFrame))")
                Text("Local before \(formatted(change.before.cameraCenterInActiveFrame)) after \(formatted(change.after.cameraCenterInActiveFrame))")
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.primary)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func applyControls() {
        canvas.inputMode = mode
        canvas.drawingInputPolicy = drawingInputPolicy
        applyBrushStyle()
    }

    private func applyBrushStyle() {
        canvas.brushStyle = LabyrinthBrushStyle(
            width: strokeWidth,
            color: .ink,
            strokeWidthMode: strokeWidthMode
        )
    }

    private func formattedPath(_ path: [LabyrinthGridIndex]?) -> String {
        guard let path else { return "nil" }
        guard !path.isEmpty else { return "root" }
        return path.map { "\($0.col),\($0.row)" }.joined(separator: "/")
    }

    private func formatted(_ point: LabyrinthPoint) -> String {
        "(\(formatted(point.x)), \(formatted(point.y)))"
    }

    private func formattedOptional(_ point: LabyrinthPoint?) -> String {
        guard let point else { return "nil" }
        return formatted(point)
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
