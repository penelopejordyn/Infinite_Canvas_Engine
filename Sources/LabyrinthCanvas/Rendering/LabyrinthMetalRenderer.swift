#if canImport(MetalKit)
import CoreGraphics
import Foundation
import Metal
import MetalKit
import simd

private struct LabyrinthMetalQuadVertex {
    var corner: SIMD2<Float>
}

private struct LabyrinthMetalBatchedStrokeTransform {
    var cameraCenterWorld: SIMD2<Float>
    var zoomScale: Float
    var screenWidth: Float
    var screenHeight: Float
    var rotationAngle: Float
    var featherPx: Float
    var depthBias: Float
    var depthScale: Float
}

private struct LabyrinthMetalStrokeInstance {
    var p0World: SIMD2<Float>
    var p1World: SIMD2<Float>
    var color: SIMD4<Float>
    var params: SIMD4<Float>
}

final class LabyrinthMetalRenderer {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let quadVertexBuffer: MTLBuffer
    private var customRenderers: [String: LabyrinthObjectRenderer] = [:]

    init?(device: MTLDevice, colorPixelFormat: MTLPixelFormat) {
        self.device = device
        guard let commandQueue = device.makeCommandQueue() else { return nil }
        self.commandQueue = commandQueue

        do {
            let library: MTLLibrary
            #if SWIFT_PACKAGE
            if let shaderURL = Bundle.module.url(forResource: "Shaders", withExtension: "metal") {
                let shaderSource = try String(contentsOf: shaderURL, encoding: .utf8)
                library = try device.makeLibrary(source: shaderSource, options: nil)
            } else {
                library = try device.makeDefaultLibrary(bundle: .module)
            }
            #else
            guard let defaultLibrary = device.makeDefaultLibrary() else {
                return nil
            }
            library = defaultLibrary
            #endif
            guard let vertex = library.makeFunction(name: "labyrinth_vertex_segment_sdf_batched"),
                  let fragment = library.makeFunction(name: "labyrinth_fragment_segment_sdf_batched") else {
                return nil
            }

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

            let vertexDescriptor = MTLVertexDescriptor()
            vertexDescriptor.attributes[0].format = .float2
            vertexDescriptor.attributes[0].offset = 0
            vertexDescriptor.attributes[0].bufferIndex = 0
            vertexDescriptor.layouts[0].stride = MemoryLayout<LabyrinthMetalQuadVertex>.stride
            descriptor.vertexDescriptor = vertexDescriptor

            self.pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            return nil
        }

        let vertices = [
            LabyrinthMetalQuadVertex(corner: SIMD2<Float>(0, 0)),
            LabyrinthMetalQuadVertex(corner: SIMD2<Float>(1, 0)),
            LabyrinthMetalQuadVertex(corner: SIMD2<Float>(0, 1)),
            LabyrinthMetalQuadVertex(corner: SIMD2<Float>(1, 0)),
            LabyrinthMetalQuadVertex(corner: SIMD2<Float>(1, 1)),
            LabyrinthMetalQuadVertex(corner: SIMD2<Float>(0, 1))
        ]

        guard let buffer = device.makeBuffer(bytes: vertices,
                                             length: MemoryLayout<LabyrinthMetalQuadVertex>.stride * vertices.count,
                                             options: .storageModeShared) else {
            return nil
        }
        self.quadVertexBuffer = buffer
    }

