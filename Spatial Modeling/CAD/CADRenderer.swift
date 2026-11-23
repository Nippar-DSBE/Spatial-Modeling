// Copyright (c) 2026 Design Studio Butterfly Effect
// SPDX-License-Identifier: MIT

import Foundation
import SwiftUI
import RealityKit
import Metal
#if canImport(UIKit)
import UIKit
private typealias CADColor = UIColor
#else
import AppKit
private typealias CADColor = NSColor
#endif
import simd

// Face component kept for compatibility with the Phase 2 host regression checks.
struct CADFaceTarget: Component { let objectID: UUID; let body: UInt64; let revision: UInt64; let face: UInt32 }
struct CADTopologyTarget: Component {
    let objectID: UUID; let body: UInt64; let revision: UInt64
    let selection: CADSelection
}

@MainActor final class CADStagedMesh {
    let group: Entity
    let mesh: LowLevelMesh
    let snapshot: CADMesh
    let objectID: UUID
    let handles: [CADSelection: ModelEntity]
    let meshUpdateMS: Double
    init(group: Entity, mesh: LowLevelMesh, snapshot: CADMesh, objectID: UUID,
         handles: [CADSelection: ModelEntity], meshUpdateMS: Double) {
        self.group = group; self.mesh = mesh; self.snapshot = snapshot
        self.objectID = objectID; self.handles = handles; self.meshUpdateMS = meshUpdateMS
    }
}

@MainActor final class CADRenderer {
    let root = Entity()
    private var objectMode = false
    private var installed: CADStagedMesh?
    private var displayedFaces: [UInt32] = []
    private let gray = SimpleMaterial(color: CADColor(white: 0.6, alpha: 1), roughness: 0.8, isMetallic: false)
    private let orange = SimpleMaterial(color: .systemOrange, roughness: 0.7, isMetallic: false)
    private let whiteHandle = UnlitMaterial(color: .white)
    private let orangeHandle = UnlitMaterial(color: .systemOrange)
    private lazy var sphere = MeshResource.generateSphere(radius: 0.006)
    private lazy var collision = ShapeResource.generateSphere(radius: 0.014)
    private(set) var mode: CADSelectionMode = .face
    init() { root.isEnabled = false }

