//
// ARContent.swift
// SpatialTag
//
// Core model managing AR content visualization, tag placement, and spatial awareness
// with enhanced performance monitoring and thread safety
//

import ARKit // v6.0
import SceneKit // latest
import simd // latest
import os.log // latest
import Combine // latest

// MARK: - Global Constants

private let MAX_RENDER_DISTANCE: Float = 50.0
private let MIN_RENDER_DISTANCE: Float = 0.5
private let DEFAULT_SCALE: Float = 1.0
private let REFRESH_RATE: Float = 30.0
private let UPDATE_QUEUE_QOS: DispatchQoS = .userInteractive
private let FRAME_PROCESSING_TIMEOUT: TimeInterval = 0.033 // ~30fps

// MARK: - Error Types

enum ARContentError: Error {
    case invalidPosition
    case nodeNotFound
    case renderingError
    case outOfRange
    case threadingError
    case performanceError
}

// MARK: - Supporting Types

@propertyWrapper
struct AtomicProperty<T> {
    private let lock = NSLock()
    private var value: T
    
    init(wrappedValue: T) {
        self.value = wrappedValue
    }
    
    var wrappedValue: T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
    }
}

// MARK: - Frame Processor

private class FrameProcessor {
    private let performanceLog = OSLog(subsystem: "com.spatialtag.ar", category: "Performance")
    private var lastFrameTime: TimeInterval = 0
    
    func processFrame(_ frame: ARFrame) -> Bool {
        let currentTime = CACurrentMediaTime()
        let frameDelta = currentTime - lastFrameTime
        
        guard frameDelta >= FRAME_PROCESSING_TIMEOUT else {
            return false
        }
        
        lastFrameTime = currentTime
        
        os_signpost(.event, log: performanceLog, name: "FrameProcessing",
                   "Frame processed in %{public}f ms", frameDelta * 1000)
        
        return true
    }
}

// MARK: - ARContent Class

public class ARContent {
    
    // MARK: - Properties
    
    @AtomicProperty private var tagNodes: [UUID: SCNNode] = [:]
    private let sceneView: ARSCNView
    private var currentScale: Float = DEFAULT_SCALE
    private var isInitialized: Bool = false
    private let updateQueue: DispatchQueue
    private let frameProcessor: FrameProcessor
    @AtomicProperty private var isUpdating: Bool = false
    
    private let logger = Logger(minimumLevel: .debug, category: "ARContent")
    
    // MARK: - Initialization
    
    public init(sceneView: ARSCNView) {
        self.sceneView = sceneView
        self.updateQueue = DispatchQueue(label: "com.spatialtag.ar.update",
                                       qos: UPDATE_QUEUE_QOS)
        self.frameProcessor = FrameProcessor()
        
        configureSceneView()
        logger.debug("ARContent initialized")
    }
    
    private func configureSceneView() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.environmentTexturing = .automatic
        configuration.planeDetection = [.horizontal, .vertical]
        
        sceneView.session.configuration = configuration
        sceneView.automaticallyUpdatesLighting = true
        sceneView.rendersContinuously = true
        
        isInitialized = true
    }
    
    // MARK: - Public Methods
    
    public func addTag(_ tag: Tag, position: simd_float4) -> Result<Bool, ARContentError> {
        guard isInitialized else {
            logger.error("ARContent not initialized")
            return .failure(.renderingError)
        }
        
        let startTime = CACurrentMediaTime()
        
        return updateQueue.sync { [weak self] in
            guard let self = self else {
                return .failure(.threadingError)
            }
            
            guard validatePosition(position) else {
                logger.warning("Invalid position for tag: \(tag.id)")
                return .failure(.invalidPosition)
            }
            
            do {
                let node = try createTagNode(for: tag, at: position)
                tagNodes[tag.id] = node
                sceneView.scene.rootNode.addChildNode(node)
                
                let endTime = CACurrentMediaTime()
                logger.performance("AddTag",
                                duration: endTime - startTime,
                                threshold: 0.1,
                                metadata: ["tagId": tag.id.uuidString])
                
                return .success(true)
            } catch {
                logger.error("Failed to create tag node: \(error.localizedDescription)")
                return .failure(.renderingError)
            }
        }
    }
    
    public func removeTag(tagId: UUID) -> Result<Bool, ARContentError> {
        let startTime = CACurrentMediaTime()
        
        return updateQueue.sync { [weak self] in
            guard let self = self else {
                return .failure(.threadingError)
            }
            
            guard let node = tagNodes[tagId] else {
                return .failure(.nodeNotFound)
            }
            
            node.removeFromParentNode()
            tagNodes.removeValue(forKey: tagId)
            
            let endTime = CACurrentMediaTime()
            logger.performance("RemoveTag",
                            duration: endTime - startTime,
                            metadata: ["tagId": tagId.uuidString])
            
            return .success(true)
        }
    }
    
    public func updateFrame(_ frame: ARFrame) {
        guard !isUpdating else { return }
        isUpdating = true
        
        let startTime = CACurrentMediaTime()
        
        updateQueue.async { [weak self] in
            guard let self = self else { return }
            
            defer {
                self.isUpdating = false
            }
            
            guard self.frameProcessor.processFrame(frame) else { return }
            
            for (tagId, node) in self.tagNodes {
                do {
                    try self.updateNodePosition(node, with: frame)
                } catch {
                    self.logger.error("Failed to update node position: \(error.localizedDescription)")
                }
            }
            
            let endTime = CACurrentMediaTime()
            self.logger.performance("FrameUpdate",
                                 duration: endTime - startTime,
                                 threshold: FRAME_PROCESSING_TIMEOUT,
                                 metadata: ["frameId": frame.timestamp])
        }
    }
    
    // MARK: - Private Methods
    
    private func validatePosition(_ position: simd_float4) -> Bool {
        let distance = simd_length(position.xyz)
        return distance >= MIN_RENDER_DISTANCE && distance <= MAX_RENDER_DISTANCE
    }
    
    private func createTagNode(for tag: Tag, at position: simd_float4) throws -> SCNNode {
        let node = SCNNode()
        
        // Create visual representation
        let geometry = SCNBox(width: 0.1, height: 0.1, length: 0.1, chamferRadius: 0.01)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.systemBlue.withAlphaComponent(0.8)
        material.metalness.contents = 0.5
        material.roughness.contents = 0.5
        geometry.materials = [material]
        
        node.geometry = geometry
        node.position = SCNVector3(position.x, position.y, position.z)
        node.scale = SCNVector3(currentScale, currentScale, currentScale)
        
        // Add physics for interaction
        node.physicsBody = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: geometry))
        
        return node
    }
    
    private func updateNodePosition(_ node: SCNNode, with frame: ARFrame) throws {
        let worldPosition = node.worldPosition
        let screenPosition = sceneView.projectPoint(worldPosition)
        
        // Check if node is visible in current frame
        let isVisible = sceneView.isNode(node, insideFrustumOf: sceneView.pointOfView)
        node.isHidden = !isVisible
        
        // Update node transform based on frame data
        if isVisible {
            let distance = simd_length(simd_float3(worldPosition))
            let scale = max(0.1, min(1.0, 1.0 / (distance * 0.1)))
            node.scale = SCNVector3(scale, scale, scale)
        }
    }
}

// MARK: - ARContent Extension for Combine

extension ARContent {
    public func tagPublisher(for tagId: UUID) -> AnyPublisher<SCNNode?, Never> {
        updateQueue.sync {
            Just(tagNodes[tagId])
                .eraseToAnyPublisher()
        }
    }
}