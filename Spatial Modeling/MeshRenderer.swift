// Copyright (c) 2026 Design Studio Butterfly Effect
// SPDX-License-Identifier: MIT

import Foundation
import RealityKit
#if canImport(UIKit)
import UIKit
private typealias MeshColor = UIColor
#else
import AppKit
private typealias MeshColor = NSColor
#endif
import Metal

@MainActor
final class MeshRenderer {
    let root = Entity()
    let objectID: UUID
    private var surface = ModelEntity()
    private var objectMode = false
    private var lastMode: EditMode = .vertex
    private var mesh: LowLevelMesh?
    private var geometry: MeshGeometry?
    private var handles: [Selection: ModelEntity] = [:]
    private var edgeLines: [Int: ModelEntity] = [:]
    private let neutral = SimpleMaterial(color: MeshColor(white: 0.58, alpha: 1), roughness: 0.8, isMetallic: false)
    private let orange = SimpleMaterial(color: .systemOrange, roughness: 0.65, isMetallic: false)
    private let handleMaterial = UnlitMaterial(color: MeshColor(white: 0.93, alpha: 1))
    private let selectedMaterial = UnlitMaterial(color: .systemOrange)

    init(objectID: UUID) { self.objectID = objectID; root.isEnabled = false }

    func prepare(document: MeshDocument, mode: EditMode, revision: UInt64) throws {
        guard mesh == nil else { update(document: document, mode: mode, revision: revision); return }
        let geometry = MeshGeometry(document: document)
        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexCapacity = geometry.triangles.count * 3
        descriptor.indexCapacity = descriptor.vertexCapacity
        descriptor.vertexAttributes = [
            .init(semantic: .position, format: .float3, offset: MemoryLayout<RenderVertex>.offset(of: \RenderVertex.position)!),
            .init(semantic: .normal, format: .float3, offset: MemoryLayout<RenderVertex>.offset(of: \RenderVertex.normal)!)
        ]
        descriptor.vertexLayouts = [.init(bufferIndex: 0, bufferStride: MemoryLayout<RenderVertex>.stride)]
        descriptor.indexType = .uint32
        let mesh = try LowLevelMesh(descriptor: descriptor)
        mesh.withUnsafeMutableIndices { bytes in
            let indices = bytes.bindMemory(to: UInt32.self)
            for index in 0..<descriptor.indexCapacity { indices[index] = UInt32(index) }
        }
        self.mesh = mesh
        self.geometry = geometry
        updateSurface(document)
        let resource: MeshResource
        do {
            resource = try MeshResource(from: mesh)
        } catch {
            self.mesh = nil
            self.geometry = nil
            throw error
        }
        var base = neutral
        base.faceCulling = .none
        var highlight = orange
        highlight.faceCulling = .none
        surface.model = ModelComponent(mesh: resource, materials: [base, highlight])
        root.addChild(surface)
        let sphere = MeshResource.generateSphere(radius: 0.005)
        let hitShape = ShapeResource.generateSphere(radius: 0.014)
        func makeHandle(_ selection: Selection) {
            let handle = ModelEntity(mesh: sphere, materials: [handleMaterial])
            handle.name = "\(selection.mode.rawValue)-\(selection.id)"
            handle.components.set(EditTargetComponent(selection: selection, objectID: objectID, revision: revision))
            handle.components.set(InputTargetComponent(allowedInputTypes: .indirect))
            handle.components.set(CollisionComponent(shapes: [hitShape]))
            handle.components.set(HoverEffectComponent())
            root.addChild(handle)
            handles[selection] = handle
        }
        for vertex in document.vertices { makeHandle(Selection(mode: .vertex, id: vertex.id)) }
        let cylinder = MeshResource.generateCylinder(height: 1, radius: 1)
        for edge in document.edges {
            makeHandle(Selection(mode: .edge, id: edge.id))
            let line = ModelEntity(mesh: cylinder, materials: [handleMaterial])
            root.addChild(line)
            edgeLines[edge.id] = line
        }
        for face in document.faces { makeHandle(Selection(mode: .face, id: face.id)) }
        update(document: document, mode: mode, revision: revision)
    }

