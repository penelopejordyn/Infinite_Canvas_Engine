import LabyrinthCanvas
import SwiftUI

struct ContentView: View {
    @StateObject private var canvas = LabyrinthCanvasModel()

    @State private var mode: LabyrinthInputMode = .draw
    @State private var strokeWidth: Double = 7
    @State private var strokeWidthMode: LabyrinthStrokeWidthMode = .fixedScreenSize
    @State private var drawingInputPolicy: LabyrinthDrawingInputPolicy = .fingerAndStylus
    @State private var savedDocument: Data?

    var body: some View {
        ZStack(alignment: .top) {
            LabyrinthCanvasView(model: canvas)
                .ignoresSafeArea()

            controlPanel
                .padding(.horizontal, 12)
                .padding(.top, 12)
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
}