    /// Preview writes the same LowLevelMesh; the gesture's handle Entity is never replaced.
    private func write(_ snapshot: CADMesh, to mesh: LowLevelMesh, highlight: UInt32? = nil) throws -> [UInt32] {
        guard !snapshot.vertices.isEmpty, snapshot.indices.count == snapshot.triangleFaces.count * 3,
              snapshot.vertices.count <= mesh.descriptor.vertexCapacity,
              snapshot.indices.count <= mesh.descriptor.indexCapacity else {
            throw CADIntegrationError(message: "プレビューの描画容量を超えました。")
        }
        let faceOrder = Array(Set(snapshot.triangleFaces)).sorted()
        guard faceOrder.count == snapshot.faceCount else { throw CADIntegrationError(message: "面IDが不正です。") }
        var grouped = [UInt32: [UInt32]]()
        for (triangle, face) in snapshot.triangleFaces.enumerated() {
            grouped[face, default: []].append(contentsOf: snapshot.indices[(triangle * 3)..<(triangle * 3 + 3)])
        }
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let buffer = raw.bindMemory(to: CADRenderVertex.self)
            for i in snapshot.vertices.indices { buffer[i] = snapshot.vertices[i] }
        }
        let ordered = faceOrder.flatMap { grouped[$0]! }
        mesh.withUnsafeMutableIndices { raw in
            let buffer = raw.bindMemory(to: UInt32.self)
            for i in ordered.indices { buffer[i] = ordered[i] }
        }
        var offset = 0
        var parts: [LowLevelMesh.Part] = []
        for face in faceOrder {
            let indices = grouped[face]!
            let points = indices.map { snapshot.vertices[Int($0)].position }
            let low = points.reduce(points[0]) { simd_min($0, $1) } - SIMD3<Float>(repeating: 0.001)
            let high = points.reduce(points[0]) { simd_max($0, $1) } + SIMD3<Float>(repeating: 0.001)
            parts.append(.init(indexOffset: offset * 4, indexCount: indices.count, topology: .triangle,
                               materialIndex: face == highlight ? 1 : 0, bounds: BoundingBox(min: low, max: high)))
            offset += indices.count
        }
        mesh.parts.replaceAll(parts)
        return faceOrder
    }

    func stage(_ snapshot: CADMesh, objectID: UUID) throws -> CADStagedMesh {
        var descriptor = LowLevelMesh.Descriptor()
        // Fixed reserve for live CAD retessellation. Exceeding it refuses the preview safely.
        descriptor.vertexCapacity = max(4096, snapshot.vertices.count * 4)
        descriptor.indexCapacity = max(16384, snapshot.indices.count * 4)
        descriptor.indexType = .uint32
        descriptor.vertexAttributes = [
            .init(semantic: .position, format: .float3, offset: MemoryLayout<CADRenderVertex>.offset(of: \CADRenderVertex.position)!),
            .init(semantic: .normal, format: .float3, offset: MemoryLayout<CADRenderVertex>.offset(of: \CADRenderVertex.normal)!)
        ]
        descriptor.vertexLayouts = [.init(bufferIndex: 0, bufferStride: MemoryLayout<CADRenderVertex>.stride)]
        let start = DispatchTime.now().uptimeNanoseconds
        let mesh = try LowLevelMesh(descriptor: descriptor)
        _ = try write(snapshot, to: mesh)
        let time = milliseconds(DispatchTime.now().uptimeNanoseconds - start)
        let resource = try MeshResource(from: mesh)
        let group = Entity()
        group.addChild(ModelEntity(mesh: resource, materials: [gray, orange]))
        var handles: [CADSelection: ModelEntity] = [:]
        for element in snapshot.topology {
            let handle = ModelEntity(mesh: sphere, materials: [whiteHandle])
            handle.position = element.position
            handle.name = "CAD \(element.selection.mode.rawValue) \(element.selection.id) · r\(snapshot.revision)"
            handle.components.set(CADTopologyTarget(objectID: objectID, body: snapshot.body, revision: snapshot.revision, selection: element.selection))
            if element.selection.mode == .face {
                handle.components.set(CADFaceTarget(objectID: objectID, body: snapshot.body, revision: snapshot.revision, face: element.selection.id))
            }
            handle.components.set(InputTargetComponent(allowedInputTypes: .indirect))
            handle.components.set(CollisionComponent(shapes: [collision]))
            handle.components.set(HoverEffectComponent())
            handle.isEnabled = element.selection.mode == mode
            handles[element.selection] = handle
            group.addChild(handle)
        }
        return CADStagedMesh(group: group, mesh: mesh, snapshot: snapshot, objectID: objectID, handles: handles, meshUpdateMS: time)
    }

    func install(_ staged: CADStagedMesh) {
        root.children.removeAll(); root.addChild(staged.group); installed = staged
        displayedFaces = Array(Set(staged.snapshot.triangleFaces)).sorted()
        setMode(mode)
    }
    func setObjectMode(_ enabled: Bool) {
        guard objectMode != enabled else { return }
        objectMode = enabled
        for (selection, handle) in installed?.handles ?? [:] { handle.isEnabled = !enabled && selection.mode == mode }
    }
    func setMode(_ mode: CADSelectionMode) {
        self.mode = mode
        if let installed {
            for i in 0..<installed.mesh.parts.count {
                var part = installed.mesh.parts[i]; part.materialIndex = 0; installed.mesh.parts[i] = part
            }
            for handle in installed.handles.values { handle.model?.materials = [whiteHandle] }
        }
        for (selection, handle) in installed?.handles ?? [:] { handle.isEnabled = !objectMode && selection.mode == mode }
    }
    func select(_ target: CADFaceTarget) -> Bool {
        select(CADTopologyTarget(objectID: target.objectID, body: target.body, revision: target.revision,
                                 selection: CADSelection(mode: .face, id: target.face)))
    }
    func select(_ target: CADTopologyTarget) -> Bool {
        guard let installed, target.objectID == installed.objectID, target.body == installed.snapshot.body,
              target.revision == installed.snapshot.revision, target.selection.mode == mode,
              installed.handles[target.selection] != nil else { return false }
        for (i, face) in displayedFaces.enumerated() {
            var part = installed.mesh.parts[i]
            part.materialIndex = target.selection == CADSelection(mode: .face, id: face) ? 1 : 0
            installed.mesh.parts[i] = part
        }
        for (selection, handle) in installed.handles {
            handle.model?.materials = selection == target.selection ? [orangeHandle] : [whiteHandle]
        }
        return true
    }
    func beginPreview(_ selected: CADSelection) {
        for (selection, handle) in installed?.handles ?? [:] { handle.isEnabled = selection == selected }
    }
    func preview(_ snapshot: CADMesh, selected: CADTopologyElement, distanceMM: Double) throws -> Double {
        guard let installed else { throw CADIntegrationError(message: "描画形状がありません。") }
        let start = DispatchTime.now().uptimeNanoseconds
        let moved = selected.position + CADCoordinateConversion.offsetMeters(distanceMM, along: selected.normal)
        // Record indices may change after local operations. Match the offset plane geometrically for highlighting only.
        let face = snapshot.topology.first {
            $0.selection.mode == .face && simd_dot($0.normal, selected.normal) > 0.9999
                && abs(simd_dot($0.position - moved, selected.normal)) < 0.00001
        }?.selection.id
        displayedFaces = try write(snapshot, to: installed.mesh, highlight: face)
        installed.handles[selected.selection]?.position = moved
        return milliseconds(DispatchTime.now().uptimeNanoseconds - start)
    }
    func previewHybrid(_ snapshot: CADMesh, selected: CADTopologyElement, delta: SIMD3<Float>) throws -> Double {
        guard let installed else { throw CADIntegrationError(message:"No installed CAD mesh.") }
        let start=DispatchTime.now().uptimeNanoseconds
        displayedFaces=try write(snapshot,to:installed.mesh)
        installed.handles[selected.selection]?.position=selected.position+delta
        return milliseconds(DispatchTime.now().uptimeNanoseconds-start)
    }
    func restorePreview(selection: CADSelection?) {
        guard let installed else { return }
        displayedFaces = (try? write(installed.snapshot, to: installed.mesh)) ?? displayedFaces
        for element in installed.snapshot.topology { installed.handles[element.selection]?.position = element.position }
        setMode(mode)
        if let selection {
            _ = select(CADTopologyTarget(objectID: installed.objectID, body: installed.snapshot.body,
                                        revision: installed.snapshot.revision, selection: selection))
        }
    }
}