    /// Stage a topology replacement before touching the displayed document/resources.
    func replace(document: MeshDocument, mode: EditMode, revision: UInt64) throws {
        let staged=MeshRenderer(objectID:objectID)
        try staged.prepare(document:document,mode:mode,revision:revision)
        let wasObject=objectMode
        root.children.removeAll()
        surface=staged.surface;mesh=staged.mesh;geometry=staged.geometry;handles=staged.handles;edgeLines=staged.edgeLines;lastMode=mode
        for child in Array(staged.root.children) { root.addChild(child) }
        objectMode=false;setObjectMode(wasObject)
    }
    func setObjectMode(_ enabled: Bool) {
        guard objectMode != enabled else { return }
        objectMode = enabled
        for (selection, handle) in handles { handle.isEnabled = !enabled && selection.mode == lastMode }
        for line in edgeLines.values { line.isEnabled = !enabled && lastMode == .edge }
    }
    func update(document: MeshDocument, mode: EditMode, revision: UInt64) {
        lastMode = mode
        updateSurface(document)
        let positions = document.positions
        for (selection, handle) in handles {
            let active = !objectMode && selection.mode == mode
            handle.isEnabled = active
            // Disabled entities do not participate in input or collision queries.
            guard active else { continue }
            handle.components.set(EditTargetComponent(selection: selection, objectID: objectID, revision: revision))
            let ids = document.vertexIDs(for: selection)
            handle.position = ids.reduce(SIMD3<Float>.zero) { $0 + positions[$1]! } / Float(ids.count)
            handle.model?.materials = document.selection == selection ? [selectedMaterial] : [handleMaterial]
        }
        for edge in document.edges {
            guard let line = edgeLines[edge.id] else { continue }
            line.isEnabled = !objectMode && mode == .edge
            guard mode == .edge else { continue }
            let a = positions[edge.vertexIDs[0]]!
            let b = positions[edge.vertexIDs[1]]!
            let delta = b - a
            let length = simd_length(delta)
            line.position = (a + b) / 2
            line.scale = [0.0012, max(length, 0.00001), 0.0012]
            line.orientation = length > 0.00001 ? simd_quatf(from: [0, 1, 0], to: delta / length) : simd_quatf()
            line.model?.materials = document.selection == Selection(mode: .edge, id: edge.id)
                ? [selectedMaterial] : [handleMaterial]
        }
    }

    private func updateSurface(_ document: MeshDocument) {
        guard let mesh, let geometry else { return }
        let positions = document.positions
        let vertices = geometry.vertices(positions: positions)
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { bytes in
            let buffer = bytes.bindMemory(to: RenderVertex.self)
            for index in vertices.indices { buffer[index] = vertices[index] }
        }
        // Index offsets are bytes. Each logical face gets its own material slot.
        var parts: [LowLevelMesh.Part] = []
        for face in document.faces {
            guard let first = geometry.triangles.firstIndex(where: { $0.faceID == face.id }) else { continue }
            let count = geometry.triangles.filter { $0.faceID == face.id }.count * 3
            let points = face.vertexIDs.map { positions[$0]! }
            let padding = SIMD3<Float>(repeating: 0.001)
            let minimum = points.reduce(points[0], simd_min) - padding
            let maximum = points.reduce(points[0], simd_max) + padding
            parts.append(.init(indexOffset: first * 3 * MemoryLayout<UInt32>.stride,
                               indexCount: count, topology: .triangle,
                               materialIndex: document.selection == Selection(mode: .face, id: face.id) ? 1 : 0,
                               bounds: BoundingBox(min: minimum, max: maximum)))
        }
        mesh.parts.replaceAll(parts)
    }
}
