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

private struct LabyrinthHoverPostProcessUniforms {
    var centerRadius: SIMD4<Float>
    var outlineParams: SIMD4<Float>
    var handleLight: SIMD4<Float>
    var handleDark: SIMD4<Float>

    static let zero = LabyrinthHoverPostProcessUniforms(
        centerRadius: .zero,
        outlineParams: .zero,
        handleLight: .zero,
        handleDark: .zero
    )
}

final class LabyrinthMetalRenderer {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let quadVertexBuffer: MTLBuffer
    private var postProcessPipelineState: MTLRenderPipelineState?
    private var samplerState: MTLSamplerState?
    private var offscreenColorTexture: MTLTexture?
    private var offscreenTextureWidth: Int = 0
    private var offscreenTextureHeight: Int = 0
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
            descriptor.colorAttachments[0].rgbBlendOperation = .add
            descriptor.colorAttachments[0].alphaBlendOperation = .add
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

            let vertexDescriptor = MTLVertexDescriptor()
            vertexDescriptor.attributes[0].format = .float2
            vertexDescriptor.attributes[0].offset = 0
            vertexDescriptor.attributes[0].bufferIndex = 0
            vertexDescriptor.layouts[0].stride = MemoryLayout<LabyrinthMetalQuadVertex>.stride
            descriptor.vertexDescriptor = vertexDescriptor