    func draw(in view: MTKView, model: LabyrinthCanvasModel) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        let background = model.options.backgroundColor
        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(background.red),
            green: Double(background.green),
            blue: Double(background.blue),
            alpha: Double(background.alpha)
        )
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }

        let viewSize = CGSize(width: max(view.bounds.width, 1), height: max(view.bounds.height, 1))
        drawStrokes(model: model, viewSize: viewSize, encoder: encoder)
        drawCustomObjects(model: model,
                          viewSize: viewSize,
                          commandBuffer: commandBuffer,
                          encoder: encoder)

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func drawStrokes(model: LabyrinthCanvasModel,
                             viewSize: CGSize,
                             encoder: MTLRenderCommandEncoder) {
        let instances = makeStrokeInstances(model: model)
        guard !instances.isEmpty else { return }

        guard let instanceBuffer = device.makeBuffer(bytes: instances,
                                                     length: MemoryLayout<LabyrinthMetalStrokeInstance>.stride * instances.count,
                                                     options: .storageModeShared) else {
            return
        }

        let cameraCenter = LabyrinthCanvasMath.screenToWorld(
            CGPoint(x: viewSize.width / 2.0, y: viewSize.height / 2.0),
            viewSize: viewSize,
            camera: model.camera
        )
        var transform = LabyrinthMetalBatchedStrokeTransform(
            cameraCenterWorld: SIMD2<Float>(Float(cameraCenter.x), Float(cameraCenter.y)),
            zoomScale: Float(model.camera.zoom),
            screenWidth: Float(max(viewSize.width, 1)),
            screenHeight: Float(max(viewSize.height, 1)),
            rotationAngle: model.camera.rotation,
            featherPx: 1,
            depthBias: 0,
            depthScale: 1
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(quadVertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&transform,
                               length: MemoryLayout<LabyrinthMetalBatchedStrokeTransform>.stride,
                               index: 1)
        encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 2)
        encoder.drawPrimitives(type: .triangle,
                               vertexStart: 0,
                               vertexCount: 6,
                               instanceCount: instances.count)
    }

    private func drawCustomObjects(model: LabyrinthCanvasModel,
                                   viewSize: CGSize,
                                   commandBuffer: MTLCommandBuffer,
                                   encoder: MTLRenderCommandEncoder) {
        for frame in model.allFrames() {
            guard let transform = model.transformFromActive(to: frame) else { continue }
            for object in frame.objects where object.typeID != LabyrinthStrokePayload.typeID {
                guard let renderer = renderer(for: object.typeID, registry: model.objects) else { continue }
                let context = LabyrinthObjectRenderContext(
                    device: device,
                    commandBuffer: commandBuffer,
                    encoder: encoder,
                    viewSize: viewSize,
                    camera: model.camera,
                    transformFromActive: transform
                )
                renderer.draw(object: object, frame: frame, context: context)
            }
        }
    }

    private func renderer(for typeID: String, registry: LabyrinthObjectRegistry) -> LabyrinthObjectRenderer? {
        if let renderer = customRenderers[typeID] {
            return renderer
        }
        guard let renderer = registry.type(for: typeID)?.makeRenderer?() else {
            return nil
        }
        customRenderers[typeID] = renderer
        return renderer
    }

    private func makeStrokeInstances(model: LabyrinthCanvasModel) -> [LabyrinthMetalStrokeInstance] {
        var entries: [(zIndex: UInt32, instance: LabyrinthMetalStrokeInstance)] = []
        let frames = model.allFrames()

        for frame in frames {
            guard let transform = model.transformFromActive(to: frame),
                  transform.scale.isFinite,
                  abs(transform.scale) > 1e-12 else {
                continue
            }

            for object in frame.objects where object.typeID == LabyrinthStrokePayload.typeID {
                guard let stroke = try? object.decodedPayload(as: LabyrinthStrokePayload.self),
                      !stroke.samples.isEmpty else {
                    continue
                }

                let origin = object.transform.positionSIMD
                let activeWidth = max(stroke.worldWidth / transform.scale, 1e-9)

                func activePoint(for sample: LabyrinthStrokeSample) -> SIMD2<Float> {
                    let pointInFrame = origin + SIMD2<Double>(Double(sample.x), Double(sample.y))
                    let pointActive = (pointInFrame - transform.translation) / transform.scale
                    return SIMD2<Float>(Float(pointActive.x), Float(pointActive.y))
                }

                if stroke.samples.count == 1 {
                    let sample = stroke.samples[0]
                    entries.append((
                        object.zIndex,
                        LabyrinthMetalStrokeInstance(
                            p0World: activePoint(for: sample),
                            p1World: activePoint(for: sample),
                            color: stroke.color.simd,
                            params: SIMD4<Float>(Float(activeWidth), 0, sample.pressure ?? -1, sample.pressure ?? -1)
                        )
                    ))
                    continue
                }

                for index in 0..<(stroke.samples.count - 1) {
                    let a = stroke.samples[index]
                    let b = stroke.samples[index + 1]
                    entries.append((
                        object.zIndex,
                        LabyrinthMetalStrokeInstance(
                            p0World: activePoint(for: a),
                            p1World: activePoint(for: b),
                            color: stroke.color.simd,
                            params: SIMD4<Float>(Float(activeWidth), 0, a.pressure ?? -1, b.pressure ?? -1)
                        )
                    ))
                }
            }
        }

        entries.sort { lhs, rhs in
            lhs.zIndex < rhs.zIndex
        }
        return entries.map(\.instance)
    }
}
#endif