            self.pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)

            if let postVertex = library.makeFunction(name: "labyrinth_vertex_fullscreen_triangle"),
               let postFragment = library.makeFunction(name: "labyrinth_fragment_fxaa") {
                let postDescriptor = MTLRenderPipelineDescriptor()
                postDescriptor.vertexFunction = postVertex
                postDescriptor.fragmentFunction = postFragment
                postDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat
                self.postProcessPipelineState = try device.makeRenderPipelineState(descriptor: postDescriptor)
            }
        } catch {
            return nil
        }

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)

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
        guard let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        let viewSize = CGSize(width: max(view.bounds.width, 1), height: max(view.bounds.height, 1))
        let background = model.options.backgroundColor
        let clearColor = MTLClearColor(red: Double(background.red),
                                       green: Double(background.green),
                                       blue: Double(background.blue),
                                       alpha: Double(background.alpha))

        let drawableDescriptor = view.currentRenderPassDescriptor
        let postPipeline = postProcessPipelineState
        let postSampler = samplerState
        let offscreenTexture = postPipeline == nil ? nil : ensureOffscreenTexture(drawableSize: view.drawableSize)
        let rendersOffscreen = offscreenTexture != nil && postPipeline != nil && postSampler != nil && drawableDescriptor != nil

        let sceneDescriptor: MTLRenderPassDescriptor
        if let offscreenTexture, rendersOffscreen {
            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture = offscreenTexture
            descriptor.colorAttachments[0].clearColor = clearColor
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].storeAction = .store
            sceneDescriptor = descriptor
        } else if let descriptor = drawableDescriptor {
            descriptor.colorAttachments[0].clearColor = clearColor
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].storeAction = .store
            sceneDescriptor = descriptor
        } else {
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: sceneDescriptor) else {
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }

        drawStrokes(model: model, viewSize: viewSize, encoder: encoder)
        drawCustomObjects(model: model,
                          viewSize: viewSize,
                          commandBuffer: commandBuffer,
                          encoder: encoder)

        encoder.endEncoding()

        if rendersOffscreen,
           let offscreenTexture,
           let descriptor = drawableDescriptor,
           let postPipeline,
           let postSampler {
            descriptor.colorAttachments[0].loadAction = .dontCare
            descriptor.colorAttachments[0].storeAction = .store
            guard let postEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return
            }
            postEncoder.setRenderPipelineState(postPipeline)
            postEncoder.setCullMode(.none)
            postEncoder.setFragmentTexture(offscreenTexture, index: 0)
            postEncoder.setFragmentSamplerState(postSampler, index: 0)
            var invResolution = SIMD2<Float>(
                1.0 / Float(max(offscreenTextureWidth, 1)),
                1.0 / Float(max(offscreenTextureHeight, 1))
            )
            postEncoder.setFragmentBytes(&invResolution, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
            var hover = LabyrinthHoverPostProcessUniforms.zero
            postEncoder.setFragmentBytes(&hover, length: MemoryLayout<LabyrinthHoverPostProcessUniforms>.stride, index: 1)
            postEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            postEncoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func ensureOffscreenTexture(drawableSize: CGSize) -> MTLTexture? {
        let width = max(Int(drawableSize.width.rounded(.down)), 1)
        let height = max(Int(drawableSize.height.rounded(.down)), 1)
        guard width != offscreenTextureWidth ||
              height != offscreenTextureHeight ||
              offscreenColorTexture == nil else {
            return offscreenColorTexture
        }

        offscreenTextureWidth = width
        offscreenTextureHeight = height

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        descriptor.sampleCount = 1
        offscreenColorTexture = device.makeTexture(descriptor: descriptor)
        return offscreenColorTexture
    }

    private func drawStrokes(model: LabyrinthCanvasModel,
                             viewSize: CGSize,
                             encoder: MTLRenderCommandEncoder) {
        let cameraCenter = LabyrinthCanvasMath.screenToWorld(
            CGPoint(x: viewSize.width / 2.0, y: viewSize.height / 2.0),
            viewSize: viewSize,
            camera: model.camera
        )
        let instances = makeStrokeInstances(model: model,
                                            viewSize: viewSize,
                                            cameraCenterActive: cameraCenter)
        guard !instances.isEmpty else { return }

        guard let instanceBuffer = device.makeBuffer(bytes: instances,
                                                     length: MemoryLayout<LabyrinthMetalStrokeInstance>.stride * instances.count,
                                                     options: .storageModeShared) else {
            return
        }

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

    private func makeStrokeInstances(model: LabyrinthCanvasModel,
                                     viewSize: CGSize,
                                     cameraCenterActive: SIMD2<Double>) -> [LabyrinthMetalStrokeInstance] {
        var entries: [(zIndex: UInt32, instance: LabyrinthMetalStrokeInstance)] = []
        let frames = model.allFrames()
        let viewportRadiusActive = hypot(Double(viewSize.width), Double(viewSize.height)) * 0.5 / max(model.camera.zoom, 1e-9)

        for frame in frames {
            guard let transform = model.transformFromActive(to: frame),
                  transform.scale.isFinite,
                  abs(transform.scale) > 1e-12 else {
                continue
            }

            for object in frame.objects where object.typeID == LabyrinthStrokePayload.typeID {
                guard let stroke = try? object.decodedPayload(as: LabyrinthStrokePayload.self),
                      !stroke.segments.isEmpty else {
                    continue
                }

                let origin = object.transform.positionSIMD
                let safeScale = max(abs(transform.scale), 1e-12)
                let activeWidth = max(stroke.worldWidth / safeScale, 1e-9)
                let zoomInFrame = max(model.camera.zoom / safeScale, 1e-9)
                guard stroke.renderedHalfPixelWidth(at: zoomInFrame, cullBelowMinimum: true) != nil else {
                    continue
                }

                let originActive = (origin - transform.translation) / transform.scale
                let distanceFromCamera = simd_length(originActive - cameraCenterActive)
                let strokeRadiusActive = stroke.cullingRadiusWorld / safeScale
                if distanceFromCamera > strokeRadiusActive + viewportRadiusActive {
                    continue
                }

                func activePoint(_ localPoint: SIMD2<Float>) -> SIMD2<Float> {
                    let pointInFrame = origin + SIMD2<Double>(Double(localPoint.x), Double(localPoint.y))
                    let pointActive = (pointInFrame - transform.translation) / transform.scale
                    return SIMD2<Float>(Float(pointActive.x), Float(pointActive.y))
                }

                for segment in stroke.segments {
                    entries.append((
                        object.zIndex,
                        LabyrinthMetalStrokeInstance(
                            p0World: activePoint(segment.p0SIMD),
                            p1World: activePoint(segment.p1SIMD),
                            color: segment.color.simd,
                            params: SIMD4<Float>(
                                Float(activeWidth),
                                0,
                                segment.pressure0Storage,
                                segment.pressure1Storage
                            )
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
